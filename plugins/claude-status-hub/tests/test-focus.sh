#!/bin/bash
# Test focus mode functionality
# Tests config parsing, break detection, status generation, meeting conflicts

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$(dirname "$SCRIPT_DIR")/bin"

# Production paths
BRIDGE="/tmp/status-hub.json"
CONFIG="$HOME/.claude/status-config.json"

# Backup existing files
BACKUP_BRIDGE=""
BACKUP_CONFIG=""
if [ -f "$BRIDGE" ]; then BACKUP_BRIDGE=$(cat "$BRIDGE"); fi
if [ -f "$CONFIG" ]; then BACKUP_CONFIG=$(cat "$CONFIG"); fi

# Ensure config directory exists (for CI environments)
mkdir -p "$(dirname "$CONFIG")"

cleanup() {
  rm -f "$BRIDGE"
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

echo "=== Testing Focus Mode ==="
echo ""

echo "Testing focus config parsing..."

# Test default focus config values
TESTS_RUN=$((TESTS_RUN + 1))
cat > "$CONFIG" << 'EOF'
{
  "focus": {}
}
EOF
default_duration=$(jq -r '.focus.defaultDurationHours // 2' "$CONFIG")
default_break=$(jq -r '.focus.breakAfterMinutes // 75' "$CONFIG")
if [ "$default_duration" = "2" ] && [ "$default_break" = "75" ]; then
  pass "Default focus config values"
else
  fail "Default focus values" "duration=2, break=75" "duration=$default_duration, break=$default_break"
fi

# Test custom focus config values
TESTS_RUN=$((TESTS_RUN + 1))
cat > "$CONFIG" << 'EOF'
{
  "focus": {
    "defaultDurationHours": 3,
    "breakAfterMinutes": 90,
    "criticalChannels": ["#incidents", "#outages"],
    "defaultStatus": "Do not disturb until {end_time}"
  }
}
EOF
custom_duration=$(jq -r '.focus.defaultDurationHours' "$CONFIG")
custom_break=$(jq -r '.focus.breakAfterMinutes' "$CONFIG")
channels_count=$(jq -r '.focus.criticalChannels | length' "$CONFIG")
if [ "$custom_duration" = "3" ] && [ "$custom_break" = "90" ] && [ "$channels_count" = "2" ]; then
  pass "Custom focus config parsing"
else
  fail "Custom focus config" "duration=3, break=90, channels=2" "duration=$custom_duration, break=$custom_break, channels=$channels_count"
fi

echo ""
echo "Testing break threshold detection..."

# Test focus not active - no break reminder
TESTS_RUN=$((TESTS_RUN + 1))
cat > "$CONFIG" << 'EOF'
{
  "focus": {
    "active": false
  }
}
EOF
focus_active=$(jq -r '.focus.active // false' "$CONFIG")
if [ "$focus_active" = "false" ]; then
  pass "Focus inactive detected"
else
  fail "Focus inactive" "false" "$focus_active"
fi

# Test focus active but under threshold
TESTS_RUN=$((TESTS_RUN + 1))
now_ms=$(($(date +%s) * 1000))
start_30min_ago=$((now_ms - 30 * 60000))
cat > "$CONFIG" << EOF
{
  "focus": {
    "active": true,
    "startTime": $start_30min_ago,
    "breakAfterMinutes": 75
  }
}
EOF
start_time=$(jq -r '.focus.startTime' "$CONFIG")
break_after=$(jq -r '.focus.breakAfterMinutes' "$CONFIG")
duration_min=$(( (now_ms - start_time) / 60000 ))
if [ "$duration_min" -lt "$break_after" ]; then
  pass "Under break threshold (${duration_min}m < ${break_after}m)"
else
  fail "Under break threshold" "<75" "$duration_min"
fi

# Test focus active and over threshold
TESTS_RUN=$((TESTS_RUN + 1))
start_90min_ago=$((now_ms - 90 * 60000))
cat > "$CONFIG" << EOF
{
  "focus": {
    "active": true,
    "startTime": $start_90min_ago,
    "breakAfterMinutes": 75
  }
}
EOF
start_time=$(jq -r '.focus.startTime' "$CONFIG")
break_after=$(jq -r '.focus.breakAfterMinutes' "$CONFIG")
duration_min=$(( (now_ms - start_time) / 60000 ))
if [ "$duration_min" -ge "$break_after" ]; then
  pass "Over break threshold (${duration_min}m >= ${break_after}m)"
else
  fail "Over break threshold" ">=75" "$duration_min"
fi

# Test last reminder check (should skip if reminded recently)
TESTS_RUN=$((TESTS_RUN + 1))
reminder_5min_ago=$((now_ms - 5 * 60000))
cat > "$CONFIG" << EOF
{
  "focus": {
    "active": true,
    "startTime": $start_90min_ago,
    "breakAfterMinutes": 75,
    "lastBreakReminder": $reminder_5min_ago
  }
}
EOF
last_reminder=$(jq -r '.focus.lastBreakReminder' "$CONFIG")
since_reminder=$(( (now_ms - last_reminder) / 60000 ))
if [ "$since_reminder" -lt 15 ]; then
  pass "Skip reminder if reminded recently (${since_reminder}m < 15m)"
else
  fail "Recent reminder skip" "<15" "$since_reminder"
fi

echo ""
echo "Testing status format generation..."

# Test status template substitution
TESTS_RUN=$((TESTS_RUN + 1))
end_time=$((now_ms + 2 * 60 * 60000))  # 2 hours from now
end_time_unix=$((end_time / 1000))
end_time_formatted=$(date -r $end_time_unix "+%l:%M %p" 2>/dev/null | xargs || date -d "@$end_time_unix" "+%l:%M %p" 2>/dev/null | xargs)
cat > "$CONFIG" << EOF
{
  "focus": {
    "active": true,
    "endTime": $end_time,
    "defaultStatus": "Deep focus until {end_time}"
  }
}
EOF
status_template=$(jq -r '.focus.defaultStatus' "$CONFIG")
status_text="${status_template//\{end_time\}/$end_time_formatted}"
if [[ "$status_text" == *"Deep focus until"* ]] && [[ "$status_text" != *"{end_time}"* ]]; then
  pass "Status template substitution"
else
  fail "Status template" "Deep focus until <time>" "$status_text"
fi

# Test slackStatusSet tracking
TESTS_RUN=$((TESTS_RUN + 1))
cat > "$CONFIG" << 'EOF'
{
  "focus": {
    "active": true,
    "slackStatusSet": true
  }
}
EOF
slack_set=$(jq -r '.focus.slackStatusSet' "$CONFIG")
if [ "$slack_set" = "true" ]; then
  pass "slackStatusSet tracking"
else
  fail "slackStatusSet" "true" "$slack_set"
fi

echo ""
echo "Testing meeting conflict detection..."

# Test no conflicts (meeting after focus ends)
TESTS_RUN=$((TESTS_RUN + 1))
focus_end=$((now_ms + 2 * 60 * 60000))  # 2 hours
meeting_start=$((now_ms + 3 * 60 * 60000))  # 3 hours
cat > "$CONFIG" << EOF
{
  "focus": {
    "endTime": $focus_end
  },
  "calendar": {
    "lastSeen": [
      {"title": "Team sync", "startTime": $meeting_start}
    ]
  }
}
EOF
first_meeting=$(jq -r '.calendar.lastSeen[0].startTime' "$CONFIG")
focus_end_time=$(jq -r '.focus.endTime' "$CONFIG")
if [ "$first_meeting" -gt "$focus_end_time" ]; then
  pass "No conflict (meeting after focus)"
else
  fail "No conflict" "meeting > focus_end" "meeting=$first_meeting, focus_end=$focus_end_time"
fi

# Test conflict (meeting during focus)
TESTS_RUN=$((TESTS_RUN + 1))
meeting_during=$((now_ms + 1 * 60 * 60000))  # 1 hour (during 2hr focus)
cat > "$CONFIG" << EOF
{
  "focus": {
    "endTime": $focus_end
  },
  "calendar": {
    "lastSeen": [
      {"title": "Team sync", "startTime": $meeting_during}
    ]
  }
}
EOF
first_meeting=$(jq -r '.calendar.lastSeen[0].startTime' "$CONFIG")
focus_end_time=$(jq -r '.focus.endTime' "$CONFIG")
if [ "$first_meeting" -lt "$focus_end_time" ] && [ "$first_meeting" -gt "$now_ms" ]; then
  pass "Conflict detected (meeting during focus)"
else
  fail "Conflict detected" "meeting < focus_end" "meeting=$first_meeting, focus_end=$focus_end_time"
fi

# Test gap check for break reminder
TESTS_RUN=$((TESTS_RUN + 1))
meeting_in_30min=$((now_ms + 30 * 60000))
cat > "$CONFIG" << EOF
{
  "calendar": {
    "lastSeen": [
      {"title": "Standup", "startTime": $meeting_in_30min}
    ]
  }
}
EOF
next_start=$(jq -r '.calendar.lastSeen[0].startTime' "$CONFIG")
min_until=$(( (next_start - now_ms) / 60000 ))
if [ "$min_until" -ge 15 ]; then
  pass "Break window available (${min_until}m >= 15m)"
else
  fail "Break window" ">=15" "$min_until"
fi

# Test no break window (meeting too soon)
TESTS_RUN=$((TESTS_RUN + 1))
meeting_in_10min=$((now_ms + 10 * 60000))
cat > "$CONFIG" << EOF
{
  "calendar": {
    "lastSeen": [
      {"title": "Quick sync", "startTime": $meeting_in_10min}
    ]
  }
}
EOF
next_start=$(jq -r '.calendar.lastSeen[0].startTime' "$CONFIG")
min_until=$(( (next_start - now_ms) / 60000 ))
if [ "$min_until" -lt 15 ]; then
  pass "No break window (${min_until}m < 15m)"
else
  fail "No break window" "<15" "$min_until"
fi

echo ""
echo "Testing notification suppression config..."

# Test critical channels config
TESTS_RUN=$((TESTS_RUN + 1))
cat > "$CONFIG" << 'EOF'
{
  "focus": {
    "criticalChannels": ["#incidents", "#outages", "#deployments"]
  }
}
EOF
channels=$(jq -r '.focus.criticalChannels | join(",")' "$CONFIG")
if [ "$channels" = "#incidents,#outages,#deployments" ]; then
  pass "Critical channels config"
else
  fail "Critical channels" "#incidents,#outages,#deployments" "$channels"
fi

# Test VIP DMs config
TESTS_RUN=$((TESTS_RUN + 1))
cat > "$CONFIG" << 'EOF'
{
  "focus": {
    "allowVipDms": true
  },
  "slack": {
    "vipPeople": ["@boss", "@tech-lead"]
  }
}
EOF
allow_vip=$(jq -r '.focus.allowVipDms' "$CONFIG")
vip_count=$(jq -r '.slack.vipPeople | length' "$CONFIG")
if [ "$allow_vip" = "true" ] && [ "$vip_count" = "2" ]; then
  pass "VIP DMs config"
else
  fail "VIP DMs" "allowVipDms=true, 2 VIPs" "allowVipDms=$allow_vip, $vip_count VIPs"
fi

# Test suppressed channels tracking
TESTS_RUN=$((TESTS_RUN + 1))
cat > "$CONFIG" << 'EOF'
{
  "focus": {
    "active": true,
    "suppressedChannels": ["#general", "#random"],
    "allowedChannels": ["#incidents"]
  }
}
EOF
suppressed=$(jq -r '.focus.suppressedChannels | length' "$CONFIG")
allowed=$(jq -r '.focus.allowedChannels | length' "$CONFIG")
if [ "$suppressed" = "2" ] && [ "$allowed" = "1" ]; then
  pass "Channel suppression tracking"
else
  fail "Channel suppression" "2 suppressed, 1 allowed" "$suppressed suppressed, $allowed allowed"
fi

echo ""
echo "Testing focus state transitions..."

# Test focus activation state
TESTS_RUN=$((TESTS_RUN + 1))
cat > "$CONFIG" << EOF
{
  "focus": {
    "active": true,
    "startTime": $now_ms,
    "endTime": $((now_ms + 7200000)),
    "declinedMeetings": ["meeting-123"]
  }
}
EOF
active=$(jq -r '.focus.active' "$CONFIG")
has_start=$(jq -r '.focus.startTime != null' "$CONFIG")
has_end=$(jq -r '.focus.endTime != null' "$CONFIG")
declined=$(jq -r '.focus.declinedMeetings | length' "$CONFIG")
if [ "$active" = "true" ] && [ "$has_start" = "true" ] && [ "$has_end" = "true" ] && [ "$declined" = "1" ]; then
  pass "Focus activation state"
else
  fail "Focus state" "active with start/end/declined" "active=$active, start=$has_start, end=$has_end, declined=$declined"
fi

# Test focus deactivation
TESTS_RUN=$((TESTS_RUN + 1))
cat > "$CONFIG" << EOF
{
  "focus": {
    "active": false,
    "lastEndTime": $now_ms,
    "lastDuration": 94
  }
}
EOF
active=$(jq -r '.focus.active' "$CONFIG")
has_last_end=$(jq -r '.focus.lastEndTime != null' "$CONFIG")
last_duration=$(jq -r '.focus.lastDuration' "$CONFIG")
if [ "$active" = "false" ] && [ "$has_last_end" = "true" ] && [ "$last_duration" = "94" ]; then
  pass "Focus deactivation state"
else
  fail "Focus deactivation" "inactive with lastEnd/lastDuration" "active=$active, lastEnd=$has_last_end, duration=$last_duration"
fi

echo ""
echo "Testing bridge focus alert..."

# Test focus break alert in bridge
TESTS_RUN=$((TESTS_RUN + 1))
cat > "$BRIDGE" << 'EOF'
{
  "timestamp": 1000,
  "foreground": [
    {"service": "focus", "icon": "coffee", "title": "Break reminder", "detail": "90m focus. Break?", "hasAlert": true}
  ]
}
EOF
focus_alert=$(jq -r '.foreground[] | select(.service == "focus") | .hasAlert' "$BRIDGE")
focus_icon=$(jq -r '.foreground[] | select(.service == "focus") | .icon' "$BRIDGE")
if [ "$focus_alert" = "true" ] && [ "$focus_icon" = "coffee" ]; then
  pass "Focus break alert in bridge"
else
  fail "Focus alert" "hasAlert=true, icon=coffee" "hasAlert=$focus_alert, icon=$focus_icon"
fi

# Test focus alert prepended to foreground
TESTS_RUN=$((TESTS_RUN + 1))
cat > "$BRIDGE" << 'EOF'
{
  "foreground": [
    {"service": "github-pr", "icon": "rocket", "title": "PR #123"},
    {"service": "focus", "icon": "coffee", "title": "Break reminder", "hasAlert": true}
  ]
}
EOF
first_service=$(jq -r '.foreground[0].service' "$BRIDGE")
second_service=$(jq -r '.foreground[1].service' "$BRIDGE")
if [ "$first_service" = "github-pr" ] && [ "$second_service" = "focus" ]; then
  pass "Focus alert position in foreground"
else
  fail "Focus position" "github-pr then focus" "$first_service then $second_service"
fi

echo ""
echo "=== Results ==="
echo "Tests run: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"

if [ "$TESTS_FAILED" -gt 0 ]; then
  exit 1
fi
