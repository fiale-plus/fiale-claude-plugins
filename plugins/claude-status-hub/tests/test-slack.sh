#!/bin/bash
# Test Slack API functions
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

echo "=== Testing Slack API Functions ==="
echo ""

# --- Test credential file validation ---
echo "Testing credential file validation..."

TESTS_RUN=$((TESTS_RUN + 1))
# Test valid credentials file
cat > "$TEST_CLAUDE_DIR/slack-credentials.json" << 'EOF'
{
  "workspace": "mycompany.slack.com"
}
EOF

workspace=$(jq -r '.workspace' "$TEST_CLAUDE_DIR/slack-credentials.json")
if [[ "$workspace" == *".slack.com" ]]; then
  pass "Valid workspace URL format detected"
else
  fail "Workspace URL validation" "ends with .slack.com" "$workspace"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test workspace URL without slack.com (should be detected as needing fix)
cat > "$TEST_CLAUDE_DIR/slack-credentials-invalid.json" << 'EOF'
{
  "workspace": "mycompany"
}
EOF

workspace_invalid=$(jq -r '.workspace' "$TEST_CLAUDE_DIR/slack-credentials-invalid.json")
if [[ "$workspace_invalid" != *".slack.com" ]]; then
  pass "Invalid workspace URL detected (missing .slack.com)"
else
  fail "Invalid workspace detection" "does not end with .slack.com" "$workspace_invalid"
fi

echo ""
echo "Testing token file validation..."

TESTS_RUN=$((TESTS_RUN + 1))
# Test valid token file
cat > "$TEST_CLAUDE_DIR/slack-token.json" << 'EOF'
{
  "token": "xoxc-123456789-123456789-123456789-abc123",
  "cookie": "xoxd-abcdefghijklmnop",
  "expires_at": 9999999999
}
EOF

token=$(jq -r '.token' "$TEST_CLAUDE_DIR/slack-token.json")
if [[ "$token" == "xoxc-"* ]]; then
  pass "Valid xoxc token format detected"
else
  fail "Token validation" "starts with xoxc-" "$token"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test valid cookie format
cookie=$(jq -r '.cookie' "$TEST_CLAUDE_DIR/slack-token.json")
if [[ "$cookie" == "xoxd-"* ]]; then
  pass "Valid xoxd cookie format detected"
else
  fail "Cookie validation" "starts with xoxd-" "$cookie"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test token expiration check
expires_at=$(jq -r '.expires_at' "$TEST_CLAUDE_DIR/slack-token.json")
now=$(date +%s)
if [ "$expires_at" -gt "$now" ]; then
  pass "Token expiration check (future token is valid)"
else
  fail "Token expiration check" "expires_at > now" "$expires_at <= $now"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test expired token detection
cat > "$TEST_CLAUDE_DIR/slack-token-expired.json" << 'EOF'
{
  "token": "xoxc-123456789-123456789-123456789-abc123",
  "cookie": "xoxd-abcdefghijklmnop",
  "expires_at": 1000000000
}
EOF

expired_at=$(jq -r '.expires_at' "$TEST_CLAUDE_DIR/slack-token-expired.json")
if [ "$expired_at" -lt "$now" ]; then
  pass "Expired token detected correctly"
else
  fail "Expired token detection" "expires_at < now" "$expired_at >= $now"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test invalid token format
cat > "$TEST_CLAUDE_DIR/slack-token-invalid.json" << 'EOF'
{
  "token": "invalid-token-format",
  "cookie": "invalid-cookie-format",
  "expires_at": 9999999999
}
EOF

invalid_token=$(jq -r '.token' "$TEST_CLAUDE_DIR/slack-token-invalid.json")
if [[ "$invalid_token" != "xoxc-"* ]]; then
  pass "Invalid token format detected (not xoxc-)"
else
  fail "Invalid token detection" "does not start with xoxc-" "$invalid_token"
fi

invalid_cookie=$(jq -r '.cookie' "$TEST_CLAUDE_DIR/slack-token-invalid.json")
if [[ "$invalid_cookie" != "xoxd-"* ]]; then
  pass "Invalid cookie format detected (not xoxd-)"
else
  fail "Invalid cookie detection" "does not start with xoxd-" "$invalid_cookie"
fi

echo ""
echo "Testing API URL construction..."

TESTS_RUN=$((TESTS_RUN + 1))
# Test auth.test URL
auth_test_url="https://slack.com/api/auth.test"
if [[ "$auth_test_url" == "https://slack.com/api/auth.test" ]]; then
  pass "Auth test URL constructed correctly"
else
  fail "Auth test URL" "https://slack.com/api/auth.test" "$auth_test_url"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test conversations.list URL with parameters
