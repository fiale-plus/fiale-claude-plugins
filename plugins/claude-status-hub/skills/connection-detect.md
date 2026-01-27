# Connection Detection

Shared logic for detecting and selecting the best available connection method for calendar and Slack integrations.

## Connection Hierarchies

| Service | Priority 1 | Priority 2 | Priority 3 | Priority 4 |
|---------|------------|------------|------------|------------|
| Calendar | Chrome MCP | Playwright | - | - |
| Slack | Slack MCP | Chrome MCP | Playwright | API (legacy) |

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

## Service URLs

Default URLs for auto-opening tabs when not found:

```javascript
const SERVICE_URLS = {
  calendar: 'https://calendar.google.com/calendar/u/0/r/day',
  slack: (config) => `https://${config.slack?.workspace || 'app.slack.com'}/client`,
  youtube_music: 'https://music.youtube.com',
  spotify: 'https://open.spotify.com'
};
```

## Auto-Open Tab (Shared Logic)

When a Chrome tab is not found, auto-open it instead of failing. This is the recovery flow used by all Chrome-bound services.

```javascript
async function ensureTabOpen(service, config, configPath = '~/.claude/status-config.json') {
  const storedTabId = config[service]?.chrome?.tabId;

  // Step 1: Check if stored tab is still valid
  if (storedTabId) {
    try {
      const context = await mcp__claude-in-chrome__tabs_context_mcp({ createIfEmpty: false });
      const tabExists = context?.tabs?.some(t => t.id === storedTabId);
      if (tabExists) return { tabId: storedTabId, wasRecovered: false };
    } catch (e) { /* tab not found, will recover */ }
  }

  // Step 2: Tab not found - auto-open new one
  const url = typeof SERVICE_URLS[service] === 'function'
    ? SERVICE_URLS[service](config)
    : SERVICE_URLS[service];

  if (!url) return { error: `No URL configured for ${service}` };

  // Create new tab and navigate
  const newTab = await mcp__claude-in-chrome__tabs_create_mcp();
  const tabId = newTab.tabId;
  await mcp__claude-in-chrome__navigate({ url, tabId });

  // Wait for page load
  await new Promise(r => setTimeout(r, 2000));

  // Step 3: Update config with new tabId
  config[service] = config[service] || {};
  config[service].chrome = config[service].chrome || {};
  config[service].chrome.tabId = tabId;
  // Config should be written by caller after successful operation

  return { tabId, wasRecovered: true, url };
}
```

**Usage in refresh skills:**
```javascript
const { tabId, wasRecovered, error } = await ensureTabOpen('calendar', config);
if (error) return { error };
// Proceed with tabId - it's now guaranteed valid
// If wasRecovered, save config after successful refresh
```

## Generic MCP Check

All MCP availability checks follow this pattern:

```javascript
async function checkMcpAvailable(testCall) {
  try {
    const result = await testCall();
    return { installed: true, ready: result && !result.error };
  } catch (e) {
    const notFound = e.message?.includes('not found') ||
                     e.message?.includes('unknown tool') ||
                     e.message?.includes('MCP server');
    return { installed: !notFound, ready: false };
  }
}

// Usage:
const chrome = await checkMcpAvailable(() =>
  mcp__claude-in-chrome__tabs_context_mcp({ createIfEmpty: false }));

const playwright = await checkMcpAvailable(() =>
  mcp__playwright__browser_navigate({ url: 'about:blank' }));

const slackMcp = await checkMcpAvailable(() =>
  mcp__slack__list_channels({ limit: 1 }));
```

## Detection Logic

```javascript
async function detectConnection(config, service) {
  const preferred = config[service]?.connection || 'auto';
  if (preferred === 'disabled') return { method: 'disabled' };
  if (preferred !== 'auto') return { method: preferred };

  // Auto-detect based on service hierarchy
  const hierarchy = service === 'calendar'
    ? ['chrome', 'playwright']
    : ['mcp', 'chrome', 'playwright', 'api'];

  for (const method of hierarchy) {
    const status = await checkMethodAvailable(method, config, service);
    if (status.ready) return { method, ...status };
    if (status.installed && method === 'chrome') {
      // Auto-recover: ensure tab is open, creating if needed
      const { tabId, wasRecovered, error } = await ensureTabOpen(service, config);
      if (error) continue; // Try next method
      return { method: 'chrome', tabId, wasRecovered };
    }
  }
  return { method: 'unavailable', error: 'No connection method available' };
}
```

**Note:** When `wasRecovered: true`, the caller should save the updated config after a successful refresh to persist the new tabId.

## API Credentials Check (Slack only)

```javascript
function checkSlackApiCredentials() {
  const tokenFile = `${HOME}/.claude/slack-token.json`;
  const credsFile = `${HOME}/.claude/slack-credentials.json`;
  try {
    const token = JSON.parse(fs.readFileSync(tokenFile));
    const creds = JSON.parse(fs.readFileSync(credsFile));
    return token.token && token.cookie && creds.workspace;
  } catch (e) { return false; }
}
```

## Connection Method Usage

### Chrome MCP

```javascript
const context = await mcp__claude-in-chrome__tabs_context_mcp({ createIfEmpty: true });
const data = await mcp__claude-in-chrome__javascript_tool({
  action: 'javascript_exec', tabId, text: extractionScript
});
```

### Playwright MCP

```javascript
await mcp__playwright__browser_navigate({ url });
const snapshot = await mcp__playwright__browser_snapshot();
// Or: await mcp__playwright__browser_evaluate({ expression: script });
```

### Slack MCP

```javascript
const channels = await mcp__slack__list_channels({ limit: 100 });
const messages = await mcp__slack__get_channel_history({ channel: 'C123', limit: 20 });
```

## Error Handling & Fallback

```javascript
async function withFallback(config, service, operation) {
  const methods = service === 'calendar' ? ['chrome', 'playwright']
    : ['mcp', 'chrome', 'playwright', 'api'];

  for (const method of methods) {
    try { return await operation(method); }
    catch (e) { console.log(`${service}: ${method} failed - ${e.message}`); }
  }
  throw new Error(`All connection methods failed for ${service}`);
}
```

## Setup Integration

When `needsSetup: true` returned, prompt user:
- Calendar: `/hub-setup-gcalendar`
- Slack: `/hub-setup-slack`

Status display in wizards:
- Installed + ready: "✓ Ready"
- Installed + not ready: "⚠️ Not connected"
- Not installed: "⚠️ Requires installation"
