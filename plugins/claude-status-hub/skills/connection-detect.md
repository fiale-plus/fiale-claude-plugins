# Connection Detection

Shared logic for detecting and selecting the best available connection method for calendar and Slack integrations.

## Connection Hierarchies

### Google Calendar
1. **Chrome MCP** (`chrome`) - Primary, requires open browser tab
2. **Playwright** (`playwright`) - Fallback, headless browser automation

### Slack
1. **Slack MCP** (`mcp`) - Primary for non-corporate setups, official Slack integration
2. **Chrome MCP** (`chrome`) - For corporate setups blocking Slack MCP
3. **Playwright** (`playwright`) - Headless browser fallback
4. **API** (`api`) - xoxc+d cookie method (unreliable, last resort)

## Config Structure

```json
{
  "calendar": {
    "connection": "auto",
    "chrome": { "tabId": null },
    "playwright": { "profile": "default", "headless": false }
  },
  "slack": {
    "connection": "auto",
    "workspace": "mycompany.slack.com",
    "chrome": { "tabId": null },
    "playwright": { "profile": "default", "headless": false }
  }
}
```

## Detection Logic

### Calendar Connection Detection

```javascript
async function detectCalendarConnection(config) {
  const preferred = config.calendar?.connection || 'auto';

  if (preferred === 'disabled') return { method: 'disabled' };
  if (preferred !== 'auto') return { method: preferred };

  // Auto-detect: Chrome > Playwright

  // 1. Try Chrome MCP
  const chromeAvailable = await checkChromeMcp();
  if (chromeAvailable) {
    const tabId = config.calendar?.chrome?.tabId;
    if (tabId) {
      return { method: 'chrome', tabId };
    }
    // Chrome available but no tab configured
    return { method: 'chrome', needsSetup: true };
  }

  // 2. Try Playwright
  const playwrightAvailable = await checkPlaywrightMcp();
  if (playwrightAvailable) {
    return { method: 'playwright' };
  }

  return { method: 'unavailable', error: 'No connection method available' };
}
```

### Slack Connection Detection

```javascript
async function detectSlackConnection(config) {
  const preferred = config.slack?.connection || 'auto';

  if (preferred === 'disabled') return { method: 'disabled' };
  if (preferred !== 'auto') return { method: preferred };

  // Auto-detect: Slack MCP > Chrome > Playwright > API

  // 1. Try Slack MCP (best for non-corporate)
  const slackMcpAvailable = await checkSlackMcp();
  if (slackMcpAvailable) {
    return { method: 'mcp' };
  }

  // 2. Try Chrome MCP (corporate environments often block MCP)
  const chromeAvailable = await checkChromeMcp();
  if (chromeAvailable) {
    const tabId = config.slack?.chrome?.tabId;
    if (tabId) {
      return { method: 'chrome', tabId };
    }
    return { method: 'chrome', needsSetup: true };
  }

  // 3. Try Playwright
  const playwrightAvailable = await checkPlaywrightMcp();
  if (playwrightAvailable) {
    return { method: 'playwright' };
  }

  // 4. Fall back to API (xoxc+d cookie)
  const apiConfigured = checkSlackApiCredentials();
  if (apiConfigured) {
    return { method: 'api' };
  }

  return { method: 'unavailable', error: 'No connection method available' };
}
```

## MCP Availability Checks

### Check Slack MCP

Test if Slack MCP server is available by calling a simple tool:

```javascript
async function checkSlackMcp() {
  try {
    // The Slack MCP provides tools prefixed with mcp__slack__
    // Try listing channels or a simple auth check
    const result = await mcp__slack__list_channels({ limit: 1 });
    return result && !result.error;
  } catch (e) {
    return false;
  }
}
```

**Slack MCP Tools** (from official plugin):
- Server URL: `https://mcp.slack.com/sse` (SSE transport)
- Expected tools: `mcp__slack__list_channels`, `mcp__slack__get_messages`, etc.