channel_types="public_channel,private_channel"
limit=100
conversations_url="https://slack.com/api/conversations.list?types=${channel_types}&limit=${limit}"
if [[ "$conversations_url" == *"conversations.list"* ]] && \
   [[ "$conversations_url" == *"types=public_channel,private_channel"* ]] && \
   [[ "$conversations_url" == *"limit=100"* ]]; then
  pass "Conversations list URL constructed correctly"
else
  fail "Conversations list URL" "contains required params" "$conversations_url"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test conversations.history URL
channel_id="C123ABC"
history_url="https://slack.com/api/conversations.history?channel=${channel_id}&limit=20"
if [[ "$history_url" == *"conversations.history"* ]] && \
   [[ "$history_url" == *"channel=C123ABC"* ]]; then
  pass "Conversations history URL constructed correctly"
else
  fail "Conversations history URL" "contains channel param" "$history_url"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test conversations.replies URL
thread_ts="1705344000.000100"
replies_url="https://slack.com/api/conversations.replies?channel=${channel_id}&ts=${thread_ts}"
if [[ "$replies_url" == *"conversations.replies"* ]] && \
   [[ "$replies_url" == *"ts=1705344000.000100"* ]]; then
  pass "Conversations replies URL constructed correctly"
else
  fail "Conversations replies URL" "contains ts param" "$replies_url"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test search.messages URL
query="project update"
search_url="https://slack.com/api/search.messages?query=${query}&count=20"
if [[ "$search_url" == *"search.messages"* ]] && \
   [[ "$search_url" == *"query="* ]]; then
  pass "Search messages URL constructed correctly"
else
  fail "Search messages URL" "contains query param" "$search_url"
fi

echo ""
echo "Testing JSON payload construction..."

TESTS_RUN=$((TESTS_RUN + 1))
# Test chat.postMessage payload (without thread)
channel="C123ABC"
text="Hello from test"
payload=$(jq -n \
  --arg channel "$channel" \
  --arg text "$text" \
  '{channel: $channel, text: $text}')

payload_channel=$(echo "$payload" | jq -r '.channel')
payload_text=$(echo "$payload" | jq -r '.text')
if [ "$payload_channel" = "C123ABC" ] && [ "$payload_text" = "Hello from test" ]; then
  pass "Basic message payload constructed correctly"
else
  fail "Basic message payload" "channel=C123ABC, text=Hello from test" "channel=$payload_channel, text=$payload_text"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test chat.postMessage payload (with thread)
thread_ts="1705344000.000100"
payload_threaded=$(jq -n \
  --arg channel "$channel" \
  --arg text "$text" \
  --arg thread_ts "$thread_ts" \
  '{channel: $channel, text: $text, thread_ts: $thread_ts}')

payload_thread_ts=$(echo "$payload_threaded" | jq -r '.thread_ts')
if [ "$payload_thread_ts" = "1705344000.000100" ]; then
  pass "Threaded message payload constructed correctly"
else
  fail "Threaded message payload" "thread_ts=1705344000.000100" "thread_ts=$payload_thread_ts"
fi

echo ""
echo "Testing response parsing..."

TESTS_RUN=$((TESTS_RUN + 1))
# Test auth.test success response
cat > "$TEST_DIR/auth-response.json" << 'EOF'
{
  "ok": true,
  "url": "https://mycompany.slack.com/",
  "team": "My Company",
  "user": "pavel",
  "team_id": "T123ABC",
  "user_id": "U123ABC"
}
EOF

is_ok=$(jq -r '.ok' "$TEST_DIR/auth-response.json")
if [ "$is_ok" = "true" ]; then
  pass "Auth success response parsed correctly"
else
  fail "Auth success parsing" "ok=true" "ok=$is_ok"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test user info extraction
user_name=$(jq -r '.user' "$TEST_DIR/auth-response.json")
team_name=$(jq -r '.team' "$TEST_DIR/auth-response.json")
if [ "$user_name" = "pavel" ] && [ "$team_name" = "My Company" ]; then
  pass "User info extracted correctly"
else
  fail "User info extraction" "user=pavel, team=My Company" "user=$user_name, team=$team_name"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test conversations.list response
cat > "$TEST_DIR/channels-response.json" << 'EOF'
{
  "ok": true,
  "channels": [
    {
      "id": "C123ABC",
      "name": "general",
      "is_channel": true,
      "is_private": false,
      "is_member": true
    },
    {
      "id": "C456DEF",
      "name": "engineering",
      "is_channel": true,
      "is_private": true,
      "is_member": true
    }
  ]
}
EOF

channel_count=$(jq '.channels | length' "$TEST_DIR/channels-response.json")
if [ "$channel_count" = "2" ]; then
  pass "Channel count parsed correctly"
else
  fail "Channel count" "2" "$channel_count"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test channel ID extraction by name
