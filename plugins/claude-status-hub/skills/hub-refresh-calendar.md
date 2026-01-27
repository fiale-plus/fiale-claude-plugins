# Hub Refresh - Calendar

Refresh calendar data using the configured connection method.

See `connection-detect.md` for detection logic and `tool-gcalendar.md` for extraction scripts.

## Refresh Flow

```javascript
async function refreshCalendar(config) {
  const connection = await detectCalendarConnection(config);

  if (connection.method === 'disabled') return { disabled: true };
  if (connection.method === 'unavailable') return { error: 'Run /hub-setup-gcalendar' };

  // Get events via Chrome or Playwright (see tool-gcalendar.md for scripts)
  const events = await refreshViaMethod(connection.method, config, connection.tabId);
  const result = processCalendarData(events, config);

  // If tab was auto-recovered, save updated config with new tabId
  if (connection.wasRecovered) result.configUpdated = true;

  return result;
}
```

**Auto-Recovery:** If the calendar tab was closed, `detectCalendarConnection` auto-opens it (see `connection-detect.md`). The new tabId is stored in `config.calendar.chrome.tabId` and should be persisted after successful refresh.

## Process Calendar Data

```javascript
function processCalendarData(events, config) {
  const now = Date.now();
  const alertMinutes = config.calendar?.alertMinutesBefore || 5;

  const parsed = events
    .map(e => ({ ...e, startTime: parseEventTime(e.time) }))
    .filter(e => e.startTime && e.startTime > now)
    .sort((a, b) => a.startTime - b.startTime);

  const nextMeeting = parsed[0] || null;
  let hasAlert = false;

  if (nextMeeting) {
    const minutesUntil = (nextMeeting.startTime - now) / 60000;
    hasAlert = minutesUntil > 0 && minutesUntil <= alertMinutes;
  }

  // Trigger contextual music when alert state changes to true
  if (hasAlert && !config.calendar?.lastSeen?.hasAlert) {
    // Bash: ${CLAUDE_PLUGIN_ROOT}/bin/music-event.sh "meeting_starting" &
  }

  return { events: parsed.slice(0, 5), nextMeeting, hasAlert };
}
```

## Output Format

**With alert (starting soon/now):**
```json
{
  "site": "calendar",
  "icon": "🔴",
  "title": "Team Standup",
  "detail": "NOW | meet.google.com/xxx-yyy",
  "hasAlert": true
}
```

**Upcoming (no alert):**
```json
{
  "site": "calendar",
  "icon": "📅",
  "title": "Team Standup",
  "detail": "in 15m",
  "hasAlert": false
}
```

Detail format:
- Alert + URL: `"NOW | https://meet.google.com/xxx"` or `"in 2m | https://meet.google.com/xxx"`
- Alert, no URL: `"NOW"` or `"in 2m"`
- No alert: `"in 15m"`

**Important:** Always include `https://` prefix for URLs - makes them clickable in terminal.

**No meetings:** Return `null` (don't add to foreground). Silence is the signal.

## Bridge Update

```bash
${CLAUDE_PLUGIN_ROOT}/bin/update-bridge.sh calendar '{"icon":"📅","title":"Team Standup","detail":"in 15m"}'
```

## Config Update

Store for ack:
```json
{ "calendar": { "lastSeen": { "nextMeeting": { "title": "...", "startTime": ..., "meetingLink": "..." } } } }
```
