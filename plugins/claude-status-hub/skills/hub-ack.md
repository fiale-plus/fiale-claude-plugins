# Hub Ack - Contextual Action Dispatcher

Handle alerts with context-aware actions. Routes to service-specific ack skills.

## Step 1: Clear Error

```bash
${CLAUDE_PLUGIN_ROOT}/bin/update-bridge.sh --clear-error
```

## Step 2: Read State

```bash
cat /tmp/status-hub.json
cat ~/.claude/status-config.json
```

Find items with `hasAlert: true`.

## Step 3: Priority Order

1. `github-pr` CI failures (X)
2. `github-pr` conflicts (⚡)
3. `github-pr` merge-ready (🚀)
4. `calendar` meetings
5. `focus` break/interruptions
6. `slack` VIP messages
7. `github-pr` review activity
8. Other

## Step 4: Route to Skill

| Service | Skill |
|---------|-------|
| github-pr | hub-ack-github-pr.md |
| calendar | hub-ack-calendar.md |
| focus | hub-ack-focus.md |
| slack | hub-ack-slack.md |
| finance | Just dismiss |

Check for user-authored `.user.md` variants too.

## Step 5: No Alerts

```
✓ No pending alerts
<list items with current state>
[r] Refresh  [d] Done
```

## Step 6: Multiple Alerts

```
📬 N alerts:
[1] <icon> <service>: <brief>
[2] ...
[a] Handle all  [d] Dismiss all
```

## Step 7: Update After Ack

See `lib-common.md` for config update and bridge update patterns. Bridge must be updated immediately for statusline.