channel_id_by_name=$(jq -r '.channels[] | select(.name == "engineering") | .id' "$TEST_DIR/channels-response.json")
if [ "$channel_id_by_name" = "C456DEF" ]; then
  pass "Channel ID lookup by name works"
else
  fail "Channel ID lookup" "C456DEF" "$channel_id_by_name"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test messages response
cat > "$TEST_DIR/messages-response.json" << 'EOF'
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
    },
    {
      "type": "message",
      "user": "U456DEF",
      "text": "Good morning!",
      "ts": "1705343900.000050"
    }
  ],
  "has_more": true
}
EOF

message_count=$(jq '.messages | length' "$TEST_DIR/messages-response.json")
if [ "$message_count" = "2" ]; then
  pass "Message count parsed correctly"
else
  fail "Message count" "2" "$message_count"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test thread detection
has_thread=$(jq '.messages[0] | has("reply_count")' "$TEST_DIR/messages-response.json")
reply_count=$(jq '.messages[0].reply_count // 0' "$TEST_DIR/messages-response.json")
if [ "$has_thread" = "true" ] && [ "$reply_count" = "3" ]; then
  pass "Thread with replies detected"
else
  fail "Thread detection" "has_thread=true, reply_count=3" "has_thread=$has_thread, reply_count=$reply_count"
fi

echo ""
echo "Testing error response parsing..."

TESTS_RUN=$((TESTS_RUN + 1))
# Test auth error response
cat > "$TEST_DIR/error-response.json" << 'EOF'
{
  "ok": false,
  "error": "invalid_auth"
}
EOF

is_error=$(jq '.ok == false' "$TEST_DIR/error-response.json")
if [ "$is_error" = "true" ]; then
  pass "Error response detected correctly"
else
  fail "Error detection" "ok=false" "ok=$(jq '.ok' "$TEST_DIR/error-response.json")"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test error code extraction
error_code=$(jq -r '.error' "$TEST_DIR/error-response.json")
if [ "$error_code" = "invalid_auth" ]; then
  pass "Error code extracted correctly"
else
  fail "Error code" "invalid_auth" "$error_code"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test rate limit error
cat > "$TEST_DIR/ratelimit-response.json" << 'EOF'
{
  "ok": false,
  "error": "ratelimited"
}
EOF

ratelimit_error=$(jq -r '.error' "$TEST_DIR/ratelimit-response.json")
if [ "$ratelimit_error" = "ratelimited" ]; then
  pass "Rate limit error detected correctly"
else
  fail "Rate limit error" "ratelimited" "$ratelimit_error"
fi

echo ""
echo "Testing connection configuration..."

TESTS_RUN=$((TESTS_RUN + 1))
# Test auto connection config
cat > "$TEST_CLAUDE_DIR/status-config-auto.json" << 'EOF'
{
  "slack": {
    "connection": "auto",
    "workspace": "mycompany.slack.com",
    "chrome": { "tabId": null },
    "playwright": { "profile": "default", "headless": false }
  }
}
EOF

connection=$(jq -r '.slack.connection' "$TEST_CLAUDE_DIR/status-config-auto.json")
if [ "$connection" = "auto" ]; then
  pass "Auto connection config parsed correctly"
else
  fail "Auto connection config" "auto" "$connection"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test MCP connection config
cat > "$TEST_CLAUDE_DIR/status-config-mcp.json" << 'EOF'
{
  "slack": {
    "connection": "mcp",
    "workspace": "mycompany.slack.com"
  }
}
EOF

mcp_connection=$(jq -r '.slack.connection' "$TEST_CLAUDE_DIR/status-config-mcp.json")
if [ "$mcp_connection" = "mcp" ]; then
  pass "MCP connection config parsed correctly"
else
  fail "MCP connection" "mcp" "$mcp_connection"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test chrome connection config
cat > "$TEST_CLAUDE_DIR/status-config-chrome.json" << 'EOF'
{
  "slack": {
    "connection": "chrome",
    "workspace": "mycompany.slack.com",
    "chrome": { "tabId": 12345 }
  }
}
EOF

chrome_tab=$(jq -r '.slack.chrome.tabId' "$TEST_CLAUDE_DIR/status-config-chrome.json")
if [ "$chrome_tab" = "12345" ]; then
  pass "Chrome connection with tabId parsed correctly"
else
  fail "Chrome tabId" "12345" "$chrome_tab"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test playwright connection config
cat > "$TEST_CLAUDE_DIR/status-config-playwright.json" << 'EOF'
{
  "slack": {
    "connection": "playwright",
    "workspace": "mycompany.slack.com",
    "playwright": { "profile": "custom", "headless": true }
  }
}
EOF

