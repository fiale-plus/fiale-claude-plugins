---
name: hub-setup-gcalendar
description: Set up Google Calendar API access (for environments without Chrome MCP)
---

# Google Calendar Setup Wizard

Configure Google Calendar integration via browser automation. See `connection-detect.md` for detection logic.

## Files

- `~/.claude/status-config.json` - Hub config
- `~/.claude/playwright-profile/` - Playwright browser profile

## Wizard Flow

### Step 1: Detect Available Methods

```javascript
const chromeStatus = await checkMcpAvailable(() =>
  mcp__claude-in-chrome__tabs_context_mcp({ createIfEmpty: false }));

const playwrightStatus = await checkMcpAvailable(() =>
  mcp__playwright__browser_navigate({ url: 'about:blank' }));
```

### Step 2: Present Options

```json
{
  "question": "How would you like to connect to Google Calendar?",
  "header": "Connection",
  "options": [
    {"label": "Chrome browser tab", "description": "<dynamic: ✓ Ready | ⚠️ Requires extension>"},
    {"label": "Playwright (headless)", "description": "<dynamic: ✓ Ready | ⚠️ Requires MCP>"},
    {"label": "Skip calendar setup", "description": "Configure later"}
  ]
}
```

---

## Chrome Setup

1. Get/create tab in MCP group, navigate to day view:
```javascript
const newTab = await mcp__claude-in-chrome__tabs_create_mcp();
await mcp__claude-in-chrome__navigate({
  tabId: newTab.tabId,
  url: 'https://calendar.google.com/calendar/u/0/r/day'
});
```
2. If login required, inform user and wait
3. Verify: `document.querySelectorAll("[data-eventid]").length`
4. Proceed to alert timing

**If not installed**: Show Chrome Web Store instructions, set `calendar.connection: "disabled"`.

---

## Playwright Setup

1. Check login state: navigate and snapshot
2. If login needed:
```
npx playwright open --save-storage=~/.claude/playwright-profile https://calendar.google.com
```
3. Verify login and proceed to alert timing

**If not installed**: Show MCP config instructions, set `calendar.connection: "disabled"`.

---

## Alert Timing

```json
{
  "question": "When should calendar alerts appear?",
  "header": "Alerts",
  "options": [
    {"label": "5 minutes before (Recommended)", "description": "Standard reminder"},
    {"label": "10 minutes before", "description": "More time to wrap up"},
    {"label": "Custom", "description": "Set your own timing"}
  ]
}
```

---

## Save Configuration

```json
{
  "calendar": {
    "connection": "<chrome|playwright|disabled>",
    "chrome": { "tabId": 12345 },
    "playwright": { "profile": "default", "headless": false },
    "alertMinutesBefore": 5,
    "alertWithDocsBefore": 10
  }
}
```

---

## Troubleshooting

**Playwright issues**: Clear cache (`rm -rf ~/Library/Caches/ms-playwright`), reinstall (`npx playwright install chromium`), re-login.

**Chrome extension issues**: Verify installed and signed in at chrome://extensions, ensure Chrome is running.
