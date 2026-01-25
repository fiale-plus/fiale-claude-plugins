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
      const tabId = config[service]?.chrome?.tabId;
      if (tabId) return { method: 'chrome', tabId };
      return { method: 'chrome', needsSetup: true };
    }
  }
  return { method: 'unavailable', error: 'No connection method available' };
}
```

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