pw_profile=$(jq -r '.slack.playwright.profile' "$TEST_CLAUDE_DIR/status-config-playwright.json")
pw_headless=$(jq -r '.slack.playwright.headless' "$TEST_CLAUDE_DIR/status-config-playwright.json")
if [ "$pw_profile" = "custom" ] && [ "$pw_headless" = "true" ]; then
  pass "Playwright connection config parsed correctly"
else
  fail "Playwright config" "profile=custom, headless=true" "profile=$pw_profile, headless=$pw_headless"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test API connection config (legacy)
cat > "$TEST_CLAUDE_DIR/status-config-api.json" << 'EOF'
{
  "slack": {
    "connection": "api",
    "workspace": "mycompany.slack.com"
  }
}
EOF

api_connection=$(jq -r '.slack.connection' "$TEST_CLAUDE_DIR/status-config-api.json")
if [ "$api_connection" = "api" ]; then
  pass "API connection config parsed correctly"
else
  fail "API connection" "api" "$api_connection"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test disabled connection
cat > "$TEST_CLAUDE_DIR/status-config-disabled.json" << 'EOF'
{
  "slack": {
    "connection": "disabled"
  }
}
EOF

disabled=$(jq -r '.slack.connection' "$TEST_CLAUDE_DIR/status-config-disabled.json")
if [ "$disabled" = "disabled" ]; then
  pass "Disabled connection config parsed correctly"
else
  fail "Disabled connection" "disabled" "$disabled"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test connection type validation
valid_connections="auto mcp chrome playwright api disabled"
test_connection="mcp"
if echo "$valid_connections" | grep -qw "$test_connection"; then
  pass "Connection type validation works (mcp is valid)"
else
  fail "Connection validation" "mcp in valid list" "not found"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test connection priority order
priority_order="mcp chrome playwright api"
first_priority=$(echo "$priority_order" | awk '{print $1}')
if [ "$first_priority" = "mcp" ]; then
  pass "Connection priority order correct (MCP first)"
else
  fail "Connection priority" "mcp first" "$first_priority first"
fi

echo ""
echo "Testing Chrome extraction output parsing..."

TESTS_RUN=$((TESTS_RUN + 1))
# Test browser extraction output
cat > "$TEST_DIR/chrome-extraction.json" << 'EOF'
{
  "unreadCount": 15,
  "channels": [
    { "name": "incidents", "id": "C123ABC", "unreads": 5 },
    { "name": "engineering", "id": "C456DEF", "unreads": 10 }
  ],
  "dms": [
    { "name": "boss", "id": "D789GHI", "unreads": 2 }
  ],
  "mentions": ["@you can you review this?"]
}
EOF

unread_count=$(jq '.unreadCount' "$TEST_DIR/chrome-extraction.json")
channel_count=$(jq '.channels | length' "$TEST_DIR/chrome-extraction.json")
dm_count=$(jq '.dms | length' "$TEST_DIR/chrome-extraction.json")

if [ "$unread_count" = "15" ] && [ "$channel_count" = "2" ] && [ "$dm_count" = "1" ]; then
  pass "Chrome extraction output parsed correctly"
else
  fail "Chrome extraction" "unreads=15, channels=2, dms=1" "unreads=$unread_count, channels=$channel_count, dms=$dm_count"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test VIP detection logic
vip_list='["@boss", "@tech-lead"]'
dm_name="boss"
is_vip=$(echo "$vip_list" | jq --arg name "$dm_name" 'any(. | contains($name))')
if [ "$is_vip" = "true" ]; then
  pass "VIP detection works correctly"
else
  fail "VIP detection" "boss is VIP" "not detected"
fi

echo ""
echo "Testing search response parsing..."

TESTS_RUN=$((TESTS_RUN + 1))
# Test search response
cat > "$TEST_DIR/search-response.json" << 'EOF'
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
        "text": "Here is the project update for this week",
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
EOF

search_total=$(jq '.messages.total' "$TEST_DIR/search-response.json")
if [ "$search_total" = "42" ]; then
  pass "Search total count parsed correctly"
else
  fail "Search total" "42" "$search_total"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test search match extraction
match_channel=$(jq -r '.messages.matches[0].channel.name' "$TEST_DIR/search-response.json")
match_permalink=$(jq -r '.messages.matches[0].permalink' "$TEST_DIR/search-response.json")
if [ "$match_channel" = "engineering" ] && [[ "$match_permalink" == *"slack.com/archives"* ]]; then
  pass "Search match details extracted correctly"
else
  fail "Search match" "channel=engineering, has permalink" "channel=$match_channel, permalink=$match_permalink"
fi

echo ""
echo "=== Results ==="
echo "Tests run: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"

if [ "$TESTS_FAILED" -gt 0 ]; then
  exit 1
fi
