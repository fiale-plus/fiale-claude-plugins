# Tool: Google Calendar

Browser-based Google Calendar operations via Chrome MCP or Playwright.

## Connection Hierarchy

1. **Chrome MCP** (primary) - Requires open Google Calendar tab
2. **Playwright** (fallback) - Headless browser automation

See `connection-detect.md` for detection logic.

## Config Structure

Calendar config in `~/.claude/status-config.json`:

```json
{
  "calendar": {
    "connection": "auto",
    "chrome": { "tabId": 12345 },
    "playwright": { "profile": "default", "headless": false },
    "alertMinutesBefore": 5,
    "alertWithDocsBefore": 10,
    "lateMessageTo": "organizer"
  }
}
```

## Chrome MCP Mode

### Prerequisites

- Google Calendar open in a browser tab
- Claude-in-Chrome extension installed
- Tab ID stored in `calendar.chrome.tabId`

### Data Extraction Script

Run via `mcp__claude-in-chrome__javascript_tool`:

```javascript
(() => {
  const events = [];
  const now = new Date();
  const today = now.toISOString().split('T')[0];

  // Find events in day/schedule view
  const eventEls = document.querySelectorAll('[data-eventid], [data-eventchip]');

  eventEls.forEach(el => {
    try {
      // Get event title from aria-label or text content
      const ariaLabel = el.getAttribute('aria-label') || '';
      const title = ariaLabel.split(',')[0] ||
                    el.innerText?.split('\n')[0] ||
                    'Unknown Event';

      // Extract time from aria-label
      const timeMatch = ariaLabel.match(/(\d{1,2}(?::\d{2})?\s*(?:AM|PM|am|pm)?)/);

      // Look for meeting links
      const meetLink = el.querySelector('a[href*="meet.google.com"]')?.href ||
                       el.querySelector('a[href*="zoom.us"]')?.href ||
                       el.querySelector('a[href*="teams.microsoft.com"]')?.href || '';

      // Get event ID for deduplication
      const eventId = el.getAttribute('data-eventid') ||
                      el.getAttribute('data-eventchip') ||
                      title.substring(0, 20);

      // Check for attachments
      const hasAttachments = el.querySelector('[aria-label*="attachment"]') !== null ||
                             ariaLabel.includes('attachment');

      if (title && title !== 'Unknown Event') {
        events.push({
          id: eventId,
          title: title.substring(0, 50),
          time: timeMatch ? timeMatch[1] : null,
          meetingLink: meetLink,
          hasAttachments: hasAttachments,
          ariaLabel: ariaLabel.substring(0, 200)
        });
      }
    } catch (e) {
      // Skip malformed events
    }
  });

  // Deduplicate by ID
  const seen = new Set();
  return events.filter(e => {
    if (seen.has(e.id)) return false;
    seen.add(e.id);
    return true;
  }).slice(0, 10);
})()
```

### Usage Example

```javascript
// 1. Get or verify tab context
const context = await mcp__claude-in-chrome__tabs_context_mcp({ createIfEmpty: false });
const tabId = config.calendar.chrome.tabId;

// 2. Verify tab is on Google Calendar
const pageText = await mcp__claude-in-chrome__get_page_text({ tabId });
if (!pageText.includes('calendar.google.com')) {
  // Tab may have navigated away, need to refresh
  await mcp__claude-in-chrome__navigate({ tabId, url: 'https://calendar.google.com' });
}

// 3. Extract events
const events = await mcp__claude-in-chrome__javascript_tool({
  action: 'javascript_exec',
  tabId: tabId,
  text: extractionScript
});
```

## Playwright Mode

### Prerequisites

- Playwright MCP installed (`npx @playwright/mcp@latest`)
- Google account logged in (via persistent profile)

### Profile Setup

Playwright uses persistent browser profiles for authentication:

```bash
# First-time setup: log into Google manually
npx playwright open --save-storage=~/.claude/playwright-profile https://calendar.google.com
```

