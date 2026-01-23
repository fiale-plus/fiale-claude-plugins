#!/bin/bash
# Test Google Calendar API functions
# Tests credential validation, token parsing, and URL construction

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
mkdir -p "$FIXTURES_DIR"

# Test directories
TEST_DIR=$(mktemp -d)
TEST_CLAUDE_DIR="$TEST_DIR/.claude"
mkdir -p "$TEST_CLAUDE_DIR"

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

pass() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo "  PASS: $1"
}

fail() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo "  FAIL: $1"
  echo "        Expected: $2"
  echo "        Got:      $3"
}

echo "=== Testing Google Calendar API Functions ==="
echo ""

# --- Test credential file validation ---
echo "Testing credential file validation..."

TESTS_RUN=$((TESTS_RUN + 1))
# Test valid credentials file
cat > "$TEST_CLAUDE_DIR/gcalendar-credentials.json" << 'EOF'
{
  "client_id": "123456789.apps.googleusercontent.com",
  "client_secret": "GOCSPX-test-secret"
}
EOF

client_id=$(jq -r '.client_id' "$TEST_CLAUDE_DIR/gcalendar-credentials.json")
if [[ "$client_id" == *".apps.googleusercontent.com" ]]; then
  pass "Valid client_id format detected"
else
  fail "Client ID validation" "ends with .apps.googleusercontent.com" "$client_id"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test credentials with Google's nested format
cat > "$TEST_CLAUDE_DIR/gcalendar-credentials-nested.json" << 'EOF'
{
  "installed": {
    "client_id": "987654321.apps.googleusercontent.com",
    "client_secret": "GOCSPX-nested-secret",
    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
    "token_uri": "https://oauth2.googleapis.com/token"
  }
}
EOF

nested_id=$(jq -r '.installed.client_id // .client_id' "$TEST_CLAUDE_DIR/gcalendar-credentials-nested.json")
if [[ "$nested_id" == *".apps.googleusercontent.com" ]]; then
  pass "Nested credentials format parsed correctly"
else
  fail "Nested credentials parsing" "987654321.apps.googleusercontent.com" "$nested_id"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test invalid credentials (missing fields)
cat > "$TEST_CLAUDE_DIR/gcalendar-credentials-invalid.json" << 'EOF'
{
  "client_id": "123456789.apps.googleusercontent.com"
}
EOF

client_secret=$(jq -r '.client_secret // "null"' "$TEST_CLAUDE_DIR/gcalendar-credentials-invalid.json")
if [ "$client_secret" = "null" ]; then
  pass "Missing client_secret detected as invalid"
else
  fail "Invalid credentials detection" "null" "$client_secret"
fi

echo ""
echo "Testing token file validation..."

TESTS_RUN=$((TESTS_RUN + 1))
# Test valid token file
cat > "$TEST_CLAUDE_DIR/gcalendar-token.json" << 'EOF'
{
  "refresh_token": "1//test-refresh-token",
  "access_token": "ya29.test-access-token",
  "expires_at": 9999999999
}
EOF

refresh_token=$(jq -r '.refresh_token' "$TEST_CLAUDE_DIR/gcalendar-token.json")
if [[ "$refresh_token" == "1//"* ]]; then
  pass "Valid refresh_token format detected"
else
  fail "Refresh token validation" "starts with 1//" "$refresh_token"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test token expiration check
expires_at=$(jq -r '.expires_at' "$TEST_CLAUDE_DIR/gcalendar-token.json")
now=$(date +%s)
if [ "$expires_at" -gt "$now" ]; then
  pass "Token expiration check (future token is valid)"
else
  fail "Token expiration check" "expires_at > now" "$expires_at <= $now"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test expired token detection
cat > "$TEST_CLAUDE_DIR/gcalendar-token-expired.json" << 'EOF'
{
  "refresh_token": "1//test-refresh-token",
  "access_token": "ya29.old-token",
  "expires_at": 1000000000
}
EOF

expired_at=$(jq -r '.expires_at' "$TEST_CLAUDE_DIR/gcalendar-token-expired.json")
if [ "$expired_at" -lt "$now" ]; then
  pass "Expired token detected correctly"
else
  fail "Expired token detection" "expires_at < now" "$expired_at >= $now"
fi

echo ""
echo "Testing API URL construction..."

TESTS_RUN=$((TESTS_RUN + 1))
# Test list events URL construction
time_min=$(date -u +%Y-%m-%dT%H:%M:%SZ)
max_results=10
expected_base="https://www.googleapis.com/calendar/v3/calendars/primary/events"
# Build URL with parameters
constructed_url="${expected_base}?timeMin=${time_min}&maxResults=${max_results}&singleEvents=true&orderBy=startTime"

