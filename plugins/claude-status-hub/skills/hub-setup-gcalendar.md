---
name: hub-setup-gcalendar
description: Set up Google Calendar integration (Chrome MCP or Playwright)
---

# Google Calendar Setup Wizard

Interactive wizard to configure Google Calendar integration via browser.

## When to Use

- User runs `/hub-setup-gcalendar`
- Calendar connection method needs configuration
- Chrome tab or Playwright profile needs setup

## File Locations

- `~/.claude/status-config.json` - Hub config (calendar settings)
- `~/.claude/playwright-profile/` - Playwright browser profile (if using Playwright)

## Connection Methods

| Method | Best For | Requirements |
|--------|----------|--------------|
| Chrome MCP | Active browser use | Claude-in-Chrome extension |
| Playwright | Headless/background | Playwright MCP plugin |

## Wizard Flow

### Step 1: Choose Connection Method

Use AskUserQuestion:

```
question: "How would you like to connect to Google Calendar?"
header: "Connection"
options:
  - label: "Chrome browser tab (Recommended)"
    description: "Use an open Calendar tab with Claude-in-Chrome extension"
  - label: "Playwright (headless)"
    description: "Automated browser - works without visible Chrome"
  - label: "Skip calendar setup"
    description: "Set up calendar later"
```

---

## Chrome MCP Setup

### Step 2a: Check Chrome Extension

```
question: "Do you have the Claude-in-Chrome extension installed?"
header: "Extension"
options:
  - label: "Yes, it's installed"
    description: "Proceed to tab setup"
  - label: "No, I need to install it"
    description: "Show installation instructions"
```

If needs installation:

```
## Installing Claude-in-Chrome

1. Install from Chrome Web Store (search "Claude in Chrome")
2. Click the extension icon and sign in
3. Come back here when ready

The extension allows Claude to interact with browser tabs.
```

### Step 3a: Open Google Calendar

```
question: "Please open Google Calendar in your browser and come back."
header: "Open Calendar"
options:
  - label: "Calendar is open"
    description: "Proceed to connect"
  - label: "I'll do this later"
    description: "Cancel setup for now"
```

### Step 4a: Get Tab Context

```javascript
// Get current tabs
const context = await mcp__claude-in-chrome__tabs_context_mcp({ createIfEmpty: true });

// Find calendar tab or ask user to select
const tabs = context.tabs || [];
const calendarTab = tabs.find(t => t.url?.includes('calendar.google.com'));

if (calendarTab) {
  // Found it automatically
  tabId = calendarTab.id;
} else {
  // Ask user to navigate to calendar
  // Then take screenshot to confirm
}
```

### Step 5a: Verify and Save

Test extraction on the tab:

```javascript
const events = await mcp__claude-in-chrome__javascript_tool({
  action: 'javascript_exec',
  tabId: tabId,
  text: '(() => { return document.querySelectorAll("[data-eventid]").length; })()'
});
```

Save config:

```json
{
  "calendar": {
    "connection": "chrome",
    "chrome": { "tabId": 12345 },
    "alertMinutesBefore": 5,
    "alertWithDocsBefore": 10
  }
}
```

### Success Message (Chrome)

```
Google Calendar connected via Chrome!

Tab ID: 12345
Found events on your calendar.

Your statusline will now show:
- Upcoming meetings with time remaining
- Alerts before meetings start

Keep the calendar tab open for best results.
Use /hub-ack to interact with calendar alerts.
```

---

## Playwright Setup

### Step 2b: Check Playwright Installation

```
question: "Do you have the Playwright plugin installed?"
header: "Playwright"
options:
  - label: "Yes, it's installed"
    description: "Proceed to login"
  - label: "No, I need to install it"
    description: "Show installation instructions"
```

If needs installation:

```
## Installing Playwright Plugin

1. In Claude Code, run: /install playwright
   (from the claude-plugins-official marketplace)

2. Restart Claude Code after installation

3. Come back and run /hub-setup-gcalendar again
```

