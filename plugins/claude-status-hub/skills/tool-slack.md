# Tool: Slack

Slack integration with multiple connection methods for different environments.

## Connection Hierarchy

1. **Slack MCP** (`mcp`) - Primary for non-corporate setups, official Slack integration
2. **Chrome MCP** (`chrome`) - For corporate setups blocking Slack MCP
3. **Playwright** (`playwright`) - Headless browser fallback
4. **API** (`api`) - xoxc+d cookie method (unreliable, last resort)

See `connection-detect.md` for detection logic.

## Config Structure

See `connection-detect.md` for full config schema.

---

## Slack MCP Mode (Primary)

### Overview

Official Slack MCP plugin provides direct API access without browser automation.
Best for non-corporate environments where MCP connections are allowed.

**Server:** `https://mcp.slack.com/sse` (SSE transport)

### Available Tools

| Tool | Description |
|------|-------------|
| `mcp__slack__list_channels` | List accessible channels |
| `mcp__slack__get_channel_history` | Get messages from a channel |
| `mcp__slack__get_thread` | Get thread replies |
| `mcp__slack__search_messages` | Search across workspace |
| `mcp__slack__post_message` | Send a message |
| `mcp__slack__get_users` | List workspace users |

### Usage Examples

```javascript
// List channels
const channels = await mcp__slack__list_channels({
  limit: 100,
  types: 'public_channel,private_channel'
});

// Get recent messages from a channel
const messages = await mcp__slack__get_channel_history({
  channel: 'C123ABC',
  limit: 20
});

// Search messages
const results = await mcp__slack__search_messages({
  query: 'project update from:@boss'
});

// Get thread replies
const thread = await mcp__slack__get_thread({
  channel: 'C123ABC',
  ts: '1705344000.000100'
});

// Post a message
await mcp__slack__post_message({
  channel: 'C123ABC',
  text: 'Hello from Claude!'
});
```

### Get Unread Counts

```javascript
async function getUnreadsViaMcp() {
  // Slack MCP may have a specific unread endpoint
  // Otherwise, iterate channels and check for unreads
  const channels = await mcp__slack__list_channels({ limit: 100 });

  let totalUnread = 0;
  const unreadChannels = [];

  for (const ch of channels.channels || []) {
    if (ch.unread_count > 0) {
      totalUnread += ch.unread_count;
      unreadChannels.push({
        name: ch.name,
        id: ch.id,
        unreads: ch.unread_count
      });
    }
  }

  return { totalUnread, unreadChannels };
}
```

---

## Chrome MCP Mode

### Overview

For corporate environments that block Slack MCP but allow browser access.
Requires Slack open in a Chrome tab with Claude-in-Chrome extension.

### Prerequisites

- Slack workspace open in browser tab
- Claude-in-Chrome extension installed
- Tab ID stored in `slack.chrome.tabId`

### Data Extraction Script

Run via `mcp__claude-in-chrome__javascript_tool`:

```javascript
(() => {
  const result = {
    unreadCount: 0,
    channels: [],
    dms: [],
    mentions: []
  };

  // Get total unread badge
  const unreadBadge = document.querySelector('.p-team_sidebar__mentions_badge');
  result.unreadCount = parseInt(unreadBadge?.textContent || '0', 10);

  // Get channel unreads
  document.querySelectorAll('[data-qa="channel_sidebar_name_button"]').forEach(ch => {
    const name = ch.textContent?.trim();
    const container = ch.closest('[data-qa-channel-sidebar-channel-id]');
    const badge = container?.querySelector('.p-channel_sidebar__badge');
    const unreads = parseInt(badge?.textContent || '0', 10);

    if (name && unreads > 0) {
      result.channels.push({
        name: name,
        channelId: container?.getAttribute('data-qa-channel-sidebar-channel-id'),
        unreads: unreads
      });
    }
  });

  // Get DM unreads
  document.querySelectorAll('[data-qa="im_sidebar_name_button"]').forEach(dm => {
    const name = dm.textContent?.trim();
    const container = dm.closest('[data-qa-channel-sidebar-channel-id]');
    const badge = container?.querySelector('.p-channel_sidebar__badge');
    const unreads = parseInt(badge?.textContent || '0', 10);

    if (name && unreads > 0) {
      result.dms.push({
        name: name,
        channelId: container?.getAttribute('data-qa-channel-sidebar-channel-id'),
        unreads: unreads
      });
    }
  });

  // Get mentions from activity section
  document.querySelectorAll('[data-qa="activity_item"]').forEach(item => {
    const text = item.textContent?.substring(0, 100);
    if (text) {
      result.mentions.push(text);
    }
  });

  return result;
})()
```