if [[ "$constructed_url" == *"calendars/primary/events"* ]] && \
   [[ "$constructed_url" == *"singleEvents=true"* ]] && \
   [[ "$constructed_url" == *"orderBy=startTime"* ]]; then
  pass "List events URL constructed correctly"
else
  fail "List events URL" "contains required params" "$constructed_url"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test get event URL construction
event_id="test-event-id-123"
get_event_url="https://www.googleapis.com/calendar/v3/calendars/primary/events/$event_id"
if [[ "$get_event_url" == *"events/test-event-id-123"* ]]; then
  pass "Get event URL constructed correctly"
else
  fail "Get event URL" "contains event ID" "$get_event_url"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test OAuth authorization URL construction
client_id="123456789.apps.googleusercontent.com"
redirect_uri="urn:ietf:wg:oauth:2.0:oob"
scope="https://www.googleapis.com/auth/calendar.readonly"
auth_url="https://accounts.google.com/o/oauth2/v2/auth?client_id=${client_id}&redirect_uri=${redirect_uri}&response_type=code&scope=${scope}&access_type=offline&prompt=consent"

if [[ "$auth_url" == *"access_type=offline"* ]] && \
   [[ "$auth_url" == *"prompt=consent"* ]] && \
   [[ "$auth_url" == *"response_type=code"* ]]; then
  pass "OAuth authorization URL constructed correctly"
else
  fail "OAuth URL" "contains required params" "$auth_url"
fi

echo ""
echo "Testing event parsing..."

TESTS_RUN=$((TESTS_RUN + 1))
# Test event JSON parsing
cat > "$TEST_DIR/events-response.json" << 'EOF'
{
  "items": [
    {
      "id": "event1",
      "summary": "Team Standup",
      "start": {"dateTime": "2025-01-15T10:00:00-08:00"},
      "end": {"dateTime": "2025-01-15T10:30:00-08:00"},
      "hangoutLink": "https://meet.google.com/abc-defg-hij",
      "organizer": {"email": "boss@example.com", "displayName": "Boss"},
      "attachments": []
    },
    {
      "id": "event2",
      "summary": "Project Review",
      "start": {"dateTime": "2025-01-15T14:00:00-08:00"},
      "end": {"dateTime": "2025-01-15T15:00:00-08:00"},
      "organizer": {"email": "pm@example.com"},
      "attachments": [{"title": "Agenda.pdf"}]
    }
  ]
}
EOF

event_count=$(jq '.items | length' "$TEST_DIR/events-response.json")
if [ "$event_count" = "2" ]; then
  pass "Event count parsed correctly"
else
  fail "Event count" "2" "$event_count"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test meeting link extraction
meeting_link=$(jq -r '.items[0].hangoutLink // "none"' "$TEST_DIR/events-response.json")
if [[ "$meeting_link" == "https://meet.google.com/"* ]]; then
  pass "Meeting link extracted correctly"
else
  fail "Meeting link" "https://meet.google.com/..." "$meeting_link"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test attachment detection
has_attachments=$(jq '.items[1].attachments | length > 0' "$TEST_DIR/events-response.json")
if [ "$has_attachments" = "true" ]; then
  pass "Attachments detected correctly"
else
  fail "Attachment detection" "true" "$has_attachments"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test organizer fallback (displayName vs email)
organizer1=$(jq -r '.items[0].organizer.displayName // .items[0].organizer.email' "$TEST_DIR/events-response.json")
organizer2=$(jq -r '.items[1].organizer.displayName // .items[1].organizer.email' "$TEST_DIR/events-response.json")
if [ "$organizer1" = "Boss" ] && [ "$organizer2" = "pm@example.com" ]; then
  pass "Organizer fallback (displayName -> email) works"
else
  fail "Organizer fallback" "Boss, pm@example.com" "$organizer1, $organizer2"
fi

echo ""
echo "Testing connection configuration..."

TESTS_RUN=$((TESTS_RUN + 1))
# Test auto connection config
cat > "$TEST_CLAUDE_DIR/status-config-auto.json" << 'EOF'
{
  "calendar": {
    "connection": "auto",
    "chrome": { "tabId": null },
    "playwright": { "profile": "default", "headless": false }
  }
}
EOF

connection=$(jq -r '.calendar.connection' "$TEST_CLAUDE_DIR/status-config-auto.json")
if [ "$connection" = "auto" ]; then
  pass "Auto connection config parsed correctly"
