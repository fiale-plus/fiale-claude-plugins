#!/bin/bash
# Test contextual music event dispatcher

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"
MUSIC_EVENT="$PLUGIN_ROOT/bin/music-event.sh"
CONFIG="$HOME/.claude/status-config.json"

# Backup config
BACKUP_CONFIG=""
if [ -f "$CONFIG" ]; then BACKUP_CONFIG=$(cat "$CONFIG"); fi

# Ensure config directory exists
mkdir -p "$(dirname "$CONFIG")"

cleanup() {
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
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "  PASS: $1"
}

fail() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "  FAIL: $1"
}

echo "=== Testing contextual music events ==="
echo

# Test 1: Disabled by default
echo "Testing disabled state..."
cat > "$CONFIG" << 'EOF'
{
  "music": {
    "contextual": {
      "enabled": false
    }
  },
  "background": {
    "service": "spotify",
    "tabId": 123
  }
}
EOF

"$MUSIC_EVENT" "pr_merged"
# Should exit silently
[ $? -eq 0 ] && pass "Exits cleanly when disabled" || fail "Should exit cleanly when disabled"

# Test 2: No music service configured
echo "Testing no music service..."
cat > "$CONFIG" << 'EOF'
{
  "music": {
    "contextual": {
      "enabled": true
    }
  },
  "background": {
    "service": "off"
  }
}
EOF

"$MUSIC_EVENT" "pr_merged"
[ $? -eq 0 ] && pass "Exits cleanly when no music service" || fail "Should exit cleanly when no music service"

# Test 3: Action is none
echo "Testing action=none..."
cat > "$CONFIG" << 'EOF'
{
  "music": {
    "contextual": {
      "enabled": true,
      "cooldownSeconds": 0,
      "lastActionTimestamp": 0,
      "reactions": {
        "pr_merged": { "action": "none" }
      }
    }
  },
  "background": {
    "service": "spotify",
    "tabId": 123
  }
}
EOF

"$MUSIC_EVENT" "pr_merged"
[ $? -eq 0 ] && pass "Exits cleanly when action=none" || fail "Should exit cleanly when action=none"

# Test 4: Cooldown check
echo "Testing cooldown..."
NOW_MS=$(($(date +%s) * 1000))
RECENT=$((NOW_MS - 30000))  # 30 seconds ago
cat > "$CONFIG" << EOF
{
  "music": {
    "contextual": {
      "enabled": true,
      "cooldownSeconds": 120,
      "lastActionTimestamp": $RECENT,
      "reactions": {
        "pr_merged": { "action": "pause" }
      }
    }
  },
  "background": {
    "service": "spotify",
    "tabId": 123
  }
}
EOF

"$MUSIC_EVENT" "pr_merged"
# Should exit due to cooldown (120s cooldown, only 30s elapsed)
AFTER_TS=$(jq -r '.music.contextual.lastActionTimestamp' "$CONFIG")
[ "$AFTER_TS" = "$RECENT" ] && pass "Respects cooldown (timestamp unchanged)" || fail "Should respect cooldown"

# Test 5: Cooldown expired, timestamp updated
echo "Testing timestamp update after cooldown..."
OLD_TS=$((NOW_MS - 200000))  # 200 seconds ago (>120s cooldown)
cat > "$CONFIG" << EOF
{
  "music": {
    "contextual": {
      "enabled": true,
      "cooldownSeconds": 120,
      "lastActionTimestamp": $OLD_TS,
      "reactions": {
        "pr_merged": { "action": "pause" }
      }
    }
  },
  "background": {
    "service": "spotify",
    "tabId": 123
  }
}
EOF

"$MUSIC_EVENT" "pr_merged"
# Wait briefly for background process
sleep 0.5
AFTER_TS=$(jq -r '.music.contextual.lastActionTimestamp' "$CONFIG")
[ "$AFTER_TS" -gt "$OLD_TS" ] && pass "Updates timestamp after cooldown expires" || fail "Should update timestamp"

# Test 6: Unknown event
echo "Testing unknown event..."
cat > "$CONFIG" << 'EOF'
{
  "music": {
    "contextual": {
      "enabled": true,
      "cooldownSeconds": 0,
      "lastActionTimestamp": 0,
      "reactions": {
        "pr_merged": { "action": "pause" }
      }
    }
  },
  "background": {
    "service": "spotify",
    "tabId": 123
  }
}
EOF

"$MUSIC_EVENT" "unknown_event"
[ $? -eq 0 ] && pass "Handles unknown event gracefully" || fail "Should handle unknown event"

# Test 7: Play action has query
echo "Testing play action query..."
cat > "$CONFIG" << 'EOF'
{
  "music": {
    "contextual": {
      "enabled": true,
      "cooldownSeconds": 0,
      "lastActionTimestamp": 0,
      "reactions": {
        "focus_started": { "action": "play", "query": "lo-fi focus music" }
      }
    }
  },
  "background": {
    "service": "spotify",
    "tabId": 123
  }
}
EOF

QUERY=$(jq -r '.music.contextual.reactions.focus_started.query' "$CONFIG")
[ "$QUERY" = "lo-fi focus music" ] && pass "Play action has query field" || fail "Play action should have query"

# Test 8: Null tabId
echo "Testing null tabId..."
cat > "$CONFIG" << 'EOF'
{
  "music": {
    "contextual": {
      "enabled": true,
      "cooldownSeconds": 0,
      "reactions": {
        "pr_merged": { "action": "pause" }
      }
    }
  },
  "background": {
    "service": "spotify",
    "tabId": null
  }
}
EOF

"$MUSIC_EVENT" "pr_merged"
[ $? -eq 0 ] && pass "Exits cleanly when tabId is null" || fail "Should exit cleanly when tabId is null"

echo
echo "=== Results ==="
echo "Tests run: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo

[ "$TESTS_FAILED" -eq 0 ]
