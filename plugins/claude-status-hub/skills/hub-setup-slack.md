---
name: hub-setup-slack
description: Set up Slack integration (Slack MCP, Chrome, Playwright, or API)
---

# Slack Setup Wizard

Interactive wizard to configure Slack integration with multiple connection options.

## When to Use

- User runs `/hub-setup-slack`
- Slack connection method needs configuration
- Connection is failing and needs reconfiguration

## File Locations

- `~/.claude/status-config.json` - Hub config (slack settings)
- `~/.claude/slack-credentials.json` - Workspace URL (API mode)
- `~/.claude/slack-token.json` - xoxc token + d cookie (API mode)
- `~/.claude/playwright-profile/` - Playwright browser profile

## Connection Methods

| Method | Best For | Requirements |
|--------|----------|--------------|
| Slack MCP | Non-corporate | Slack MCP plugin |
| Chrome MCP | Corporate (MCP blocked) | Claude-in-Chrome extension |
| Playwright | Headless/background | Playwright MCP plugin |
| API | Last resort | Manual token extraction |

## Wizard Flow

### Step 1: Choose Connection Method

Use AskUserQuestion:

```
question: "How would you like to connect to Slack?"
header: "Connection"
options:
  - label: "Slack MCP plugin (Recommended)"
    description: "Official Slack integration - best for non-corporate environments"
  - label: "Chrome browser tab"
    description: "Use an open Slack tab - works in corporate environments"
  - label: "Playwright (headless)"
    description: "Automated browser - works without visible Chrome"
  - label: "API tokens (manual)"
    description: "Extract xoxc token manually - unreliable, last resort"
```

---

## Slack MCP Setup

### Step 2a: Check Slack MCP Installation

```
question: "Do you have the Slack MCP plugin installed?"
header: "Slack MCP"
options:
  - label: "Yes, it's installed"
    description: "Test the connection"
  - label: "No, I need to install it"
    description: "Show installation instructions"
```

If needs installation:

```
## Installing Slack MCP Plugin

1. In Claude Code, run: /install slack
   (from the claude-plugins-official marketplace)

2. Restart Claude Code after installation

3. You'll be prompted to authorize with Slack

4. Run /hub-setup-slack again
```

### Step 3a: Test Slack MCP Connection

```javascript
// Test if Slack MCP is working
try {
  const channels = await mcp__slack__list_channels({ limit: 1 });
  if (channels && !channels.error) {
    // Success!
    return { connected: true, method: 'mcp' };
  }
} catch (e) {
  // MCP not available or blocked
}
```

If connection fails:

```
Slack MCP connection failed.

This usually means:
- Corporate firewall is blocking the connection
- Plugin needs reauthorization

Try one of these alternatives:
- Chrome browser tab (works in most corporate environments)
- Playwright (headless browser automation)

Would you like to try a different method?
```

### Step 4a: Get Workspace Info

```
question: "What's your Slack workspace URL? (e.g., mycompany.slack.com)"
header: "Workspace"
options:
  - label: "Continue..."
    description: "I'll enter the workspace in the 'Other' field"
```

### Step 5a: Save Config (MCP)

```json
{
  "slack": {
    "connection": "mcp",
    "workspace": "mycompany.slack.com",
    "vipPeople": [],
    "channels": []
  }
}
```

### Success Message (MCP)

```
Slack connected via Slack MCP!

Workspace: mycompany.slack.com

Your statusline will now show:
- Unread message counts
- Alerts for VIP messages (configure in /hub)

Use /hub-ack to interact with Slack alerts.
```

---

## Chrome MCP Setup

### Step 2b: Check Chrome Extension

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

### Step 3b: Open Slack

```
question: "Please open your Slack workspace in the browser and come back."
header: "Open Slack"
options:
  - label: "Slack is open"
    description: "Proceed to connect"
  - label: "I'll do this later"
    description: "Cancel setup for now"
```

### Step 4b: Get Tab Context

```javascript
// Get current tabs
const context = await mcp__claude-in-chrome__tabs_context_mcp({ createIfEmpty: true });

// Find Slack tab
const tabs = context.tabs || [];
const slackTab = tabs.find(t => t.url?.includes('slack.com'));

if (slackTab) {
  tabId = slackTab.id;
  workspace = new URL(slackTab.url).hostname;
}
```

