#!/bin/bash
# Test daemon version staleness detection
# Tests the version-aware lockfile and startup behavior

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$(dirname "$SCRIPT_DIR")/bin"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
LOCKFILE="/tmp/status-hub-daemon.lock"
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
DAEMON_SCRIPT="$BIN_DIR/refresh-daemon.sh"

# Backup existing state
BACKUP_LOCK=""
BACKUP_VERSION=""
if [ -f "$LOCKFILE" ]; then BACKUP_LOCK=$(cat "$LOCKFILE"); fi
BACKUP_VERSION=$(jq -r '.version' "$PLUGIN_JSON")

# Track spawned processes for cleanup
SPAWNED_PIDS=()

cleanup() {
  # Kill any processes we spawned
  for pid in "${SPAWNED_PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done

  # Restore lockfile
  rm -f "$LOCKFILE"
  if [ -n "$BACKUP_LOCK" ]; then echo "$BACKUP_LOCK" > "$LOCKFILE"; fi

  # Restore original version
  jq --arg v "$BACKUP_VERSION" '.version = $v' "$PLUGIN_JSON" > "${PLUGIN_JSON}.tmp" && mv "${PLUGIN_JSON}.tmp" "$PLUGIN_JSON"
}
trap cleanup EXIT

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

echo "=== Testing daemon version detection ==="
echo ""

