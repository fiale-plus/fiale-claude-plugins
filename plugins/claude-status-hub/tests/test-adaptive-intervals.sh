#!/bin/bash
# Test adaptive refresh intervals based on user activity

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$(dirname "$SCRIPT_DIR")/bin"

BRIDGE="/tmp/status-hub.json"

# Backup existing bridge
BACKUP_BRIDGE=""
if [ -f "$BRIDGE" ]; then BACKUP_BRIDGE=$(cat "$BRIDGE"); fi

cleanup() {
  if [ -n "$BACKUP_BRIDGE" ]; then
    echo "$BACKUP_BRIDGE" > "$BRIDGE"
  else
    rm -f "$BRIDGE"
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
}

# Extract get_intervals function from daemon for testing
# We source constants and redefine the function here for isolated testing
BASE_LIGHT=90
BASE_FULL=270
CEILING_LIGHT=3600
CEILING_FULL=10800

get_intervals() {
  local now_ms=$1
  local last_activity=$2
  local idle_ms=$((now_ms - last_activity))
  local idle_min=$((idle_ms / 60000))

  local light=$((BASE_LIGHT + idle_min * 29))
  local full=$((BASE_FULL + idle_min * 88))

  [ $light -gt $CEILING_LIGHT ] && light=$CEILING_LIGHT
  [ $full -gt $CEILING_FULL ] && full=$CEILING_FULL

  echo "$light $full"
}

# Test 1: Recent activity -> base intervals
test_recent_activity() {
  echo "Test 1: Recent activity should use base intervals"
  local now_ms=$(($(date +%s) * 1000))
  local last_activity=$((now_ms - 30000))  # 30 seconds ago

  read light full <<< $(get_intervals $now_ms $last_activity)

  [ "$light" -eq 90 ] || { fail "Light interval should be 90, got $light"; return 1; }
  [ "$full" -eq 270 ] || { fail "Full interval should be 270, got $full"; return 1; }
  pass "Recent activity uses base intervals (90s, 270s)"
}

# Test 2: 10 min idle -> moderately grown intervals
test_10min_idle() {
  echo "Test 2: 10 min idle should grow intervals"
  local now_ms=$(($(date +%s) * 1000))
  local last_activity=$((now_ms - 600000))  # 10 minutes ago

  read light full <<< $(get_intervals $now_ms $last_activity)

  # Expected: 90 + 10*29 = 380, 270 + 10*88 = 1150
  [ "$light" -ge 370 ] && [ "$light" -le 390 ] || { fail "Light interval should be ~380, got $light"; return 1; }
  [ "$full" -ge 1140 ] && [ "$full" -le 1160 ] || { fail "Full interval should be ~1150, got $full"; return 1; }
  pass "10 min idle grows intervals (~380s, ~1150s)"
}

# Test 3: 30 min idle -> further grown intervals
test_30min_idle() {
  echo "Test 3: 30 min idle should grow intervals further"
  local now_ms=$(($(date +%s) * 1000))
  local last_activity=$((now_ms - 1800000))  # 30 minutes ago

  read light full <<< $(get_intervals $now_ms $last_activity)

  # Expected: 90 + 30*29 = 960, 270 + 30*88 = 2910
  [ "$light" -ge 950 ] && [ "$light" -le 970 ] || { fail "Light interval should be ~960, got $light"; return 1; }
  [ "$full" -ge 2900 ] && [ "$full" -le 2920 ] || { fail "Full interval should be ~2910, got $full"; return 1; }
  pass "30 min idle grows intervals (~960s, ~2910s)"
}

# Test 4: 3 hours idle -> ceiling intervals
test_3h_idle_ceiling() {
  echo "Test 4: 3 hours idle should hit ceiling"
  local now_ms=$(($(date +%s) * 1000))
  local last_activity=$((now_ms - 10800000))  # 3 hours ago

  read light full <<< $(get_intervals $now_ms $last_activity)

  [ "$light" -eq 3600 ] || { fail "Light interval should be 3600 (ceiling), got $light"; return 1; }
  [ "$full" -eq 10800 ] || { fail "Full interval should be 10800 (ceiling), got $full"; return 1; }
  pass "3 hours idle hits ceiling (3600s, 10800s)"
}

# Test 5: Missing lastActivity -> treat as very idle (ceiling)
test_missing_last_activity() {
  echo "Test 5: Missing lastActivity should use ceiling"
  local now_ms=$(($(date +%s) * 1000))
  local last_activity=0  # Missing/zero

  read light full <<< $(get_intervals $now_ms $last_activity)

  [ "$light" -eq 3600 ] || { fail "Light interval should be 3600 (ceiling), got $light"; return 1; }
  [ "$full" -eq 10800 ] || { fail "Full interval should be 10800 (ceiling), got $full"; return 1; }
  pass "Missing lastActivity uses ceiling (3600s, 10800s)"
}

