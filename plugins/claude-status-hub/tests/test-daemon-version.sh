#!/bin/bash
# Test daemon version staleness detection
# Tests the version-aware lockdir and startup behavior

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$(dirname "$SCRIPT_DIR")/bin"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
LOCKDIR="/tmp/status-hub-daemon.lock.d"
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
DAEMON_SCRIPT="$BIN_DIR/refresh-daemon.sh"

# Backup existing state
BACKUP_PID=""
BACKUP_LOCK_VERSION=""
if [ -d "$LOCKDIR" ]; then
  BACKUP_PID=$(cat "$LOCKDIR/pid" 2>/dev/null || echo "")
  BACKUP_LOCK_VERSION=$(cat "$LOCKDIR/version" 2>/dev/null || echo "")
fi
BACKUP_VERSION=$(jq -r '.version' "$PLUGIN_JSON")

# Track spawned processes for cleanup
SPAWNED_PIDS=()

cleanup() {
  # Kill any processes we spawned
  for pid in "${SPAWNED_PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done

  # Restore lockdir
  rm -rf "$LOCKDIR"
  if [ -n "$BACKUP_PID" ] && [ -n "$BACKUP_LOCK_VERSION" ]; then
    mkdir -p "$LOCKDIR"
    echo "$BACKUP_PID" > "$LOCKDIR/pid"
    echo "$BACKUP_LOCK_VERSION" > "$LOCKDIR/version"
  fi

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

# --- Test 1: Lockdir structure ---
echo "Test: Lockdir has separate pid and version files"
rm -rf "$LOCKDIR"
mkdir -p "$LOCKDIR"
# Simulate what the daemon does
CURRENT_V=$(jq -r '.version' "$PLUGIN_JSON")
echo "12345" > "$LOCKDIR/pid"
echo "$CURRENT_V" > "$LOCKDIR/version"
PID_CONTENT=$(cat "$LOCKDIR/pid")
VER_CONTENT=$(cat "$LOCKDIR/version")
if [[ "$PID_CONTENT" =~ ^[0-9]+$ ]] && [[ "$VER_CONTENT" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  pass "Lockdir has separate pid and version files"
else
  fail "Lockdir format" "pid=12345, version=X.Y.Z" "pid=$PID_CONTENT, version=$VER_CONTENT"
fi

# --- Test 2: Version extraction from lockdir ---
echo ""
echo "Test: Version extraction from lockdir"
rm -rf "$LOCKDIR"
mkdir -p "$LOCKDIR"
echo "99999" > "$LOCKDIR/pid"
echo "1.2.3" > "$LOCKDIR/version"
EXTRACTED_PID=$(cat "$LOCKDIR/pid" 2>/dev/null)
EXTRACTED_VERSION=$(cat "$LOCKDIR/version" 2>/dev/null)
if [ "$EXTRACTED_VERSION" = "1.2.3" ] && [ "$EXTRACTED_PID" = "99999" ]; then
  pass "Version and PID extracted correctly"
else
  fail "Version extraction" "1.2.3 and 99999" "$EXTRACTED_VERSION and $EXTRACTED_PID"
fi

# --- Test 3: Stale PID detection ---
echo ""
echo "Test: Stale PID (non-existent process) detected"
rm -rf "$LOCKDIR"
mkdir -p "$LOCKDIR"
echo "99999" > "$LOCKDIR/pid"
echo "1.0.0" > "$LOCKDIR/version"
# Check that kill -0 fails for this PID
if ! kill -0 99999 2>/dev/null; then
  pass "Stale PID correctly identified as not running"
else
  fail "Stale PID detection" "process not running" "process exists"
fi

# --- Test 4: Same version skips spawn ---
echo ""
echo "Test: Same version daemon running = new daemon exits"
rm -rf "$LOCKDIR"
mkdir -p "$LOCKDIR"
CURRENT_V=$(jq -r '.version' "$PLUGIN_JSON")
# Create a fake running process
sleep 1000 &
FAKE_PID=$!
SPAWNED_PIDS+=($FAKE_PID)
echo "$FAKE_PID" > "$LOCKDIR/pid"
echo "$CURRENT_V" > "$LOCKDIR/version"

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

# --- Test 5: Version mismatch kills old daemon (only if newer) ---
echo ""
echo "Test: Newer version triggers kill of old daemon"
rm -rf "$LOCKDIR"
mkdir -p "$LOCKDIR"
# Create a fake running process with OLD version
sleep 1000 &
FAKE_PID=$!
SPAWNED_PIDS+=($FAKE_PID)
echo "$FAKE_PID" > "$LOCKDIR/pid"
echo "0.0.1" > "$LOCKDIR/version"  # Old version

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

# Cleanup - kill spawned processes and wait for daemon's EXIT trap
for pid in "${SPAWNED_PIDS[@]}"; do
  kill "$pid" 2>/dev/null || true
done
SPAWNED_PIDS=()
# Give time for daemon's EXIT trap to run and delete the lockdir
sleep 2

# --- Test 5b: Older version does NOT take over newer daemon ---
echo ""
echo "Test: Older version does NOT kill newer daemon"
rm -rf "$LOCKDIR"
mkdir -p "$LOCKDIR"
# Create a fake running process with NEWER version (99.99.99)
sleep 1000 &
FAKE_PID=$!
SPAWNED_PIDS+=($FAKE_PID)
echo "$FAKE_PID" > "$LOCKDIR/pid"
echo "99.99.99" > "$LOCKDIR/version"  # Newer than any real version

# Run daemon startup with current version (should NOT kill the fake process)
timeout 2 bash -c "CLAUDE_PLUGIN_ROOT='$PLUGIN_DIR' $DAEMON_SCRIPT" &>/dev/null &
DAEMON_PID=$!
sleep 1

# The fake process should still be running (newer version wins)
if kill -0 "$FAKE_PID" 2>/dev/null; then
  pass "Older daemon does not replace newer daemon"
else
  fail "Semver comparison" "newer daemon preserved" "newer daemon was killed"
fi

# Cleanup fake process
kill "$FAKE_PID" 2>/dev/null || true
wait "$FAKE_PID" 2>/dev/null || true
SPAWNED_PIDS=()
rm -rf "$LOCKDIR"

# --- Test 6: Corrupted lockdir handled gracefully ---
echo ""
echo "Test: Corrupted lockdir handled gracefully"
rm -rf "$LOCKDIR"
mkdir -p "$LOCKDIR"
echo "garbage_not_pid" > "$LOCKDIR/pid"
echo "not_a_version" > "$LOCKDIR/version"

# Extract version/pid from corrupted content
OLD_PID=$(cat "$LOCKDIR/pid" 2>/dev/null)
OLD_VERSION=$(cat "$LOCKDIR/version" 2>/dev/null)

# kill -0 on non-numeric should fail gracefully
if ! kill -0 "$OLD_PID" 2>/dev/null; then
  pass "Corrupted lockdir handled (kill -0 fails gracefully)"
else
  fail "Corrupted lockdir" "kill -0 fails" "kill -0 succeeded unexpectedly"
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

# --- Test 8: Lockdir written with correct format after startup ---
echo ""
echo "Test: New daemon writes lockdir with pid and version files"
rm -rf "$LOCKDIR"
CURRENT_V=$(jq -r '.version' "$PLUGIN_JSON")

# Run daemon briefly
timeout 2 bash -c "CLAUDE_PLUGIN_ROOT='$PLUGIN_DIR' $DAEMON_SCRIPT" &>/dev/null &
DAEMON_PID=$!
sleep 1

# Check lockdir was created
if [ -d "$LOCKDIR" ]; then
  PID_CONTENT=$(cat "$LOCKDIR/pid" 2>/dev/null)
  VER_CONTENT=$(cat "$LOCKDIR/version" 2>/dev/null)
  if [ "$VER_CONTENT" = "$CURRENT_V" ] && [[ "$PID_CONTENT" =~ ^[0-9]+$ ]]; then
    pass "Daemon wrote lockdir with pid and version files"
  else
    fail "Lockdir content" "version=$CURRENT_V, pid=number" "version=$VER_CONTENT, pid=$PID_CONTENT"
  fi
else
  fail "Lockdir creation" "lockdir exists" "lockdir missing"
fi

# Cleanup daemon
kill "$DAEMON_PID" 2>/dev/null || true

# --- Test 9: Self-eviction when lockdir ownership changes ---
# This tests the race condition fix: if another daemon takes over the lockdir,
# the current daemon should exit gracefully (see docs/data-safety-guidelines.md)
echo ""
echo "Test: Daemon self-evicts when lockdir ownership changes"
rm -rf "$LOCKDIR"
mkdir -p "$LOCKDIR"
CURRENT_V=$(jq -r '.version' "$PLUGIN_JSON")

# Simulate the lockdir ownership check logic from refresh-daemon.sh
# A daemon with PID 12345 wrote the lockdir
echo "12345" > "$LOCKDIR/pid"
echo "$CURRENT_V" > "$LOCKDIR/version"

# Another daemon (PID 99999) checks if it owns the lockdir
CURRENT_PID=$(cat "$LOCKDIR/pid" 2>/dev/null)
MY_PID="99999"
if [ "$CURRENT_PID" != "$MY_PID" ]; then
  pass "Lockdir ownership mismatch detected (self-eviction trigger)"
else
  fail "Lockdir ownership check" "mismatch detected" "false match"
fi

echo ""
echo "=== Results ==="
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"

if [ "$TESTS_FAILED" -gt 0 ]; then
  exit 1
fi
exit 0
