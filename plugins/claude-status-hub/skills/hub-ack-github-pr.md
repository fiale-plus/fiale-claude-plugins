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
   [5] 🔄 Fix loop (stay in session until CI passes)
   [d] Dismiss
```

Actions:
- **Re-run failed**: `gh run rerun <run_id> --failed --repo <owner>/<repo>`
- **Re-run full**: `gh run rerun <run_id> --repo <owner>/<repo>`
- **Investigate**: Read the failing test output and propose fix
- **View logs**: `gh run view <run_id> --repo <owner>/<repo> --log-failed`
- **Fix loop**: Enter interactive fix mode (see below)

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

### Fix Loop Mode

When user selects "Fix loop", enter an interactive cycle that stays in the foreground until CI passes:

```
🔄 Fix Loop Mode - PR #<number>
   Stay in session until CI passes. I'll help you iterate.

   Current status: ❌ <check_name> failing
```

**Loop steps:**

1. **Investigate** - Read failure logs and analyze
   ```bash
   gh run view <run_id> --repo <owner>/<repo> --log-failed
   ```

2. **Propose fix** - Suggest code changes based on failure

3. **Apply & push** - After user approves:
   ```bash
   git add -A && git commit -m "<fix message>" && git push
   ```

4. **Wait for CI** - Poll for check status:
   ```bash
   # Poll every 30s until checks complete
   while true; do
     STATUS=$(gh pr view <number> --repo <owner>/<repo> --json statusCheckRollup --jq '
       if ([.statusCheckRollup[] | select(.status == "IN_PROGRESS" or .status == "QUEUED" or .status == "PENDING")] | length) > 0 then "pending"
       elif ([.statusCheckRollup[] | select(.conclusion == "FAILURE")] | length) > 0 then "failed"
       else "passed"
       end
     ')
     echo "CI status: $STATUS"
     [ "$STATUS" != "pending" ] && break
     sleep 30
   done
   ```

5. **Evaluate result:**
   - **Passed** → 🎉 Exit loop, check if merge-ready (see below)
   - **Failed** → Show new failure, loop back to step 1

**On CI pass - check merge readiness:**
```bash
gh pr view <number> --repo <owner>/<repo> --json reviewDecision,mergeable --jq '{reviewDecision, mergeable}'
```

If `reviewDecision == "APPROVED"` and `mergeable == "MERGEABLE"`:
```
🎉 CI Passed! PR #<number> is now merge-ready!

   ✅ Fix worked: <commit message>
   ✅ Approved by: @reviewer
   ✅ No conflicts

   [1] Post /aviator merge (configured default)
   [2] Merge now (squash)
   [3] Done - merge manually later
```

If still waiting for approval:
```
🎉 CI Passed! PR #<number> checks green.

   ✅ Fix worked: <commit message>
   ⏳ Waiting for approval

   [1] Request review from @someone
   [2] Done
```

**Loop UI:**
```
🔄 Iteration 2 - PR #<number>

   Previous fix: <commit message>
   Result: ❌ Still failing

   New failure analysis:
   ...

   [1] Apply suggested fix
   [2] Try different approach
   [3] Re-run CI (maybe flaky)
   [x] Exit loop (keep tracking)
```

**Exit conditions:**
- CI passes → Success, update `lastSeen.checksFailed: 0`
- User exits → Keep `lastSeen.checksFailed` at current count (will alert on changes)
- User dismisses → Set `lastSeen` to current state (no alert until new failure)

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

### Proactive Merge on Unblock

When a PR transitions to merge-ready (approval obtained OR checks go green), proactively offer to execute the configured merge strategy:

**Trigger conditions:**
- `reviewDecision` changed to `APPROVED` (was waiting for approval)
- `checksFailed` changed from `> 0` to `0` (CI fixed)
- AND all merge conditions now met (approved + checks pass + no conflicts)

**Proactive wizard:**
```
🚀 PR #<number> is now merge-ready!

   Just unblocked by: ✅ Approval from @reviewer
   (or: ✅ CI now passing)

   Your configured merge strategy: <strategy>

   [1] Execute now → <merge command>
   [2] Review PR first, then merge
   [d] Dismiss (merge manually later)
```

**If strategy is "aviator" or "auto-merge":**
```
🚀 PR #<number> is now merge-ready!

   Just unblocked by: ✅ CI now passing

   [1] Post /aviator merge now (configured default)
   [2] Enable auto-merge instead
   [3] Merge immediately (squash)
   [d] Dismiss
```

**Config for auto-post:**
```json
{
  "github": {
    "mergeStrategy": {
      "default": "aviator",
      "autoPostOnReady": true  // Auto-post merge command when unblocked
    }
  }
}
```

When `autoPostOnReady: true`, skip the wizard and execute immediately:
```
🚀 PR #<number> merge-ready → Posted /aviator merge

   Unblocked by: ✅ Approval from @reviewer
   Action: Posted "/aviator merge" comment (configured auto-post)

   [View PR] [Undo]
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
