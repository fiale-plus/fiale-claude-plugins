#!/bin/bash
# Demo test that intentionally fails
# This test is created to demonstrate CI failure handling

set -e

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

echo "=== Demo Failing Test ==="

# Test 1: This passes
TESTS_RUN=$((TESTS_RUN + 1))
if [ 1 -eq 1 ]; then
  pass "Basic sanity check works"
else
  fail "Basic sanity check works"
fi

# Test 2: This intentionally fails
TESTS_RUN=$((TESTS_RUN + 1))
expected="success"
actual="epic_failure"
if [ "$expected" = "$actual" ]; then
  pass "Demo assertion (this should fail)"
else
  fail "Demo assertion (this should fail) - expected '$expected' but got '$actual'"
fi

echo ""
echo "Tests run: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"

if [ $TESTS_FAILED -gt 0 ]; then
  exit 1
fi