### Check Chrome MCP

Test if Claude-in-Chrome extension is available:

```javascript
async function checkChromeMcp() {
  try {
    // Check if we can get tab context
    const context = await mcp__claude-in-chrome__tabs_context_mcp({ createIfEmpty: false });
    return context && !context.error;
  } catch (e) {
    return false;
  }
}
```

### Check Playwright MCP

Test if Playwright MCP server is available:

```javascript
async function checkPlaywrightMcp() {
  try {
    // The Playwright MCP runs via npx @playwright/mcp@latest
    // Try a simple browser operation
    const result = await mcp__playwright__browser_navigate({ url: 'about:blank' });
    return result && !result.error;
  } catch (e) {
    return false;
  }
}
```

**Playwright MCP Tools** (from @playwright/mcp):
- `mcp__playwright__browser_navigate` - Navigate to URL
- `mcp__playwright__browser_snapshot` - Take accessibility snapshot
- `mcp__playwright__browser_click` - Click element
- `mcp__playwright__browser_type` - Type text
- `mcp__playwright__browser_screenshot` - Capture screenshot

### Check API Credentials

```javascript
function checkSlackApiCredentials() {
  const tokenFile = `${HOME}/.claude/slack-token.json`;
  const credsFile = `${HOME}/.claude/slack-credentials.json`;

  try {
    const token = JSON.parse(fs.readFileSync(tokenFile));
    const creds = JSON.parse(fs.readFileSync(credsFile));
    return token.token && token.cookie && creds.workspace;
  } catch (e) {
    return false;
  }
}
```

## Connection Method Usage

### Chrome MCP Usage

For both Calendar and Slack:

```javascript
// Get tab context first
const context = await mcp__claude-in-chrome__tabs_context_mcp({ createIfEmpty: true });

// Execute JavaScript on the page
const data = await mcp__claude-in-chrome__javascript_tool({
  action: 'javascript_exec',
  tabId: tabId,
  text: extractionScript
});
```

### Playwright MCP Usage

```javascript
// Navigate to page
await mcp__playwright__browser_navigate({ url: 'https://calendar.google.com' });

// Take snapshot for parsing
const snapshot = await mcp__playwright__browser_snapshot();

// Or execute JavaScript
const result = await mcp__playwright__browser_evaluate({
  expression: extractionScript
});
```

### Slack MCP Usage

Direct API access without browser:

```javascript
// List channels
const channels = await mcp__slack__list_channels({ limit: 100 });

// Get messages from a channel
const messages = await mcp__slack__get_channel_history({
  channel: 'C123ABC',
  limit: 20
});

// Search messages
const results = await mcp__slack__search_messages({ query: 'project update' });
```

## Error Handling

When a connection method fails:

1. **Log the failure** with specific error
2. **Try next method** in hierarchy
3. **Update config** if a method is discovered to not work
4. **Inform user** if all methods fail

```javascript
async function withFallback(config, service, operation) {
  const methods = service === 'calendar'
    ? ['chrome', 'playwright']
    : ['mcp', 'chrome', 'playwright', 'api'];

  for (const method of methods) {
    try {
      return await operation(method);
    } catch (e) {
      console.log(`${service}: ${method} failed - ${e.message}`);
      continue;
    }
  }

  throw new Error(`All connection methods failed for ${service}`);
}
```

## Setup Integration

When connection detection returns `needsSetup: true`:

1. Prompt user to run the appropriate setup command:
   - Calendar: `/hub-setup-gcalendar`
   - Slack: `/hub-setup-slack`

2. The setup wizard will:
   - Detect available methods
   - Guide through configuration
   - Store preferences in config

---

## Detect Installed Connection Methods

Before presenting setup options, detect what connection methods are actually installed vs just potentially available.

### Installation Status Object

