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
        checks_arr+='{"name": "ci-'$i'", "conclusion": "FAILURE"}'
      done
    fi
    if [ "$checks_pending" -gt 0 ]; then
      for i in $(seq 1 $checks_pending); do
        [ "$first" = "false" ] && checks_arr+=","
        first=false
        checks_arr+='{"name": "ci-pending-'$i'", "conclusion": null}'
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

# Create mock gh with named checks (for testing continuous check detection)
create_mock_gh_with_checks() {
  local pr_state="$1"
  local is_draft="$2"
  local review="$3"
  local mergeable="$4"
  local comments="$5"
  shift 5
  # Remaining args are check specs: "name:conclusion" (conclusion can be SUCCESS, FAILURE, or null)

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

  # Build statusCheckRollup array from check specs
  local checks_arr="["
  local first=true
  for spec in "$@"; do
    local name="${spec%%:*}"
    local conclusion="${spec#*:}"
    [ "$first" = "false" ] && checks_arr+=","
    first=false
    if [ "$conclusion" = "null" ]; then
      checks_arr+="{\"name\": \"$name\", \"conclusion\": null}"
    else
      checks_arr+="{\"name\": \"$name\", \"conclusion\": \"$conclusion\"}"
    fi
  done
  checks_arr+="]"

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
  local last_checks_pending="${4:-0}"

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
        "state": "$last_state",
        "checksPending": $last_checks_pending
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
echo "Testing continuous check handling..."

# Test Aviator running (continuous check) with all other checks passed → 🚀 with ⏳
TESTS_RUN=$((TESTS_RUN + 1))
setup_config 0 "" ""
create_mock_gh_with_checks "OPEN" "false" "APPROVED" "MERGEABLE" 0 \
  "build:SUCCESS" "test:SUCCESS" "aviator/merge-queue:null"
run_refresh
icon=$(jq -r '.foreground[0].icon' "$BRIDGE")
detail=$(jq -r '.foreground[0].detail' "$BRIDGE")
if [ "$icon" = "🚀" ] && [[ "$detail" == *"⏳1"* ]]; then
  pass "Aviator running → 🚀 with ⏳1"
else
  fail "Aviator continuous check" "🚀 with ⏳1" "$icon / $detail"
fi

# Test Mergify running (continuous check) → 🚀 with ⏳
TESTS_RUN=$((TESTS_RUN + 1))
setup_config 0 "" ""
create_mock_gh_with_checks "OPEN" "false" "APPROVED" "MERGEABLE" 0 \
  "ci:SUCCESS" "mergify/merge-queue:null"
run_refresh
icon=$(jq -r '.foreground[0].icon' "$BRIDGE")
detail=$(jq -r '.foreground[0].detail' "$BRIDGE")
if [ "$icon" = "🚀" ] && [[ "$detail" == *"⏳1"* ]]; then
  pass "Mergify running → 🚀 with ⏳1"
else
  fail "Mergify continuous check" "🚀 with ⏳1" "$icon / $detail"
fi

# Test regular pending check (not continuous) → ~ (checks pending)
TESTS_RUN=$((TESTS_RUN + 1))
setup_config 0 "" ""
create_mock_gh_with_checks "OPEN" "false" "APPROVED" "MERGEABLE" 0 \
  "build:SUCCESS" "test:null"
run_refresh
icon=$(jq -r '.foreground[0].icon' "$BRIDGE")
if [ "$icon" = "~" ]; then
  pass "Regular pending check → ~ icon"
else
  fail "Regular pending check" "~" "$icon"
fi

# Test mixed: regular pending + continuous → ~ (blocking takes priority)
TESTS_RUN=$((TESTS_RUN + 1))
setup_config 0 "" ""
create_mock_gh_with_checks "OPEN" "false" "APPROVED" "MERGEABLE" 0 \
  "build:null" "aviator/queue:null"
run_refresh
icon=$(jq -r '.foreground[0].icon' "$BRIDGE")
if [ "$icon" = "~" ]; then
  pass "Mixed pending (regular + continuous) → ~ icon"
else
  fail "Mixed pending checks" "~" "$icon"
fi

# Test multiple continuous checks → 🚀 with ⏳2
TESTS_RUN=$((TESTS_RUN + 1))
setup_config 0 "" ""
create_mock_gh_with_checks "OPEN" "false" "APPROVED" "MERGEABLE" 0 \
  "build:SUCCESS" "aviator/merge-queue:null" "mergify/queue:null"
run_refresh
icon=$(jq -r '.foreground[0].icon' "$BRIDGE")
detail=$(jq -r '.foreground[0].detail' "$BRIDGE")
if [ "$icon" = "🚀" ] && [[ "$detail" == *"⏳2"* ]]; then
  pass "Multiple continuous checks → 🚀 with ⏳2"
else
  fail "Multiple continuous checks" "🚀 with ⏳2" "$icon / $detail"
fi

# Test continuous check + failed blocking → X (failure takes priority)
TESTS_RUN=$((TESTS_RUN + 1))
setup_config 0 "" ""
create_mock_gh_with_checks "OPEN" "false" "APPROVED" "MERGEABLE" 0 \
  "build:FAILURE" "aviator/merge-queue:null"
run_refresh
icon=$(jq -r '.foreground[0].icon' "$BRIDGE")
if [ "$icon" = "X" ]; then
  pass "Continuous + failed blocking → X icon"
else
  fail "Continuous with failure" "X" "$icon"
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

# Test blocking checks finishing triggers alert
TESTS_RUN=$((TESTS_RUN + 1))
setup_config 0 "APPROVED" "OPEN" 2  # lastSeen had 2 pending checks
create_mock_gh "OPEN" "false" "APPROVED" "MERGEABLE" 0 0 0  # Now 0 pending
run_refresh
has_alert=$(jq -r '.foreground[0].hasAlert' "$BRIDGE")
if [ "$has_alert" = "true" ]; then
  pass "Blocking checks finishing triggers alert"
else
  fail "Checks finish alert" "true" "$has_alert"
fi

# Test continuous checks don't trigger alert when they're the only ones pending
TESTS_RUN=$((TESTS_RUN + 1))
setup_config 0 "APPROVED" "OPEN" 0  # lastSeen had 0 blocking pending
create_mock_gh_with_checks "OPEN" "false" "APPROVED" "MERGEABLE" 0 \
  "build:SUCCESS" "aviator/queue:null"  # Aviator still pending (continuous)
run_refresh
has_alert=$(jq -r '.foreground[0].hasAlert' "$BRIDGE")
if [ "$has_alert" = "false" ]; then
  pass "Continuous check alone = no alert"
else
  fail "Continuous check alert" "false" "$has_alert"
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
echo "Testing auto-merge functionality..."

# Helper: Setup config with autoMerge flag
setup_config_with_automerge() {
  local last_comments="${1:-0}"
  local last_review="${2:-}"
  local last_state="${3:-}"
  local last_checks_pending="${4:-0}"
  local auto_merge="${5:-false}"

  cat > "$CONFIG" << EOF
{
  "foreground": [
    {
      "owner": "test",
      "repo": "repo",
      "number": 1,
      "autoMerge": $auto_merge,
      "lastSeen": {
        "commentsCount": $last_comments,
        "reviewDecision": "$last_review",
        "state": "$last_state",
        "checksPending": $last_checks_pending
      }
    }
  ],
  "github": {
    "mergeStrategy": {
      "default": "squash"
    }
  }
}
EOF
}

# Helper: Setup merge strategy config for resolution tests
setup_merge_config() {
  local strategy_json="$1"
  cat > "$CONFIG" << EOF
{
  "foreground": [
    {
      "owner": "test",
      "repo": "repo",
      "number": 1,
      "autoMerge": false,
      "lastSeen": {}
    }
  ],
  "github": {
    "mergeStrategy": $strategy_json
  }
}
EOF
}

# Helper: Create mock gh that tracks merge calls
create_mock_gh_tracking() {
  local pr_state="$1"
  local is_draft="$2"
  local review="$3"
  local mergeable="$4"
  local calls_dir="$MOCK_BIN/calls"

  mkdir -p "$calls_dir"
  rm -f "$calls_dir/"* 2>/dev/null

  cat > "$MOCK_BIN/gh" << EOF
#!/bin/bash
# Track the command
echo "\$@" >> "$calls_dir/gh-calls.log"
if [[ "\$1" == "pr" && "\$2" == "merge" ]]; then
  touch "$calls_dir/gh-merge"
  echo "Merged"
  exit 0
fi
if [[ "\$1" == "pr" && "\$2" == "comment" ]]; then
  touch "$calls_dir/gh-comment"
  echo "Comment posted"
  exit 0
fi
if [[ "\$1" == "pr" && "\$2" == "view" ]]; then
cat << 'ENDJSON'
{
  "state": "$pr_state",
  "isDraft": $is_draft,
  "reviewDecision": "$review",
  "mergeable": "$mergeable",
  "comments": [],
  "statusCheckRollup": []
}
ENDJSON
fi
EOF
  chmod +x "$MOCK_BIN/gh"
}

# Test: autoMerge flag included in bridge output
TESTS_RUN=$((TESTS_RUN + 1))
setup_config_with_automerge 0 "" "" 0 true
create_mock_gh "OPEN" "false" "APPROVED" "MERGEABLE" 0 0 0
run_refresh
auto_merge=$(jq -r '.foreground[0].autoMerge' "$BRIDGE")
if [ "$auto_merge" = "true" ]; then
  pass "autoMerge flag in bridge output"
else
  fail "autoMerge in bridge" "true" "$auto_merge"
fi

# Test: autoMerge=false also in bridge output
TESTS_RUN=$((TESTS_RUN + 1))
setup_config_with_automerge 0 "" "" 0 false
create_mock_gh "OPEN" "false" "APPROVED" "MERGEABLE" 0 0 0
run_refresh
auto_merge=$(jq -r '.foreground[0].autoMerge' "$BRIDGE")
if [ "$auto_merge" = "false" ]; then
  pass "autoMerge=false in bridge output"
else
  fail "autoMerge false in bridge" "false" "$auto_merge"
fi

# Test: transition from pending → ready triggers auto-merge
TESTS_RUN=$((TESTS_RUN + 1))
setup_config_with_automerge 0 "APPROVED" "OPEN" 2 true  # was pending
create_mock_gh_tracking "OPEN" "false" "APPROVED" "MERGEABLE"
run_refresh
if [ -f "$MOCK_BIN/calls/gh-merge" ]; then
  pass "Auto-merge triggered on checks passing"
else
  fail "Auto-merge on checks pass" "gh merge called" "not called"
fi

# Test: transition from not-approved → approved triggers auto-merge
TESTS_RUN=$((TESTS_RUN + 1))
setup_config_with_automerge 0 "" "OPEN" 0 true  # was not approved
create_mock_gh_tracking "OPEN" "false" "APPROVED" "MERGEABLE"
run_refresh
if [ -f "$MOCK_BIN/calls/gh-merge" ]; then
  pass "Auto-merge triggered on approval"
else
  fail "Auto-merge on approval" "gh merge called" "not called"
fi

# Test: already ready + autoMerge does NOT trigger (no transition)
TESTS_RUN=$((TESTS_RUN + 1))
setup_config_with_automerge 0 "APPROVED" "OPEN" 0 true  # was already ready
create_mock_gh_tracking "OPEN" "false" "APPROVED" "MERGEABLE"
run_refresh
if [ ! -f "$MOCK_BIN/calls/gh-merge" ]; then
  pass "No auto-merge when already ready"
else
  fail "No auto-merge already ready" "gh merge NOT called" "was called"
fi

# Test: transition to ready but autoMerge:false does NOT trigger
TESTS_RUN=$((TESTS_RUN + 1))
setup_config_with_automerge 0 "APPROVED" "OPEN" 2 false  # autoMerge disabled
create_mock_gh_tracking "OPEN" "false" "APPROVED" "MERGEABLE"
run_refresh
if [ ! -f "$MOCK_BIN/calls/gh-merge" ]; then
  pass "No auto-merge when disabled"
else
  fail "No auto-merge when disabled" "gh merge NOT called" "was called"
fi

echo ""
echo "=== Results ==="
echo "Tests run: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"

if [ "$TESTS_FAILED" -gt 0 ]; then
  exit 1
fi
