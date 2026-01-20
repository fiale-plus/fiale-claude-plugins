# Hub Refresh - Calendar (Browser-Based)

Refresh calendar data from Google Calendar browser tab via Chrome MCP.

## Config Structure

Calendar config in `~/.claude/status-config.json`:

```json
{
  "calendar": {
    "connection": "chrome",
    "chrome": { "tabId": 12345 },
    "alertMinutesBefore": 5,
    "alertWithDocsBefore": 10,
    "lateMessageTo": "organizer"
  }
}
```

## Prerequisites

- User must have Google Calendar open in a browser tab
- Tab ID stored in `calendar.chrome.tabId`
- Chrome MCP must be available

## Data Extraction

Run via `mcp__claude-in-chrome__javascript_tool` on calendar tab:

```javascript
(() => {
  const events = [];
  const now = new Date();
  const today = now.toISOString().split('T')[0];

  // Try to find events in the day view or schedule view
  const eventEls = document.querySelectorAll('[data-eventid], [data-eventchip]');

  eventEls.forEach(el => {
    try {
      // Get event title
      const title = el.getAttribute('aria-label') ||
                    el.innerText?.split('\\n')[0] ||
                    'Unknown Event';

      // Try to extract time from aria-label or data attributes
      const ariaLabel = el.getAttribute('aria-label') || '';
      const timeMatch = ariaLabel.match(/(\\d{1,2}(?::\\d{2})?\\s*(?:AM|PM|am|pm)?)/);

      // Look for meeting links
      const meetLink = el.querySelector('a[href*="meet.google.com"]')?.href ||
                       el.querySelector('a[href*="zoom.us"]')?.href || '';

      // Try to get event ID for deduplication
      const eventId = el.getAttribute('data-eventid') ||
                      el.getAttribute('data-eventchip') ||
                      title.substring(0, 20);

      if (title && title !== 'Unknown Event') {
        events.push({
          id: eventId,
          title: title.substring(0, 50),
          time: timeMatch ? timeMatch[1] : null,
          meetingLink: meetLink,
          hasAttachments: el.querySelector('[aria-label*="attachment"]') !== null
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

## Time Parsing

Convert extracted time strings to proper timestamps:

```javascript
function parseEventTime(timeStr, baseDate) {
  if (!timeStr) return null;

  // Handle formats like "2:30 PM", "14:30", "2pm"
  const match = timeStr.match(/(\\d{1,2})(?::(\\d{2}))?\\s*(AM|PM|am|pm)?/);
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

## Alert Detection

For each event, check if alert should trigger:

```javascript
const now = Date.now();
const alertMinutes = config.calendar.alertMinutesBefore || 5;
const alertWithDocs = config.calendar.alertWithDocsBefore || 10;

const shouldAlert = events.some(event => {
  if (!event.startTime) return false;
  const diff = (event.startTime - now) / 60000; // minutes until start

  // Alert based on timing
  const threshold = event.hasAttachments ? alertWithDocs : alertMinutes;
  return diff > 0 && diff <= threshold;
});
```

Set `hasAlert: true` if any upcoming meeting is within the alert window.

## Detecting Next Meeting

Find the next upcoming meeting:

```javascript
const upcoming = events
  .filter(e => e.startTime && e.startTime > now)
  .sort((a, b) => a.startTime - b.startTime)[0];
```

## Output Format

Return for bridge:

```json
{
  "site": "calendar",
  "icon": "📅",
  "title": "<meeting title truncated>",
  "detail": "in <N>m" or "now" or "started <N>m ago",
  "hasAlert": true,
  "data": {
    "startTime": 1234567890000,
    "meetingLink": "https://meet.google.com/...",
    "organizer": "<organizer if available>"
  }
}
```

Icon options:
- `📅` = upcoming meeting
- `🔴` = meeting starting now or missed
- `✓` = no upcoming meetings

## Update Config

Store the detected meetings for ack:

```json
{
  "calendar": {
    "lastSeen": {
      "nextMeeting": {
        "title": "...",
        "startTime": 1234567890000,
        "meetingLink": "...",
        "organizer": "..."
      }
    }
  }
}
```

## Error Handling

If tab is unavailable or JS execution fails:

```bash
${CLAUDE_PLUGIN_ROOT}/bin/update-bridge.sh --error "Calendar: Tab not accessible"
```

## Alternative: Fallback to Text Extraction

If the DOM-based approach fails, try reading page text:

```
mcp__claude-in-chrome__get_page_text(tabId: calendar.chrome.tabId)
```

Then parse the text for meeting information.
