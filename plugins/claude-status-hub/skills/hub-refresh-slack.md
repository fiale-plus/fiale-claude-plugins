# Hub Refresh - Slack

Refresh Slack data using the configured connection method (Slack MCP, Chrome MCP, Playwright, or API).

## Connection Detection

Check `slack.connection` in config. If "auto", detect available method.

See `connection-detect.md` for detection logic and `tool-slack.md` for implementation details.

## Config Structure

See `connection-detect.md` for full config schema.

## Refresh Flow

```javascript
async function refreshSlack(config) {
  // 1. Detect connection method
  const connection = await detectSlackConnection(config);

  if (connection.method === 'disabled') {
    return { disabled: true };
  }

  if (connection.method === 'unavailable') {
    return { error: 'No connection available. Run /hub-setup-slack' };
  }

  // 2. Get data via appropriate method
  let data;
  switch (connection.method) {
    case 'mcp':
      data = await refreshViaMcp(config);
      break;
    case 'chrome':
      data = await refreshViaChrome(config, connection.tabId);
      break;
    case 'playwright':
      data = await refreshViaPlaywright(config);
      break;
    case 'api':
      data = await refreshViaApi(config);
      break;
  }

  // 3. Process and return
  return processSlackData(data, config);
}
```

---

## Slack MCP Mode

### Overview

Official Slack MCP provides direct API access. Best for non-corporate environments.

### Usage

```javascript
async function refreshViaMcp(config) {
  // Get channels with unread counts
  const channels = await mcp__slack__list_channels({
    limit: 100,
    types: 'public_channel,private_channel,im,mpim'
  });

  let totalUnread = 0;
  const unreadChannels = [];
  const unreadDms = [];

  for (const ch of channels.channels || []) {
    if (ch.unread_count > 0) {
      totalUnread += ch.unread_count;

      const item = {
        name: ch.name || ch.user,
        id: ch.id,
        unreads: ch.unread_count
      };

      if (ch.is_im || ch.is_mpim) {
        unreadDms.push(item);
      } else {
        unreadChannels.push(item);
      }
    }
  }

  return {
    unreadCount: totalUnread,
    channels: unreadChannels,
    dms: unreadDms,
    mentions: []
  };
}
```

---

## Chrome MCP Mode

### Overview

For corporate environments blocking Slack MCP. Requires Slack open in Chrome.

### Data Extraction Script

See `tool-slack.md` for the JavaScript extraction script.

### Usage