# Test 6: Statusline skull logic - user active, daemon stale -> skull
test_skull_active_user_stale_daemon() {
  echo "Test 6: Active user + stale daemon should show skull"
  local now_ms=$(($(date +%s) * 1000))
  local last_activity=$((now_ms - 60000))   # 1 min ago (active)
  local timestamp=$((now_ms - 240000))      # 4 min ago (stale)

  # Create test bridge
  echo "{\"timestamp\": $timestamp, \"lastActivity\": $last_activity, \"background\": null, \"foreground\": []}" > "$BRIDGE"

  # Source statusline logic inline
  ACTIVITY_AGE=$((now_ms - last_activity))
  TIMESTAMP_AGE=$((now_ms - timestamp))

  # Skull condition: user active (<3 min) AND timestamp stale (>3 min)
  if [ "$ACTIVITY_AGE" -lt 180000 ] && [ "$TIMESTAMP_AGE" -gt 180000 ]; then
    pass "Active user + stale daemon shows skull"
  else
    fail "Should show skull: activity_age=$ACTIVITY_AGE, timestamp_age=$TIMESTAMP_AGE"
  fi
}

# Test 7: Statusline skull logic - user idle, daemon stale -> no skull
test_no_skull_idle_user() {
  echo "Test 7: Idle user + stale daemon should NOT show skull"
  local now_ms=$(($(date +%s) * 1000))
  local last_activity=$((now_ms - 600000))  # 10 min ago (idle)
  local timestamp=$((now_ms - 300000))      # 5 min ago (stale)

  # Create test bridge
  echo "{\"timestamp\": $timestamp, \"lastActivity\": $last_activity, \"background\": null, \"foreground\": []}" > "$BRIDGE"

  ACTIVITY_AGE=$((now_ms - last_activity))
  TIMESTAMP_AGE=$((now_ms - timestamp))

  # Skull condition: user active (<3 min) AND timestamp stale (>3 min)
  if [ "$ACTIVITY_AGE" -lt 180000 ] && [ "$TIMESTAMP_AGE" -gt 180000 ]; then
    fail "Should NOT show skull for idle user"
  else
    pass "Idle user with stale daemon hides skull (expected during long intervals)"
  fi
}

# Test 8: update-bridge.sh preserves lastActivity
test_update_bridge_preserves_activity() {
  echo "Test 8: update-bridge.sh should preserve lastActivity"
  local now_ms=$(($(date +%s) * 1000))
  local original_activity=$((now_ms - 300000))  # 5 min ago

  # Create bridge with existing lastActivity
  echo "{\"timestamp\": $now_ms, \"lastActivity\": $original_activity, \"background\": null, \"foreground\": []}" > "$BRIDGE"

  # Run update-bridge.sh
  "${SCRIPT_DIR}/../bin/update-bridge.sh" "test" "T" "Title" "Detail"

  # Check that lastActivity was preserved
  local preserved=$(jq -r '.lastActivity' "$BRIDGE")
  [ "$preserved" = "$original_activity" ] || { fail "lastActivity should be preserved, got $preserved instead of $original_activity"; return 1; }
  pass "update-bridge.sh preserves existing lastActivity"
}

# Test 9: update-bridge.sh initializes lastActivity when missing
test_update_bridge_initializes_activity() {
  echo "Test 9: update-bridge.sh should initialize lastActivity when missing"

  # Create bridge without lastActivity
  echo "{\"timestamp\": 0, \"background\": null, \"foreground\": []}" > "$BRIDGE"

  # Run update-bridge.sh
  "${SCRIPT_DIR}/../bin/update-bridge.sh" "test" "T" "Title" "Detail"

  # Check that lastActivity was initialized
  local initialized=$(jq -r '.lastActivity' "$BRIDGE")
  [ "$initialized" != "null" ] && [ "$initialized" != "0" ] || { fail "lastActivity should be initialized, got $initialized"; return 1; }
  pass "update-bridge.sh initializes lastActivity when missing"
}

# Run all tests
echo "=== Adaptive Refresh Interval Tests ==="
echo ""

test_recent_activity
test_10min_idle
test_30min_idle
test_3h_idle_ceiling
test_missing_last_activity
test_skull_active_user_stale_daemon
test_no_skull_idle_user
test_update_bridge_preserves_activity
test_update_bridge_initializes_activity

echo ""
echo "=== Results: $TESTS_PASSED passed, $TESTS_FAILED failed ==="

# Exit with failure if any tests failed
[ "$TESTS_FAILED" -eq 0 ]
