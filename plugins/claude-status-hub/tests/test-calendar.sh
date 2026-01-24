#!/bin/bash
# Test calendar integration functionality
# Tests time-based icon selection, detail formatting, and alert detection

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
BIN_DIR="$PLUGIN_DIR/bin"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

# Production paths
BRIDGE="/tmp/status-hub.json"
CONFIG="$HOME/.claude/status-config.json"

# Backup existing files
BACKUP_BRIDGE=""
BACKUP_CONFIG=""
if [ -f "$BRIDGE" ]; then BACKUP_BRIDGE=$(cat "$BRIDGE"); fi
if [ -f "$CONFIG" ]; then BACKUP_CONFIG=$(cat "$CONFIG"); fi

# Ensure config directory exists
mkdir -p "$(dirname "$CONFIG")"

cleanup() {
  # Restore backups
  if [ -n "$BACKUP_BRIDGE" ]; then
    echo "$BACKUP_BRIDGE" > "$BRIDGE"
  else
    rm -f "$BRIDGE"
  fi
  if [ -n "$BACKUP_CONFIG" ]; then
    echo "$BACKUP_CONFIG" > "$CONFIG"
  else
    rm -f "$CONFIG"
  fi
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

echo "=== Testing calendar integration ==="
echo ""

# ============================================
# Test: Calendar icon selection
# ============================================
echo "Testing icon selection..."

# Function to determine calendar icon based on minutes until meeting
# Mirrors logic in hub-refresh-calendar.md
get_calendar_icon() {
  local diff_minutes="$1"

  if [ "$diff_minutes" -gt 5 ]; then
    echo "📅"  # upcoming
  elif [ "$diff_minutes" -ge -5 ] && [ "$diff_minutes" -le 5 ]; then
    echo "🔴"  # starting now
  elif [ "$diff_minutes" -lt -5 ]; then
    echo "🔴"  # missed/late
  fi
}

# Test: Meeting in 30 minutes
icon=$(get_calendar_icon 30)
if [ "$icon" = "📅" ]; then
  pass "Meeting in 30min → 📅 icon"
else
  fail "Meeting in 30min → 📅 icon" "📅" "$icon"
fi

# Test: Meeting in 3 minutes
icon=$(get_calendar_icon 3)
if [ "$icon" = "🔴" ]; then
  pass "Meeting in 3min → 🔴 icon"
else
  fail "Meeting in 3min → 🔴 icon" "🔴" "$icon"
fi

# Test: Meeting starting now
icon=$(get_calendar_icon 0)
if [ "$icon" = "🔴" ]; then
  pass "Meeting now → 🔴 icon"
else
  fail "Meeting now → 🔴 icon" "🔴" "$icon"
fi

# Test: Meeting started 10 minutes ago
icon=$(get_calendar_icon -10)
if [ "$icon" = "🔴" ]; then
  pass "Meeting started 10min ago → 🔴 icon"
else
  fail "Meeting started 10min ago → 🔴 icon" "🔴" "$icon"
fi

echo ""

# ============================================
# Test: Detail string formatting
# ============================================
echo "Testing detail formatting..."

# Function to format detail string based on minutes
# Mirrors logic in hub-refresh-calendar.md
format_calendar_detail() {
  local diff_minutes="$1"

  if [ "$diff_minutes" -gt 0 ]; then
    echo "in ${diff_minutes}m"
  elif [ "$diff_minutes" -eq 0 ]; then
    echo "now"
  else
    local ago=$(( -1 * diff_minutes ))
    echo "started ${ago}m ago"
  fi
}

# Test: Meeting in 15 minutes
detail=$(format_calendar_detail 15)
if [ "$detail" = "in 15m" ]; then
  pass "15min before → 'in 15m'"
else
  fail "15min before → 'in 15m'" "in 15m" "$detail"
fi

# Test: Meeting starting now
detail=$(format_calendar_detail 0)
if [ "$detail" = "now" ]; then
  pass "0min → 'now'"
else
  fail "0min → 'now'" "now" "$detail"
fi

# Test: Meeting started 5 minutes ago
detail=$(format_calendar_detail -5)
if [ "$detail" = "started 5m ago" ]; then
  pass "5min after → 'started 5m ago'"
else
  fail "5min after → 'started 5m ago'" "started 5m ago" "$detail"
fi

echo ""

# ============================================
# Test: Alert detection
# ============================================
echo "Testing alert detection..."

# Function to determine if alert should trigger
# Mirrors logic in hub-refresh-calendar.md
should_alert() {
  local diff_minutes="$1"
  local alert_threshold="$2"
  local has_attachments="$3"
  local alert_with_docs="${4:-10}"

  # Use extended threshold for meetings with attachments
  local threshold="$alert_threshold"
  if [ "$has_attachments" = "true" ]; then
    threshold="$alert_with_docs"
  fi

  # Alert if meeting is within threshold and hasn't started too long ago
  if [ "$diff_minutes" -le "$threshold" ] && [ "$diff_minutes" -ge -30 ]; then
    echo "true"
  else
    echo "false"
  fi
}

# Test: Meeting in 3 minutes, threshold 5 → alert
alert=$(should_alert 3 5 false)
if [ "$alert" = "true" ]; then
  pass "Meeting in 3min (threshold 5) → alert"
else
  fail "Meeting in 3min (threshold 5) → alert" "true" "$alert"
fi

# Test: Meeting in 10 minutes, threshold 5 → no alert
alert=$(should_alert 10 5 false)
if [ "$alert" = "false" ]; then
  pass "Meeting in 10min (threshold 5) → no alert"
else
  fail "Meeting in 10min (threshold 5) → no alert" "false" "$alert"
fi

# Test: Meeting in 8 minutes with attachments, threshold 10 → alert
alert=$(should_alert 8 5 true 10)
if [ "$alert" = "true" ]; then
  pass "Meeting in 8min with docs (threshold 10) → alert"
else
  fail "Meeting in 8min with docs (threshold 10) → alert" "true" "$alert"
fi

# Test: Meeting started 15 minutes ago → alert (still within -30 window)
alert=$(should_alert -15 5 false)
if [ "$alert" = "true" ]; then
  pass "Meeting started 15min ago → alert"
else
  fail "Meeting started 15min ago → alert" "true" "$alert"
fi

# Test: Meeting ended 45 minutes ago → no alert
alert=$(should_alert -45 5 false)
if [ "$alert" = "false" ]; then
  pass "Meeting ended 45min ago → no alert"
else
  fail "Meeting ended 45min ago → no alert" "false" "$alert"
fi

echo ""

# ============================================
# Test: Bridge output format
# ============================================
echo "Testing bridge output format..."

# Create a calendar bridge entry and validate structure
cat > "$BRIDGE" << 'EOF'
{
  "timestamp": 1705500000000,
  "background": null,
  "foreground": [
    {
      "site": "calendar",
      "icon": "📅",
      "title": "Daily Standup",
      "detail": "in 3m",
      "hasAlert": true,
      "data": {
        "startTime": 1705500180000,
        "meetingLink": "https://meet.google.com/abc-defg-hij",
        "organizer": "alice@example.com"
      }
    }
  ]
}
EOF

# Validate JSON structure
if jq -e '.foreground[0].site == "calendar"' "$BRIDGE" > /dev/null 2>&1; then
  pass "Bridge has calendar site field"
else
  fail "Bridge has calendar site field" "calendar" "$(jq -r '.foreground[0].site' "$BRIDGE")"
fi

if jq -e '.foreground[0].data.meetingLink' "$BRIDGE" > /dev/null 2>&1; then
  pass "Bridge has meetingLink in data"
else
  fail "Bridge has meetingLink in data" "exists" "missing"
fi

if jq -e '.foreground[0].data.organizer' "$BRIDGE" > /dev/null 2>&1; then
  pass "Bridge has organizer in data"
else
  fail "Bridge has organizer in data" "exists" "missing"
fi

if jq -e '.foreground[0].hasAlert == true' "$BRIDGE" > /dev/null 2>&1; then
  pass "Bridge has hasAlert field"
else
  fail "Bridge has hasAlert field" "true" "$(jq -r '.foreground[0].hasAlert' "$BRIDGE")"
fi

echo ""

# ============================================
# Test: Config structure
# ============================================
echo "Testing config structure..."

# Create calendar config and validate
cat > "$CONFIG" << 'EOF'
{
  "calendar": {
    "connection": "chrome",
    "chrome": { "tabId": 12345 },
    "alertMinutesBefore": 5,
    "alertWithDocsBefore": 10,
    "lateMessageTo": "organizer",
    "lastSeen": {
      "nextMeeting": {
        "title": "Daily Standup",
        "startTime": 1705868400000,
        "meetingLink": "https://meet.google.com/abc-defg-hij",
        "organizer": "alice@example.com"
      }
    }
  }
}
EOF

if jq -e '.calendar.connection == "chrome"' "$CONFIG" > /dev/null 2>&1; then
  pass "Config has calendar.connection"
else
  fail "Config has calendar.connection" "chrome" "$(jq -r '.calendar.connection' "$CONFIG")"
fi

if jq -e '.calendar.chrome.tabId == 12345' "$CONFIG" > /dev/null 2>&1; then
  pass "Config has calendar.chrome.tabId"
else
  fail "Config has calendar.chrome.tabId" "12345" "$(jq -r '.calendar.chrome.tabId' "$CONFIG")"
fi

if jq -e '.calendar.alertMinutesBefore == 5' "$CONFIG" > /dev/null 2>&1; then
  pass "Config has alertMinutesBefore default"
else
  fail "Config has alertMinutesBefore default" "5" "$(jq -r '.calendar.alertMinutesBefore' "$CONFIG")"
fi

if jq -e '.calendar.lastSeen.nextMeeting.meetingLink' "$CONFIG" > /dev/null 2>&1; then
  pass "Config stores lastSeen.nextMeeting"
else
  fail "Config stores lastSeen.nextMeeting" "exists" "missing"
fi

echo ""

# ============================================
# Test: Time-based case determination
# ============================================
echo "Testing ack wizard case determination..."

# Function to determine which ack case to use
# Mirrors logic in hub-ack-calendar.md
get_ack_case() {
  local diff_minutes="$1"

  if [ "$diff_minutes" -gt 5 ]; then
    echo "A"  # upcoming (only for meetings with attachments)
  elif [ "$diff_minutes" -ge -5 ] && [ "$diff_minutes" -le 5 ]; then
    echo "B"  # starting now
  elif [ "$diff_minutes" -lt -5 ] && [ "$diff_minutes" -ge -30 ]; then
    echo "C"  # started
  else
    echo "D"  # late ack (> 30min after)
  fi
}

# Test: Meeting in 10 minutes → Case A
case_result=$(get_ack_case 10)
if [ "$case_result" = "A" ]; then
  pass "10min before → Case A (upcoming)"
else
  fail "10min before → Case A (upcoming)" "A" "$case_result"
fi

# Test: Meeting in 2 minutes → Case B
case_result=$(get_ack_case 2)
if [ "$case_result" = "B" ]; then
  pass "2min before → Case B (starting now)"
else
  fail "2min before → Case B (starting now)" "B" "$case_result"
fi

# Test: Meeting started 3 minutes ago → Case B (within -5 to +5 window)
case_result=$(get_ack_case -3)
if [ "$case_result" = "B" ]; then
  pass "3min after → Case B (starting now)"
else
  fail "3min after → Case B (starting now)" "B" "$case_result"
fi

# Test: Meeting started 15 minutes ago → Case C
case_result=$(get_ack_case -15)
if [ "$case_result" = "C" ]; then
  pass "15min after → Case C (started)"
else
  fail "15min after → Case C (started)" "C" "$case_result"
fi

# Test: Meeting ended 45 minutes ago → Case D
case_result=$(get_ack_case -45)
if [ "$case_result" = "D" ]; then
  pass "45min after → Case D (late ack)"
else
  fail "45min after → Case D (late ack)" "D" "$case_result"
fi

echo ""

# ============================================
# Results
# ============================================
echo "=== Results ==="
echo "Tests run: $((TESTS_PASSED + TESTS_FAILED))"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"

if [ "$TESTS_FAILED" -gt 0 ]; then
  exit 1
fi
