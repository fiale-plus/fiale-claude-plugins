# Connection Detection

Shared logic for detecting and selecting connection methods.

## Hierarchies

| Service | Priority 1 | Priority 2 | Priority 3 | Priority 4 |
|---------|------------|------------|------------|------------|
| Calendar | Chrome MCP | Playwright | - | - |
| Slack | Slack MCP | Chrome MCP | Playwright | API |

## Service URLs

```javascript
const SERVICE_URLS = {
  calendar: 'https://calendar.google.com/calendar/u/0/r/day',
  slack: (cfg) => `https://${cfg.slack?.workspace || 'app.slack.com'}/client`,
  youtube_music: 'https://music.youtube.com',
  spotify: 'https://open.spotify.com'
};
```

## Auto-Open Tab

When Chrome tab missing, auto-open instead of failing:

```javascript
async function ensureTabOpen(service, config) {
  const storedTabId = config[service]?.chrome?.tabId;
  if (storedTabId) {
    const ctx = await mcp__claude-in-chrome__tabs_context_mcp({ createIfEmpty: false });
    if (ctx?.tabs?.some(t => t.id === storedTabId)) return { tabId: storedTabId, wasRecovered: false };
  }
  const url = typeof SERVICE_URLS[service] === 'function' ? SERVICE_URLS[service](config) : SERVICE_URLS[service];
  if (!url) return { error: `No URL for ${service}` };
  const newTab = await mcp__claude-in-chrome__tabs_create_mcp();
  await mcp__claude-in-chrome__navigate({ url, tabId: newTab.tabId });
  await new Promise(r => setTimeout(r, 2000));
  config[service] = config[service] || {}; config[service].chrome = { tabId: newTab.tabId };
  return { tabId: newTab.tabId, wasRecovered: true, url };
}
```

## MCP Check

```javascript
async function checkMcpAvailable(testCall) {
  try { const r = await testCall(); return { installed: true, ready: r && !r.error }; }
  catch (e) { return { installed: !e.message?.includes('not found'), ready: false }; }
}
```

## Detection Logic

```javascript
async function detectConnection(config, service) {
  const pref = config[service]?.connection || 'auto';
  if (pref === 'disabled') return { method: 'disabled' };
  if (pref !== 'auto') return { method: pref };
  const hierarchy = service === 'calendar' ? ['chrome', 'playwright'] : ['mcp', 'chrome', 'playwright', 'api'];
  for (const m of hierarchy) {
    const s = await checkMethodAvailable(m, config, service);
    if (s.ready) return { method: m, ...s };
    if (s.installed && m === 'chrome') {
      const { tabId, wasRecovered, error } = await ensureTabOpen(service, config);
      if (!error) return { method: 'chrome', tabId, wasRecovered };
    }
  }
  return { method: 'unavailable', error: 'No connection available' };
}
```

## Setup Integration

When `needsSetup: true`: prompt `/hub-setup-gcalendar` or `/hub-setup-slack`.

Status: Ready = "✓", Not connected = "⚠️ Not connected", Not installed = "⚠️ Requires installation".
