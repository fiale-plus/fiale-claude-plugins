# Hub Focus - Smart Focus Mode

Proactive focus mode with calendar awareness.

## Step 1: Check Calendar

Get upcoming meetings from `calendar.lastSeen` in config or extract via browser (see `tool-gcalendar.md`).

## Step 2: Read Focus Config

```bash
cat ~/.claude/status-config.json | jq '.focus // {}'
```

Defaults: `defaultDurationHours` (2), `meetingConflictHandling` ("ask"), `criticalChannels` ([]), `defaultStatus` ("🎯 Deep focus until {end_time}").

## Step 3: Calculate Conflicts

```javascript
const focusEndTime = Date.now() + config.focus.defaultDurationHours * 3600000;
const conflicts = meetings.filter(m => m.startTime > Date.now() && m.startTime < focusEndTime);
```

## Step 4: Present Options

**No conflicts:**
```
🎯 Starting Focus Mode
   📅 No meetings for next <N> hours
   [1] 30 min  [2] 1 hour  [3] 2 hours (default)  [4] Until next meeting  [c] Custom  [x] Cancel
```

**With conflicts:** Show conflicting meetings, offer adjusted durations.

## Step 5: Handle Meeting Conflicts

For each conflict, offer: Decline + DM, Keep meeting (interrupt focus).

## Step 6: Configure Notifications

Offer options for what alerts during focus: critical channels, VIP DMs, @mentions.

## Step 7: Activate Focus

Store in config:
```json
{ "focus": { "active": true, "startTime": <ms>, "endTime": <ms>, "suppressedChannels": [], "allowedChannels": [] } }
```

**Calendar block:** Offer to create focus event via `calendar.google.com/calendar/render?action=TEMPLATE&text=...`.

**Slack status:** Set via Slack MCP (`mcp__slack__set_status`) or Chrome MCP (navigate profile menu → status).

**Music:** Trigger `${CLAUDE_PLUGIN_ROOT}/bin/music-event.sh "focus_started" &`

## Step 8: Confirm

```
🎯 Focus Mode Active
   Duration: <N> hours (until <time>)
   Run /hub-focus again to: [End early] [Extend 30m]
```

## Focus Already Active

If run while active, offer: End early, Extend 30m/1h, Keep current.

## Error Handling

If calendar unavailable: "⚠️ Cannot check conflicts. Start anyway? [1] Yes [2] Setup first [x] Cancel"
