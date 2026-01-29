# Hub Ack - Slack Message Actions

Handle Slack VIP DM and watched channel alerts.

## Input

Item with `alerts[]`: `type` (vip_dm/watched_channel), `from`/`channel`, `unreads`.

## Step 1: Get Connection

```bash
cat ~/.claude/status-config.json | jq '.slack // {}'
```

Need `chrome.tabId`. If missing: "Run `/hub-setup-slack` to configure."

## Step 2: Navigate to Conversation

```javascript
// DM
const dm = Array.from(document.querySelectorAll('[data-qa="im_sidebar_name_button"]'))
  .find(el => el.textContent?.toLowerCase().includes("<name>"));
if (dm) dm.click();
// Channel
const ch = Array.from(document.querySelectorAll('[data-qa="channel_sidebar_name_button"]'))
  .find(el => el.textContent?.toLowerCase().includes("<name>"));
if (ch) ch.click();
```

Wait 1s for load.

## Step 3: Fetch Messages

```javascript
const msgs = []; document.querySelectorAll('[data-qa="message_container"]').forEach(m => {
  const sender = m.querySelector('[data-qa="message_sender_name"]')?.textContent?.trim();
  const text = m.querySelector('[data-qa="message-text"]')?.textContent?.substring(0, 500);
  if (text) msgs.push({ sender, text });
}); return msgs.slice(-10);
```

## Step 4: Present Options

**VIP DM:**
```
💬 Message from <sender>: "<preview>"
[1] "On it!"  [2] "Let me check..."  [3] "Thanks, will follow up"  [c] Custom  [v] View  [d] Dismiss
```

**Watched channel:**
```
#<channel> - <N> new: "<last message>"
[1] Mark read  [2] View  [c] Reply  [d] Dismiss
```

## Step 5: Send Reply

Focus `[data-qa="message_input"]`, type text, press Return.

## Step 6: Update State

See `lib-common.md` for config update and bridge update patterns.

## Errors

| Error | Action |
|-------|--------|
| Tab not found | Run `/hub-setup-slack` |
| Can't find DM | Open Slack manually |
| Send failed | Clipboard fallback: `echo "<text>" | pbcopy` |
