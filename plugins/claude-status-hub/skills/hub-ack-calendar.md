# Hub Ack - Calendar Meeting Actions

Handle calendar meeting alerts with time-aware contextual actions.

## Input

Receives calendar item from dispatcher with:
- `title` - meeting name
- `startTime` - ISO timestamp or epoch ms
- `meetingLink` - Google Meet/Zoom URL (if available) - **always show full URL**
- `organizer` - meeting organizer name/email
- `tabId` - browser tab ID for calendar
- `hasAttachments` - whether meeting has docs/prep materials

## Step 1: Calculate Time Context

```javascript
const now = Date.now();
const start = new Date(item.startTime).getTime();
const diffMinutes = Math.round((start - now) / 60000);
```

Determine case:
- **Case A**: `diffMinutes > 5` (meeting upcoming) - **normally suppress these alerts**
- **Case B**: `diffMinutes >= -5 && diffMinutes <= 5` (meeting starting now)
- **Case C**: `diffMinutes < -5 && diffMinutes >= -30` (meeting started)
- **Case D**: `diffMinutes < -30` (late ack, meeting may have ended)

## Alert Threshold Policy

**Default**: Only alert when `diffMinutes <= 5` (meeting imminent or started)

**Exception - meetings with prep**:
- If `hasAttachments: true` (meeting has docs) → alert at configured `alertWithDocsBefore` (default 10min)
- Allows time to review materials before joining

```javascript
const shouldAlert = (
  diffMinutes <= 5 ||  // Always alert when imminent
  (item.hasAttachments && diffMinutes <= config.calendar.alertWithDocsBefore)
);
```

This prevents noise from meetings 30+ minutes away while ensuring prep meetings get early notice.

## Step 2: Show Time-Appropriate Wizard

### Case A: Meeting Upcoming (> 5min before)

**Note**: Only shown for meetings with prep materials (hasAttachments: true).

```
📅 <title> (<time>) - in <N> minutes
   Organizer: <organizer>
   📎 Has attachments to review

   🔗 <full meetingLink URL>

   [1] Join meeting now (early)
   [2] Set reminder for 2 min before
   [3] DM <organizer>: "Hey! I'll be ~5 min late"
   [d] Dismiss
```

### Case B: Meeting Starting (-5min to +5min)

```
📅 <title> - starting NOW

   🔗 <full meetingLink URL>

   [1] Join meeting
   [2] DM <organizer>: "Hey! Joining in about 5 minutes"
   [3] DM <organizer>: "Running a bit behind, ~10 min"
   [c] Custom message to <organizer>...
   [d] Dismiss

   📋 Context handoff will print below if you join.
```

### Case C: Meeting Started (+5min to +30min)

```
📅 <title> - started <N> minutes ago

   🔗 <full meetingLink URL>

   [1] Join now (late)
   [2] DM <organizer>: "On my way! Joining in a moment"
   [3] DM <organizer>: "Won't make it - can we catch up async?"
   [d] Dismiss
```

### Case D: Late Ack (> 30min after alert)

```
📅 <title> - ended <N> minutes ago

   📋 What you were working on when alert fired:
      <context from session>

   [1] Dismiss
   [2] DM <organizer>: "Sorry I missed this! Let me know if you need anything from me"
```

## Humanized Message Templates

Use natural, friendly language for all DM messages:

| Situation | Message |
|-----------|---------|
| ~5 min late | "Hey! I'll be joining in about 5 minutes" |
| ~10 min late | "Running a bit behind, should be there in ~10 min" |
| Joining shortly | "On my way! Joining in a moment" |
| Can't make it | "Won't be able to make it - can we catch up async?" |
| Missed meeting | "Sorry I missed this! Let me know if you need anything from me" |
| Custom late | "Hey! I'll be a bit late - [user reason]" |

These can be customized in config:
```json
{
  "calendar": {
    "lateMessages": {
      "5min": "Hey! I'll be joining in about 5 minutes",
      "10min": "Running a bit behind, should be there in ~10 min",
      "joining": "On my way! Joining in a moment",
      "skip": "Won't be able to make it - can we catch up async?",
      "missed": "Sorry I missed this! Let me know if you need anything from me"
    }
  }
}
```

## Step 3: Execute Selected Action

### Join Meeting

If user selects "Join meeting":

1. Open meeting link in browser:
   ```
   mcp__claude-in-chrome__navigate(url: meetingLink, tabId: <new tab or existing>)
   ```

2. Print context handoff (see Step 4)

### DM Organizer

If user selects a late message option:

1. Read Slack config to find organizer:
   ```bash
   cat ~/.claude/status-config.json | jq '.slack'
   ```

2. If Slack browser tab available, compose DM:
   - Navigate to Slack DM with organizer
   - Type message (but don't send - user confirms)

3. If no Slack, show message to copy:
   ```
   Message for <organizer>:
   "<message text>"

   [Copy to clipboard] [Cancel]
   ```

### Custom Message

If user selects custom message:
```
Enter message for <organizer>:
> [user input]

[Send] [Cancel]
```

## Step 4: Context Handoff

When user joins meeting OR acks late, provide session context:

```
📋 Session Context Handoff
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   Project: <current working directory name>
   Working on: <recent file if available>

   Recent activity:
   • <summary of recent work from session>

   Open todos:
   • <any in_progress todos from TodoWrite>

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

To gather context:
1. Get current working directory
2. Check git status for recent changes
3. Read any active todos

## Step 5: Update Config

After successful action:
- Update `lastSeen.startTime` to current meeting
- Set `hasAlert: false`
- Write updated config

## Error Handling

If meeting link is missing:
```
📅 <title> - <time context>

   ⚠️ No meeting link found

   [1] Open calendar tab to find link
   [d] Dismiss
```

If calendar tab unavailable:
```
⚠️ Calendar tab not found

   Run /hub-setup to configure calendar integration.

   [d] Dismiss
```