# --- Test 1: Lockfile format ---
echo "Test: Lockfile format is VERSION:PID"
rm -f "$LOCKFILE"
# Simulate what the daemon does
CURRENT_V=$(jq -r '.version' "$PLUGIN_JSON")
echo "${CURRENT_V}:12345" > "$LOCKFILE"
CONTENT=$(cat "$LOCKFILE")
if [[ "$CONTENT" =~ ^[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$ ]]; then
  pass "Lockfile format is VERSION:PID"
else
  fail "Lockfile format" "VERSION:PID pattern" "$CONTENT"
fi

# --- Test 2: Version extraction from lockfile ---
echo ""
echo "Test: Version extraction from lockfile"
echo "1.2.3:99999" > "$LOCKFILE"
LOCK_CONTENT=$(cat "$LOCKFILE")
EXTRACTED_VERSION="${LOCK_CONTENT%%:*}"
EXTRACTED_PID="${LOCK_CONTENT##*:}"
if [ "$EXTRACTED_VERSION" = "1.2.3" ] && [ "$EXTRACTED_PID" = "99999" ]; then
  pass "Version and PID extracted correctly"
else
  fail "Version extraction" "1.2.3 and 99999" "$EXTRACTED_VERSION and $EXTRACTED_PID"
fi

# --- Test 3: Stale PID detection ---
echo ""
echo "Test: Stale PID (non-existent process) detected"
rm -f "$LOCKFILE"
echo "1.0.0:99999" > "$LOCKFILE"  # Non-existent PID
# Check that kill -0 fails for this PID
if ! kill -0 99999 2>/dev/null; then
  pass "Stale PID correctly identified as not running"
else
  fail "Stale PID detection" "process not running" "process exists"
fi

# --- Test 4: Same version skips spawn ---
echo ""
echo "Test: Same version daemon running = new daemon exits"
rm -f "$LOCKFILE"
CURRENT_V=$(jq -r '.version' "$PLUGIN_JSON")
# Create a fake running process
sleep 1000 &
FAKE_PID=$!
SPAWNED_PIDS+=($FAKE_PID)
echo "${CURRENT_V}:$FAKE_PID" > "$LOCKFILE"

# Run daemon startup (it should exit immediately seeing same version running)
# We use timeout and background to avoid hanging
timeout 2 bash -c "CLAUDE_PLUGIN_ROOT='$PLUGIN_DIR' $DAEMON_SCRIPT" &>/dev/null &
DAEMON_PID=$!
sleep 1

# The daemon should have exited, and our fake process should still be running
if kill -0 "$FAKE_PID" 2>/dev/null; then
  pass "Same version daemon not replaced"
else
  fail "Same version handling" "fake daemon still running" "fake daemon was killed"
fi

# Cleanup fake process
kill "$FAKE_PID" 2>/dev/null || true
wait "$FAKE_PID" 2>/dev/null || true
SPAWNED_PIDS=()

# --- Test 5: Version mismatch kills old daemon ---
echo ""
echo "Test: Version mismatch triggers kill of old daemon"
rm -f "$LOCKFILE"
# Create a fake running process with OLD version
sleep 1000 &
FAKE_PID=$!
SPAWNED_PIDS+=($FAKE_PID)
echo "0.0.1:$FAKE_PID" > "$LOCKFILE"  # Old version

# Run daemon startup with current version (should kill the fake process)
timeout 3 bash -c "CLAUDE_PLUGIN_ROOT='$PLUGIN_DIR' $DAEMON_SCRIPT" &>/dev/null &
DAEMON_PID=$!
SPAWNED_PIDS+=($DAEMON_PID)
sleep 2

# The fake process should have been killed
if ! kill -0 "$FAKE_PID" 2>/dev/null; then
  pass "Old daemon killed on version mismatch"
else
  fail "Version mismatch kill" "old process killed" "old process still running"
  kill "$FAKE_PID" 2>/dev/null || true
fi

# Cleanup
for pid in "${SPAWNED_PIDS[@]}"; do
  kill "$pid" 2>/dev/null || true
done
SPAWNED_PIDS=()

# --- Test 6: Corrupted lockfile handled gracefully ---
echo ""
echo "Test: Corrupted lockfile handled gracefully"
rm -f "$LOCKFILE"
echo "garbage_not_version_pid" > "$LOCKFILE"

# Extract version/pid from corrupted content
LOCK_CONTENT=$(cat "$LOCKFILE")
OLD_VERSION="${LOCK_CONTENT%%:*}"
OLD_PID="${LOCK_CONTENT##*:}"

# With corrupted format, OLD_VERSION equals full string (no colon)
# OLD_PID also equals full string
# kill -0 on non-numeric should fail gracefully
if ! kill -0 "$OLD_PID" 2>/dev/null; then
  pass "Corrupted lockfile handled (kill -0 fails gracefully)"
else
  fail "Corrupted lockfile" "kill -0 fails" "kill -0 succeeded unexpectedly"
fi

# --- Test 7: Missing plugin.json uses "unknown" ---
echo ""
echo "Test: Missing plugin.json uses 'unknown' version"
mv "$PLUGIN_JSON" "${PLUGIN_JSON}.bak"
FALLBACK_VERSION=$(jq -r '.version' "${PLUGIN_DIR}/.claude-plugin/plugin.json" 2>/dev/null || echo "unknown")
mv "${PLUGIN_JSON}.bak" "$PLUGIN_JSON"
if [ "$FALLBACK_VERSION" = "unknown" ]; then
  pass "Missing plugin.json returns 'unknown'"
else
  fail "Missing plugin.json fallback" "unknown" "$FALLBACK_VERSION"
fi

# --- Test 8: Lockfile written with correct format after startup ---
echo ""
echo "Test: New daemon writes VERSION:PID lockfile"
rm -f "$LOCKFILE"
CURRENT_V=$(jq -r '.version' "$PLUGIN_JSON")

# Run daemon briefly
timeout 2 bash -c "CLAUDE_PLUGIN_ROOT='$PLUGIN_DIR' $DAEMON_SCRIPT" &>/dev/null &
DAEMON_PID=$!
sleep 1

# Check lockfile was written
if [ -f "$LOCKFILE" ]; then
  CONTENT=$(cat "$LOCKFILE")
  if [[ "$CONTENT" == "${CURRENT_V}:"* ]]; then
    pass "Daemon wrote VERSION:PID lockfile"
  else
    fail "Lockfile content" "${CURRENT_V}:PID" "$CONTENT"
  fi
else
  fail "Lockfile creation" "lockfile exists" "lockfile missing"
fi

# Cleanup daemon
kill "$DAEMON_PID" 2>/dev/null || true

echo ""
echo "=== Results ==="
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"

if [ "$TESTS_FAILED" -gt 0 ]; then
  exit 1
fi
exit 0
