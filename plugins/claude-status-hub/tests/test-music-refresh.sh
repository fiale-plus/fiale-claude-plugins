#!/bin/bash
# Test refresh-music.sh functionality
# Tests OS-level detection, skip-if-unchanged, and fallback behavior

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$(dirname "$SCRIPT_DIR")/bin"
SCRIPT="$BIN_DIR/refresh-music.sh"

# Production paths
BRIDGE="/tmp/status-hub.json"
CONFIG="$HOME/.claude/status-config.json"

# Backup existing files
BACKUP_BRIDGE=""
BACKUP_CONFIG=""
if [ -f "$BRIDGE" ]; then BACKUP_BRIDGE=$(cat "$BRIDGE"); fi
if [ -f "$CONFIG" ]; then BACKUP_CONFIG=$(cat "$CONFIG"); fi

# Create mock bin directory
MOCK_BIN="/tmp/test-mock-bin-$$"
mkdir -p "$MOCK_BIN"

# Ensure config directory exists
mkdir -p "$(dirname "$CONFIG")"

cleanup() {
  rm -rf "$MOCK_BIN"
  rm -f "$BRIDGE"
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

# Create a mock osascript that returns predefined values
create_mock_osascript() {
  local title="$1"
  local artist="$2"
  local state="$3"  # "playing" or "paused"
  local app="$4"    # "Spotify" or "Music"

  cat > "$MOCK_BIN/osascript" << ENDSCRIPT
#!/bin/bash
# Mock osascript
case "\$*" in
  *"name of current track"*)  echo "$title" ;;
  *"artist of current track"*) echo "$artist" ;;
  *"player state"*)            echo "$state" ;;
  *)                           echo "" ;;
esac
ENDSCRIPT
  chmod +x "$MOCK_BIN/osascript"
}

# Create a mock pgrep that reports app as running
create_mock_pgrep() {
  local app="$1"
  cat > "$MOCK_BIN/pgrep" << ENDSCRIPT
#!/bin/bash
# Mock pgrep - report $app as running
if [[ "\$*" == *"$app"* ]]; then
  echo "12345"
  exit 0
fi
exit 1
ENDSCRIPT
  chmod +x "$MOCK_BIN/pgrep"
}

# Create a mock nowplaying-cli
create_mock_nowplaying() {
  local title="$1"
  local artist="$2"
  local rate="$3"  # "1" = playing, "0" = paused

  cat > "$MOCK_BIN/nowplaying-cli" << ENDSCRIPT
#!/bin/bash
# Mock nowplaying-cli
case "\$2" in
  title)        echo "$title" ;;
  artist)       echo "$artist" ;;
  playbackRate) echo "$rate" ;;
  *)            echo "" ;;
esac
ENDSCRIPT
  chmod +x "$MOCK_BIN/nowplaying-cli"
}

setup_config() {
  local service="$1"
  cat > "$CONFIG" << EOF
{
  "background": {
    "service": "$service"
  }
}
EOF
}

setup_bridge() {
  local icon="$1"
  local title="$2"
  local detail="$3"
  local site="${4:-$SERVICE}"
  cat > "$BRIDGE" << EOF
{
  "timestamp": 1000,
  "lastActivity": 1000,
  "background": {
    "site": "$site",
    "icon": "$icon",
    "title": "$title",
    "detail": "$detail"
  },
  "foreground": [{"service":"test","icon":"T","title":"Test","detail":"item"}]
}
EOF
}

# Run with mocked PATH
run_refresh() {
  PATH="$MOCK_BIN:$PATH" "$SCRIPT"
}

echo "=== Testing refresh-music.sh ==="
echo ""

echo "Testing service=off exits early..."

# Test: service=off exits without touching bridge
TESTS_RUN=$((TESTS_RUN + 1))
setup_config "off"
rm -f "$BRIDGE"
run_refresh
if [ ! -f "$BRIDGE" ]; then
  pass "service=off exits without creating bridge"
else
  fail "service=off early exit" "no bridge" "bridge created"
fi

echo ""
echo "Testing no config exits early..."

# Test: missing config exits
TESTS_RUN=$((TESTS_RUN + 1))
rm -f "$CONFIG" "$BRIDGE"
run_refresh
if [ ! -f "$BRIDGE" ]; then
  pass "missing config exits without creating bridge"
else
  fail "missing config exit" "no bridge" "bridge created"
fi

echo ""
echo "Testing Spotify detection..."

