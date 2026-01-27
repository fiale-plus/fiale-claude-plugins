# Hub Refresh - Slack

Refresh Slack data using the configured connection method.

See `connection-detect.md` for detection logic and `tool-slack.md` for extraction scripts.

## Refresh Flow

```javascript
async function refreshSlack(config) {
  const connection = await detectSlackConnection(config);

  if (connection.method === 'disabled') return { disabled: true };
  if (connection.method === 'unavailable') return { error: 'Run /hub-setup-slack' };

  // Get data via appropriate method (see tool-slack.md for scripts)
  const data = await refreshViaMethod(connection.method, config, connection.tabId);
  const result = processSlackData(data, config);

  // If tab was auto-recovered, save updated config with new tabId
  if (connection.wasRecovered) result.configUpdated = true;

  return result;
}
```

**Auto-Recovery:** If the Slack tab was closed, `detectSlackConnection` auto-opens it (see `connection-detect.md`). The new tabId is stored in `config.slack.chrome.tabId` and should be persisted after successful refresh.

## Process Slack Data

```javascript
function processSlackData(data, config) {
  const vips = config.slack?.vipPeople || [];
  const watchedChannels = config.slack?.channels || [];
  const alerts = [];

  for (const dm of data.dms || []) {
    if (vips.some(v => dm.name.toLowerCase().includes(v.replace('@', '').toLowerCase()))) {
      alerts.push({ type: 'vip_dm', from: dm.name, unreads: dm.unreads });
    }
  }

  for (const ch of data.channels || []) {
    if (watchedChannels.some(w => ch.name === w.replace('#', ''))) {
      alerts.push({ type: 'watched_channel', channel: ch.name, unreads: ch.unreads });
    }
  }

  return {
    unreadCount: data.unreadCount || 0,
    channels: data.channels || [],
    dms: data.dms || [],
    hasAlert: alerts.length > 0,
    alerts
  };
}
```

## Output Format

```json
{
  "site": "slack",
  "icon": "💬",
  "title": "Slack",
  "detail": "15 unreads",
  "hasAlert": true,
  "data": {
    "unreadCount": 15,
    "alerts": [{ "type": "vip_dm", "from": "boss", "unreads": 2 }]
  }
}
```

Icons: `💬` unreads, `🔴` alert, `✓` clear

## Bridge Update

```bash
${CLAUDE_PLUGIN_ROOT}/bin/update-bridge.sh slack '{"icon":"💬","title":"Slack","detail":"15 unreads","hasAlert":true}'
```

## Config Update

Store for ack:
```json
{ "slack": { "lastSeen": { "unreadCount": 15, "alerts": [...] } } }
```
