#!/bin/bash
# Zero-token music status refresh - replaces claude -p call in light cycle
# Uses macOS native APIs (osascript, nowplaying-cli) instead of Chrome MCP
# Falls back silently - full refresh cycle handles detection via Chrome MCP

CONFIG="$HOME/.claude/status-config.json"
BRIDGE="/tmp/status-hub.json"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"

# Read music service config
[ -f "$CONFIG" ] || exit 0
SERVICE=$(jq -r '.background.service // "off"' "$CONFIG" 2>/dev/null)
[ "$SERVICE" = "off" ] && exit 0

TITLE=""
ARTIST=""
IS_PLAYING=false

case "$SERVICE" in
  spotify)
    # Native Spotify.app AppleScript (no browser needed)
    if pgrep -xq "Spotify"; then
      TITLE=$(osascript -e 'tell application "Spotify" to name of current track' 2>/dev/null || echo "")
      ARTIST=$(osascript -e 'tell application "Spotify" to artist of current track' 2>/dev/null || echo "")
      STATE=$(osascript -e 'tell application "Spotify" to player state as string' 2>/dev/null || echo "")
      [ "$STATE" = "playing" ] && IS_PLAYING=true
    fi
    ;;
  apple-music)
    # Native Music.app AppleScript
    if pgrep -xq "Music"; then
      TITLE=$(osascript -e 'tell application "Music" to name of current track' 2>/dev/null || echo "")
      ARTIST=$(osascript -e 'tell application "Music" to artist of current track' 2>/dev/null || echo "")
      STATE=$(osascript -e 'tell application "Music" to player state as string' 2>/dev/null || echo "")
      [ "$STATE" = "playing" ] && IS_PLAYING=true
    fi
    ;;
  youtube-music)
    # Browser-based - use nowplaying-cli if available
    if command -v nowplaying-cli &>/dev/null; then
      TITLE=$(nowplaying-cli get title 2>/dev/null || echo "")
      ARTIST=$(nowplaying-cli get artist 2>/dev/null || echo "")
      RATE=$(nowplaying-cli get playbackRate 2>/dev/null || echo "0")
      [ "$RATE" != "0" ] && [ "$RATE" != "" ] && IS_PLAYING=true
    fi
    # If nowplaying-cli not available, exit silently - full refresh handles it
    ;;
  *)
    # Unknown service - try nowplaying-cli as generic fallback
    if command -v nowplaying-cli &>/dev/null; then
      TITLE=$(nowplaying-cli get title 2>/dev/null || echo "")
      ARTIST=$(nowplaying-cli get artist 2>/dev/null || echo "")
      RATE=$(nowplaying-cli get playbackRate 2>/dev/null || echo "0")
      [ "$RATE" != "0" ] && [ "$RATE" != "" ] && IS_PLAYING=true
    fi
    ;;
esac

# Nothing detected - exit silently (full refresh will handle it)
[ -z "$TITLE" ] && exit 0

# Determine icon
ICON="⏸"
[ "$IS_PLAYING" = true ] && ICON="▶"

# Truncate for statusline display
TITLE="${TITLE:0:30}"
ARTIST="${ARTIST:0:25}"

# Skip-if-unchanged: compare with current bridge data
if [ -f "$BRIDGE" ]; then
  CURRENT_TITLE=$(jq -r '.background.title // ""' "$BRIDGE" 2>/dev/null)
  CURRENT_DETAIL=$(jq -r '.background.detail // ""' "$BRIDGE" 2>/dev/null)
  CURRENT_ICON=$(jq -r '.background.icon // ""' "$BRIDGE" 2>/dev/null)

  if [ "$TITLE" = "$CURRENT_TITLE" ] && [ "$ARTIST" = "$CURRENT_DETAIL" ] && [ "$ICON" = "$CURRENT_ICON" ]; then
    exit 0
  fi
fi

# Update bridge with new music data (preserves foreground)
"$PLUGIN_ROOT/bin/update-bridge.sh" "$SERVICE" "$ICON" "$TITLE" "$ARTIST"