### Usage Example

```javascript
// 1. Get tab context
const context = await mcp__claude-in-chrome__tabs_context_mcp({ createIfEmpty: false });
const tabId = config.slack.chrome.tabId;

// 2. Verify tab is on Slack
const pageText = await mcp__claude-in-chrome__get_page_text({ tabId });
if (!pageText.includes('slack.com')) {
  await mcp__claude-in-chrome__navigate({
    tabId,
    url: `https://${config.slack.workspace}`
  });
}

// 3. Extract Slack data
const data = await mcp__claude-in-chrome__javascript_tool({
  action: 'javascript_exec',
  tabId: tabId,
  text: extractionScript
});
```

### Reading Messages

To read actual message content from a channel:

```javascript
(() => {
  const messages = [];

  document.querySelectorAll('[data-qa="message_container"]').forEach(msg => {
    const sender = msg.querySelector('[data-qa="message_sender_name"]')?.textContent;
    const text = msg.querySelector('[data-qa="message-text"]')?.textContent;
    const time = msg.querySelector('[data-qa="message_time"]')?.textContent;

    if (text) {
      messages.push({
        sender: sender?.trim(),
        text: text.substring(0, 500),
        time: time?.trim()
      });
    }
  });

  return messages.slice(-20); // Last 20 messages
})()
```

---

## Playwright Mode

### Overview

Headless browser automation when Chrome MCP is unavailable.
Uses persistent profile for authentication.

### Prerequisites

- Playwright MCP installed (`npx @playwright/mcp@latest`)
- Slack workspace logged in (via persistent profile)

### Profile Setup

```bash
# First-time setup: log into Slack manually
npx playwright open --save-storage=~/.claude/playwright-profile https://mycompany.slack.com
```

### Usage Example

```javascript
// 1. Navigate to Slack
await mcp__playwright__browser_navigate({
  url: `https://${config.slack.workspace}`
});

// 2. Wait for page load
await mcp__playwright__browser_wait({
  selector: '[data-qa="channel_sidebar"]',
  timeout: 15000
});

// 3. Execute extraction script
const data = await mcp__playwright__browser_evaluate({
  expression: extractionScript
});
```

---

## API Mode (Legacy Fallback)

### Overview

Uses xoxc token + d cookie extracted from browser.
**Unreliable** - tokens expire frequently and require manual refresh.

Use only when all other methods fail.

### Credential Files

- `~/.claude/slack-credentials.json` - Workspace URL
- `~/.claude/slack-token.json` - xoxc token + d cookie

### Token Management

```bash
slack_get_token() {
  local token_file="$HOME/.claude/slack-token.json"
  local creds_file="$HOME/.claude/slack-credentials.json"

  if [ ! -f "$token_file" ] || [ ! -f "$creds_file" ]; then
    echo "ERROR: Slack credentials not configured" >&2
    return 1
  fi

  local token=$(jq -r '.token' "$token_file")
  local expires_at=$(jq -r '.expires_at // 0' "$token_file")
  local now=$(date +%s)

  if [ "$expires_at" -gt $((now + 300)) ] && [ -n "$token" ]; then
    echo "$token"
    return 0
  fi

  # Token expired, try refresh
  slack_refresh_token
}

slack_refresh_token() {
  local creds_file="$HOME/.claude/slack-credentials.json"
  local token_file="$HOME/.claude/slack-token.json"

  local workspace=$(jq -r '.workspace' "$creds_file")
  local cookie=$(jq -r '.cookie' "$token_file")

  local response=$(curl -sL --cookie "d=$cookie" "https://$workspace")
  local new_token=$(echo "$response" | grep -oE '"token":"xoxc-[^"]+' | head -1 | cut -d'"' -f4)

  if [ -z "$new_token" ]; then
    echo "ERROR: Token refresh failed" >&2
    return 1
  fi

  local new_expires_at=$(($(date +%s) + 21600))
  jq --arg token "$new_token" --argjson expires "$new_expires_at" \
    '.token = $token | .expires_at = $expires' "$token_file" > "$token_file.tmp" \
    && mv "$token_file.tmp" "$token_file"

  echo "$new_token"
}
```

### API Calls

```bash
# Auth test
slack_auth_test() {
  local token=$(slack_get_token) || return 1
  local cookie=$(jq -r '.cookie' "$HOME/.claude/slack-token.json")

  curl -s "https://slack.com/api/auth.test" \
    -H "Authorization: Bearer $token" \
    --cookie "d=$cookie"
}

