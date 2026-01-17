#!/bin/bash
# Test statusline.sh functionality
# Tests display states: error, alert, idle, stale daemon

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$(dirname "$SCRIPT_DIR")/bin"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

# Production paths
BRIDGE="/tmp/status-hub.json"
ERROR_FILE="/tmp/status-hub-error.txt"
HUB_CONFIG="$HOME/.claude/status-config.json"
BASE_CONFIG="$HOME/.claude/status-base-config.json"

# Backup existing files
BACKUP_BRIDGE=""
BACKUP_ERROR=""
BACKUP_HUB_CONFIG=""
BACKUP_BASE_CONFIG=""
[ -f "$BRIDGE" ] && BACKUP_BRIDGE=$(cat "$BRIDGE")
[ -f "$ERROR_FILE" ] && BACKUP_ERROR=$(cat "$ERROR_FILE")
[ -f "$HUB_CONFIG" ] && BACKUP_HUB_CONFIG=$(cat "$HUB_CONFIG")
[ -f "$BASE_CONFIG" ] && BACKUP_BASE_CONFIG=$(cat "$BASE_CONFIG")

cleanup() {
  rm -f "$BRIDGE" "$ERROR_FILE"
  # Restore backups
  if [ -n "$BACKUP_BRIDGE" ]; then echo "$BACKUP_BRIDGE" > "$BRIDGE"; else rm -f "$BRIDGE"; fi
  if [ -n "$BACKUP_ERROR" ]; then echo "$BACKUP_ERROR" > "$ERROR_FILE"; else rm -f "$ERROR_FILE"; fi
  if [ -n "$BACKUP_HUB_CONFIG" ]; then echo "$BACKUP_HUB_CONFIG" > "$HUB_CONFIG"; fi
  if [ -n "$BACKUP_BASE_CONFIG" ]; then echo "$BACKUP_BASE_CONFIG" > "$BASE_CONFIG"; fi
}
trap cleanup EXIT

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

pass() {
  ((TESTS_PASSED++))
  echo "  PASS: $1"
}

fail() {
  ((TESTS_FAILED++))
  echo "  FAIL: $1"
  echo "        Expected: $2"
  echo "        Got:      $3"
}

# Mock context input (minimal valid JSON)
MOCK_CONTEXT='{"workspace":{"current_dir":"~"}}'

# Strip ANSI codes for easier testing
strip_ansi() {
  sed 's/\x1b\[[0-9;]*m//g'
}

run_statusline() {
  echo "$MOCK_CONTEXT" | "$BIN_DIR/statusline.sh" | strip_ansi
}

echo "=== Testing statusline.sh ==="
echo ""

# Disable context display for cleaner tests
cat > "$HUB_CONFIG" << 'EOF'
{"contextDisplay": "off", "quota": {"displayFormat": "off"}}
EOF

# Clear base config to use defaults
rm -f "$BASE_CONFIG"

echo "Testing error state..."

# Test error file display (highest priority)
((TESTS_RUN++))
rm -f "$BRIDGE"
echo "Test error message" > "$ERROR_FILE"
output=$(run_statusline)
if echo "$output" | grep -q "Test error message"; then
  pass "Error file message displayed"
else
  fail "Error message display" "contains 'Test error message'" "$output"
fi
rm -f "$ERROR_FILE"

echo ""
echo "Testing alert state..."

# Test alert state: foreground expanded, shows alert item
((TESTS_RUN++))
rm -f "$ERROR_FILE"
NOW_MS=$(($(date +%s) * 1000))
cat > "$BRIDGE" << EOF
{
  "timestamp": $NOW_MS,
  "background": {"site": "spotify", "icon": "▶", "title": "Song", "detail": "Artist"},
  "foreground": [
    {"site": "github-pr", "icon": "!", "title": "PR #123", "detail": "changes requested", "hasAlert": true}
  ]
}
EOF
output=$(run_statusline)
if echo "$output" | grep -q "!" && echo "$output" | grep -q "PR #123"; then
  pass "Alert state shows expanded foreground"
else
  fail "Alert foreground" "contains ! and PR #123" "$output"
fi

# Test alert state: background is compact (icon only)
((TESTS_RUN++))
# Background should show just icon, not full title
if echo "$output" | grep -q "▶" && ! echo "$output" | grep -q "Song"; then
  pass "Alert state shows compact background (icon only)"
