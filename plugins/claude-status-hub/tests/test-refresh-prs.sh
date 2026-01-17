#!/bin/bash
# Test refresh-prs.sh functionality
# Tests PR icon determination and alert detection

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$(dirname "$SCRIPT_DIR")/bin"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

# Production paths
BRIDGE="/tmp/status-hub.json"
CONFIG="$HOME/.claude/status-config.json"

# Backup existing files
BACKUP_BRIDGE=""
BACKUP_CONFIG=""
if [ -f "$BRIDGE" ]; then BACKUP_BRIDGE=$(cat "$BRIDGE"); fi
if [ -f "$CONFIG" ]; then BACKUP_CONFIG=$(cat "$CONFIG"); fi

# Create mock gh directory
MOCK_BIN="/tmp/test-mock-bin-$$"
mkdir -p "$MOCK_BIN"

# Ensure config directory exists (for CI environments)
mkdir -p "$(dirname "$CONFIG")"

cleanup() {
  rm -rf "$MOCK_BIN"
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

# Create mock gh command that returns predefined JSON
create_mock_gh() {
  local pr_state="$1"
  local is_draft="$2"
  local review="$3"
  local mergeable="$4"
  local checks_failed="$5"
  local checks_pending="$6"
  local comments="$7"

  # Build comments array
  local comments_arr="[]"
  if [ "$comments" -gt 0 ]; then
    comments_arr="["
    local first_comment=true
    for i in $(seq 1 $comments); do
      [ "$first_comment" = "false" ] && comments_arr+=","
      first_comment=false
      comments_arr+="{}"
    done
    comments_arr+="]"
  fi

  # Build statusCheckRollup array
  local checks_arr="[]"
  if [ "$checks_failed" -gt 0 ] || [ "$checks_pending" -gt 0 ]; then
    checks_arr="["
    local first=true
    # Note: seq 1 0 on macOS counts down (1,0), so check >0 before looping
    if [ "$checks_failed" -gt 0 ]; then
      for i in $(seq 1 $checks_failed); do
        [ "$first" = "false" ] && checks_arr+=","
        first=false
        checks_arr+='{"conclusion": "FAILURE"}'
      done
    fi
    if [ "$checks_pending" -gt 0 ]; then
      for i in $(seq 1 $checks_pending); do
        [ "$first" = "false" ] && checks_arr+=","
        first=false
        checks_arr+='{"conclusion": null}'
      done
    fi
    checks_arr+="]"
  fi

  cat > "$MOCK_BIN/gh" << EOF
#!/bin/bash
# Mock gh command
cat << 'ENDJSON'
{
  "state": "$pr_state",
  "isDraft": $is_draft,
  "reviewDecision": "$review",
  "mergeable": "$mergeable",
  "comments": $comments_arr,
  "statusCheckRollup": $checks_arr
}
ENDJSON
EOF
  chmod +x "$MOCK_BIN/gh"
}

# Create a config with one PR
setup_config() {
  local last_comments="${1:-0}"
  local last_review="${2:-}"
  local last_state="${3:-}"

  cat > "$CONFIG" << EOF
{
  "foreground": [
    {
      "owner": "test",
      "repo": "repo",
      "number": 1,
      "lastSeen": {
        "commentsCount": $last_comments,
        "reviewDecision": "$last_review",
        "state": "$last_state"
      }
    }
  ]
}
EOF
}

# Run refresh-prs with mock gh
run_refresh() {
  PATH="$MOCK_BIN:$PATH" "$BIN_DIR/refresh-prs.sh"
}

echo "=== Testing refresh-prs.sh ==="
echo ""

echo "Testing icon determination..."

# Test MERGED state → M
TESTS_RUN=$((TESTS_RUN + 1))
setup_config 0 "" ""
create_mock_gh "MERGED" "false" "" "UNKNOWN" 0 0 0
run_refresh
icon=$(jq -r '.foreground[0].icon' "$BRIDGE")
if [ "$icon" = "M" ]; then
  pass "MERGED state → M icon"
else
  fail "MERGED icon" "M" "$icon"
fi

# Test CLOSED state → C
TESTS_RUN=$((TESTS_RUN + 1))
setup_config 0 "" ""
create_mock_gh "CLOSED" "false" "" "UNKNOWN" 0 0 0
run_refresh
icon=$(jq -r '.foreground[0].icon' "$BRIDGE")
if [ "$icon" = "C" ]; then
  pass "CLOSED state → C icon"
else
  fail "CLOSED icon" "C" "$icon"
fi

# Test checks failing → X
TESTS_RUN=$((TESTS_RUN + 1))
setup_config 0 "" ""
create_mock_gh "OPEN" "false" "APPROVED" "MERGEABLE" 2 0 0
run_refresh
icon=$(jq -r '.foreground[0].icon' "$BRIDGE")
if [ "$icon" = "X" ]; then
  pass "Checks failing → X icon"
else
  fail "Checks failing icon" "X" "$icon"
fi

# Test conflicts → ⚡
TESTS_RUN=$((TESTS_RUN + 1))
setup_config 0 "" ""
create_mock_gh "OPEN" "false" "APPROVED" "CONFLICTING" 0 0 0
run_refresh
icon=$(jq -r '.foreground[0].icon' "$BRIDGE")
if [ "$icon" = "⚡" ]; then
  pass "Conflicts → ⚡ icon"
else
  fail "Conflicts icon" "⚡" "$icon"
fi

# Test changes requested → !
TESTS_RUN=$((TESTS_RUN + 1))
setup_config 0 "" ""
create_mock_gh "OPEN" "false" "CHANGES_REQUESTED" "MERGEABLE" 0 0 0
run_refresh
icon=$(jq -r '.foreground[0].icon' "$BRIDGE")
if [ "$icon" = "!" ]; then
  pass "Changes requested → ! icon"
else
  fail "Changes requested icon" "!" "$icon"
fi

# Test checks pending → ~
TESTS_RUN=$((TESTS_RUN + 1))
setup_config 0 "" ""
create_mock_gh "OPEN" "false" "APPROVED" "MERGEABLE" 0 2 0
run_refresh
icon=$(jq -r '.foreground[0].icon' "$BRIDGE")
if [ "$icon" = "~" ]; then
  pass "Checks pending → ~ icon"
else
  fail "Checks pending icon" "~" "$icon"
fi

# Test review required → ?
TESTS_RUN=$((TESTS_RUN + 1))
setup_config 0 "" ""
create_mock_gh "OPEN" "false" "REVIEW_REQUIRED" "MERGEABLE" 0 0 0
run_refresh
icon=$(jq -r '.foreground[0].icon' "$BRIDGE")
if [ "$icon" = "?" ]; then
  pass "Review required → ? icon"
else
  fail "Review required icon" "?" "$icon"
fi

# Test draft → D
TESTS_RUN=$((TESTS_RUN + 1))
setup_config 0 "" ""
create_mock_gh "OPEN" "true" "APPROVED" "MERGEABLE" 0 0 0
run_refresh
icon=$(jq -r '.foreground[0].icon' "$BRIDGE")
if [ "$icon" = "D" ]; then
  pass "Draft PR → D icon"
else
  fail "Draft icon" "D" "$icon"
fi

# Test ready to merge → 🚀
TESTS_RUN=$((TESTS_RUN + 1))
setup_config 0 "" ""
create_mock_gh "OPEN" "false" "APPROVED" "MERGEABLE" 0 0 0
run_refresh
icon=$(jq -r '.foreground[0].icon' "$BRIDGE")
if [ "$icon" = "🚀" ]; then
  pass "Ready to merge → 🚀 icon"
else
  fail "Ready to merge icon" "🚀" "$icon"
fi

echo ""
echo "Testing alert detection..."

# Test new comment triggers alert
TESTS_RUN=$((TESTS_RUN + 1))
setup_config 2 "APPROVED" "OPEN"  # lastSeen has 2 comments
create_mock_gh "OPEN" "false" "APPROVED" "MERGEABLE" 0 0 5  # Now 5 comments
run_refresh
has_alert=$(jq -r '.foreground[0].hasAlert' "$BRIDGE")
if [ "$has_alert" = "true" ]; then
  pass "New comments trigger alert"
else
  fail "Comment alert" "true" "$has_alert"
fi

# Test review change triggers alert
TESTS_RUN=$((TESTS_RUN + 1))
setup_config 0 "REVIEW_REQUIRED" "OPEN"  # Was review required
create_mock_gh "OPEN" "false" "APPROVED" "MERGEABLE" 0 0 0  # Now approved
run_refresh
has_alert=$(jq -r '.foreground[0].hasAlert' "$BRIDGE")
if [ "$has_alert" = "true" ]; then
  pass "Review decision change triggers alert"
else
  fail "Review change alert" "true" "$has_alert"
fi

# Test state change triggers alert
TESTS_RUN=$((TESTS_RUN + 1))
setup_config 0 "APPROVED" "OPEN"  # Was open
create_mock_gh "MERGED" "false" "" "UNKNOWN" 0 0 0  # Now merged
run_refresh
has_alert=$(jq -r '.foreground[0].hasAlert' "$BRIDGE")
if [ "$has_alert" = "true" ]; then
  pass "State change triggers alert"
else
  fail "State change alert" "true" "$has_alert"
fi

# Test no change = no alert
TESTS_RUN=$((TESTS_RUN + 1))
setup_config 0 "APPROVED" "OPEN"  # Same as current
create_mock_gh "OPEN" "false" "APPROVED" "MERGEABLE" 0 0 0  # Same state
run_refresh
has_alert=$(jq -r '.foreground[0].hasAlert' "$BRIDGE")
if [ "$has_alert" = "false" ]; then
  pass "No changes = no alert"
else
  fail "No changes alert" "false" "$has_alert"
fi

echo ""
echo "Testing bridge output..."

# Test bridge structure
TESTS_RUN=$((TESTS_RUN + 1))
setup_config 0 "" ""
# Create existing background in bridge
cat > "$BRIDGE" << 'EOF'
{
  "timestamp": 1000,
  "background": {"site": "spotify", "icon": "▶", "title": "Song", "detail": "Artist"},
  "foreground": []
}
EOF
create_mock_gh "OPEN" "false" "APPROVED" "MERGEABLE" 0 0 0
run_refresh
bg_site=$(jq -r '.background.site' "$BRIDGE")
fg_count=$(jq -r '.foreground | length' "$BRIDGE")
if [ "$bg_site" = "spotify" ] && [ "$fg_count" = "1" ]; then
  pass "Bridge preserves background while updating foreground"
else
  fail "Bridge structure" "spotify bg + 1 fg" "$bg_site + $fg_count fg"
fi

echo ""
echo "=== Results ==="
echo "Tests run: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"

if [ "$TESTS_FAILED" -gt 0 ]; then
  exit 1
fi