# List channels
slack_list_channels() {
  local token=$(slack_get_token) || return 1
  local cookie=$(jq -r '.cookie' "$HOME/.claude/slack-token.json")

  curl -s "https://slack.com/api/conversations.list" \
    -H "Authorization: Bearer $token" \
    --cookie "d=$cookie" \
    -G --data-urlencode "types=public_channel,private_channel" \
    --data-urlencode "limit=100"
}

# Get messages
slack_get_messages() {
  local channel="$1"
  local limit="${2:-20}"
  local token=$(slack_get_token) || return 1
  local cookie=$(jq -r '.cookie' "$HOME/.claude/slack-token.json")

  curl -s "https://slack.com/api/conversations.history" \
    -H "Authorization: Bearer $token" \
    --cookie "d=$cookie" \
    -G --data-urlencode "channel=$channel" \
    --data-urlencode "limit=$limit"
}

# Post message
slack_post_message() {
  local channel="$1"
  local text="$2"
  local token=$(slack_get_token) || return 1
  local cookie=$(jq -r '.cookie' "$HOME/.claude/slack-token.json")

  local payload=$(jq -n --arg ch "$channel" --arg txt "$text" \
    '{channel: $ch, text: $txt}')

  curl -s -X POST "https://slack.com/api/chat.postMessage" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    --cookie "d=$cookie" \
    -d "$payload"
}
```

---

## Output Format

Standardized format for hub integration:

```json
{
  "unreadCount": 15,
  "channels": [
    { "name": "incidents", "id": "C123ABC", "unreads": 5 },
    { "name": "engineering", "id": "C456DEF", "unreads": 10 }
  ],
  "dms": [
    { "name": "alice", "id": "D789GHI", "unreads": 2 }
  ],
  "mentions": [
    { "channel": "engineering", "preview": "@you can you review this PR?" }
  ]
}
```

## Alert Detection

Check for VIP messages and important keywords:

```javascript
function checkAlerts(data, config) {
  const vips = config.slack?.vipPeople || [];
  const watchedChannels = config.slack?.channels || [];
  const keywords = config.slack?.keywords || [];

  const alerts = [];

  // Check for VIP DMs
  for (const dm of data.dms || []) {
    if (vips.some(v => dm.name.includes(v.replace('@', '')))) {
      alerts.push({
        type: 'vip_dm',
        from: dm.name,
        unreads: dm.unreads
      });
    }
  }

  // Check watched channels
  for (const ch of data.channels || []) {
    if (watchedChannels.some(w => ch.name === w.replace('#', ''))) {
      alerts.push({
        type: 'watched_channel',
        channel: ch.name,
        unreads: ch.unreads
      });
    }
  }

  return {
    shouldAlert: alerts.length > 0,
    alerts: alerts
  };
}
```

## Fallback Strategy

```javascript
async function getSlackData(config) {
  const connection = await detectSlackConnection(config);

  switch (connection.method) {
    case 'mcp':
      return await getDataViaMcp();

    case 'chrome':
      return await getDataViaChrome(config, connection.tabId);

    case 'playwright':
      return await getDataViaPlaywright(config);

    case 'api':
      return await getDataViaApi(config);

    case 'unavailable':
      throw new Error('Slack: No connection available. Run /hub-setup-slack');

    case 'disabled':
      return { unreadCount: 0, disabled: true };
  }
}
```

## Error Handling

| Error | Method | Solution |
|-------|--------|----------|
| MCP connection refused | `mcp` | Corporate firewall blocking; try Chrome mode |
| Tab not found | `chrome` | Re-run `/hub-setup-slack` |
| Session expired | `playwright` | Re-login via setup |
| invalid_auth | `api` | Token expired; re-extract credentials |
| ratelimited | all | Wait and retry |

## Troubleshooting

For connection issues (MCP blocked, Playwright cache, API token expiry), run `/hub-setup-slack` which includes troubleshooting steps and can reconfigure your connection method.
