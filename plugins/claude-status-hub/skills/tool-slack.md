# Tool: Slack

Slack extraction per connection method. See `connection-detect.md` for detection and auto-recovery.

## Slack MCP Mode

Server: `https://mcp.slack.com/sse`

```javascript
const channels = await mcp__slack__list_channels({ limit: 100 });
await mcp__slack__get_channel_history({ channel: 'C123', limit: 20 });
await mcp__slack__set_status({ status_text: "Focus", status_emoji: ":dart:" });
```

## Chrome MCP Mode

### Extraction

```javascript
(() => {
  const r = { unreadCount: 0, channels: [], dms: [], mentions: [] };
  r.unreadCount = parseInt(document.querySelector('.p-team_sidebar__mentions_badge')?.textContent || '0', 10);
  document.querySelectorAll('[data-qa="channel_sidebar_name_button"]').forEach(ch => {
    const name = ch.textContent?.trim();
    const container = ch.closest('[data-qa-channel-sidebar-channel-id]');
    const unreads = parseInt(container?.querySelector('.p-channel_sidebar__badge')?.textContent || '0', 10);
    if (name && unreads > 0) r.channels.push({ name, channelId: container?.getAttribute('data-qa-channel-sidebar-channel-id'), unreads });
  });
  document.querySelectorAll('[data-qa="im_sidebar_name_button"]').forEach(dm => {
    const name = dm.textContent?.trim();
    const container = dm.closest('[data-qa-channel-sidebar-channel-id]');
    const unreads = parseInt(container?.querySelector('.p-channel_sidebar__badge')?.textContent || '0', 10);
    if (name && unreads > 0) r.dms.push({ name, channelId: container?.getAttribute('data-qa-channel-sidebar-channel-id'), unreads });
  });
  return r;
})()
```

### Read Messages

```javascript
(() => {
  const msgs = [];
  document.querySelectorAll('[data-qa="message_container"]').forEach(m => {
    const sender = m.querySelector('[data-qa="message_sender_name"]')?.textContent?.trim();
    const text = m.querySelector('[data-qa="message-text"]')?.textContent?.substring(0, 500);
    const time = m.querySelector('[data-qa="message_time"]')?.textContent?.trim();
    if (text) msgs.push({ sender, text, time });
  });
  return msgs.slice(-20);
})()
```

### Navigate & Send

Navigate: Click `[data-qa="im_sidebar_name_button"]` or `[data-qa="channel_sidebar_name_button"]` matching name.

Send: Focus `[data-qa="message_input"]`, type text, press Return.

## Alert Detection

```javascript
function checkAlerts(data, config) {
  const vips = config.slack?.vipPeople || [], watched = config.slack?.channels || [], alerts = [];
  for (const dm of data.dms || []) if (vips.some(v => dm.name.includes(v.replace('@', '')))) alerts.push({ type: 'vip_dm', from: dm.name, unreads: dm.unreads });
  for (const ch of data.channels || []) if (watched.some(w => ch.name === w.replace('#', ''))) alerts.push({ type: 'watched_channel', channel: ch.name, unreads: ch.unreads });
  return { shouldAlert: alerts.length > 0, alerts };
}
```

## Errors

| Error | Solution |
|-------|----------|
| MCP refused | Firewall; try Chrome mode |
| Tab not found | Auto-recovered |
| invalid_auth | Re-extract credentials |
| Send failed | Clipboard fallback |
