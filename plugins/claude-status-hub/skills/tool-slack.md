# Tool: Slack API

Curl-based Slack API operations using browser session tokens (xoxc + d cookie).

## Config Structure

Slack API config in `~/.claude/status-config.json`:

```json
{
  "slack": {
    "workspace": "mycompany.slack.com",
    "defaultChannel": "C123ABC"
  }
}
```

Credentials stored separately:
- `~/.claude/slack-credentials.json` - Workspace URL
- `~/.claude/slack-token.json` - xoxc token + d cookie

## Credential Files

### `slack-credentials.json`

```json
{
  "workspace": "mycompany.slack.com"
}
```

### `slack-token.json`

```json
{
  "token": "xoxc-xxx-xxx-xxx",
  "cookie": "xoxd-xxx",
  "expires_at": 1234567890
}
```

## Authentication

API calls require both the `xoxc-` token and `d` cookie:

```bash
curl -s -X POST "https://slack.com/api/METHOD" \
  -H "Authorization: Bearer $token" \
  -H "Content-Type: application/json" \
  --cookie "d=$cookie" \
  -d '{"channel":"C123","text":"Hello"}'
```

## Token Refresh

The xoxc token can expire (hours to days). Refresh by fetching the workspace page with the d cookie:

```bash
slack_refresh_token() {
  local creds_file="$HOME/.claude/slack-credentials.json"
  local token_file="$HOME/.claude/slack-token.json"

  # Check files exist
  if [ ! -f "$creds_file" ] || [ ! -f "$token_file" ]; then
    echo "ERROR: Slack credentials not configured. Run /hub-setup-slack" >&2
    return 1
  fi

  local workspace=$(jq -r '.workspace' "$creds_file")
  local cookie=$(jq -r '.cookie' "$token_file")

  # Fetch workspace page with cookie to get new token
  local response=$(curl -sL --cookie "d=$cookie" "https://$workspace")

  # Extract new xoxc token from response
  local new_token=$(echo "$response" | grep -oE '"token":"xoxc-[^"]+' | head -1 | cut -d'"' -f4)

  if [ -z "$new_token" ]; then
    echo "ERROR: Could not refresh token. Cookie may have expired." >&2
    return 1
  fi

  # Update token file with new expiry (assume 6 hours)
  local new_expires_at=$(($(date +%s) + 21600))
  jq --arg token "$new_token" --argjson expires "$new_expires_at" \
    '.token = $token | .expires_at = $expires' "$token_file" > "$token_file.tmp" \
    && mv "$token_file.tmp" "$token_file"

  echo "$new_token"
}
```

## Get Token

Get current token, refreshing if expired:

```bash
slack_get_token() {
  local creds_file="$HOME/.claude/slack-credentials.json"
  local token_file="$HOME/.claude/slack-token.json"

  # Check files exist
  if [ ! -f "$creds_file" ] || [ ! -f "$token_file" ]; then
    echo "ERROR: Slack credentials not configured. Run /hub-setup-slack" >&2
    return 1
  fi

  # Read token info
  local token=$(jq -r '.token' "$token_file")
  local expires_at=$(jq -r '.expires_at // 0' "$token_file")

  # Check if token is still valid (with 5 min buffer)
  local now=$(date +%s)
  if [ "$expires_at" -gt $((now + 300)) ] && [ -n "$token" ] && [ "$token" != "null" ]; then
    echo "$token"
    return 0
  fi

  # Token expired or near expiry, refresh it
  slack_refresh_token
}
```

## Auth Test - Verify Credentials

Verify credentials are valid:

```bash
slack_auth_test() {
  local token_file="$HOME/.claude/slack-token.json"
  local token=$(jq -r '.token' "$token_file")
  local cookie=$(jq -r '.cookie' "$token_file")

  curl -s "https://slack.com/api/auth.test" \
    -H "Authorization: Bearer $token" \
    --cookie "d=$cookie"
}
```

Response structure:
```json
{
  "ok": true,
  "url": "https://mycompany.slack.com/",
  "team": "My Company",
  "user": "pavel",
  "team_id": "T123ABC",
  "user_id": "U123ABC"
}
```

Error response:
```json
{
  "ok": false,
  "error": "invalid_auth"
}
```

## List Channels

Get channels the user has access to:

```bash
slack_list_channels() {
  local token=$(slack_get_token) || return 1
  local token_file="$HOME/.claude/slack-token.json"
  local cookie=$(jq -r '.cookie' "$token_file")

  curl -s "https://slack.com/api/conversations.list" \
    -H "Authorization: Bearer $token" \
    --cookie "d=$cookie" \
    -G \
    --data-urlencode "types=public_channel,private_channel" \
    --data-urlencode "limit=100"
}
```

Response structure:
```json
{
  "ok": true,
  "channels": [
    {
      "id": "C123ABC",
      "name": "general",
      "is_channel": true,
      "is_private": false,
      "is_member": true,
      "topic": {"value": "Company-wide announcements"},
      "purpose": {"value": "General discussion"}
    }
  ]
}
```

## Get Channel Messages

Get recent messages from a channel:

```bash
slack_get_messages() {
  local channel="$1"
  local limit="${2:-20}"

  local token=$(slack_get_token) || return 1
  local token_file="$HOME/.claude/slack-token.json"
  local cookie=$(jq -r '.cookie' "$token_file")

  curl -s "https://slack.com/api/conversations.history" \
    -H "Authorization: Bearer $token" \
    --cookie "d=$cookie" \
    -G \
    --data-urlencode "channel=$channel" \
    --data-urlencode "limit=$limit"
}
```

Response structure:
```json
{
  "ok": true,
  "messages": [
    {
      "type": "message",
      "user": "U123ABC",
      "text": "Hello team!",
      "ts": "1705344000.000100",
      "thread_ts": "1705344000.000100",
      "reply_count": 3
    }
  ],
  "has_more": true
}
```