else
  fail "Alert background" "shows ▶ without Song" "$output"
fi

echo ""
echo "Testing idle state..."

# Test idle state: background expanded
((TESTS_RUN++))
NOW_MS=$(($(date +%s) * 1000))
cat > "$BRIDGE" << EOF
{
  "timestamp": $NOW_MS,
  "background": {"site": "spotify", "icon": "▶", "title": "Chill Vibes", "detail": "Lo-Fi"},
  "foreground": [
    {"site": "github-pr", "icon": "✓", "title": "PR #123", "detail": "approved", "hasAlert": false}
  ]
}
EOF
output=$(run_statusline)
if echo "$output" | grep -q "Chill Vibes" && echo "$output" | grep -q "Lo-Fi"; then
  pass "Idle state shows expanded background"
else
  fail "Idle background" "contains Chill Vibes and Lo-Fi" "$output"
fi

# Test idle state: foreground shows count
((TESTS_RUN++))
if echo "$output" | grep -q "1 PR"; then
  pass "Idle state shows PR count"
else
  fail "Idle foreground" "contains '1 PR'" "$output"
fi

echo ""
echo "Testing stale daemon indicator..."

# Test stale bridge (timestamp > 3 minutes old) shows skull
((TESTS_RUN++))
OLD_TS=$(($(date +%s) * 1000 - 200000))  # 200 seconds ago
cat > "$BRIDGE" << EOF
{
  "timestamp": $OLD_TS,
  "background": {"site": "off", "icon": "", "title": "", "detail": ""},
  "foreground": []
}
EOF
output=$(run_statusline)
if echo "$output" | grep -q "💀"; then
  pass "Stale daemon shows skull indicator"
else
  fail "Stale indicator" "contains 💀" "$output"
fi

# Test fresh bridge doesn't show skull
((TESTS_RUN++))
NOW_MS=$(($(date +%s) * 1000))
cat > "$BRIDGE" << EOF
{
  "timestamp": $NOW_MS,
  "background": {"site": "off", "icon": "", "title": "", "detail": ""},
  "foreground": []
}
EOF
output=$(run_statusline)
if ! echo "$output" | grep -q "💀"; then
  pass "Fresh daemon no skull indicator"
else
  fail "No stale indicator" "no 💀" "$output"
fi

echo ""
echo "Testing multiple foreground items..."

# Test multiple PRs show count
((TESTS_RUN++))
NOW_MS=$(($(date +%s) * 1000))
cat > "$BRIDGE" << EOF
{
  "timestamp": $NOW_MS,
  "background": {"site": "off", "icon": "", "title": "", "detail": ""},
  "foreground": [
    {"site": "github-pr", "icon": "✓", "title": "PR #1", "detail": "ok", "hasAlert": false},
    {"site": "github-pr", "icon": "?", "title": "PR #2", "detail": "review", "hasAlert": false},
    {"site": "github-pr", "icon": "!", "title": "PR #3", "detail": "changes", "hasAlert": false}
  ]
}
EOF
output=$(run_statusline)
if echo "$output" | grep -q "3 PRs"; then
  pass "Multiple PRs show correct count"
else
  fail "PR count" "contains '3 PRs'" "$output"
fi

# Test mixed foreground (PRs + other)
((TESTS_RUN++))
NOW_MS=$(($(date +%s) * 1000))
cat > "$BRIDGE" << EOF
{
  "timestamp": $NOW_MS,
  "background": {"site": "off", "icon": "", "title": "", "detail": ""},
  "foreground": [
    {"site": "github-pr", "icon": "✓", "title": "PR #1", "detail": "ok", "hasAlert": false},
    {"site": "email", "icon": "📧", "title": "Inbox", "detail": "3 new", "hasAlert": false}
  ]
}
EOF
output=$(run_statusline)
if echo "$output" | grep -q "1 PR" && echo "$output" | grep -q "📧"; then
  pass "Mixed foreground shows PR count and other icon"
else
  fail "Mixed foreground" "contains '1 PR' and 📧" "$output"
fi

echo ""
echo "=== Results ==="
echo "Tests run: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"

if [ "$TESTS_FAILED" -gt 0 ]; then
  exit 1
fi
