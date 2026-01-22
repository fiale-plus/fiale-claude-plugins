---
name: hub-setup-gcalendar
description: Set up Google Calendar API access (for environments without Chrome MCP)
---

# Google Calendar API Setup Wizard

Interactive wizard to configure Google Calendar API access using OAuth2.

## When to Use

- User runs `/hub-setup-gcalendar`
- User wants calendar integration without Chrome MCP
- User is in a headless/remote environment

## File Locations

- `~/.claude/gcalendar-credentials.json` - OAuth client credentials
- `~/.claude/gcalendar-token.json` - Refresh/access tokens
- `~/.claude/status-config.json` - Hub config (calendar.connection: "api")

## Wizard Flow

### Step 1: Check Prerequisites

Use AskUserQuestion:

```
question: "To connect Google Calendar via API, you'll need OAuth2 credentials from Google Cloud Console. Do you have credentials.json ready?"
header: "Setup"
options:
  - label: "I have credentials ready"
    description: "You've downloaded credentials.json from Google Cloud Console"
  - label: "Guide me through setup"
    description: "Show step-by-step instructions to create credentials"
  - label: "Skip calendar setup"
    description: "Set up calendar later"
```

### Step 2a: Guide Through Credential Creation

If user selected "Guide me through setup", show these instructions:

```
## Google Calendar API Setup Guide

1. **Go to Google Cloud Console**
   https://console.cloud.google.com

2. **Create or Select a Project**
   - Click the project dropdown at the top
   - Click "New Project" or select an existing one
   - Name it something like "Claude Calendar"

3. **Enable Calendar API**
   - Go to "APIs & Services" > "Library"
   - Search for "Google Calendar API"
   - Click it and press "Enable"

4. **Configure OAuth Consent Screen**
   - Go to "APIs & Services" > "OAuth consent screen"
   - Select "External" user type
   - Fill in app name (e.g., "Claude Calendar")
   - Add your email as test user
   - Save

5. **Create OAuth Credentials**
   - Go to "APIs & Services" > "Credentials"
   - Click "Create Credentials" > "OAuth client ID"
   - Application type: "Desktop app"
   - Name: "Claude Calendar Client"
   - Click "Create"

6. **Download Credentials**
   - Click the download button (JSON)
   - Save the file

Come back when you have the credentials.json file downloaded!
```

Then ask:
```
question: "Do you have your credentials.json ready now?"
header: "Ready?"
options:
  - label: "Yes, I have it"
    description: "Proceed to enter credentials"
  - label: "Not yet"
    description: "Cancel setup for now"
```

### Step 2b: Collect Credentials

Ask user to paste credentials:

```
question: "Paste the contents of your credentials.json file (the entire JSON):"
header: "Credentials"
options:
  - label: "Continue..."
    description: "I'll paste in the 'Other' field below"
```

User will paste in the "Other" text field.

### Step 3: Validate and Save Credentials

Parse the pasted JSON:

```javascript
// The user may paste the full Google format or just client_id/client_secret
let creds;
try {
  const input = JSON.parse(userInput);

  // Google's format wraps in "installed" or "web" key
  if (input.installed) {
    creds = {
      client_id: input.installed.client_id,
      client_secret: input.installed.client_secret
    };
  } else if (input.web) {
    creds = {
      client_id: input.web.client_id,
      client_secret: input.web.client_secret
    };
  } else if (input.client_id && input.client_secret) {
    creds = {
      client_id: input.client_id,
      client_secret: input.client_secret
    };
  } else {
    throw new Error("Missing client_id or client_secret");
  }
} catch (e) {
  // Show error and ask to retry
}
```

Validate:
- `client_id` ends with `.apps.googleusercontent.com`
- `client_secret` is non-empty

Save to `~/.claude/gcalendar-credentials.json`:
```json
{
  "client_id": "xxx.apps.googleusercontent.com",
  "client_secret": "GOCSPX-xxx"
}
```

### Step 4: Generate Authorization URL

Build the OAuth authorization URL:

```bash
CLIENT_ID=$(jq -r '.client_id' ~/.claude/gcalendar-credentials.json)
REDIRECT_URI="urn:ietf:wg:oauth:2.0:oob"
SCOPE="https://www.googleapis.com/auth/calendar.readonly"

AUTH_URL="https://accounts.google.com/o/oauth2/v2/auth"
AUTH_URL="${AUTH_URL}?client_id=${CLIENT_ID}"
AUTH_URL="${AUTH_URL}&redirect_uri=${REDIRECT_URI}"
AUTH_URL="${AUTH_URL}&response_type=code"
AUTH_URL="${AUTH_URL}&scope=${SCOPE}"
AUTH_URL="${AUTH_URL}&access_type=offline"
AUTH_URL="${AUTH_URL}&prompt=consent"

echo "$AUTH_URL"
```

