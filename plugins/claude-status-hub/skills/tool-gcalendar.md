# Tool: Google Calendar

Browser-based Google Calendar operations. See `connection-detect.md` for connection hierarchy and detection logic.

---

## Chrome MCP Mode

**Prerequisite:** Google Calendar open in **day view** (`/calendar/u/0/r/day`)

### Step 1: Scroll to Current Time

Before extracting, press "t" to go to today (scrolls to current time area):

```
computer tool: action="key", text="t"
```

This ensures upcoming meetings near current time are visible for extraction.

### Step 2: Data Extraction Script

```javascript
(() => {
  const events = [];
  const eventEls = document.querySelectorAll("[data-eventid], [data-eventchip]");

  eventEls.forEach(el => {
    try {
      const text = el.innerText || "";
      const lines = text.split("\n").map(l => l.trim()).filter(l => l);
      if (lines.length < 2) return;

      const title = lines[1] || lines[0] || "Untitled Event";
      const timeMatch = text.match(/(\d{1,2}:\d{2})/);

      let meetLink = el.querySelector("a[href*='meet.google.com']")?.href ||
                     el.querySelector("a[href*='zoom.us']")?.href ||
                     el.querySelector("[data-call-url]")?.getAttribute("data-call-url") || "";
      if (!meetLink) {
        const meetMatch = text.match(/https:\/\/meet\.google\.com\/[a-z-]+/i);
        if (meetMatch) meetLink = meetMatch[0];
      }

      const eventId = el.getAttribute("data-eventid") || title.substring(0, 20);
      if (title && timeMatch) {
        events.push({ id: eventId, title: title.substring(0, 50), time: timeMatch[1], meetingLink: meetLink });
      }
    } catch (e) {}
  });

  const seen = new Set();
  return events.filter(e => { if (seen.has(e.id)) return false; seen.add(e.id); return true; }).slice(0, 10);
})()
```

---

## Playwright Mode

```javascript
await mcp__playwright__browser_navigate({ url: 'https://calendar.google.com/calendar/u/0/r/day' });
await mcp__playwright__browser_wait({ selector: '[data-eventid]', timeout: 10000 });
const events = await mcp__playwright__browser_evaluate({ expression: extractionScript });
```

Profile setup: `npx playwright open --save-storage=~/.claude/playwright-profile https://calendar.google.com`

---

## Time Parsing

```javascript
function parseEventTime(timeStr, baseDate = new Date()) {
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

---

## Output Format

```json
{
  "events": [{
    "id": "event_abc123",
    "title": "Team Standup",
    "startTime": 1705344000000,
    "meetingLink": "https://meet.google.com/xxx-yyyy-zzz"
  }],
  "nextMeeting": {
    "title": "Team Standup",
    "startTime": 1705344000000,
    "minutesUntil": 15,
    "meetingLink": "https://meet.google.com/xxx-yyyy-zzz"
  }
}
```

## Alert Detection

```javascript
function checkAlerts(events, config) {
  const now = Date.now();
  const alertMinutes = config.calendar?.alertMinutesBefore || 5;

  for (const event of events) {
    if (!event.startTime) continue;
    const minutesUntil = (event.startTime - now) / 60000;
    if (minutesUntil > 0 && minutesUntil <= alertMinutes) {
      return { shouldAlert: true, event, minutesUntil: Math.round(minutesUntil) };
    }
  }
  return { shouldAlert: false };
}
```

## Error Table

| Error | Method | Solution |
|-------|--------|----------|
| Tab not found | chrome | Re-run `/hub-setup-gcalendar` |
| Wrong page | chrome | Navigate to calendar day view |
| Session expired | playwright | Re-login via setup |
| No events found | both | Check calendar view (use day view) |
