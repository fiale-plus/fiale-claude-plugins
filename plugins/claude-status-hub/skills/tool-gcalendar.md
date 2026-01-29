# Tool: Google Calendar

Browser-based calendar extraction. See `connection-detect.md` for detection.

## Chrome MCP Mode

**Prerequisite:** Day view (`/calendar/u/0/r/day`). Press "t" to scroll to current time first.

### Extraction

```javascript
(() => {
  const events = [];
  document.querySelectorAll("[data-eventid], [data-eventchip]").forEach(el => {
    const text = el.innerText || "";
    const lines = text.split("\n").map(l => l.trim()).filter(l => l);
    if (lines.length < 2) return;
    const title = lines[1] || lines[0] || "Untitled";
    const timeMatch = text.match(/(\d{1,2}:\d{2})/);
    let meetLink = el.querySelector("a[href*='meet.google.com']")?.href ||
                   el.querySelector("a[href*='zoom.us']")?.href ||
                   text.match(/https:\/\/meet\.google\.com\/[a-z-]+/i)?.[0] || "";
    if (title && timeMatch) events.push({ id: el.getAttribute("data-eventid") || title.substring(0, 20), title: title.substring(0, 50), time: timeMatch[1], meetingLink: meetLink });
  });
  const seen = new Set();
  return events.filter(e => { if (seen.has(e.id)) return false; seen.add(e.id); return true; }).slice(0, 10);
})()
```

## Time Parsing

```javascript
function parseEventTime(timeStr, base = new Date()) {
  const m = timeStr.match(/(\d{1,2})(?::(\d{2}))?\s*(AM|PM|am|pm)?/);
  if (!m) return null;
  let h = parseInt(m[1], 10), mins = parseInt(m[2] || '0', 10);
  if (m[3]?.toUpperCase() === 'PM' && h < 12) h += 12;
  if (m[3]?.toUpperCase() === 'AM' && h === 12) h = 0;
  const d = new Date(base); d.setHours(h, mins, 0, 0);
  return d.getTime();
}
```

## Alert Detection

Alert if meeting within `alertMinutesBefore` (default 5).

## Errors

| Error | Solution |
|-------|----------|
| Tab not found | Auto-recovered |
| Wrong page | Navigate to day view |
| No events | Check view (use day view) |
