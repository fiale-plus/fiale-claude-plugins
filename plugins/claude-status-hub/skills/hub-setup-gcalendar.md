---
name: hub-setup-gcalendar
description: Set up Google Calendar API access (for environments without Chrome MCP)
---

# Google Calendar Setup Wizard

Interactive wizard to configure Google Calendar integration via browser automation.

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
| Playwright | Headless/background | Playwright MCP server |

---

## Wizard Flow

### Step 1: Detect Available Connection Methods

Before presenting options, check what's installed (sequential detection):

```javascript
// Check Chrome MCP
let chromeStatus = { installed: false, ready: false };
try {
  const context = await mcp__claude-in-chrome__tabs_context_mcp({ createIfEmpty: false });
  chromeStatus = { installed: true, ready: !context.error };
} catch (e) {
  chromeStatus = { installed: false, ready: false };
}

// Check Playwright MCP
let playwrightStatus = { installed: false, ready: false };
try {
  const result = await mcp__playwright__browser_navigate({ url: 'about:blank' });
  playwrightStatus = { installed: true, ready: !result.error };
} catch (e) {
  playwrightStatus = { installed: false, ready: false };
}
```

### Step 2: Present Consolidated Connection Wizard

Show ALL connection methods with dynamic status indicators:

```javascript
const chromeDesc = chromeStatus.installed
  ? "✓ Ready - uses open Calendar tab"
  : "⚠️ Requires Claude-in-Chrome extension";

const playwrightDesc = playwrightStatus.installed
  ? "✓ Ready - works in background"
  : "⚠️ Requires Playwright MCP server";
```

Use AskUserQuestion with computed descriptions:

```json
{
  "questions": [{
    "question": "How would you like to connect to Google Calendar?",
    "header": "Connection",
    "options": [
      {
        "label": "Chrome browser tab",
        "description": "<chromeDesc>"
      },
      {
        "label": "Playwright (headless)",
        "description": "<playwrightDesc>"
      },
      {
        "label": "Skip calendar setup",
        "description": "Cancel and set up later"
      }
    ],
    "multiSelect": false
  }]
}
```

### Step 3: Handle User Selection

#### If User Selects Chrome (Installed)

1. **Prompt to open Calendar:**
   ```
   Please open Google Calendar in Chrome, then confirm.
   ```

2. **Find the calendar tab:**
   ```javascript
   const context = await mcp__claude-in-chrome__tabs_context_mcp({ createIfEmpty: true });
   const tabs = context.tabs || [];
   const calendarTab = tabs.find(t => t.url?.includes('calendar.google.com'));
   ```

3. **If not found, ask user to navigate**

4. **Test extraction:**
   ```javascript
   const events = await mcp__claude-in-chrome__javascript_tool({
     action: 'javascript_exec',
     tabId: tabId,
     text: '(() => { return document.querySelectorAll("[data-eventid]").length; })()'
   });
   ```

5. **Proceed to alert timing (Step 4)**

#### If User Selects Chrome (Not Installed)

Show installation guidance:

```
📦 Installing Claude-in-Chrome Extension

The Claude-in-Chrome extension is required for this option.

1. Install from Chrome Web Store (search "Claude in Chrome")
2. Click the extension icon and sign in
3. Restart Claude Code session

After installing, run /hub-setup-gcalendar again to continue.
```

Set `calendar.connection: "disabled"` and exit wizard.

#### If User Selects Playwright (Installed)

1. **Check login state:**
   ```javascript
   await mcp__playwright__browser_navigate({ url: 'https://calendar.google.com' });
   const snapshot = await mcp__playwright__browser_snapshot();
   // Look for calendar elements vs login page
   ```

2. **If login needed:**
   ```
   Playwright needs a logged-in browser session.

   Run this command in your terminal:

   npx playwright open --save-storage=~/.claude/playwright-profile https://calendar.google.com

   1. A browser window will open
   2. Log into your Google account
   3. Navigate to calendar.google.com
   4. Close the browser when done

   This saves your login session for Playwright to use.
   ```

3. **Verify login and proceed to alert timing (Step 4)**

#### If User Selects Playwright (Not Installed)

Show installation guidance:

```
📦 Installing Playwright MCP

The Playwright MCP server is required for this option.

1. Add to your Claude Code MCP settings:
   {
     "mcpServers": {
       "playwright": {
         "command": "npx",
         "args": ["@playwright/mcp@latest"]
       }
     }
   }

2. Restart Claude Code session

After installing, run /hub-setup-gcalendar again to continue.
```

Set `calendar.connection: "disabled"` and exit wizard.

#### If User Selects Skip

Set `calendar.connection: "disabled"` and exit wizard.

---

### Step 4: Configure Alert Timing

Only shown after successful connection setup:

```json
{
  "questions": [{
    "question": "When should calendar alerts appear?",
    "header": "Alerts",
    "options": [
      {"label": "5 minutes before", "description": "Standard reminder (Recommended)"},
      {"label": "10 minutes before", "description": "More time to wrap up"},
      {"label": "Custom", "description": "Set your own timing"}
    ],
    "multiSelect": false
  }]
}
```

If "Custom" selected:

```json
{
  "questions": [{
    "question": "How many minutes before meetings should alerts appear?",
    "header": "Minutes",
    "options": [
      {"label": "3 minutes", "description": "Quick heads-up"},
      {"label": "15 minutes", "description": "Plenty of preparation time"},
      {"label": "30 minutes", "description": "Early warning"}
    ],
    "multiSelect": false
  }]
}
```

---

### Step 5: Save Configuration

```json
{
  "calendar": {
    "connection": "<chrome|playwright>",
    "chrome": { "tabId": 12345 },
    "playwright": { "profile": "default", "headless": false },
    "alertMinutesBefore": 5,
    "alertWithDocsBefore": 10
  }
}
```

---

### Step 6: Success Message

**For Chrome:**

```
Google Calendar connected via Chrome!

Tab ID: 12345
Alerts: X minutes before meetings

Your statusline will now show:
- Upcoming meetings with time remaining
- Alerts before meetings start

Keep the calendar tab open for best results.
Use /hub-ack to interact with calendar alerts.
```

**For Playwright:**

```
Google Calendar connected via Playwright!

Alerts: X minutes before meetings

Your statusline will now show:
- Upcoming meetings with time remaining
- Alerts before meetings start

Playwright will open a browser when refreshing calendar data.
Set "headless": true in config for invisible operation.

Use /hub-ack to interact with calendar alerts.
```

---

## Troubleshooting

### Playwright Issues

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

### Chrome Extension Issues

```
## Chrome Extension Troubleshooting

If you're having issues with Chrome MCP:

1. **Verify extension is installed:**
   - Check Chrome extensions page (chrome://extensions)
   - Look for "Claude in Chrome"

2. **Verify extension is signed in:**
   - Click the extension icon in Chrome toolbar
   - Ensure you're logged in

3. **Verify Chrome is running:**
   - Chrome browser must be open
   - Extension must be active (not disabled)

4. **Restart Claude Code session**

5. **Run /hub-setup-gcalendar again**
```

---

## Security Notes

- Chrome mode: Uses your existing browser session
- Playwright mode: Session saved to `~/.claude/playwright-profile/`
- No passwords or tokens are stored by this plugin
- Calendar data is read-only (viewing events, not modifying)