### Data Extraction

```javascript
// 1. Navigate to Google Calendar
await mcp__playwright__browser_navigate({
  url: 'https://calendar.google.com'
});

// 2. Wait for page load
await mcp__playwright__browser_wait({
  selector: '[data-eventid]',
  timeout: 10000
});

// 3. Execute extraction script
const events = await mcp__playwright__browser_evaluate({
  expression: extractionScript
});

// 4. Take screenshot for verification (optional)
const screenshot = await mcp__playwright__browser_screenshot();
```

### Headless vs Headed

- `headless: false` - Shows browser window, useful for debugging
- `headless: true` - No visible window, better for background refresh

Configure in `calendar.playwright.headless`.

## Time Parsing

Convert extracted time strings to timestamps:

```javascript
function parseEventTime(timeStr, baseDate = new Date()) {
  if (!timeStr) return null;

  // Handle formats: "2:30 PM", "14:30", "2pm", "2:30pm"
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

## Output Format

Standardized format for hub integration:

```json
{
  "events": [
    {
      "id": "event_abc123",
      "title": "Team Standup",
      "startTime": 1705344000000,
      "meetingLink": "https://meet.google.com/xxx-yyyy-zzz",
      "hasAttachments": false,
      "organizer": "alice@company.com"
    }
  ],
  "nextMeeting": {
    "title": "Team Standup",
    "startTime": 1705344000000,
    "minutesUntil": 15,
    "meetingLink": "https://meet.google.com/xxx-yyyy-zzz"
  }
}
```

## Alert Detection

Check if any meeting needs an alert:

```javascript
function checkAlerts(events, config) {
  const now = Date.now();
  const alertMinutes = config.calendar?.alertMinutesBefore || 5;
  const alertWithDocs = config.calendar?.alertWithDocsBefore || 10;

  for (const event of events) {
    if (!event.startTime) continue;

    const minutesUntil = (event.startTime - now) / 60000;
    const threshold = event.hasAttachments ? alertWithDocs : alertMinutes;

    if (minutesUntil > 0 && minutesUntil <= threshold) {
      return {
        shouldAlert: true,
        event: event,
        minutesUntil: Math.round(minutesUntil)
      };
    }
  }

  return { shouldAlert: false };
}
```

## Error Handling

### Chrome Tab Issues

| Error | Cause | Solution |
|-------|-------|----------|
| Tab not found | Tab closed or ID stale | Re-run `/hub-setup-gcalendar` |
| Wrong page | Tab navigated away | Navigate back to calendar |
| No events found | Calendar view issue | Try different view (day/schedule) |

### Playwright Issues

| Error | Cause | Solution |
|-------|-------|----------|
| Not logged in | Session expired | Re-login via `/hub-setup-gcalendar` |
| Timeout | Slow load | Increase timeout or retry |
| MCP unavailable | Playwright not installed | Run `npx @playwright/mcp@latest` |

## Fallback Strategy

```javascript
async function getCalendarEvents(config) {
  const connection = await detectCalendarConnection(config);

  switch (connection.method) {
    case 'chrome':
      return await getEventsViaChrome(config, connection.tabId);

    case 'playwright':
      return await getEventsViaPlaywright(config);

    case 'unavailable':
      throw new Error('Calendar: No connection available. Run /hub-setup-gcalendar');

    case 'disabled':
      return { events: [], disabled: true };
  }
}
```

## Troubleshooting

### Playwright Cache Issues

If Playwright has authentication or browser issues:

```bash
# Clear Playwright cache
rm -rf ~/.cache/ms-playwright      # Linux
rm -rf ~/Library/Caches/ms-playwright  # macOS

# Re-login
npx playwright open --save-storage=~/.claude/playwright-profile https://calendar.google.com
```

### Chrome Extension Issues

1. Verify extension is installed and enabled
2. Check that tab group permissions allow calendar access
3. Try creating a new tab via `/hub-setup-gcalendar`
