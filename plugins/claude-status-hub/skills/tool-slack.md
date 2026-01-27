# Tool: Slack

Slack data extraction scripts for each connection method. See `connection-detect.md` for connection hierarchy and detection logic.

---

## Slack MCP Mode

**Server:** `https://mcp.slack.com/sse` (SSE transport)

```javascript
// Get unreads
const channels = await mcp__slack__list_channels({ limit: 100 });
let totalUnread = 0;
const unreadChannels = [];
for (const ch of channels.channels || []) {
  if (ch.unread_count > 0) {
    totalUnread += ch.unread_count;
    unreadChannels.push({ name: ch.name, id: ch.id, unreads: ch.unread_count });
  }
}

// Other operations
await mcp__slack__get_channel_history({ channel: 'C123', limit: 20 });
await mcp__slack__search_messages({ query: 'from:@boss' });
await mcp__slack__set_status({ status_text: "Deep focus", status_emoji: ":dart:" });
```

---

## Chrome MCP Mode

### Data Extraction Script

```javascript
(() => {
  const result = { unreadCount: 0, channels: [], dms: [], mentions: [] };

  const unreadBadge = document.querySelector('.p-team_sidebar__mentions_badge');
  result.unreadCount = parseInt(unreadBadge?.textContent || '0', 10);

  document.querySelectorAll('[data-qa="channel_sidebar_name_button"]').forEach(ch => {
    const name = ch.textContent?.trim();
    const container = ch.closest('[data-qa-channel-sidebar-channel-id]');
    const badge = container?.querySelector('.p-channel_sidebar__badge');
    const unreads = parseInt(badge?.textContent || '0', 10);
    if (name && unreads > 0) {
      result.channels.push({
        name, channelId: container?.getAttribute('data-qa-channel-sidebar-channel-id'), unreads
      });
    }
  });

  document.querySelectorAll('[data-qa="im_sidebar_name_button"]').forEach(dm => {
    const name = dm.textContent?.trim();
    const container = dm.closest('[data-qa-channel-sidebar-channel-id]');
    const badge = container?.querySelector('.p-channel_sidebar__badge');
    const unreads = parseInt(badge?.textContent || '0', 10);
    if (name && unreads > 0) {
      result.dms.push({
        name, channelId: container?.getAttribute('data-qa-channel-sidebar-channel-id'), unreads
      });
    }
  });

  document.querySelectorAll('[data-qa="activity_item"]').forEach(item => {
    const text = item.textContent?.substring(0, 100);
    if (text) result.mentions.push(text);
  });

  return result;
})()
```

### Reading Messages

```javascript
(() => {
  const messages = [];
  document.querySelectorAll('[data-qa="message_container"]').forEach(msg => {
    const sender = msg.querySelector('[data-qa="message_sender_name"]')?.textContent;
    const text = msg.querySelector('[data-qa="message-text"]')?.textContent;
    const time = msg.querySelector('[data-qa="message_time"]')?.textContent;
    if (text) messages.push({ sender: sender?.trim(), text: text.substring(0, 500), time: time?.trim() });
  });
  return messages.slice(-20);
})()
```

---

## API Mode (Legacy)

Credential files: `~/.claude/slack-token.json`, `~/.claude/slack-credentials.json`

```bash
slack_get_token() {
  local token_file="$HOME/.claude/slack-token.json"
  local token=$(jq -r '.token' "$token_file")
  local expires_at=$(jq -r '.expires_at // 0' "$token_file")
  [ "$expires_at" -gt $(($(date +%s) + 300)) ] && echo "$token" && return 0
  slack_refresh_token
}

slack_api_call() {
  local endpoint="$1" token=$(slack_get_token) || return 1
  local cookie=$(jq -r '.cookie' "$HOME/.claude/slack-token.json")
  curl -s "https://slack.com/api/$endpoint" -H "Authorization: Bearer $token" --cookie "d=$cookie" "${@:2}"
}
```

---

## Output Format

```json
{
  "unreadCount": 15,
  "channels": [{ "name": "incidents", "id": "C123", "unreads": 5 }],
  "dms": [{ "name": "alice", "id": "D789", "unreads": 2 }],
  "mentions": [{ "channel": "engineering", "preview": "@you review this PR?" }]
}
```

## Alert Detection

```javascript
function checkAlerts(data, config) {
  const vips = config.slack?.vipPeople || [];
  const watchedChannels = config.slack?.channels || [];
  const alerts = [];

  for (const dm of data.dms || []) {
    if (vips.some(v => dm.name.includes(v.replace('@', '')))) {
      alerts.push({ type: 'vip_dm', from: dm.name, unreads: dm.unreads });
    }
  }
  for (const ch of data.channels || []) {
    if (watchedChannels.some(w => ch.name === w.replace('#', ''))) {
      alerts.push({ type: 'watched_channel', channel: ch.name, unreads: ch.unreads });
    }
  }
  return { shouldAlert: alerts.length > 0, alerts };
}
```

---

## Chrome MCP Mode - Sending Messages

### Navigate to Conversation

```javascript
// Navigate to DM by name
(() => {
  const targetName = "<name>".toLowerCase();
  const dmButton = Array.from(document.querySelectorAll('[data-qa="im_sidebar_name_button"]'))
    .find(el => el.textContent?.toLowerCase().includes(targetName));
  if (dmButton) {
    dmButton.click();
    return { success: true, type: 'dm' };
  }
  const chButton = Array.from(document.querySelectorAll('[data-qa="channel_sidebar_name_button"]'))
    .find(el => el.textContent?.toLowerCase().includes(targetName));
  if (chButton) {
    chButton.click();
    return { success: true, type: 'channel' };
  }
  return { success: false, error: 'Conversation not found' };
})()
```

### Focus Message Input

```javascript
(() => {
  const input = document.querySelector('[data-qa="message_input"]');
  if (input) {
    input.focus();
    return { success: true };
  }
  // Fallback: contenteditable div
  const editor = document.querySelector('.ql-editor[contenteditable="true"]');
  if (editor) {
    editor.focus();
    return { success: true, fallback: true };
  }
  return { success: false, error: 'Message input not found' };
})()
```

### Send Message Flow

1. Navigate to conversation (script above)
2. Wait 500ms for load
3. Focus message input (script above)
4. Type message: `mcp__claude-in-chrome__computer({ action: 'type', text: '<message>', tabId })`
5. Send: `mcp__claude-in-chrome__computer({ action: 'key', text: 'Return', tabId })`
6. Wait 300ms, verify send

### Verify Message Sent

```javascript
(() => {
  // Check if input is now empty (message was sent)
  const input = document.querySelector('[data-qa="message_input"]');
  const isEmpty = !input?.textContent?.trim();
  // Check for recent message from self
  const messages = document.querySelectorAll('[data-qa="message_container"]');
  const lastMsg = messages[messages.length - 1];
  const isSelf = lastMsg?.querySelector('[data-qa="message_sender_name"]')?.textContent?.includes('You');
  return { sent: isEmpty || isSelf };
})()
```

---

## Error Table

| Error | Method | Solution |
|-------|--------|----------|
| MCP connection refused | mcp | Corporate firewall; try Chrome mode |
| Tab not found | chrome | Auto-recovered (see `connection-detect.md`) |
| Session expired | playwright | Re-login via setup |
| invalid_auth | api | Token expired; re-extract credentials |
| ratelimited | all | Wait and retry |
| Message input not found | chrome | Slack UI may have changed; try clicking conversation first |
| Send failed | chrome | Copy to clipboard as fallback |
