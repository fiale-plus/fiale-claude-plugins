# Hub Ack - GitHub PR Actions

Handle GitHub PR alerts with contextual actions based on PR state.

## Input

Receives PR item with: `owner`, `repo`, `number`, `icon` (X, ⚡, 🚀, !, ?, ✓)

## Step 1: Get Fresh PR Data

```bash
gh pr view <number> --repo <owner>/<repo> --json state,isDraft,reviewDecision,statusCheckRollup,title,comments,mergeable,mergeStateStatus,headRefName,baseRefName --jq '{
  state, isDraft, reviewDecision, title, mergeable, mergeStateStatus, headRefName, baseRefName,
  commentsCount: (.comments | length),
  checksPassed: ([.statusCheckRollup[] | select(.conclusion == "SUCCESS")] | length),
  checksFailed: ([.statusCheckRollup[] | select(.conclusion == "FAILURE")] | length),
  checksPending: ([.statusCheckRollup[] | select(.status == "IN_PROGRESS" or .status == "QUEUED")] | length),
  failedChecks: [.statusCheckRollup[] | select(.conclusion == "FAILURE") | .name]
}'
```

## Step 2: Route by State

### Case A: CI Failure (checksFailed > 0)

Check if flaky (also fails on main):
```bash
gh run list --repo <owner>/<repo> --branch main --limit 5 --json conclusion,name --jq '[.[] | select(.conclusion == "failure")] | .[0].name // "none"'
```

**If flaky:** Show warning, offer re-run or comment.

**If not flaky:**
```
❌ PR #<number> CI Failed - <check>

   [1] Re-run failed checks
   [2] Re-run full CI
   [3] Investigate & fix
   [4] View logs
   [5] 🔄 Fix loop
   [d] Dismiss
```

Actions: `gh run rerun <run_id> --failed`, `gh run view <run_id> --log-failed`

**Buildkite support:** If detailsUrl contains "buildkite" and Buildkite MCP available, use `mcp__buildkite__get_job_logs` for richer output.

### Fix Loop Mode

Stay in session until CI passes:
1. Read failure logs
2. Propose fix
3. Apply & push: `git add -A && git commit && git push`
4. Poll CI every 30s until complete
5. If passed → check merge readiness, offer merge
6. If failed → loop back with new analysis

Exit: CI passes, user exits, or user dismisses.

### Case B: Merge Conflicts (mergeable == "CONFLICTING")

```
⚡ PR #<number> - Merge Conflicts

   [1] 🤖 Resolve with AI
   [2] Open PR in browser
   [3] Resolve locally
   [d] Dismiss
```

**AI resolution:** Checkout, merge, analyze conflicts, propose resolutions, commit & push.

### Case C: Ready to Merge (🚀)

Get merge strategy from config: `repos["owner/repo"]` > `orgs["owner"]` > `default`

```
🚀 PR #<number> - Ready to Merge!

   ✅ Approved | ✅ CI passing | ✅ No conflicts

   [1] Merge (<strategy>)
   [2] Squash
   [3] Rebase
   [4] Auto-merge
   [5] /aviator merge
   [c] Custom command
   [d] Dismiss
```

**Per-PR auto-merge:** When `autoMerge: true` in config, daemon executes strategy automatically. Shows `🔁` indicator.

### Case D: Changes Requested

```
❗ PR #<number> - Changes Requested

   [1] View comments
   [2] Summarize changes
   [d] Dismiss
```

### Case E: Review Required

```
? PR #<number> - Waiting for Review

   [1] Request review
   [2] Bump reviewers
   [d] Dismiss
```

### Case F: New Comments

```
💬 PR #<number> - <N> new comments

   [1] View in browser
   [2] Summarize
   [d] Mark read
```

### Case G: Merged PR

```
✅ PR #<number> - Merged

   [1] Stop tracking (remove)
   [d] Keep tracking
```

## Step 3: Execute Action

Run appropriate gh command based on selection.

## Step 4: Update Config and Bridge

### 4a: Update Config

Update `lastSeen` with current values. Special cases:
- Fix applied → set `lastSeen.checksFailed: 0`
- Stop tracking → remove from `foreground[]`
- Set `hasAlert: false`

### 4b: Update Bridge

**CRITICAL**: Statusline reads bridge, not config. Update immediately:

```bash
FOREGROUND=$(jq -c '.foreground // []' ~/.claude/status-config.json)
BACKGROUND=$(jq -c '.background // {}' /tmp/status-hub.json)
${CLAUDE_PLUGIN_ROOT}/bin/update-bridge.sh \
  "$(echo "$BACKGROUND" | jq -r '.site')" \
  "$(echo "$BACKGROUND" | jq -r '.icon')" \
  "$(echo "$BACKGROUND" | jq -r '.title')" \
  "$(echo "$BACKGROUND" | jq -r '.detail')" \
  --foreground "$FOREGROUND"
```

## Error Handling

If gh command fails: show error, offer retry, don't update lastSeen.
