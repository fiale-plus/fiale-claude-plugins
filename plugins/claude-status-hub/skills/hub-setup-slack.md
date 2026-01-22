---
name: hub-setup-slack
description: Set up Slack API access using browser session credentials (xoxc token + d cookie)
---

# Slack API Setup Wizard

Interactive wizard to configure Slack API access using browser session tokens.

## When to Use

- User runs `/hub-setup-slack`
- User wants Slack integration without creating a Slack App
- User needs to read/post messages programmatically

## File Locations

- `~/.claude/slack-credentials.json` - Workspace URL
- `~/.claude/slack-token.json` - xoxc token + d cookie
- `~/.claude/status-config.json` - Hub config (slack settings)

## Wizard Flow

### Step 1: Introduction

Use AskUserQuestion:

```
question: "Slack API setup uses browser session credentials (no Slack App required). How would you like to proceed?"
header: "Setup"
options:
  - label: "I'll extract credentials from DevTools"
    description: "You know how to get the xoxc token and d cookie"
  - label: "Guide me through extraction"
    description: "Show step-by-step instructions to get credentials"
  - label: "Skip Slack setup"
    description: "Set up Slack later"
```

### Step 2a: Guide Through Credential Extraction

If user selected "Guide me through extraction", show these instructions:

```
## Extracting Slack Credentials

You need two things: the `d` cookie and the `xoxc-` token.

### Step 1: Open Slack in your browser
Navigate to your Slack workspace (e.g., https://mycompany.slack.com)

### Step 2: Open DevTools
Press F12 (Windows/Linux) or Cmd+Opt+I (Mac)

### Step 3: Get the `d` cookie
1. Go to the **Application** tab (Chrome) or **Storage** tab (Firefox)
2. Expand **Cookies** in the left sidebar
3. Click on your Slack domain (e.g., mycompany.slack.com)
4. Find the cookie named `d`
5. Copy its entire Value (starts with `xoxd-`)

### Step 4: Get the `xoxc` token
1. Go to the **Network** tab
2. Refresh the page (F5 or Cmd+R)
3. Click on any request to slack.com (e.g., `api/client.counts`)
4. Look in **Request Headers** for `Authorization: Bearer xoxc-...`
5. Copy the token (everything after "Bearer ", starts with `xoxc-`)

Alternative for xoxc token:
1. Go to **Application** > **Local Storage** > your Slack domain
2. Search for `xoxc-` in the values

### Step 5: Note your workspace URL
This is the domain you see in your browser (e.g., `mycompany.slack.com`)

Come back when you have all three pieces!
```

Then ask:
```
question: "Do you have your credentials ready?"
header: "Ready?"
options:
  - label: "Yes, I have them"
    description: "Proceed to enter credentials"
  - label: "Not yet"
    description: "Cancel setup for now"
```

### Step 2b: Collect Workspace URL

Ask for workspace URL:

```
question: "Enter your Slack workspace URL (e.g., mycompany.slack.com):"
header: "Workspace"
options:
  - label: "Continue..."
    description: "I'll enter the workspace URL in the 'Other' field"
```

Validate:
- Remove `https://` prefix if present
- Remove trailing slashes
- Should be a valid domain format

Save to `~/.claude/slack-credentials.json`:
```json
{
  "workspace": "mycompany.slack.com"
}
```

Set file permissions:
```bash
chmod 600 ~/.claude/slack-credentials.json
```

### Step 3: Collect d Cookie

Ask for the d cookie:

```
question: "Paste the `d` cookie value (starts with xoxd-):"
header: "Cookie"
options:
  - label: "Continue..."
    description: "I'll paste the cookie in the 'Other' field"
```

Validate:
- Must start with `xoxd-`
- Must be non-empty after prefix

### Step 4: Collect xoxc Token

Ask for the xoxc token:

```
question: "Paste the xoxc token (starts with xoxc-):"
header: "Token"
options:
  - label: "Continue..."
    description: "I'll paste the token in the 'Other' field"
```

Validate:
- Must start with `xoxc-`
- Must be non-empty after prefix

### Step 5: Save Credentials

Save token and cookie to `~/.claude/slack-token.json`:

```bash
save_slack_token() {
  local token="$1"
  local cookie="$2"
  local token_file="$HOME/.claude/slack-token.json"

  # Assume token valid for 6 hours
  local expires_at=$(($(date +%s) + 21600))

  cat > "$token_file" << EOF
{
  "token": "$token",
  "cookie": "$cookie",
  "expires_at": $expires_at
}
EOF

  chmod 600 "$token_file"
}
```

### Step 6: Verify Credentials

Test the connection using auth.test:

```bash
verify_slack() {
  local token_file="$HOME/.claude/slack-token.json"
  local token=$(jq -r '.token' "$token_file")
  local cookie=$(jq -r '.cookie' "$token_file")

  curl -s "https://slack.com/api/auth.test" \
    -H "Authorization: Bearer $token" \
    --cookie "d=$cookie"
}
```

Check response:
- If `ok: true`: Extract user info for success message
- If `ok: false`: Show error and ask to retry

### Step 7: Success Message

Show completion message with user info:

```
Slack connected!

Workspace: My Company
User: pavel (@pavel)
User ID: U123ABC

Available operations:
- List channels: slack_list_channels()
- Read messages: slack_get_messages(channel_id)
- Post messages: slack_post_message(channel_id, text)
- Search: slack_search(query)

Note: The xoxc token may expire. If you get auth errors,
run /hub-setup-slack again to refresh credentials.
```

## Error Handling

### Invalid Cookie Format

```
The cookie doesn't appear to be valid.

Expected format: xoxd-xxx...
Got: [first 20 chars of input]

Make sure you copied the entire value of the `d` cookie from DevTools.
```

### Invalid Token Format

```
The token doesn't appear to be valid.

Expected format: xoxc-xxx-xxx-xxx...
Got: [first 20 chars of input]

Make sure you copied the entire xoxc token from the Authorization header.
```

### Auth Test Failed

```
Authentication failed: [error message]

Common issues:
- Token or cookie expired (extract fresh ones from browser)
- Workspace URL incorrect (check the URL matches where you extracted credentials)
- Your session was logged out (log back into Slack in browser)

Try extracting fresh credentials and running /hub-setup-slack again.
```

### Token Refresh Failed

If token refresh fails during normal operation:

```
Could not refresh Slack token.

The d cookie may have expired (this is rare, usually lasts 1+ year).

To fix:
1. Log into Slack in your browser
2. Run /hub-setup-slack to extract fresh credentials
```

## Security Notes

- Credentials are stored with 600 permissions (owner read/write only)
- xoxc + d cookie = full user access (be careful what you share)
- The d cookie is long-lived (1+ year), xoxc token expires faster (hours to days)
- Tokens are stored in `~/.claude/` which should be user-private
- Never log tokens or share them

## Token Lifecycle

| Credential | Lifespan | Refresh Method |
|------------|----------|----------------|
| d cookie | ~1 year | Manual re-extraction from browser |
| xoxc token | Hours to days | Automatic refresh using d cookie |

The setup saves both. When xoxc expires, the tool can automatically refresh it using the d cookie. When the d cookie expires (rare), you need to re-run the setup wizard.
