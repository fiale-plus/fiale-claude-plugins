#!/bin/bash
# Contextual music event dispatcher
# Usage: music-event.sh <event_type>
# Called by refresh scripts when events occur

EVENT="$1"
CONFIG="$HOME/.claude/status-config.json"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"

# Check enabled
ENABLED=$(jq -r '.music.contextual.enabled // false' "$CONFIG" 2>/dev/null)
[ "$ENABLED" != "true" ] && exit 0

# Check cooldown
COOLDOWN=$(jq -r '.music.contextual.cooldownSeconds // 120' "$CONFIG")
LAST=$(jq -r '.music.contextual.lastActionTimestamp // 0' "$CONFIG")
NOW_MS=$(($(date +%s) * 1000))
[ $(( (NOW_MS - LAST) / 1000 )) -lt "$COOLDOWN" ] && exit 0

# Get reaction
ACTION=$(jq -r ".music.contextual.reactions.$EVENT.action // \"none\"" "$CONFIG")
[ "$ACTION" = "none" ] && exit 0

# Get music tab
SERVICE=$(jq -r '.background.service // "off"' "$CONFIG")
TAB_ID=$(jq -r '.background.tabId // null' "$CONFIG")
[ "$SERVICE" = "off" ] || [ "$TAB_ID" = "null" ] && exit 0

# Execute (detached)
case "$ACTION" in
  pause|resume|skip)
    nohup claude -p --chrome --allowedTools "mcp__claude-in-chrome__*" -- \
      "Execute $ACTION on $SERVICE music tab $TAB_ID" >/dev/null 2>&1 &
    ;;
  play)
    QUERY=$(jq -r ".music.contextual.reactions.$EVENT.query // \"music\"" "$CONFIG")
    nohup claude -p --chrome --allowedTools "Read,mcp__claude-in-chrome__*" -- \
      "Read ${PLUGIN_ROOT}/commands/hub-play.md and play '$QUERY'" >/dev/null 2>&1 &
    ;;
esac

# Update timestamp
jq --argjson ts "$NOW_MS" '.music.contextual.lastActionTimestamp = $ts' \
  "$CONFIG" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"
