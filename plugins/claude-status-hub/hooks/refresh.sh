#!/bin/bash
# Status Hub - Background Refresh Hook

# Debug logging
DEBUG_LOG="/tmp/status-hub-debug.log"
log() { echo "[$(date '+%H:%M:%S')] $1" >> "$DEBUG_LOG"; }
log "Hook triggered, CLAUDE_PLUGIN_ROOT=$CLAUDE_PLUGIN_ROOT"

CONFIG="$HOME/.claude/status-config.json"
BRIDGE="/tmp/status-hub.json"
SKILL="${CLAUDE_PLUGIN_ROOT}/skills/hub-refresh.md"
LOG="/tmp/status-hub-refresh.log"
LOCKFILE="/tmp/status-hub.lock"

# Always update lastActivity (user activity tracking for adaptive intervals)
NOW_MS=$(($(date +%s) * 1000))
if [ -f "$BRIDGE" ]; then
  jq --argjson ts "$NOW_MS" '.lastActivity = $ts' "$BRIDGE" > "${BRIDGE}.tmp" && mv "${BRIDGE}.tmp" "$BRIDGE"
  log "Updated lastActivity to $NOW_MS"
fi

# No config = nothing to track
[ -f "$CONFIG" ] || { log "No config, exiting"; exit 0; }

# Prevent pileup - skip if lock < 2min old
if [ -f "$LOCKFILE" ]; then
  LOCK_MTIME=$(stat -f %m "$LOCKFILE" 2>/dev/null || stat -c %Y "$LOCKFILE" 2>/dev/null || echo 0)
  LOCK_AGE=$(($(date +%s) - LOCK_MTIME))
  [ "$LOCK_AGE" -lt 120 ] && { log "Lock active (${LOCK_AGE}s), skipping"; exit 0; }
fi

# Check bridge freshness - skip if < 60s old
if [ -f "$BRIDGE" ]; then
  BRIDGE_TS=$(jq -r '.timestamp // 0' "$BRIDGE" 2>/dev/null)
  NOW_MS=$(($(date +%s) * 1000))
  AGE_MS=$((NOW_MS - BRIDGE_TS))
  [ "$AGE_MS" -lt 60000 ] && { log "Bridge fresh (${AGE_MS}ms), skipping"; exit 0; }
fi

# Check if anything to refresh
SERVICE=$(jq -r '.background.service // "off"' "$CONFIG" 2>/dev/null)
FG_COUNT=$(jq -r '.foreground | length' "$CONFIG" 2>/dev/null || echo 0)
[ "$SERVICE" = "off" ] && [ "$FG_COUNT" = "0" ] && { log "Nothing tracked, skipping"; exit 0; }

# Create lock
touch "$LOCKFILE"
log "Starting refresh: service=$SERVICE, fg_count=$FG_COUNT"

# Build allowed tools list
ALLOWED="Read,Write,Bash,mcp__claude-in-chrome__*,mcp__plugin_sentry_sentry__*,mcp__tradingview__*"

log "Spawning background CLI with --chrome"

# Detach completely from hook process
nohup bash -c '
  echo "[$(date "+%H:%M:%S")] Background process started" >> "'"$DEBUG_LOG"'"
  OUTPUT=$(claude -p --chrome --allowedTools "'"$ALLOWED"'" -- \
    "Read and follow the hub-refresh skill at '"$SKILL"' to refresh status hub. Config: '"$CONFIG"', Bridge: '"$BRIDGE"'" 2>&1)
  echo "$OUTPUT" > "'"$LOG"'"
  echo "[$(date "+%H:%M:%S")] Background process completed" >> "'"$DEBUG_LOG"'"
  rm -f "'"$LOCKFILE"'"
' > /dev/null 2>&1 &

disown
log "Hook exiting, background spawned"
exit 0
