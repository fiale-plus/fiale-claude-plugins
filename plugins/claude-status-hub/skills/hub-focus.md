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

### Create Calendar Focus Block (Optional)

Offer to block focus time in calendar:

```
📅 Block focus time in calendar?

   This creates a "Focus Time" event others can see.

   [1] Yes, create "🎯 Focus Time" event
   [2] Yes, create "Busy" event (no details)
   [n] No, don't block calendar
```

If user selects yes, create calendar event via browser:

```javascript
// Navigate to Google Calendar and create quick event
// URL format: https://calendar.google.com/calendar/render?action=TEMPLATE&text=Focus%20Time&dates=<start>/<end>

const startISO = new Date(startTime).toISOString().replace(/[-:]/g, '').split('.')[0] + 'Z';
const endISO = new Date(endTime).toISOString().replace(/[-:]/g, '').split('.')[0] + 'Z';
const title = encodeURIComponent('🎯 Focus Time');
const url = `https://calendar.google.com/calendar/render?action=TEMPLATE&text=${title}&dates=${startISO}/${endISO}`;
```

Or use `mcp__claude-in-chrome__navigate` to open the quick-add URL.

### Update Slack Status

Update Slack status if configured. Use connection method from `slack.connection` in config.

#### Slack MCP Mode

```javascript
// Calculate expiration timestamp
const focusEndTime = config.focus.endTime;
const expirationUnix = Math.floor(focusEndTime / 1000);

// Set status with auto-expiration
await mcp__slack__set_status({
  status_text: config.focus.defaultStatus.replace('{end_time}', endTimeFormatted),
  status_emoji: ":dart:",
  status_expiration: expirationUnix
});
```

#### Chrome MCP Mode

```javascript
// 1. Get Slack tab
const tabId = config.slack.chrome.tabId;

// 2. Click profile/avatar button to open menu
const profileBtn = await mcp__claude-in-chrome__find({
  tabId: tabId,
  query: "profile picture button or user avatar in top right"
});
await mcp__claude-in-chrome__computer({
  action: "left_click",
  ref: profileBtn.elements[0].ref,
  tabId: tabId
});

// 3. Wait for menu, then click "Update your status"
await mcp__claude-in-chrome__computer({ action: "wait", duration: 0.5, tabId });
const statusOption = await mcp__claude-in-chrome__find({
  tabId: tabId,
  query: "Update your status menu item"
});
await mcp__claude-in-chrome__computer({
  action: "left_click",
  ref: statusOption.elements[0].ref,
  tabId: tabId
});

// 4. Wait for status modal, type status text
await mcp__claude-in-chrome__computer({ action: "wait", duration: 0.5, tabId });
const statusInput = await mcp__claude-in-chrome__find({
  tabId: tabId,
  query: "status text input field"
});
await mcp__claude-in-chrome__form_input({
  tabId: tabId,
  ref: statusInput.elements[0].ref,
  value: statusText
});

// 5. Set emoji (click emoji picker, search for dart/target)
const emojiBtn = await mcp__claude-in-chrome__find({
  tabId: tabId,
  query: "emoji picker button in status modal"
});
await mcp__claude-in-chrome__computer({
  action: "left_click",
  ref: emojiBtn.elements[0].ref,
  tabId: tabId
});
// Search and select :dart: emoji

// 6. Set "Clear after" to focus end time if available
// Look for duration dropdown and set appropriately

// 7. Save status
const saveBtn = await mcp__claude-in-chrome__find({
  tabId: tabId,
  query: "Save button in status modal"
});
await mcp__claude-in-chrome__computer({
  action: "left_click",
  ref: saveBtn.elements[0].ref,
  tabId: tabId
});
```

#### API Mode

```bash
# Calculate expiration
focus_end=$(jq -r '.focus.endTime' ~/.claude/status-config.json)
expiry_unix=$((focus_end / 1000))

# Format end time for display
end_time_formatted=$(date -r $expiry_unix "+%l:%M %p" | xargs)

# Get status template and substitute
status_template=$(jq -r '.focus.defaultStatus // "🎯 Deep focus until {end_time}"' ~/.claude/status-config.json)
status_text="${status_template//\{end_time\}/$end_time_formatted}"

# Set status using tool-slack.md pattern
slack_set_status ":dart:" "$status_text" "$expiry_unix"
```

#### Record Status Was Set

After setting status, update config to track it was set:

```bash
jq '.focus.slackStatusSet = true' ~/.claude/status-config.json > /tmp/config.tmp && \
  mv /tmp/config.tmp ~/.claude/status-config.json
```

This allows hub-ack-focus.md to know whether to clear status when ending focus.

#### Trigger Contextual Music

After activating focus, trigger focus music if enabled:

```bash
${CLAUDE_PLUGIN_ROOT}/bin/music-event.sh "focus_started" &
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