### Step 5b: Verify and Save

Test extraction on the tab:

```javascript
const data = await mcp__claude-in-chrome__javascript_tool({
  action: 'javascript_exec',
  tabId: tabId,
  text: '(() => { return !!document.querySelector("[data-qa=channel_sidebar]"); })()'
});
```

Save config:

```json
{
  "slack": {
    "connection": "chrome",
    "workspace": "mycompany.slack.com",
    "chrome": { "tabId": 12345 },
    "vipPeople": [],
    "channels": []
  }
}
```

### Success Message (Chrome)

```
Slack connected via Chrome!

Tab ID: 12345
Workspace: mycompany.slack.com

Your statusline will now show:
- Unread message counts
- Alerts for VIP messages

Keep the Slack tab open for best results.
Use /hub-ack to interact with Slack alerts.
```

---

## Playwright Setup

### Step 2c: Check Playwright Installation

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

3. Come back and run /hub-setup-slack again
```

### Step 3c: Get Workspace URL

```
question: "What's your Slack workspace URL? (e.g., mycompany.slack.com)"
header: "Workspace"
options:
  - label: "Continue..."
    description: "I'll enter the workspace in the 'Other' field"
```

### Step 4c: Login to Slack

```
## Slack Login

Playwright needs a logged-in browser session.

Run this command in your terminal:

npx playwright open --save-storage=~/.claude/playwright-profile https://mycompany.slack.com

1. A browser window will open
2. Log into your Slack workspace
3. Wait until you see your channels
4. Close the browser when done

This saves your login session for Playwright to use.
```

Ask when ready:

```
question: "Have you completed the Slack login in the Playwright browser?"
header: "Login"
options:
  - label: "Yes, I'm logged in"
    description: "Test the connection"
  - label: "I need help"
    description: "Show troubleshooting steps"
  - label: "I'll do this later"
    description: "Cancel setup for now"
```

### Step 5c: Test and Save

```javascript
// Navigate to Slack
await mcp__playwright__browser_navigate({
  url: `https://${workspace}`
});

// Check if logged in
const snapshot = await mcp__playwright__browser_snapshot();
// Look for channel sidebar vs login page
```

Save config:

```json
{
  "slack": {
    "connection": "playwright",
    "workspace": "mycompany.slack.com",
    "playwright": { "profile": "default", "headless": false },
    "vipPeople": [],
    "channels": []
  }
}
```

### Success Message (Playwright)

```
Slack connected via Playwright!

Workspace: mycompany.slack.com

Your statusline will now show:
- Unread message counts
- Alerts for VIP messages

Playwright will open a browser when refreshing Slack data.
Set "headless": true in config for invisible operation.

Use /hub-ack to interact with Slack alerts.
```

---

## API Setup (Legacy)

### Step 2d: Introduction

```
## API Token Setup

This method extracts browser session tokens manually.

Note: This is the least reliable method.
- Tokens expire frequently (hours to days)
- Requires manual re-extraction when expired

Consider using Chrome or Playwright instead if possible.
```

```
question: "Do you want to proceed with API token extraction?"
header: "API Mode"
options:
  - label: "Yes, extract tokens"
    description: "Show extraction instructions"
  - label: "Try a different method"
    description: "Go back to connection selection"
```

### Step 3d: Guide Through Extraction

```
## Extracting Slack Credentials

You need two things: the `d` cookie and the `xoxc-` token.

