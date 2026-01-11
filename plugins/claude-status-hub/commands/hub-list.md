---
name: hub-list
description: Display status hub as numbered tree view
---

# Hub List - Tree View

Display all tracked items in a tree format with numbered references.

## Process

1. Read `~/.claude/status-config.json`
2. If file doesn't exist or empty, say "No items being tracked. Use `/hub <service>` or `/hub <pr-url>` to start."
3. Build tree output:

```
Status Hub
|
+- FOREGROUND
|  +- #1  PR #17163  [icon] [state]  [detail]  [NEW]
|  +- #2  PR #17042  [icon] [state]  [detail]
|  \- #3  PR #16998  [icon] [state]  [detail]
|
\- BACKGROUND
   \- #4  [icon] [service]: [title] - [detail]

Tip: /hub ack #1  |  /hub manage
```

## Foreground Items

For each PR in `config.foreground`:
1. Refresh status via `gh pr view`
2. Compare to `lastSeen` state
3. Mark as `[NEW]` if:
   - Comments increased
   - State changed
   - Review decision changed
   - Checks status changed
4. Display: `#N  PR #<number>  <icon> <state>  <detail>`

## Background Item

If `config.background` exists:
1. Get current status from browser tab (if available)
2. Display: `#N  <icon> <service>: <title> - <detail>`

## Icons

| Icon | Meaning |
|------|---------|
| > | Playing |
| \|\| | Paused |
| M | Mail/Gmail |
| ✓ | PR Approved |
| ? | PR Review needed |
| ! | Changes requested |
| X | Checks failing |
| ~ | Checks pending |
| D | Draft |