```javascript
function getConnectionStatus() {
  return {
    chrome: { installed: true/false, ready: true/false },
    playwright: { installed: true/false, ready: true/false },
    slackMcp: { installed: true/false, ready: true/false }
  };
}
```

- `installed`: The MCP server/extension is configured and responds
- `ready`: Can be used immediately (browser running, logged in, etc.)

Use `installed` to show option availability in wizards.
Use `ready` to determine if immediate use is possible without additional setup.

### Check Chrome MCP Installed

```javascript
async function checkChromeMcpInstalled() {
  try {
    // Attempt to call tabs_context_mcp
    const context = await mcp__claude-in-chrome__tabs_context_mcp({ createIfEmpty: false });

    // If we get here, the tool exists and responded
    return {
      installed: true,
      ready: context && !context.error
    };
  } catch (e) {
    // Check error type
    if (e.message?.includes('not found') ||
        e.message?.includes('unknown tool') ||
        e.message?.includes('MCP server')) {
      // Tool doesn't exist - extension not installed
      return { installed: false, ready: false };
    }

    // Tool exists but errored (Chrome not running, etc.)
    // Still count as installed
    return { installed: true, ready: false };
  }
}
```

### Check Playwright MCP Installed

```javascript
async function checkPlaywrightMcpInstalled() {
  try {
    // Attempt a simple navigation to about:blank
    const result = await mcp__playwright__browser_navigate({ url: 'about:blank' });

    return {
      installed: true,
      ready: result && !result.error
    };
  } catch (e) {
    // Check error type
    if (e.message?.includes('not found') ||
        e.message?.includes('unknown tool') ||
        e.message?.includes('MCP server')) {
      // Tool doesn't exist - Playwright MCP not configured
      return { installed: false, ready: false };
    }

    // Tool exists but errored (browser issue, etc.)
    return { installed: true, ready: false };
  }
}
```

### Check Slack MCP Installed

```javascript
async function checkSlackMcpInstalled() {
  try {
    // Attempt to list channels with minimal limit
    const result = await mcp__slack__list_channels({ limit: 1 });

    return {
      installed: true,
      ready: result && !result.error
    };
  } catch (e) {
    if (e.message?.includes('not found') ||
        e.message?.includes('unknown tool') ||
        e.message?.includes('MCP server')) {
      return { installed: false, ready: false };
    }

    // Tool exists but auth issue, etc.
    return { installed: true, ready: false };
  }
}
```

### Usage in Setup Wizards

```javascript
// Get all connection statuses before presenting wizard
const chromeStatus = await checkChromeMcpInstalled();
const playwrightStatus = await checkPlaywrightMcpInstalled();

// Build wizard options with dynamic descriptions
const options = [
  {
    label: "Chrome browser tab",
    description: chromeStatus.installed
      ? "✓ Ready - uses open Calendar tab"
      : "⚠️ Requires Claude-in-Chrome extension"
  },
  {
    label: "Playwright (headless)",
    description: playwrightStatus.installed
      ? "✓ Ready - works in background"
      : "⚠️ Requires Playwright MCP server"
  },
  {
    label: "Skip for now",
    description: "Configure later"
  }
];

// After user selection, check if they chose an uninstalled method
if (userChoice === "chrome" && !chromeStatus.installed) {
  // Show installation instructions instead of proceeding
  showChromeInstallationGuide();
  return;
}
```

### Status Descriptions

Use these consistent descriptions in wizards:

| Method | Installed | Description |
|--------|-----------|-------------|
| Chrome | ✓ | "✓ Ready - uses open Calendar tab" |
| Chrome | ✗ | "⚠️ Requires Claude-in-Chrome extension" |
| Playwright | ✓ | "✓ Ready - works in background" |
| Playwright | ✗ | "⚠️ Requires Playwright MCP server" |
| Slack MCP | ✓ | "✓ Ready - direct Slack integration" |
| Slack MCP | ✗ | "⚠️ Requires Slack MCP server" |
