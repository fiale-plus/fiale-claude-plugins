---
name: hub-ack
description: Acknowledge hub alerts
argument-hint: [#N|all]
---

# Hub Acknowledge

Mark alerts as seen so they no longer show as `[NEW]`.

## Parse Argument

- `ack` or `ack all` - Acknowledge all foreground items
- `ack #N` - Acknowledge specific item by number

## Process

1. Read `~/.claude/status-config.json`
2. For targeted item(s):
   - Update `lastSeen.comments` to current count
   - Update `lastSeen.state` to current state
   - Update `lastSeen.reviewDecision` to current
   - Update `lastSeen.checksStatus` to current
   - Set `hasAlert: false`
3. Write updated config
4. Update bridge file `/tmp/status-hub.json`:
   - Set `timestamp` to current time (milliseconds)
   - Update matching item(s) in `foreground` array with `hasAlert: false`
5. Say "Acknowledged [item description]" or "All alerts acknowledged"

## Example Config Update

Before:
```json
{
  "foreground": [{
    "type": "github-pr",
    "number": 17163,
    "lastSeen": { "comments": 2 },
    "hasAlert": true
  }]
}
```

After `/hub ack #1`:
```json
{
  "foreground": [{
    "type": "github-pr",
    "number": 17163,
    "lastSeen": { "comments": 5 },
    "hasAlert": false
  }]
}
```
