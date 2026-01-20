# Hub Ack - GitHub PR Actions

Handle GitHub PR alerts with contextual actions based on PR state.

## Input

Receives PR item from dispatcher with:
- `owner`, `repo`, `number` from config
- `icon` indicating current state (X, ⚡, 🚀, !, ?, ✓)
- Alert reason from `lastSeen` comparison

## Step 1: Get Fresh PR Data

```bash
gh pr view <number> --repo <owner>/<repo> --json state,isDraft,reviewDecision,statusCheckRollup,title,comments,mergeable,mergeStateStatus,headRefName,baseRefName --jq '{
  state, isDraft, reviewDecision, title, mergeable, mergeStateStatus, headRefName, baseRefName,
  commentsCount: (.comments | length),
  checksCount: (.statusCheckRollup | length),
  checksPassed: ([.statusCheckRollup[] | select(.conclusion == "SUCCESS")] | length),
  checksFailed: ([.statusCheckRollup[] | select(.conclusion == "FAILURE")] | length),
  checksPending: ([.statusCheckRollup[] | select(.status == "IN_PROGRESS" or .status == "QUEUED" or .status == "PENDING")] | length),
  failedChecks: [.statusCheckRollup[] | select(.conclusion == "FAILURE") | .name]
}'
```

## Step 2: Route by State

Based on PR state, show the appropriate wizard:

### Case A: CI Failure (checksFailed > 0)

First, check if the failing test also fails on main (flaky detection):

```bash
# Get the failed check names and check main branch status
gh run list --repo <owner>/<repo> --branch main --limit 5 --json conclusion,name --jq '[.[] | select(.conclusion == "failure")] | .[0].name // "none"'
```

**If test ALSO fails on main (flaky):**

```
❌ PR #<number> CI Failed - <failed_check_name>

   ⚠️ FLAKY: This test is ALSO failing on main branch

   This is likely NOT your fault.

   [1] Re-run CI (might pass)
   [2] Post comment tagging test owner
   [d] Dismiss
```

**If test only fails on PR:**

```
❌ PR #<number> CI Failed - <failed_check_name>

   🔍 Analysis:
      • Failure: <check_name>
      • Files in PR: checking impact...

   [1] Re-run failed checks only
   [2] Re-run full CI
   [3] Ask Claude to investigate and propose fix
   [4] View failure logs
   [d] Dismiss
```

Actions:
- **Re-run failed**: `gh run rerun <run_id> --failed --repo <owner>/<repo>`
- **Re-run full**: `gh run rerun <run_id> --repo <owner>/<repo>`
- **Investigate**: Read the failing test output and propose fix
- **View logs**: `gh run view <run_id> --repo <owner>/<repo> --log-failed`

**After "Investigate fix" action:**
When a fix is applied and pushed, update `lastSeen.checksFailed` to `0` (expected state).
This way:
- If CI passes → no alert (expected outcome)
- If CI fails again → alert triggers (unexpected, needs attention)

### Buildkite CI Support

If the failing check is from Buildkite (check name contains "buildkite" or statusCheckRollup has Buildkite URLs), prefer the Buildkite MCP for richer interactions:

**Detection:**
```bash
gh pr view <number> --repo <owner>/<repo> --json statusCheckRollup --jq '.statusCheckRollup[] | select(.conclusion == "FAILURE") | .detailsUrl' | grep -q buildkite
```

**If Buildkite MCP available** (`mcp__buildkite__*` tools):
- **View logs**: `mcp__buildkite__get_job_logs` - richer output than gh CLI
- **Rerun build**: `mcp__buildkite__retry_job` - direct Buildkite control
- **Get build info**: `mcp__buildkite__get_build` - detailed build metadata

**MCP setup**: Add to `.mcp.json`:
```json
{
  "mcpServers": {
    "buildkite": {
      "type": "url",
      "url": "https://mcp.buildkite.com/sse"
    }
  }
}
```

See: https://buildkite.com/docs/apis/mcp-server

### Case B: Merge Conflicts (mergeable == "CONFLICTING")

```
⚡ PR #<number> "<title>" - Merge Conflicts

   Conflicts detected with <baseRefName>

   [1] Open PR in browser to resolve
   [2] Fetch and resolve locally:
       git fetch origin <headRefName>
       git checkout <headRefName>
       git merge origin/<baseRefName>
   [d] Dismiss
```

### Case C: Ready to Merge (🚀 state)

Get merge strategy from config:

```bash
cat ~/.claude/status-config.json | jq '.github.mergeStrategy // {}'
```

**Resolution order**: repo override > org override > default

Determine strategy for this `<owner>/<repo>`:
1. Check `repos["<owner>/<repo>"]`
2. Check `orgs["<owner>"]`
3. Use `default` (fallback: "squash")

**Wizard:**

```
🚀 PR #<number> "<title>" - Ready to Merge!

   ✅ Approved by: <reviewers>
   ✅ CI: All checks passing
   ✅ No conflicts with <baseRefName>

   [1] Merge (<strategy>) - configured default
   [2] Merge (squash)
   [3] Merge (rebase)
   [4] Enable auto-merge
   [5] Post /aviator merge comment
   [c] Custom command...
   [d] Dismiss
```

Actions:
- **Merge squash**: `gh pr merge <number> --repo <owner>/<repo> --squash`
- **Merge rebase**: `gh pr merge <number> --repo <owner>/<repo> --rebase`
- **Merge commit**: `gh pr merge <number> --repo <owner>/<repo> --merge`
- **Auto-merge**: `gh pr merge <number> --repo <owner>/<repo> --auto --squash`
- **Aviator**: `gh pr comment <number> --repo <owner>/<repo> --body "/aviator merge"`
- **Custom**: Ask for command, execute it

**Custom command flow:**

```
Enter custom command (use {number} for PR number):
> [user input]

[Execute] [Cancel]
```

### Case D: Changes Requested (reviewDecision == "CHANGES_REQUESTED")

```
❗ PR #<number> "<title>" - Changes Requested

   Reviewer: <who requested changes>

   [1] View review comments in browser
   [2] Ask Claude to summarize requested changes
   [d] Dismiss (mark as seen)
```

### Case E: Review Required (reviewDecision == "REVIEW_REQUIRED")

```
? PR #<number> "<title>" - Waiting for Review

   Status: Awaiting review
   <N> reviewer(s) requested

   [1] Request review from specific person
   [2] Post comment to bump reviewers
   [d] Dismiss
```

### Case F: New Comments

```
💬 PR #<number> "<title>" - New Comments

   <N> new comment(s) since last check

   [1] View comments in browser
   [2] Summarize new comments
   [d] Mark as read
```

## Step 3: Execute Selected Action

Run the appropriate gh command based on user selection.

## Step 4: Update Config

After successful action:

```bash
# Read current config, update lastSeen for this PR, write back
```

Update the PR item's `lastSeen` with current values:
- `commentsCount`
- `state`
- `reviewDecision`
- `checksFailed` (set to `0` if fix was applied and pushed)
- `mergeable`

**Special case - fix applied:**
If user chose "Investigate fix" and a fix was committed/pushed, set `lastSeen.checksFailed: 0`.
This sets the "expected" state so:
- CI passes → no new alert (expected)
- CI fails → new alert (unexpected failure)

Set `hasAlert: false` for this item.

## Error Handling

If gh command fails:
1. Show error message to user
2. Offer to retry or dismiss
3. Don't update lastSeen (alert stays active)