### Step 1: Open Slack in your browser
Navigate to your Slack workspace (e.g., https://mycompany.slack.com)

### Step 2: Open DevTools
Press F12 (Windows/Linux) or Cmd+Opt+I (Mac)

### Step 3: Get the `d` cookie
1. Go to the **Application** tab (Chrome) or **Storage** tab (Firefox)
2. Expand **Cookies** in the left sidebar
3. Click on your Slack domain
4. Find the cookie named `d`
5. Copy its entire Value (starts with `xoxd-`)

### Step 4: Get the `xoxc` token
1. Go to the **Network** tab
2. Refresh the page (F5 or Cmd+R)
3. Click on any request to slack.com
4. Look in **Request Headers** for `Authorization: Bearer xoxc-...`
5. Copy the token (everything after "Bearer ")

### Step 5: Note your workspace URL
This is the domain (e.g., `mycompany.slack.com`)
```

### Step 4d: Collect Credentials

Ask for workspace:
```
question: "Enter your Slack workspace URL (e.g., mycompany.slack.com):"
header: "Workspace"
options:
  - label: "Continue..."
    description: "I'll enter the workspace URL in the 'Other' field"
```

Ask for d cookie:
```
question: "Paste the `d` cookie value (starts with xoxd-):"
header: "Cookie"
options:
  - label: "Continue..."
    description: "I'll paste the cookie in the 'Other' field"
```

Ask for xoxc token:
```
question: "Paste the xoxc token (starts with xoxc-):"
header: "Token"
options:
  - label: "Continue..."
    description: "I'll paste the token in the 'Other' field"
```

### Step 5d: Validate and Save

Validate formats:
- Workspace: should be `xxx.slack.com`
- Cookie: must start with `xoxd-`
- Token: must start with `xoxc-`

Test with auth.test:

```bash
curl -s "https://slack.com/api/auth.test" \
  -H "Authorization: Bearer $token" \
  --cookie "d=$cookie"
```

Save credentials:

```bash
# ~/.claude/slack-credentials.json
echo '{"workspace": "'$workspace'"}' > ~/.claude/slack-credentials.json
chmod 600 ~/.claude/slack-credentials.json

# ~/.claude/slack-token.json
expires_at=$(($(date +%s) + 21600))
cat > ~/.claude/slack-token.json << EOF
{
  "token": "$token",
  "cookie": "$cookie",
  "expires_at": $expires_at
}
EOF
chmod 600 ~/.claude/slack-token.json
```

Update config:

```json
{
  "slack": {
    "connection": "api",
    "workspace": "mycompany.slack.com",
    "vipPeople": [],
    "channels": []
  }
}
```

### Success Message (API)

```
Slack connected via API!

Workspace: My Company
User: pavel (@pavel)

Note: The xoxc token may expire. If you get auth errors,
run /hub-setup-slack again to refresh credentials.

Use /hub-ack to interact with Slack alerts.
```

---

## Alert Configuration

After any successful setup:

```
question: "Would you like to configure alert triggers?"
header: "Alerts"
options:
  - label: "Yes, configure now"
    description: "Set up VIP people and watched channels"
  - label: "Skip for now"
    description: "Configure later in /hub"
```

If configuring:

```
question: "Enter VIP people (comma-separated usernames to alert on DMs):"
header: "VIP People"
options:
  - label: "Continue..."
    description: "e.g., @boss, @tech-lead"
```

```
question: "Enter watched channels (comma-separated, alerts on any message):"
header: "Channels"
options:
  - label: "Continue..."
    description: "e.g., #incidents, #deployments"
```

---

## Playwright Troubleshooting

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

3. **Re-login to Slack:**
   npx playwright open --save-storage=~/.claude/playwright-profile https://mycompany.slack.com

4. **Restart Claude Code**

5. **Run /hub-setup-slack again**

Common issues:
- "Browser not found" → Run npx playwright install
- "Session expired" → Re-login via the command above
- "Timeout" → Check your internet connection
```

---

## Error Handling

### Slack MCP Blocked

```
Slack MCP connection failed.

This is common in corporate environments that block external connections.

Recommended alternatives:
1. Chrome browser tab - Use /hub-setup-slack and select "Chrome browser tab"
2. Playwright - Automated browser that works offline

Both methods work within your local network without external MCP calls.
```

### Invalid Token Format

```
The token doesn't appear to be valid.

Expected format: xoxc-xxx-xxx-xxx...
Got: [first 20 chars of input]

Make sure you copied the entire xoxc token from the Authorization header.
```

### Auth Test Failed

```
Authentication failed: [error message]

Common issues:
- Token or cookie expired (extract fresh ones from browser)
- Workspace URL incorrect
- Your session was logged out

Try extracting fresh credentials and running /hub-setup-slack again.
```

## Security Notes

- MCP mode: Uses official Slack OAuth
- Chrome mode: Uses your existing browser session
- Playwright mode: Session saved to `~/.claude/playwright-profile/`
- API mode: Credentials stored with 600 permissions (owner read/write only)
- xoxc + d cookie = full user access (protect these credentials)