# Test: Spotify playing → updates bridge with ▶
TESTS_RUN=$((TESTS_RUN + 1))
setup_config "spotify"
rm -f "$BRIDGE"
create_mock_pgrep "Spotify"
create_mock_osascript "Bohemian Rhapsody" "Queen" "playing" "Spotify"
run_refresh
if [ -f "$BRIDGE" ]; then
  icon=$(jq -r '.background.icon' "$BRIDGE")
  title=$(jq -r '.background.title' "$BRIDGE")
  detail=$(jq -r '.background.detail' "$BRIDGE")
  if [ "$icon" = "▶" ] && [ "$title" = "Bohemian Rhapsody" ] && [ "$detail" = "Queen" ]; then
    pass "Spotify playing → ▶ Bohemian Rhapsody / Queen"
  else
    fail "Spotify playing" "▶ Bohemian Rhapsody / Queen" "$icon $title / $detail"
  fi
else
  fail "Spotify playing" "bridge created" "no bridge"
fi

# Test: Spotify paused → updates bridge with ⏸
TESTS_RUN=$((TESTS_RUN + 1))
setup_config "spotify"
rm -f "$BRIDGE"
create_mock_pgrep "Spotify"
create_mock_osascript "Bohemian Rhapsody" "Queen" "paused" "Spotify"
run_refresh
if [ -f "$BRIDGE" ]; then
  icon=$(jq -r '.background.icon' "$BRIDGE")
  if [ "$icon" = "⏸" ]; then
    pass "Spotify paused → ⏸ icon"
  else
    fail "Spotify paused" "⏸" "$icon"
  fi
else
  fail "Spotify paused" "bridge created" "no bridge"
fi

# Test: Spotify not running → exits silently
TESTS_RUN=$((TESTS_RUN + 1))
setup_config "spotify"
rm -f "$BRIDGE"
# Mock pgrep to say Spotify is NOT running
cat > "$MOCK_BIN/pgrep" << 'ENDSCRIPT'
#!/bin/bash
exit 1
ENDSCRIPT
chmod +x "$MOCK_BIN/pgrep"
run_refresh
if [ ! -f "$BRIDGE" ]; then
  pass "Spotify not running → silent exit"
else
  fail "Spotify not running" "no bridge" "bridge created"
fi

echo ""
echo "Testing Apple Music detection..."

# Test: Apple Music playing → updates bridge
TESTS_RUN=$((TESTS_RUN + 1))
setup_config "apple-music"
rm -f "$BRIDGE"
create_mock_pgrep "Music"
create_mock_osascript "Let It Be" "The Beatles" "playing" "Music"
run_refresh
if [ -f "$BRIDGE" ]; then
  icon=$(jq -r '.background.icon' "$BRIDGE")
  title=$(jq -r '.background.title' "$BRIDGE")
  if [ "$icon" = "▶" ] && [ "$title" = "Let It Be" ]; then
    pass "Apple Music playing → ▶ Let It Be"
  else
    fail "Apple Music playing" "▶ Let It Be" "$icon $title"
  fi
else
  fail "Apple Music playing" "bridge created" "no bridge"
fi

echo ""
echo "Testing YouTube Music (nowplaying-cli)..."

# Test: YouTube Music with nowplaying-cli → updates bridge
TESTS_RUN=$((TESTS_RUN + 1))
setup_config "youtube-music"
rm -f "$BRIDGE"
create_mock_nowplaying "Never Gonna Give You Up" "Rick Astley" "1"
run_refresh
if [ -f "$BRIDGE" ]; then
  icon=$(jq -r '.background.icon' "$BRIDGE")
  title=$(jq -r '.background.title' "$BRIDGE")
  detail=$(jq -r '.background.detail' "$BRIDGE")
  if [ "$icon" = "▶" ] && [ "$title" = "Never Gonna Give You Up" ] && [ "$detail" = "Rick Astley" ]; then
    pass "YouTube Music (nowplaying-cli) → ▶ Never Gonna Give You Up / Rick Astley"
  else
    fail "YouTube Music nowplaying" "▶ Never Gonna Give You Up / Rick Astley" "$icon $title / $detail"
  fi
else
  fail "YouTube Music nowplaying" "bridge created" "no bridge"
fi

# Test: YouTube Music without nowplaying-cli → silent exit
TESTS_RUN=$((TESTS_RUN + 1))
setup_config "youtube-music"
rm -f "$BRIDGE"
rm -f "$MOCK_BIN/nowplaying-cli"
# Restrict PATH so no real nowplaying-cli is found
PATH="$MOCK_BIN:/usr/bin:/bin" "$SCRIPT"
if [ ! -f "$BRIDGE" ]; then
  pass "YouTube Music without nowplaying-cli → silent exit"
else
  fail "YouTube Music no CLI" "no bridge" "bridge created"
fi

echo ""
echo "Testing skip-if-unchanged..."

