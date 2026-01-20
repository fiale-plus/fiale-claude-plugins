# Hub Focus - Smart Focus Mode

Proactive focus mode that checks calendar and offers smart options.

## Step 1: Check Calendar for Conflicts

First, get upcoming meetings:

If calendar is configured with browser tab:
```javascript
// Run via javascript_tool on calendar tab
// Same extraction as hub-refresh-calendar.md
```

Or parse the calendar lastSeen data from config:
```bash
cat ~/.claude/status-config.json | jq '.calendar.lastSeen'
```

## Step 2: Read Focus Config

```bash
cat ~/.claude/status-config.json | jq '.focus // {}'
```

Get defaults:
- `defaultDurationHours` (default: 2)
- `meetingConflictHandling` (default: "ask")
- `criticalChannels` (default: [])
- `defaultStatus` (default: "🎯 Deep focus until {end_time}")
- `defaultDeclineMessage`

## Step 3: Calculate Conflicts

```javascript
const now = Date.now();
const focusDurationMs = config.focus.defaultDurationHours * 60 * 60 * 1000;
const focusEndTime = now + focusDurationMs;

const conflicts = meetings.filter(m => {
  const start = m.startTime;
  return start > now && start < focusEndTime;
});
```

## Step 4: Present Smart Options

### No Conflicts

```
🎯 Starting Focus Mode

   📅 No meetings for the next <N> hours

   Focus duration:
   [1] 30 minutes
   [2] 1 hour
   [3] 2 hours (default)
   [4] Until next meeting (<time>)
   [c] Custom duration...
   [x] Cancel
```

### With Conflicts

```
🎯 Starting Focus Mode

   📅 Calendar check:
      • <time1> - <meeting1> (in <N> min)
      • <time2> - <meeting2> (in <N> min)

   How long do you want to focus?
   [1] 30 minutes (no conflicts)
   [2] 1 hour (conflicts with <meeting1>)
   [3] 2 hours (conflicts with <meeting1> + <meeting2>)
   [4] Until next meeting (<N> min)
   [c] Custom duration...
   [x] Cancel
```

## Step 5: Handle Meeting Conflicts

If user selects duration with conflicts, handle each:

```
🎯 Focus Mode - Meeting Conflicts

   Your <duration> focus block conflicts with:

   📅 <time> - <meeting1>
      Organizer: <organizer>
      [1] Decline + DM "<default decline message>"
      [2] Decline + custom message...
      [3] Keep meeting (will interrupt focus)

   📅 <time> - <meeting2>
      [1] Decline + DM "<default decline message>"
      [2] Decline + custom message...
      [3] Keep meeting
```

### Declining Meetings

For browser-based calendar:
- Navigate to the meeting in calendar tab
- Provide instructions for manual decline

For DM:
- Same flow as hub-ack-calendar late message

## Step 6: Configure Notifications During Focus

```
🎯 Focus Mode - Notifications

   During focus, what should still alert you?

   [x] Critical channels: <list from config>
   [ ] VIP DMs (from configured VIPs)
   [ ] All DMs
   [ ] @mentions in any channel

   Slack status during focus:
   (x) "<default status>"
   ( ) "🔇 Do not disturb"
   ( ) Custom: [                    ]

   [Continue] [Cancel]
```

## Step 7: Activate Focus Mode

Store focus state in config:

```json
{
  "focus": {
    "active": true,
    "startTime": 1234567890000,
    "endTime": 1234567890000,
    "suppressedChannels": ["#general"],
    "allowedChannels": ["#incidents"],
    "declinedMeetings": ["meeting-id-1"]
  }
}
```

Update Slack status if configured (via browser tab):

```javascript
// Navigate to Slack status picker and set status
// This is a manual process - provide instructions
```

## Step 8: Confirm Focus Mode

```
🎯 Focus Mode Active

   Duration: <N> hours (until <time>)
   Meetings handled: <N> declined
   Alerts: Only <critical channels>

   Slack status: "<status message>"

   Run /hub-focus again to:
   [End focus early] [Extend 30m]
```

## Focus Mode Already Active

If `/hub-focus` is run while focus is active:

```
🎯 Focus Mode Active (since <time>)

   Remaining: <N> minutes (until <end_time>)

   [1] End focus early
   [2] Extend 30 minutes
   [3] Extend 1 hour
   [d] Keep current settings
```

## Break Reminder Integration

When focus has been active for `breakAfterMinutes` (default 75) and there's a gap before next meeting:

Trigger alert (via hub-refresh):
```
☕ Great focus! <N> min of deep work. Break window: <N>m before <meeting>
```

Then `/hub-ack` routes to break wizard.

## Error Handling

If calendar unavailable:
```
🎯 Starting Focus Mode

   ⚠️ Calendar not connected - cannot check for conflicts

   Focus without calendar check?
   [1] Yes, start focus anyway
   [2] No, set up calendar first (/hub-setup)
   [x] Cancel
```
