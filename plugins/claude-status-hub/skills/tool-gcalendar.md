# Tool: Google Calendar API

Curl-based Google Calendar API operations for environments without Chrome MCP.

## Config Structure

Calendar API config in `~/.claude/status-config.json`:

```json
{
  "calendar": {
    "connection": "api",
    "alertMinutesBefore": 5,
    "alertWithDocsBefore": 10,
    "lateMessageTo": "organizer"
  }
}
```

Credentials stored separately:
- `~/.claude/gcalendar-credentials.json` - OAuth client credentials
- `~/.claude/gcalendar-token.json` - Refresh/access tokens

## Credential Files

### `gcalendar-credentials.json`

```json
{
  "client_id": "xxx.apps.googleusercontent.com",
  "client_secret": "GOCSPX-xxx"
}
```

### `gcalendar-token.json`

```json
{
  "refresh_token": "1//xxx",
  "access_token": "ya29.xxx",
  "expires_at": 1234567890
}
```

## Token Refresh

Before any API call, check if access token is expired and refresh if needed:

```bash
gcal_get_token() {
  local creds_file="$HOME/.claude/gcalendar-credentials.json"
  local token_file="$HOME/.claude/gcalendar-token.json"

  # Check files exist
  if [ ! -f "$creds_file" ] || [ ! -f "$token_file" ]; then
    echo "ERROR: Calendar credentials not configured. Run /hub-setup-gcalendar" >&2
    return 1
  fi

  # Read credentials
  local client_id=$(jq -r '.client_id' "$creds_file")
  local client_secret=$(jq -r '.client_secret' "$creds_file")
  local refresh_token=$(jq -r '.refresh_token' "$token_file")
  local access_token=$(jq -r '.access_token' "$token_file")
  local expires_at=$(jq -r '.expires_at // 0' "$token_file")

  # Check if token is still valid (with 60s buffer)
  local now=$(date +%s)
  if [ "$expires_at" -gt $((now + 60)) ] && [ -n "$access_token" ] && [ "$access_token" != "null" ]; then
    echo "$access_token"
    return 0
  fi

  # Refresh the token
  local response=$(curl -s -X POST "https://oauth2.googleapis.com/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=$client_id" \
    -d "client_secret=$client_secret" \
    -d "refresh_token=$refresh_token" \
    -d "grant_type=refresh_token")

  # Check for errors
  if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
    local error=$(echo "$response" | jq -r '.error_description // .error')
    echo "ERROR: Token refresh failed: $error" >&2
    return 1
  fi

  # Extract new access token
  local new_token=$(echo "$response" | jq -r '.access_token')
  local expires_in=$(echo "$response" | jq -r '.expires_in // 3600')
  local new_expires_at=$((now + expires_in))

  # Update token file (preserve refresh_token)
  jq --arg token "$new_token" --argjson expires "$new_expires_at" \
    '.access_token = $token | .expires_at = $expires' "$token_file" > "$token_file.tmp" \
    && mv "$token_file.tmp" "$token_file"

  echo "$new_token"
}
```

## List Events

Get upcoming calendar events:

```bash
gcal_list_events() {
  local token=$(gcal_get_token) || return 1
  local max_results="${1:-10}"
  local time_min="${2:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

  curl -s -X GET \
    "https://www.googleapis.com/calendar/v3/calendars/primary/events" \
    -H "Authorization: Bearer $token" \
    -G \
    --data-urlencode "timeMin=$time_min" \
    --data-urlencode "maxResults=$max_results" \
    --data-urlencode "singleEvents=true" \
    --data-urlencode "orderBy=startTime"
}
```

Response structure:
```json
{
  "items": [
    {
      "id": "event_id",
      "summary": "Meeting Title",
      "description": "Meeting notes...",
      "start": {
        "dateTime": "2025-01-15T10:00:00-08:00",
        "timeZone": "America/Los_Angeles"
      },
      "end": {
        "dateTime": "2025-01-15T11:00:00-08:00"
      },
      "hangoutLink": "https://meet.google.com/xxx-xxxx-xxx",
      "organizer": {
        "email": "organizer@example.com",
        "displayName": "John Doe"
      },
      "attendees": [
        {"email": "attendee@example.com", "responseStatus": "accepted"}
      ],
      "attachments": [
        {"title": "Agenda.pdf", "fileUrl": "https://..."}
      ]
    }
  ]
}
```

## Get Single Event

Get detailed event info including description, attendees, and attachments:

```bash
gcal_get_event() {
  local token=$(gcal_get_token) || return 1
  local event_id="$1"

  curl -s -X GET \
    "https://www.googleapis.com/calendar/v3/calendars/primary/events/$event_id" \
    -H "Authorization: Bearer $token"
}
```

## Create Event

Create a new calendar event:

```bash
gcal_create_event() {
  local token=$(gcal_get_token) || return 1
  local summary="$1"
  local start_time="$2"  # ISO 8601 format
  local end_time="$3"    # ISO 8601 format
  local description="${4:-}"
  local attendees="${5:-}"  # Comma-separated emails

  # Build attendees JSON array
  local attendees_json="[]"
  if [ -n "$attendees" ]; then
    attendees_json=$(echo "$attendees" | tr ',' '\n' | jq -R '{"email": .}' | jq -s '.')
  fi

  # Build event JSON
  local event_json=$(jq -n \
    --arg summary "$summary" \
    --arg description "$description" \
    --arg start "$start_time" \
    --arg end "$end_time" \
    --argjson attendees "$attendees_json" \
    '{
      summary: $summary,
      description: $description,
      start: {dateTime: $start},
      end: {dateTime: $end},
      attendees: $attendees
    }')

  curl -s -X POST \
    "https://www.googleapis.com/calendar/v3/calendars/primary/events" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "$event_json"
}
```

## Parse Events for Hub

Convert API response to hub format:

```bash
gcal_parse_for_hub() {
  local events_json="$1"
  local now=$(date +%s)

  echo "$events_json" | jq --argjson now "$now" '
    .items // [] | map({
      id: .id,
      title: (.summary // "No Title") | .[0:50],
      startTime: (
        if .start.dateTime then
          (.start.dateTime | fromdateiso8601)
        elif .start.date then
          (.start.date + "T00:00:00Z" | fromdateiso8601)
        else null end
      ),
      meetingLink: (.hangoutLink // .conferenceData.entryPoints[0].uri // null),
      organizer: (.organizer.displayName // .organizer.email // null),
      hasAttachments: ((.attachments | length) > 0)
    }) | sort_by(.startTime) | map(select(.startTime > $now)) | .[0:5]
  '
}
```

## Error Codes

Common API errors:

| Error | Meaning | Action |
|-------|---------|--------|
| 401 Unauthorized | Token expired/invalid | Re-run gcal_get_token or /hub-setup-gcalendar |
| 403 Forbidden | Calendar API not enabled | Enable API in Google Cloud Console |
| 404 Not Found | Event/calendar doesn't exist | Check event ID |
| 429 Rate Limited | Too many requests | Wait and retry |

## Integration with Hub Refresh

When `calendar.connection` is `"api"`, use these curl functions instead of Chrome MCP.

In `hub-refresh-calendar.md`, check connection type:

```javascript
const config = readConfig();
if (config.calendar?.connection === "api") {
  // Use gcal_list_events() via Bash
  // Parse with gcal_parse_for_hub()
} else {
  // Use Chrome MCP (existing code)
}
```

## Scopes Required

The OAuth setup needs these scopes:
- `https://www.googleapis.com/auth/calendar.readonly` - List/read events
- `https://www.googleapis.com/auth/calendar.events` - Create events (optional)
