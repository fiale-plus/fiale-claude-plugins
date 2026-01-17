#!/bin/bash
# Test update-bridge.sh functionality
# Tests sanitization and bridge JSON output

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$(dirname "$SCRIPT_DIR")/bin"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

# Use actual paths (matching production script)
BRIDGE="/tmp/status-hub.json"
ERROR_FILE="/tmp/status-hub-error.txt"

# Backup existing files
BACKUP_BRIDGE=""
BACKUP_ERROR=""
if [ -f "$BRIDGE" ]; then BACKUP_BRIDGE=$(cat "$BRIDGE"); rm -f "$BRIDGE"; fi
if [ -f "$ERROR_FILE" ]; then BACKUP_ERROR=$(cat "$ERROR_FILE"); rm -f "$ERROR_FILE"; fi

cleanup() {
  rm -f "$BRIDGE" "$ERROR_FILE"
  # Restore backups if they existed
  if [ -n "$BACKUP_BRIDGE" ]; then echo "$BACKUP_BRIDGE" > "$BRIDGE"; fi
  if [ -n "$BACKUP_ERROR" ]; then echo "$BACKUP_ERROR" > "$ERROR_FILE"; fi
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

echo "=== Testing update-bridge.sh ==="
echo ""

# --- Test sanitize() function via actual usage ---
# Note: We check raw JSON content, not jq -r output (which decodes escapes)
echo "Testing sanitization..."
TESTS_RUN=$((TESTS_RUN + 1))

# Test backslash escaping - check that JSON is valid with backslashes
"$BIN_DIR/update-bridge.sh" "test" "T" 'path\to\file' "detail"
# jq -r decodes escapes, so path\\to\\file in JSON becomes path\to\file
result=$(jq -r '.background.title' "$BRIDGE")
expected='path\to\file'
if [ "$result" = "$expected" ]; then
  pass "Backslashes handled correctly (valid JSON)"
else
  fail "Backslash handling" "$expected" "$result"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test quote escaping - check that JSON is valid with quotes
"$BIN_DIR/update-bridge.sh" "test" "T" 'say "hello"' "detail"
# jq -r decodes escapes, so \" in JSON becomes "
result=$(jq -r '.background.title' "$BRIDGE")
expected='say "hello"'
if [ "$result" = "$expected" ]; then
  pass "Quotes handled correctly (valid JSON)"
else
  fail "Quote handling" "$expected" "$result"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test smart quotes don't break JSON validity
# Note: Current sanitize() uses ASCII quotes in sed patterns, so smart quotes
# pass through unchanged. The key test is that output remains valid JSON.
test_input=$'text with \xe2\x80\x9csmart quotes\xe2\x80\x9d'  # UTF-8 smart quotes
"$BIN_DIR/update-bridge.sh" "test" "T" "$test_input" "detail"
if jq -e '.background.title' "$BRIDGE" >/dev/null 2>&1; then
  pass "Smart quotes produce valid JSON"
else
  fail "Smart quotes JSON validity" "valid JSON" "invalid JSON"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test newline stripping
"$BIN_DIR/update-bridge.sh" "test" "T" $'line1\nline2' "detail"
result=$(jq -r '.background.title' "$BRIDGE")
if [[ "$result" != *$'\n'* ]]; then
  pass "Newlines stripped"
else
  fail "Newline stripping" "no newlines" "$result"
fi

echo ""
echo "Testing bridge JSON output..."

TESTS_RUN=$((TESTS_RUN + 1))
# Test basic bridge structure
"$BIN_DIR/update-bridge.sh" "spotify" "▶" "Test Song" "Test Artist"
if jq -e '.timestamp' "$BRIDGE" >/dev/null && \
   jq -e '.background' "$BRIDGE" >/dev/null && \
   jq -e '.foreground' "$BRIDGE" >/dev/null; then
  pass "Bridge has required structure (timestamp, background, foreground)"
else
  fail "Bridge structure" "timestamp, background, foreground" "$(cat "$BRIDGE")"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test background fields
site=$(jq -r '.background.site' "$BRIDGE")
icon=$(jq -r '.background.icon' "$BRIDGE")
title=$(jq -r '.background.title' "$BRIDGE")
detail=$(jq -r '.background.detail' "$BRIDGE")
if [ "$site" = "spotify" ] && [ "$icon" = "▶" ] && [ "$title" = "Test Song" ] && [ "$detail" = "Test Artist" ]; then
  pass "Background fields set correctly"
else
  fail "Background fields" "spotify/▶/Test Song/Test Artist" "$site/$icon/$title/$detail"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test foreground array preservation (without --foreground flag)
echo '{"foreground": [{"icon": "X"}]}' > "$BRIDGE"
"$BIN_DIR/update-bridge.sh" "test" "T" "title" "detail"
fg_count=$(jq '.foreground | length' "$BRIDGE")
if [ "$fg_count" = "1" ]; then
  pass "Foreground array preserved when no --foreground flag"
else
  fail "Foreground preservation" "1" "$fg_count"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test foreground array replacement (with --foreground flag)
"$BIN_DIR/update-bridge.sh" "test" "T" "title" "detail" --foreground '[{"icon": "A"}, {"icon": "B"}]'
fg_count=$(jq '.foreground | length' "$BRIDGE")
if [ "$fg_count" = "2" ]; then
  pass "Foreground array replaced with --foreground flag"
else
  fail "Foreground replacement" "2" "$fg_count"
fi

echo ""
echo "Testing error handling..."

TESTS_RUN=$((TESTS_RUN + 1))
# Test --error flag
rm -f "$ERROR_FILE"
"$BIN_DIR/update-bridge.sh" --error "Test error message"
if [ -f "$ERROR_FILE" ] && [ "$(cat "$ERROR_FILE")" = "Test error message" ]; then
  pass "Error file created with --error flag"
else
  fail "Error file creation" "Test error message" "$(cat "$ERROR_FILE" 2>/dev/null || echo 'file missing')"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test --clear-error flag
"$BIN_DIR/update-bridge.sh" --clear-error
if [ ! -f "$ERROR_FILE" ]; then
  pass "Error file cleared with --clear-error flag"
else
  fail "Error file clearing" "file removed" "file still exists"
fi

TESTS_RUN=$((TESTS_RUN + 1))
# Test that successful write clears error file
echo "old error" > "$ERROR_FILE"
"$BIN_DIR/update-bridge.sh" "test" "T" "title" "detail"
if [ ! -f "$ERROR_FILE" ]; then
  pass "Error file cleared on successful write"
else
  fail "Error clearing on success" "file removed" "file still exists"
fi

echo ""
echo "=== Results ==="
echo "Tests run: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"

if [ "$TESTS_FAILED" -gt 0 ]; then
  exit 1
fi