## Get Thread Replies

Get replies in a thread:

```bash
slack_get_thread() {
  local channel="$1"
  local thread_ts="$2"

  local token=$(slack_get_token) || return 1
  local token_file="$HOME/.claude/slack-token.json"
  local cookie=$(jq -r '.cookie' "$token_file")

  curl -s "https://slack.com/api/conversations.replies" \
    -H "Authorization: Bearer $token" \
    --cookie "d=$cookie" \
    -G \
    --data-urlencode "channel=$channel" \
    --data-urlencode "ts=$thread_ts"
}
```

Response structure:
```json
{
  "ok": true,
  "messages": [
    {
      "type": "message",
      "user": "U123ABC",
      "text": "Original message",
      "ts": "1705344000.000100",
      "thread_ts": "1705344000.000100",
      "reply_count": 2,
      "replies": [{"user": "U456DEF", "ts": "1705344100.000200"}]
    },
    {
      "type": "message",
      "user": "U456DEF",
      "text": "Reply message",
      "ts": "1705344100.000200",
      "thread_ts": "1705344000.000100"
    }
  ]
}
```

## Post Message

Post a message to a channel or thread:

```bash
slack_post_message() {
  local channel="$1"
  local text="$2"
  local thread_ts="${3:-}"

  local token=$(slack_get_token) || return 1
  local token_file="$HOME/.claude/slack-token.json"
  local cookie=$(jq -r '.cookie' "$token_file")

  # Build JSON payload
  local payload
  if [ -n "$thread_ts" ]; then
    payload=$(jq -n \
      --arg channel "$channel" \
      --arg text "$text" \
      --arg thread_ts "$thread_ts" \
      '{channel: $channel, text: $text, thread_ts: $thread_ts}')
  else
    payload=$(jq -n \
      --arg channel "$channel" \
      --arg text "$text" \
      '{channel: $channel, text: $text}')
  fi

  curl -s -X POST "https://slack.com/api/chat.postMessage" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    --cookie "d=$cookie" \
    -d "$payload"
}
```

Response structure:
```json
{
  "ok": true,
  "channel": "C123ABC",
  "ts": "1705344200.000300",
  "message": {
    "type": "message",
    "user": "U123ABC",
    "text": "Hello!",
    "ts": "1705344200.000300"
  }
}
```

## Search Messages

Search for messages across channels:

```bash
slack_search() {
  local query="$1"
  local count="${2:-20}"

  local token=$(slack_get_token) || return 1
  local token_file="$HOME/.claude/slack-token.json"
  local cookie=$(jq -r '.cookie' "$token_file")

  curl -s "https://slack.com/api/search.messages" \
    -H "Authorization: Bearer $token" \
    --cookie "d=$cookie" \
    -G \
    --data-urlencode "query=$query" \
    --data-urlencode "count=$count"
}
```

Response structure:
```json
{
  "ok": true,
  "query": "project update",
  "messages": {
    "total": 42,
    "matches": [
      {
        "type": "message",
        "user": "U123ABC",
        "username": "pavel",
        "text": "Here's the project update...",
        "ts": "1705344000.000100",
        "channel": {
          "id": "C123ABC",
          "name": "engineering"
        },
        "permalink": "https://mycompany.slack.com/archives/C123ABC/p1705344000000100"
      }
    ]
  }
}
```

Search modifiers:
- `from:@username` - Messages from specific user
- `in:#channel` - Messages in specific channel
- `after:2024-01-01` - Messages after date
- `before:2024-01-31` - Messages before date
- `has:link` - Messages containing links
- `has:emoji` - Messages containing emoji

## Get User Info

Get information about a user:

```bash
slack_get_user() {
  local user_id="$1"

  local token=$(slack_get_token) || return 1
  local token_file="$HOME/.claude/slack-token.json"
  local cookie=$(jq -r '.cookie' "$token_file")

  curl -s "https://slack.com/api/users.info" \
    -H "Authorization: Bearer $token" \
    --cookie "d=$cookie" \
    -G \
    --data-urlencode "user=$user_id"
}
```

Response structure:
```json
{
  "ok": true,
  "user": {
    "id": "U123ABC",
    "name": "pavel",
    "real_name": "Pavel Fadeev",
    "profile": {
      "display_name": "Pavel",
      "email": "pavel@example.com",
      "image_72": "https://..."
    }
  }
}
```

## Error Codes

Common API errors:

| Error | Meaning | Action |
|-------|---------|--------|
| `invalid_auth` | Token/cookie invalid | Re-run /hub-setup-slack |
| `token_expired` | xoxc token expired | Call slack_refresh_token |
| `channel_not_found` | Invalid channel ID | Check channel ID |
| `not_in_channel` | User not in channel | Join channel first |
| `ratelimited` | Too many requests | Wait and retry |
| `account_inactive` | Account deactivated | Check Slack account |

## Helper Functions

### Parse messages for display

```bash
slack_format_messages() {
  local messages_json="$1"

  echo "$messages_json" | jq -r '
    .messages[]? |
    "[\(.ts | tonumber | strftime("%H:%M"))] <\(.user)> \(.text | .[0:100])"
  '
}
```

### Get channel by name

```bash
slack_get_channel_id() {
  local channel_name="$1"

  slack_list_channels | jq -r --arg name "$channel_name" '
    .channels[]? | select(.name == $name) | .id
  '
}
```

## Security Notes

- Credentials are stored with 600 permissions (owner read/write only)
- xoxc + d cookie = full user access (be careful)
- The d cookie is long-lived (1+ year), xoxc token expires faster
- Tokens are stored in `~/.claude/` which should be user-private
- Never log tokens in output
