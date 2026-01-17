#!/bin/bash
# Test runner for claude-status-hub
# Runs all test scripts and reports results

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TESTS_PASSED=0
TESTS_FAILED=0

echo "======================================"
echo "  claude-status-hub Test Suite"
echo "======================================"
echo ""

run_test() {
  local test_file="$1"
  local test_name=$(basename "$test_file" .sh)

  echo "Running: $test_name"
  echo "--------------------------------------"

  if bash "$test_file"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo ""
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo ""
    echo "FAILED: $test_name"
    echo ""
  fi
}

# Run all test files
for test_file in "$SCRIPT_DIR"/test-*.sh; do
  [ -f "$test_file" ] && run_test "$test_file"
done

echo "======================================"
echo "  Final Results"
echo "======================================"
echo "Test files passed: $TESTS_PASSED"
echo "Test files failed: $TESTS_FAILED"
echo ""

if [ "$TESTS_FAILED" -gt 0 ]; then
  echo "SOME TESTS FAILED"
  exit 1
else
  echo "ALL TESTS PASSED"
  exit 0
fi
