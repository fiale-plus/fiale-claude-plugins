# Hub Ack - Slack Message Actions

Handle Slack VIP DM and watched channel alerts with contextual actions.

## Input

Receives Slack item with: `alerts[]` containing `type`, `from`/`channel`, `unreads`

## Step 1: Get Connection

Check config for Slack connection:
```bash
cat ~/.claude/status-config.json | jq '.slack // {}'
```

Extract:
- `chrome.tabId` - Slack tab for Chrome MCP
- `workspace` - Slack workspace name

If no `chrome.tabId`: "Run `/hub-setup-slack` to configure Slack connection"

## Step 2: Navigate to Conversation

For VIP DM alerts, navigate to the DM conversation:

```javascript
// Find the DM in sidebar and click
const dmName = "<alert.from>";
const dmButton = Array.from(document.querySelectorAll('[data-qa="im_sidebar_name_button"]'))
  .find(el => el.textContent?.toLowerCase().includes(dmName.toLowerCase()));
if (dmButton) dmButton.click();
```

For watched channel alerts:
```javascript
const channelName = "<alert.channel>";
const chButton = Array.from(document.querySelectorAll('[data-qa="channel_sidebar_name_button"]'))
  .find(el => el.textContent?.toLowerCase().includes(channelName.toLowerCase()));
if (chButton) chButton.click();
```

Wait 1s for conversation to load.

## Step 3: Fetch Recent Messages

Use Chrome MCP to extract messages from the conversation:

```javascript
(() => {
  const messages = [];
  document.querySelectorAll('[data-qa="message_container"]').forEach(msg => {
    const sender = msg.querySelector('[data-qa="message_sender_name"]')?.textContent;
    const text = msg.querySelector('[data-qa="message-text"]')?.textContent;
    const time = msg.querySelector('[data-qa="message_time"]')?.textContent;
    if (text) messages.push({
      sender: sender?.trim(),
      text: text.substring(0, 500),
      time: time?.trim()
    });
  });
  return messages.slice(-10);
})()
```

## Step 4: Analyze and Present Options

### Case A: VIP DM

Display:
```
💬 Message from <sender>
   <timestamp>

   "<message preview - first 200 chars>"

   Reply options:
   [1] "On it!"
   [2] "Let me check and get back to you"
   [3] "Thanks, will follow up"
   [4] "Got it, working on this now"
   [c] Custom reply
   [v] View full thread
   [d] Dismiss
```

**AI-adapted replies:** Analyze message context to prioritize options:
- Question (contains ?) → Prioritize "Let me check and get back to you"
- Request/task → Prioritize "On it!" or "Got it, working on this now"
- FYI/informational → Prioritize "Thanks, will follow up"

### Case B: Watched Channel

Display:
```
#<channel> - <N> new messages

   Latest: "<last message preview>"
   From: <sender>

   [1] Mark as read
   [2] View thread
   [c] Reply to thread
   [d] Dismiss
```

## Step 5: Execute Reply

If user selects a reply option:

### 5a: Focus Message Input

```javascript
const input = document.querySelector('[data-qa="message_input"]');
if (input) {
  input.focus();
  return true;
}
return false;
```

### 5b: Type Reply

Use `mcp__claude-in-chrome__form_input` or `computer` tool:
```javascript
// Type the reply text
mcp__claude-in-chrome__computer({
  action: 'type',
  text: '<reply_text>',
  tabId: <tabId>
})
```

### 5c: Send Message

```javascript
// Press Enter to send
mcp__claude-in-chrome__computer({
  action: 'key',
  text: 'Return',
  tabId: <tabId>
})
```

**Confirmation:** Tell user "Message sent" after successful send.

## Step 6: Custom Reply

If user selects custom reply:

1. Ask for their message text
2. Type and send via Steps 5a-5c

## Step 7: View Full Thread

If user selects view:

1. Already navigated to conversation in Step 2
2. Display last 10 messages with full text
3. Offer reply options again

## Step 8: Update Config and Bridge

After handling:

### 8a: Update Config

```bash
# Mark alert as handled
jq '.foreground |= map(if .site == "slack" then .hasAlert = false | .lastSeen.alerts = [] else . end)' \
  ~/.claude/status-config.json > /tmp/config-tmp.json && mv /tmp/config-tmp.json ~/.claude/status-config.json
```

### 8b: Update Bridge

**CRITICAL**: Statusline reads bridge, not config. Update immediately:

```bash
FOREGROUND=$(jq -c '.foreground // []' ~/.claude/status-config.json)
BACKGROUND=$(jq -c '.background // {}' /tmp/status-hub.json)
${CLAUDE_PLUGIN_ROOT}/bin/update-bridge.sh \
  "$(echo "$BACKGROUND" | jq -r '.site')" \
  "$(echo "$BACKGROUND" | jq -r '.icon')" \
  "$(echo "$BACKGROUND" | jq -r '.title')" \
  "$(echo "$BACKGROUND" | jq -r '.detail')" \
  --foreground "$FOREGROUND"
```

## Reply Templates

| Context | Template | When to use |
|---------|----------|-------------|
| Acknowledgment | "On it!" | Task assignment, request |
| Investigating | "Let me check and get back to you" | Question, needs research |
| Received | "Thanks, will follow up" | FYI, update, informational |
| Active | "Got it, working on this now" | Urgent task, priority item |

## Error Handling

| Error | Action |
|-------|--------|
| Tab not found | "Slack tab closed. Run `/hub-setup-slack`" |
| Can't find DM | "Couldn't find conversation. Open Slack manually." |
| Send failed | "Couldn't send. Message copied to clipboard." |
| No connection | "Run `/hub-setup-slack` to configure" |

## Clipboard Fallback

If Chrome MCP fails to send:
```bash
echo "<reply_text>" | pbcopy  # macOS
```
Tell user: "Couldn't send via browser. Message copied to clipboard."