Show to user:
```
## Authorization Required

Open this URL in your browser to authorize access:

<full authorization URL>

After authorizing, Google will show you an authorization code.
Copy that code and paste it below.
```

Use AskUserQuestion:
```
question: "Paste the authorization code from Google:"
header: "Auth Code"
options:
  - label: "Continue..."
    description: "I'll paste the code in the 'Other' field below"
```

### Step 5: Exchange Code for Tokens

Exchange the authorization code:

```bash
exchange_code() {
  local code="$1"
  local creds_file="$HOME/.claude/gcalendar-credentials.json"

  local client_id=$(jq -r '.client_id' "$creds_file")
  local client_secret=$(jq -r '.client_secret' "$creds_file")

  curl -s -X POST "https://oauth2.googleapis.com/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=$client_id" \
    -d "client_secret=$client_secret" \
    -d "code=$code" \
    -d "grant_type=authorization_code" \
    -d "redirect_uri=urn:ietf:wg:oauth:2.0:oob"
}
```

Validate response:
- Must have `access_token`
- Must have `refresh_token` (critical for long-term use)

If missing `refresh_token`:
```
Warning: No refresh token received. This can happen if you've authorized before.

To fix:
1. Go to https://myaccount.google.com/permissions
2. Remove "Claude Calendar" from the list
3. Run /hub-setup-gcalendar again
```

Save tokens to `~/.claude/gcalendar-token.json`:
```bash
save_tokens() {
  local response="$1"
  local token_file="$HOME/.claude/gcalendar-token.json"
  local now=$(date +%s)
  local expires_in=$(echo "$response" | jq -r '.expires_in // 3600')

  echo "$response" | jq --argjson expires "$((now + expires_in))" \
    '{
      refresh_token: .refresh_token,
      access_token: .access_token,
      expires_at: $expires
    }' > "$token_file"

  chmod 600 "$token_file"
}
```

### Step 6: Verify and Complete

Test the connection by listing events:

```bash
verify_calendar() {
  local token_file="$HOME/.claude/gcalendar-token.json"
  local access_token=$(jq -r '.access_token' "$token_file")

  curl -s -X GET \
    "https://www.googleapis.com/calendar/v3/calendars/primary/events" \
    -H "Authorization: Bearer $access_token" \
    -G \
    --data-urlencode "maxResults=5" \
    --data-urlencode "timeMin=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --data-urlencode "singleEvents=true" \
    --data-urlencode "orderBy=startTime"
}
```

Update status config:

```bash
# Read existing config or create new
config_file="$HOME/.claude/status-config.json"
if [ -f "$config_file" ]; then
  config=$(cat "$config_file")
else
  config='{"foreground":[],"background":null}'
fi

# Update calendar settings
echo "$config" | jq '.calendar = {
  "connection": "api",
  "alertMinutesBefore": 5,
  "alertWithDocsBefore": 10
}' > "$config_file"
```

### Step 7: Success Message

Show completion message:

```
Google Calendar connected!

Found X upcoming events on your calendar.

Your statusline will now show:
- Upcoming meetings with time remaining
- Alerts before meetings start (configurable)

Use /hub-ack to interact with calendar alerts.

Tip: Calendar uses the API directly (no browser needed).
To switch to browser mode, set calendar.connection to "chrome".
```

## Error Handling

### Invalid Credentials JSON

```
The credentials don't appear to be valid Google OAuth credentials.

Expected format (from Google Cloud Console):
{
  "installed": {
    "client_id": "xxx.apps.googleusercontent.com",
    "client_secret": "GOCSPX-xxx",
    ...
  }
}

Please download fresh credentials from:
https://console.cloud.google.com/apis/credentials
```

### Authorization Failed

```
Authorization failed: <error message>

Common issues:
- The authorization code expired (try again)
- The app isn't in testing mode (add yourself as test user)
- Calendar API isn't enabled (enable it in Cloud Console)
```

### No Refresh Token

```
No refresh token received.

This usually means you've authorized this app before.
To get a new refresh token:

1. Go to: https://myaccount.google.com/permissions
2. Find and remove "Claude Calendar" (or your app name)
3. Run /hub-setup-gcalendar again

The "prompt=consent" parameter should force a new token,
but Google sometimes skips it for existing authorizations.
```

## Security Notes

- Credentials are stored with 600 permissions (owner read/write only)
- Refresh tokens allow long-term access - protect them
- Only request `calendar.readonly` scope unless write access is needed
- Tokens are stored in `~/.claude/` which should be user-private