### Step 3b: Login to Google

```
## Google Calendar Login

Playwright needs a logged-in browser session.

Run this command in your terminal:

npx playwright open --save-storage=~/.claude/playwright-profile https://calendar.google.com

1. A browser window will open
2. Log into your Google account
3. Navigate to calendar.google.com
4. Close the browser when done

This saves your login session for Playwright to use.
```

Ask when ready:

```
question: "Have you completed the Google login in the Playwright browser?"
header: "Login"
options:
  - label: "Yes, I'm logged in"
    description: "Test the connection"
  - label: "I need help"
    description: "Show troubleshooting steps"
  - label: "I'll do this later"
    description: "Cancel setup for now"
```

### Step 4b: Test Playwright Connection

```javascript
// Navigate to calendar
await mcp__playwright__browser_navigate({
  url: 'https://calendar.google.com'
});

// Check if logged in
const snapshot = await mcp__playwright__browser_snapshot();
// Look for calendar elements vs login page
```

If login page detected:

```
It looks like you're not logged in yet.

Please run the login command again:
npx playwright open --save-storage=~/.claude/playwright-profile https://calendar.google.com

Make sure to:
1. Complete the Google sign-in
2. See your calendar events
3. Close the browser window
```

### Step 5b: Save Config

```json
{
  "calendar": {
    "connection": "playwright",
    "playwright": { "profile": "default", "headless": false },
    "alertMinutesBefore": 5,
    "alertWithDocsBefore": 10
  }
}
```

### Success Message (Playwright)

```
Google Calendar connected via Playwright!

Your statusline will now show:
- Upcoming meetings with time remaining
- Alerts before meetings start

Playwright will open a browser when refreshing calendar data.
Set "headless": true in config for invisible operation.

Use /hub-ack to interact with calendar alerts.
```

---

## Configuration Options

After setup, ask about alert preferences:

```
question: "When should you be alerted before meetings?"
header: "Alerts"
options:
  - label: "5 minutes before"
    description: "Standard alert timing"
  - label: "10 minutes before"
    description: "More time to prepare"
  - label: "Custom timing"
    description: "I'll configure manually"
```

---

## Playwright Troubleshooting

If Playwright has issues:

```
## Playwright Troubleshooting

If you're having issues with Playwright:

1. **Clear Playwright cache completely:**

   Linux:
   rm -rf ~/.cache/ms-playwright

   macOS:
   rm -rf ~/Library/Caches/ms-playwright

2. **Reinstall Playwright browsers:**
   npx playwright install chromium

3. **Re-login to Google:**
   npx playwright open --save-storage=~/.claude/playwright-profile https://calendar.google.com

4. **Restart Claude Code**

5. **Run /hub-setup-gcalendar again**

Common issues:
- "Browser not found" → Run npx playwright install
- "Session expired" → Re-login via the command above
- "Timeout" → Check your internet connection
```

---

## Error Handling

### Chrome Extension Not Found

```
Claude-in-Chrome extension not detected.

To install:
1. Search "Claude in Chrome" in Chrome Web Store
2. Click "Add to Chrome"
3. Sign in to the extension
4. Run /hub-setup-gcalendar again
```

### Playwright Not Installed

```
Playwright plugin not detected.

To install:
1. Run: /install playwright
2. Restart Claude Code
3. Run /hub-setup-gcalendar again
```

### Login Failed

```
Could not verify Google login.

Please try:
1. Clear browser data and re-login
2. Make sure you can see your calendar events
3. Close all Playwright browsers and try again

If using 2FA, complete the verification in the browser.
```

## Security Notes

- Chrome mode: Uses your existing browser session
- Playwright mode: Session saved to `~/.claude/playwright-profile/`
- No passwords or tokens are stored by this plugin
- Calendar data is read-only (viewing events, not modifying)
