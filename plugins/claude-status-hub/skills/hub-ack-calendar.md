# Hub Ack - Calendar Meeting Actions

Handle calendar meeting alerts with time-aware contextual actions.

## Input

Receives calendar item with: `title`, `startTime`, `meetingLink` (always show full URL), `organizer`, `tabId`, `hasAttachments`

## Step 1: Calculate Time Context

```javascript
const diffMinutes = Math.round((startTime - Date.now()) / 60000);
const alertWithDocsBefore = config.calendar?.alertWithDocsBefore || 10;
```

Cases:
- **A**: `5 < diff <= alertWithDocsBefore` and `hasAttachments` (upcoming with prep)
- **B**: `-5 <= diff <= 5` (starting now)
- **C**: `-30 <= diff < -5` (started)
- **D**: `diff < -30` (late ack)

## Step 2: Show Time-Appropriate Wizard

### Case A: Meeting Upcoming (prep time)

```
📅 <title> - in <N> min
   📎 Has attachments

   🔗 <meetingLink>

   [1] Join early
   [2] Remind in 2 min
   [3] DM: "I'll be ~5 min late"
   [d] Dismiss
```

### Case B: Starting Now

```
📅 <title> - starting NOW

   🔗 <meetingLink>

   [1] Join meeting
   [2] DM: "Joining in 5 min"
   [3] DM: "Running late, ~10 min"
   [c] Custom message
   [d] Dismiss

   📋 Context handoff prints below if you join.
```

### Case C: Meeting Started

```
📅 <title> - started <N> min ago

   🔗 <meetingLink>

   [1] Join now
   [2] DM: "Joining in a moment"
   [3] DM: "Can we catch up async?"
   [d] Dismiss
```

### Case D: Late Ack

```
📅 <title> - ended <N> min ago

   📋 What you were working on: <context>

   [1] Dismiss
   [2] DM: "Sorry I missed this!"
```

## Message Templates

| Situation | Message |
|-----------|---------|
| ~5 min late | "Hey! I'll be joining in about 5 minutes" |
| ~10 min late | "Running a bit behind, ~10 min" |
| Joining | "On my way! Joining in a moment" |
| Can't make | "Won't make it - can we catch up async?" |
| Missed | "Sorry I missed this! Let me know if you need anything" |

Customizable in `calendar.lateMessages` config.

## Step 3: Execute Action

### Join Meeting

Open link in browser:
```javascript
mcp__claude-in-chrome__navigate({ url: meetingLink, tabId: <new or existing> })
```
Then print context handoff.

### DM Organizer

1. If `slack.chrome.tabId` configured:
   - Navigate to DM: `https://<workspace>.slack.com/messages/<user-id>`
   - Type message (don't send)
   - Tell user: "Message typed. Press Enter to send."

2. Fallback: copy to clipboard
   ```bash
   echo "<message>" | pbcopy  # macOS
   ```

## Step 4: Context Handoff

When joining or acking late:
```
📋 Session Context
━━━━━━━━━━━━━━━━━━━━
   Project: <cwd>
   Recent: <git status summary>
   Todos: <in_progress items>
━━━━━━━━━━━━━━━━━━━━
```

## Step 5: Update Config and Bridge

Update `lastSeen.startTime`, set `hasAlert: false`, then update bridge immediately (see hub-ack-github-pr.md Step 4b pattern).

## Extracting Meeting Link

If `meetingLink` missing but meeting exists:

1. Click event to open popup
2. Extract from popup: `a[href*="meet.google.com"]`, `a[href*="zoom.us"]`, or text match
3. Close popup with Escape

If still not found: offer to open calendar tab.

## Error Handling

- Missing link: "[1] Open calendar tab [d] Dismiss"
- No calendar tab: "Run /hub-setup to configure"