# Test: Same data → skips bridge write
TESTS_RUN=$((TESTS_RUN + 1))
SERVICE="spotify"
setup_config "spotify"
setup_bridge "▶" "Bohemian Rhapsody" "Queen" "spotify"
ORIGINAL_TS=$(jq -r '.timestamp' "$BRIDGE")
create_mock_pgrep "Spotify"
create_mock_osascript "Bohemian Rhapsody" "Queen" "playing" "Spotify"
run_refresh
NEW_TS=$(jq -r '.timestamp' "$BRIDGE")
if [ "$ORIGINAL_TS" = "$NEW_TS" ]; then
  pass "Unchanged music → skips bridge write"
else
  fail "Skip-if-unchanged" "timestamp $ORIGINAL_TS" "timestamp $NEW_TS"
fi

# Test: Different song → updates bridge
TESTS_RUN=$((TESTS_RUN + 1))
setup_config "spotify"
setup_bridge "▶" "Old Song" "Old Artist" "spotify"
ORIGINAL_TS=$(jq -r '.timestamp' "$BRIDGE")
create_mock_pgrep "Spotify"
create_mock_osascript "New Song" "New Artist" "playing" "Spotify"
sleep 1  # Ensure timestamp differs
run_refresh
NEW_TS=$(jq -r '.timestamp' "$BRIDGE")
new_title=$(jq -r '.background.title' "$BRIDGE")
if [ "$new_title" = "New Song" ] && [ "$NEW_TS" != "$ORIGINAL_TS" ]; then
  pass "Changed song → updates bridge"
else
  fail "Changed song update" "New Song with new timestamp" "$new_title ts=$NEW_TS"
fi

# Test: Same song but icon changed (playing→paused) → updates bridge
TESTS_RUN=$((TESTS_RUN + 1))
setup_config "spotify"
setup_bridge "▶" "Same Song" "Same Artist" "spotify"
create_mock_pgrep "Spotify"
create_mock_osascript "Same Song" "Same Artist" "paused" "Spotify"
sleep 1
run_refresh
new_icon=$(jq -r '.background.icon' "$BRIDGE")
if [ "$new_icon" = "⏸" ]; then
  pass "Play state change → updates bridge"
else
  fail "Play state change" "⏸" "$new_icon"
fi

echo ""
echo "Testing foreground preservation..."

# Test: Bridge update preserves foreground items
TESTS_RUN=$((TESTS_RUN + 1))
setup_config "spotify"
setup_bridge "⏸" "Old" "Old" "spotify"
create_mock_pgrep "Spotify"
create_mock_osascript "New Track" "New Artist" "playing" "Spotify"
sleep 1
run_refresh
fg_count=$(jq '.foreground | length' "$BRIDGE")
fg_title=$(jq -r '.foreground[0].title' "$BRIDGE")
if [ "$fg_count" = "1" ] && [ "$fg_title" = "Test" ]; then
  pass "Foreground items preserved after music update"
else
  fail "Foreground preservation" "1 item with title=Test" "$fg_count items, title=$fg_title"
fi

echo ""
echo "Testing title truncation..."

# Test: Long title gets truncated to 30 chars
TESTS_RUN=$((TESTS_RUN + 1))
LONG_TITLE="This Is A Very Long Song Title That Exceeds Thirty Characters"
setup_config "spotify"
rm -f "$BRIDGE"
create_mock_pgrep "Spotify"
create_mock_osascript "$LONG_TITLE" "Artist" "playing" "Spotify"
run_refresh
title=$(jq -r '.background.title' "$BRIDGE")
title_len=${#title}
if [ "$title_len" -le 30 ]; then
  pass "Long title truncated to ${title_len} chars (max 30)"
else
  fail "Title truncation" "<=30 chars" "$title_len chars"
fi

echo ""
echo "Testing generic fallback..."

# Test: Unknown service with nowplaying-cli → works
TESTS_RUN=$((TESTS_RUN + 1))
setup_config "tidal"
rm -f "$BRIDGE"
create_mock_nowplaying "Ocean Eyes" "Billie Eilish" "1"
run_refresh
if [ -f "$BRIDGE" ]; then
  title=$(jq -r '.background.title' "$BRIDGE")
  if [ "$title" = "Ocean Eyes" ]; then
    pass "Unknown service with nowplaying-cli → works as fallback"
  else
    fail "Generic fallback" "Ocean Eyes" "$title"
  fi
else
  fail "Generic fallback" "bridge created" "no bridge"
fi

echo ""
echo "=== Results ==="
echo "Tests run: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"

if [ "$TESTS_FAILED" -gt 0 ]; then
  exit 1
fi
