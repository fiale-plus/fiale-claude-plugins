# Hub Ack Focus - Focus/Break Contextual Actions

Handle focus mode alerts with context-aware actions.

## Alert Types

1. **Break reminders** - focus duration >= breakAfterMinutes
2. **Meeting interruptions** - meeting starting during focus
3. **VIP messages** - allowed VIP messages during focus

---

## Case A: Break Reminder

Triggered when focus active for `breakAfterMinutes` (default 75) with gap before next meeting.

```bash
start_time=$(jq -r '.focus.startTime' ~/.claude/status-config.json)
duration_min=$(( ($(date +%s)*1000 - start_time) / 60000 ))
```

```json
{
  "question": "☕ Great focus! <N>m of deep work. Next: <meeting> in <N>m",
  "header": "Break",
  "options": [
    {"label": "Break + status", "description": "Set Slack ☕ Back at <time>"},
    {"label": "Break quietly", "description": "No status change"},
    {"label": "Remind in 15m", "description": "Keep working"},
    {"label": "Dismiss", "description": "No break needed"}
  ]
}
```

**Actions:**
- Break + status → Set Slack status (tool-slack.md), `active: false`
- Break quietly → `active: false`
- Remind → `lastBreakReminder: <now + 15m>`
- Dismiss → `lastBreakReminder: <now>`

---

## Case B: Meeting During Focus

Triggered when meeting starts within 5 minutes and focus active.

```json
{
  "question": "⏰ <meeting> starting in <N>m. Focus will be interrupted.",
  "header": "Meeting",
  "options": [
    {"label": "End focus", "description": "Clear status, join meeting"},
    {"label": "Skip meeting", "description": "DM organizer, extend focus"},
    {"label": "Snooze 5m", "description": "Remind again shortly"}
  ]
}
```

**Actions:**
- End focus → Clear Slack, `active: false`, route to hub-ack-calendar
- Skip → DM organizer (hub-ack-calendar late flow), extend focus
- Snooze → Mark snoozed for 5 minutes

---

## Case C: VIP Message During Focus

Only if `focus.allowVipDms: true`.

```json
{
  "question": "💬 VIP from <person>: \"<preview>\"",
  "header": "VIP",
  "options": [
    {"label": "View message", "description": "Pause focus to read"},
    {"label": "Quick reply", "description": "\"In focus, back at <time>\""},
    {"label": "Stay focused", "description": "Dismiss notification"}
  ]
}
```

**Actions:**
- View → Pause focus, open Slack DM
- Quick reply → Send canned response, continue focus
- Stay focused → Mark seen, continue

---

## End Focus Early

Via `/hub-focus` during active focus:

1. Clear Slack status (if set)
2. Update: `active: false`, `lastEndTime: <now>`, `lastDuration: <minutes>`
3. Trigger contextual music:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/music-event.sh "focus_ended" &
   ```
4. Show: "🎯 Focus ended - <N> minutes. Great work!"

---

## Config Fields

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

- Slack status fails: Log error, continue with focus state update
- Config read fails: Show error via update-bridge.sh --error, offer retry