```javascript
async function refreshViaChrome(config, tabId) {
  // Verify tab context
  const context = await mcp__claude-in-chrome__tabs_context_mcp({ createIfEmpty: false });

  if (!tabId) {
    throw new Error('Slack tab not configured. Run /hub-setup-slack');
  }

  // Verify tab is on Slack
  const pageText = await mcp__claude-in-chrome__get_page_text({ tabId });
  if (!pageText.includes('slack.com')) {
    // Navigate to Slack
    await mcp__claude-in-chrome__navigate({
      tabId,
      url: `https://${config.slack.workspace}`
    });
    // Wait for load
    await new Promise(r => setTimeout(r, 3000));
  }

  // Execute extraction
  const data = await mcp__claude-in-chrome__javascript_tool({
    action: 'javascript_exec',
    tabId: tabId,
    text: extractionScript
  });

  return data;
}
```

---

## Playwright Mode

### Overview

Headless browser automation when Chrome MCP is unavailable.

### Usage

```javascript
async function refreshViaPlaywright(config) {
  // Navigate to Slack
  await mcp__playwright__browser_navigate({
    url: `https://${config.slack.workspace}`
  });

  // Wait for sidebar to load
  await mcp__playwright__browser_wait({
    selector: '[data-qa="channel_sidebar"]',
    timeout: 15000
  });

  // Execute extraction script
  const data = await mcp__playwright__browser_evaluate({
    expression: extractionScript
  });

  return data;
}
```

---

## API Mode (Legacy)

### Overview

Uses xoxc token + d cookie. Unreliable fallback.

### Usage

```bash
refreshViaApi() {
  local token=$(slack_get_token) || return 1
  local cookie=$(jq -r '.cookie' "$HOME/.claude/slack-token.json")

  # Get conversations list with unread info
  local response=$(curl -s "https://slack.com/api/conversations.list" \
    -H "Authorization: Bearer $token" \
    --cookie "d=$cookie" \
    -G --data-urlencode "types=public_channel,private_channel,im,mpim" \
    --data-urlencode "limit=100")

  # Parse and return
  echo "$response" | jq '{
    unreadCount: ([.channels[]? | select(.unread_count > 0) | .unread_count] | add // 0),
    channels: [.channels[]? | select(.is_channel and .unread_count > 0) | {name: .name, id: .id, unreads: .unread_count}],
    dms: [.channels[]? | select(.is_im and .unread_count > 0) | {name: .user, id: .id, unreads: .unread_count}],
    mentions: []
  }'
}
```

---

## Process Slack Data

```javascript
function processSlackData(data, config) {
  const vips = config.slack?.vipPeople || [];
  const watchedChannels = config.slack?.channels || [];

  const alerts = [];

  // Check for VIP DMs
  for (const dm of data.dms || []) {
    const isVip = vips.some(v => dm.name.toLowerCase().includes(v.replace('@', '').toLowerCase()));
    if (isVip) {
      alerts.push({
        type: 'vip_dm',
        from: dm.name,
        unreads: dm.unreads
      });
    }
  }

  // Check watched channels
  for (const ch of data.channels || []) {
    const isWatched = watchedChannels.some(w => ch.name === w.replace('#', ''));
    if (isWatched) {
      alerts.push({
        type: 'watched_channel',
        channel: ch.name,
        unreads: ch.unreads
      });
    }
  }

  return {
    unreadCount: data.unreadCount || 0,
    channels: data.channels || [],
    dms: data.dms || [],
    mentions: data.mentions || [],
    hasAlert: alerts.length > 0,
    alerts: alerts
  };
}
```

## Output Format

Return for bridge/statusline:

```json
{
  "site": "slack",
  "icon": "💬",
  "title": "Slack",
  "detail": "15 unreads",
  "hasAlert": true,
  "data": {
    "unreadCount": 15,
    "channels": [
      { "name": "incidents", "id": "C123ABC", "unreads": 5 }
    ],
    "dms": [
      { "name": "boss", "id": "D789GHI", "unreads": 2 }
    ],
    "alerts": [
      { "type": "vip_dm", "from": "boss", "unreads": 2 }
    ]
  }
}
```

Icon options:
- `💬` = has unreads
- `🔴` = alert active (VIP or watched channel)
- `✓` = no unreads

## Update Config

Store last seen state for ack:

```json
{
  "slack": {
    "lastSeen": {
      "unreadCount": 15,
      "alerts": [
        { "type": "vip_dm", "from": "boss", "unreads": 2 }
      ]
    }
  }
}
```

## Error Handling

### Connection Method Failures

```javascript
async function refreshWithFallback(config) {
  const methods = ['mcp', 'chrome', 'playwright', 'api'];

  for (const method of methods) {
    try {
      switch (method) {
        case 'mcp':
          return await refreshViaMcp(config);
        case 'chrome':
          if (config.slack?.chrome?.tabId) {
            return await refreshViaChrome(config, config.slack.chrome.tabId);
          }
          continue;
        case 'playwright':
          return await refreshViaPlaywright(config);
        case 'api':
          return await refreshViaApi(config);
      }
    } catch (e) {
      console.log(`Slack ${method} failed: ${e.message}`);
      continue;
    }
  }

  throw new Error('All Slack connection methods failed');
}
```

### Specific Errors

| Error | Method | Solution |
|-------|--------|----------|
| Connection refused | `mcp` | Corporate blocking; switch to Chrome |
| Tab not found | `chrome` | Re-run `/hub-setup-slack` |
| Not logged in | `playwright` | Re-login via setup |
| invalid_auth | `api` | Token expired; re-extract |

## Bridge Update

Update the bridge file with Slack status:

```bash
${CLAUDE_PLUGIN_ROOT}/bin/update-bridge.sh slack '{"icon":"💬","title":"Slack","detail":"15 unreads","hasAlert":true}'
```

Or on error:

```bash
${CLAUDE_PLUGIN_ROOT}/bin/update-bridge.sh --error "Slack: Connection failed"
```
