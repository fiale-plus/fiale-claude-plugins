---
name: hub-setup-slack
description: Set up Slack integration (Slack MCP, Chrome, Playwright, or API)
---

# Slack Setup Wizard

Configure Slack integration. See `connection-detect.md` for detection logic.

## Files

- `~/.claude/status-config.json` - Hub config
- `~/.claude/slack-credentials.json`, `~/.claude/slack-token.json` - API mode credentials

## Wizard Flow

### Step 1: Choose Connection Method

```json
{
  "question": "How would you like to connect to Slack?",
  "header": "Connection",
  "options": [
    {"label": "Slack MCP plugin (Recommended)", "description": "Official Slack integration"},
    {"label": "Chrome browser tab", "description": "Uses open Slack tab"},
    {"label": "Playwright (headless)", "description": "Automated browser"},
    {"label": "API tokens (manual)", "description": "Extract xoxc token - unreliable"}
  ]
}
```

---

## Slack MCP Setup

1. Test connection: `mcp__slack__list_channels({ limit: 1 })`
2. If fails: suggest Chrome or Playwright instead
3. Ask workspace URL
4. Save config:
```json
{ "slack": { "connection": "mcp", "workspace": "mycompany.slack.com" } }
```

---

## Chrome MCP Setup

1. Ask workspace URL
2. Get/create tab in MCP group:
```javascript
const context = await mcp__claude-in-chrome__tabs_context_mcp({ createIfEmpty: true });
const newTab = await mcp__claude-in-chrome__tabs_create_mcp();
await mcp__claude-in-chrome__navigate({ tabId: newTab.tabId, url: `https://${workspace}` });
```
3. Verify sidebar loads: `document.querySelector("[data-qa=channel_sidebar]")`
4. Save config:
```json
{ "slack": { "connection": "chrome", "workspace": "...", "chrome": { "tabId": 12345 } } }
```

---

## Playwright Setup

1. Ask workspace URL
2. Show login command:
```
npx playwright open --save-storage=~/.claude/playwright-profile https://mycompany.slack.com
```
3. Verify login: navigate and check for sidebar
4. Save config:
```json
{ "slack": { "connection": "playwright", "workspace": "...", "playwright": { "profile": "default" } } }
```

---

## API Setup (Legacy)

1. Guide user to extract `d` cookie (xoxd-) and `xoxc-` token from DevTools
2. Validate formats, test with `auth.test`
3. Save credentials (chmod 600):
```json
// ~/.claude/slack-token.json
{ "token": "xoxc-...", "cookie": "xoxd-...", "expires_at": <timestamp> }
```
4. Save config: `{ "slack": { "connection": "api", "workspace": "..." } }`

---

## Alert Configuration (After Setup)

```json
{
  "question": "Configure alert triggers?",
  "header": "Alerts",
  "options": [
    {"label": "Yes", "description": "Set VIP people and watched channels"},
    {"label": "Skip", "description": "Configure later in /hub"}
  ]
}
```

If yes: ask for VIP people (comma-separated) and watched channels.

---

## Troubleshooting

**Slack MCP blocked**: Corporate firewall; use Chrome or Playwright.

**Playwright issues**: Clear cache (`rm -rf ~/Library/Caches/ms-playwright`), reinstall browsers (`npx playwright install chromium`), re-login.

**API invalid_auth**: Token expired; re-extract from browser.
