# Hub Ack - GitHub PR Actions

Handle PR alerts with contextual actions based on state.

## Input

Item with: `owner`, `repo`, `number`, `icon` (X, ⚡, 🚀, !, ?, ✓).

## Step 1: Get Fresh Data

```bash
gh pr view <number> --repo <owner>/<repo> --json state,isDraft,reviewDecision,statusCheckRollup,title,mergeable,mergeStateStatus,headRefName,baseRefName --jq '{
  state, isDraft, reviewDecision, title, mergeable, mergeStateStatus, headRefName, baseRefName,
  checksPassed: ([.statusCheckRollup[] | select(.conclusion == "SUCCESS")] | length),
  checksFailed: ([.statusCheckRollup[] | select(.conclusion == "FAILURE")] | length),
  checksPending: ([.statusCheckRollup[] | select(.status == "IN_PROGRESS" or .status == "QUEUED")] | length),
  failedChecks: [.statusCheckRollup[] | select(.conclusion == "FAILURE") | .name]
}'
```

## Step 2: Route by State

### CI Failure (checksFailed > 0)

```
❌ PR #<N> CI Failed - <check>
[1] Re-run failed  [2] Re-run full  [3] Investigate & fix  [4] View logs  [5] 🔄 Fix loop  [d] Dismiss
```

**Fix loop:** Read logs → propose fix → push → poll CI → repeat until pass or user exits.

### Merge Conflicts (mergeable == "CONFLICTING")

```
⚡ PR #<N> - Merge Conflicts
[1] 🤖 Resolve with AI  [2] Open in browser  [3] Resolve locally  [d] Dismiss
```

### Ready to Merge (🚀)

Get strategy from `github.mergeStrategy` config.

```
🚀 PR #<N> - Ready to Merge!
[1] Merge (<strategy>)  [2] Squash  [3] Rebase  [4] Auto-merge  [5] /aviator merge  [c] Custom  [d] Dismiss
```

### Changes Requested

```
❗ PR #<N> - Changes Requested
[1] View comments  [2] Summarize changes  [d] Dismiss
```

### Review Required

```
? PR #<N> - Waiting for Review
[1] Request review  [2] Bump reviewers  [d] Dismiss
```

### Merged

```
✅ PR #<N> - Merged
[1] Stop tracking  [d] Keep tracking
```

## Step 3: Execute & Update

Run `gh` command, then update config and bridge (see `lib-common.md`).
