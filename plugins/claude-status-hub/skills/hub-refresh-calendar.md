# Hub Refresh - Calendar

Refresh calendar data using the configured connection method (Chrome MCP or Playwright).

## Connection Detection

Check `calendar.connection` in config. If "auto", detect available method.

See `connection-detect.md` for detection logic and `tool-gcalendar.md` for implementation details.

## Config Structure

See `connection-detect.md` for full config schema.

## Refresh Flow

```javascript
async function refreshCalendar(config) {
  // 1. Detect connection method
  const connection = await detectCalendarConnection(config);

  if (connection.method === 'disabled') {
    return { disabled: true };
  }

  if (connection.method === 'unavailable') {
    return { error: 'No connection available. Run /hub-setup-gcalendar' };
  }

  // 2. Get events via appropriate method
  let events;
  if (connection.method === 'chrome') {
    events = await refreshViaChrome(config, connection.tabId);
  } else if (connection.method === 'playwright') {
    events = await refreshViaPlaywright(config);
  }

  // 3. Process and return
  return processCalendarData(events, config);
}
```

## Chrome MCP Mode

### Prerequisites

- Google Calendar open in a browser tab
- Tab ID stored in `calendar.chrome.tabId`
- Chrome MCP available

### Data Extraction

See `tool-gcalendar.md` for the JavaScript extraction script.

### Usage

```javascript
async function refreshViaChrome(config, tabId) {
  // Verify tab context
  const context = await mcp__claude-in-chrome__tabs_context_mcp({ createIfEmpty: false });

  if (!tabId) {
    throw new Error('Calendar tab not configured. Run /hub-setup-gcalendar');
  }

  // Try JavaScript extraction first (works in day/week/month views)
  let events = await mcp__claude-in-chrome__javascript_tool({
    action: 'javascript_exec',
    tabId: tabId,
    text: extractionScript
  });

  // Fallback: Accessibility extraction (required for agenda view)
  // Agenda view renders events in cross-origin iframes that block JS access
  if (!events || events.length === 0) {
    const pageData = await mcp__claude-in-chrome__read_page({ tabId, filter: 'interactive' });
    events = parseAccessibilityEvents(pageData);
  }

  return events;
}

// Parse events from read_page accessibility output
function parseAccessibilityEvents(pageData) {
  const events = [];
  // Look for button lines with time ranges
  // Format: button "С HH:MM до HH:MM, Title, Organizer, Location, Date" [ref_XX]
  const lines = pageData.split('\n');

  for (const line of lines) {
    // Match time range in button text
    const timeMatch = line.match(/(\d{1,2}:\d{2})\s*(?:до|to|-|–)\s*(\d{1,2}:\d{2})/i);
    if (!timeMatch) continue;

    // Extract quoted text from button
    const textMatch = line.match(/"([^"]+)"/);
    if (!textMatch) continue;

    const text = textMatch[1];
    const parts = text.split(',').map(p => p.trim());

    events.push({
      id: parts[1]?.substring(0, 20) + timeMatch[1],
      title: parts[1] || 'Untitled Event',
      time: timeMatch[1],
      organizer: parts[2] || '',
      meetingLink: '', // Need to click event to get link
      isAgendaView: true
    });
  }

  return events;
}
```

## Playwright Mode

### Prerequisites

- Playwright MCP installed
- Google account logged in via persistent profile

### Usage

```javascript
async function refreshViaPlaywright(config) {
  // Navigate to Google Calendar
  await mcp__playwright__browser_navigate({
    url: 'https://calendar.google.com'
  });

  // Wait for events to load
  await mcp__playwright__browser_wait({
    selector: '[data-eventid]',
    timeout: 10000
  });

  // Execute extraction script
  const events = await mcp__playwright__browser_evaluate({
    expression: extractionScript
  });

  return events;
}
```

## Time Parsing

Convert extracted time strings to timestamps:

```javascript
function parseEventTime(timeStr, baseDate = new Date()) {
  if (!timeStr) return null;

  const match = timeStr.match(/(\d{1,2})(?::(\d{2}))?\s*(AM|PM|am|pm)?/);
  if (!match) return null;

  let hours = parseInt(match[1], 10);
  const minutes = parseInt(match[2] || '0', 10);
  const meridiem = match[3]?.toUpperCase();

  if (meridiem === 'PM' && hours < 12) hours += 12;
  if (meridiem === 'AM' && hours === 12) hours = 0;

  const date = new Date(baseDate);
  date.setHours(hours, minutes, 0, 0);
  return date.getTime();
}
```

## Process Calendar Data

```javascript
function processCalendarData(events, config) {
  const now = Date.now();
  const alertMinutes = config.calendar?.alertMinutesBefore || 5;
  const alertWithDocs = config.calendar?.alertWithDocsBefore || 10;

  // Parse times and filter future events
  const parsed = events
    .map(e => ({
      ...e,
      startTime: parseEventTime(e.time)
    }))
    .filter(e => e.startTime && e.startTime > now)
    .sort((a, b) => a.startTime - b.startTime);

  const nextMeeting = parsed[0] || null;

  // Check for alerts
  let hasAlert = false;
  if (nextMeeting) {
    const minutesUntil = (nextMeeting.startTime - now) / 60000;
    const threshold = nextMeeting.hasAttachments ? alertWithDocs : alertMinutes;
    hasAlert = minutesUntil > 0 && minutesUntil <= threshold;
  }

  return {
    events: parsed.slice(0, 5),
    nextMeeting: nextMeeting,
    hasAlert: hasAlert
  };
}
```

## Output Format

Return for bridge/statusline:

```json
{
  "site": "calendar",
  "icon": "📅",
  "title": "Team Standup",
  "detail": "in 15m",
  "hasAlert": false,
  "data": {
    "startTime": 1234567890000,
    "meetingLink": "https://meet.google.com/...",
    "organizer": "alice@company.com"
  }
}
```

Icon options:
- `📅` = upcoming meeting
- `🔴` = meeting starting now or alert active
- `✓` = no upcoming meetings

## Update Config

Store detected meetings for ack:

```json
{
  "calendar": {
    "lastSeen": {
      "nextMeeting": {
        "title": "Team Standup",
        "startTime": 1234567890000,
        "meetingLink": "https://meet.google.com/...",
        "organizer": "alice@company.com"
      }
    }
  }
}
```

## Error Handling

### Chrome Tab Issues

If tab is unavailable or JS execution fails:

```javascript
if (connection.needsSetup) {
  return { error: 'Calendar tab not configured. Run /hub-setup-gcalendar' };
}
```

### Playwright Issues

If Playwright fails (not logged in, timeout):

```javascript
try {
  events = await refreshViaPlaywright(config);
} catch (e) {
  return { error: `Playwright error: ${e.message}. Run /hub-setup-gcalendar` };
}
```

### Fallback to Text Extraction

If DOM-based approach fails, try reading page text:

```javascript
const pageText = await mcp__claude-in-chrome__get_page_text({ tabId });
// Parse text for meeting information as backup
```

## Bridge Update

Update the bridge file with calendar status:

```bash
${CLAUDE_PLUGIN_ROOT}/bin/update-bridge.sh calendar '{"icon":"📅","title":"Team Standup","detail":"in 15m"}'
```

Or on error:

```bash
${CLAUDE_PLUGIN_ROOT}/bin/update-bridge.sh --error "Calendar: Tab not accessible"
```
