# Hub Ack Focus - Focus/Break Contextual Actions

Handle focus mode alerts with context-aware actions.

## Alert Types

This skill handles:
1. **Break reminders** - When focus duration >= breakAfterMinutes
2. **Meeting interruptions** - When a meeting is starting during focus
3. **VIP messages** - When allowed VIP messages arrive during focus

---

## Case A: Break Reminder

Triggered when focus has been active for `breakAfterMinutes` (default 75) and there's a gap before next meeting.

### Step 1: Gather Context

```bash
# Read focus state
focus_state=$(jq '.focus' ~/.claude/status-config.json)

# Calculate duration
start_time=$(echo "$focus_state" | jq -r '.startTime')
now_ms=$(($(date +%s) * 1000))
duration_min=$(( (now_ms - start_time) / 60000 ))

# Get next meeting
next_meeting=$(jq -r '.calendar.lastSeen[0] // null' ~/.claude/status-config.json)
```

### Step 2: Present Break Options

```
☕ Great focus session! <N> minutes of deep work.

   📊 Session stats:
      • Duration: <duration>
      • Next: <meeting> at <time> (<N> min)

   [1] Take break, set Slack "☕ Back at <time>"
   [2] Take break, no status change
   [3] Keep working, remind in 15m
   [d] Dismiss
```

Use AskUserQuestion:

```json
{
  "questions": [{
    "question": "☕ Great focus! <N> min of deep work. Next: <meeting> in <N>m. What would you like to do?",
    "header": "Break",
    "options": [
      {"label": "Break + status", "description": "Set Slack ☕ Back at <time>"},
      {"label": "Break quietly", "description": "No status change"},
      {"label": "Remind in 15m", "description": "Keep working"},
      {"label": "Dismiss", "description": "No break needed"}
    ],
    "multiSelect": false
  }]
}
```

### Step 3: Handle Selection

**Option 1 - Break + status:**
1. Set Slack status using tool-slack.md patterns
2. Update focus state: `active: false`
3. Show confirmation

**Option 2 - Break quietly:**
1. Update focus state: `active: false`
2. Show confirmation without status change

**Option 3 - Remind in 15m:**
1. Update config: `lastBreakReminder: <now + 15min>`
2. Daemon will re-trigger after 15 minutes

**Option 4 - Dismiss:**
1. Update config: `lastBreakReminder: <now>`
2. No further action

---

## Case B: Meeting Starting During Focus

Triggered when a meeting starts within 5 minutes and focus is active.

### Step 1: Gather Context

```bash
# Get meeting details from alert
meeting=$(jq -r '.calendar.lastSeen[] | select(.hasAlert == true)' ~/.claude/status-config.json)
meeting_title=$(echo "$meeting" | jq -r '.title')
meeting_time=$(echo "$meeting" | jq -r '.startTime')
minutes_until=$(( (meeting_time - $(date +%s)*1000) / 60000 ))
```

### Step 2: Present Options

```
⏰ Focus interrupted - <meeting> starting in <N> min

   [1] End focus, join meeting
   [2] Extend focus, skip meeting + DM organizer
   [3] Snooze 5 min
```

Use AskUserQuestion:

```json
{
  "questions": [{
    "question": "⏰ <meeting> starting in <N>m. Focus will be interrupted.",
    "header": "Meeting",
    "options": [
      {"label": "End focus", "description": "Clear status, join meeting"},
      {"label": "Skip meeting", "description": "DM organizer, extend focus"},
      {"label": "Snooze 5m", "description": "Remind again shortly"}
    ],
    "multiSelect": false
  }]
}
```

### Step 3: Handle Selection

**Option 1 - End focus:**
1. Clear Slack status (use tool-slack.md)
2. Update focus state: `active: false`
3. Route to hub-ack-calendar.md for join flow

**Option 2 - Skip meeting:**
1. DM organizer (use hub-ack-calendar.md late message flow)
2. Extend focus end time
3. Mark meeting as declined/skipped

**Option 3 - Snooze:**
1. Mark alert as snoozed for 5 minutes
2. Will re-alert after snooze period

---

## Case C: VIP Message During Focus

Only triggered if `focus.allowVipDms: true` in config.

### Step 1: Gather Context

```bash
# Get VIP message details from Slack alert
vip_msg=$(jq -r '.slack.lastVipMessage' ~/.claude/status-config.json)
sender=$(echo "$vip_msg" | jq -r '.from')
preview=$(echo "$vip_msg" | jq -r '.preview')
```

### Step 2: Present Options

```
💬 VIP message from <person> during focus

   "<preview of message...>"

   [1] View message (pause focus)
   [2] Reply "In focus, will respond at <end_time>"
   [3] Dismiss (stay focused)
```

Use AskUserQuestion:

```json
{
  "questions": [{
    "question": "💬 VIP from <person>: \"<preview>\"",
    "header": "VIP",
    "options": [
      {"label": "View message", "description": "Pause focus to read"},
      {"label": "Quick reply", "description": "\"In focus, back at <time>\""},
      {"label": "Stay focused", "description": "Dismiss notification"}
    ],
    "multiSelect": false
  }]
}
```

### Step 3: Handle Selection

**Option 1 - View message:**
1. Pause focus (don't end)
2. Open Slack channel/DM in browser
3. Let user handle manually

**Option 2 - Quick reply:**
1. Send canned response via tool-slack.md
2. Mark message as handled
3. Continue focus

**Option 3 - Stay focused:**
1. Mark message as seen
2. Continue focus without interruption

---

## End Focus Early

When user runs `/hub-focus` during active focus and selects "End focus early":

1. Clear Slack status (if was set)
2. Update config:
   ```json
   {
     "focus": {
       "active": false,
       "lastEndTime": <now>,
       "lastDuration": <minutes>
     }
   }
   ```
3. Show summary:
   ```
   🎯 Focus session ended

      Duration: <N> minutes
      Status: Cleared

   Great work! 👍
   ```

---

## Config Fields Used

```json
{
  "focus": {
    "active": true,
    "startTime": 1234567890000,
    "endTime": 1234567890000,
    "breakAfterMinutes": 75,
    "lastBreakReminder": 0,
    "allowVipDms": false,
    "slackStatusSet": true
  }
}
```

---

## Error Handling

If Slack status operations fail:
1. Log error but don't block the flow
2. Inform user: "⚠️ Couldn't update Slack status, but focus state updated"
3. Continue with remaining actions

If config read fails:
1. Show error via update-bridge.sh --error
2. Offer to retry or cancel