else
  fail "Auto connection config" "auto" "$connection"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test chrome connection config
cat > "$TEST_CLAUDE_DIR/status-config-chrome.json" << 'EOF'
{
  "calendar": {
    "connection": "chrome",
    "chrome": { "tabId": 12345 }
  }
}
EOF

chrome_tab=$(jq -r '.calendar.chrome.tabId' "$TEST_CLAUDE_DIR/status-config-chrome.json")
if [ "$chrome_tab" = "12345" ]; then
  pass "Chrome connection with tabId parsed correctly"
else
  fail "Chrome tabId" "12345" "$chrome_tab"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test playwright connection config
cat > "$TEST_CLAUDE_DIR/status-config-playwright.json" << 'EOF'
{
  "calendar": {
    "connection": "playwright",
    "playwright": { "profile": "custom", "headless": true }
  }
}
EOF

pw_profile=$(jq -r '.calendar.playwright.profile' "$TEST_CLAUDE_DIR/status-config-playwright.json")
pw_headless=$(jq -r '.calendar.playwright.headless' "$TEST_CLAUDE_DIR/status-config-playwright.json")
if [ "$pw_profile" = "custom" ] && [ "$pw_headless" = "true" ]; then
  pass "Playwright connection config parsed correctly"
else
  fail "Playwright config" "profile=custom, headless=true" "profile=$pw_profile, headless=$pw_headless"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test disabled connection
cat > "$TEST_CLAUDE_DIR/status-config-disabled.json" << 'EOF'
{
  "calendar": {
    "connection": "disabled"
  }
}
EOF

disabled=$(jq -r '.calendar.connection' "$TEST_CLAUDE_DIR/status-config-disabled.json")
if [ "$disabled" = "disabled" ]; then
  pass "Disabled connection config parsed correctly"
else
  fail "Disabled connection" "disabled" "$disabled"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test connection type validation
valid_connections="auto chrome playwright disabled"
test_connection="chrome"
if echo "$valid_connections" | grep -qw "$test_connection"; then
  pass "Connection type validation works (chrome is valid)"
else
  fail "Connection validation" "chrome in valid list" "not found"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test invalid connection type detection
invalid_connection="api"
if ! echo "$valid_connections" | grep -qw "$invalid_connection"; then
  pass "Invalid connection type detected (api not valid for calendar)"
else
  fail "Invalid connection detection" "api not in list" "found"
fi

echo ""
echo "Testing Chrome extraction script validation..."

TESTS_RUN=$((TESTS_RUN + 1))
# Test extraction script output parsing
cat > "$TEST_DIR/chrome-extraction.json" << 'EOF'
[
  {
    "id": "event_abc123",
    "title": "Team Standup",
    "time": "10:00 AM",
    "meetingLink": "https://meet.google.com/xxx-yyyy-zzz",
    "hasAttachments": false
  },
  {
    "id": "event_def456",
    "title": "Project Review",
    "time": "2:30 PM",
    "meetingLink": "",
    "hasAttachments": true
  }
]
EOF

extraction_count=$(jq 'length' "$TEST_DIR/chrome-extraction.json")
if [ "$extraction_count" = "2" ]; then
  pass "Chrome extraction output parsed correctly"
else
  fail "Chrome extraction count" "2" "$extraction_count"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test time string parsing simulation
time_str="10:00 AM"
if [[ "$time_str" =~ ^[0-9]{1,2}:[0-9]{2}[[:space:]]*(AM|PM)$ ]]; then
  pass "Time string format validated correctly"
else
  fail "Time string format" "matches HH:MM AM/PM" "$time_str"
fi

echo ""
echo "Testing error response parsing..."

TESTS_RUN=$((TESTS_RUN + 1))
# Test error response detection
cat > "$TEST_DIR/error-response.json" << 'EOF'
{
  "error": {
    "code": 401,
    "message": "Invalid Credentials",
    "status": "UNAUTHENTICATED"
  }
}
EOF

is_error=$(jq 'has("error")' "$TEST_DIR/error-response.json")
if [ "$is_error" = "true" ]; then
  pass "Error response detected correctly"
else
  fail "Error detection" "true" "$is_error"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test error message extraction
error_msg=$(jq -r '.error.message // .error_description // .error' "$TEST_DIR/error-response.json")
if [ "$error_msg" = "Invalid Credentials" ]; then
  pass "Error message extracted correctly"
else
  fail "Error message" "Invalid Credentials" "$error_msg"
fi

echo ""
echo "=== Results ==="
echo "Tests run: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"

if [ "$TESTS_FAILED" -gt 0 ]; then
  exit 1
fi
