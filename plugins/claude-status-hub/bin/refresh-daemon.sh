#!/bin/bash
# Background daemon - refreshes music every 90 seconds
# Started by SessionStart hook, runs until terminal closes

INTERVAL=90
LOCKFILE="/tmp/status-hub-daemon.lock"
CONFIG="$HOME/.claude/status-config.json"
BRIDGE="/tmp/status-hub.json"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
SKILL="${PLUGIN_ROOT}/skills/hub-refresh-music.md"

# Prevent multiple daemons
if [ -f "$LOCKFILE" ]; then
  # Check if the PID in lockfile is still running
  OLD_PID=$(cat "$LOCKFILE" 2>/dev/null)
  if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    exit 0  # Daemon already running
  fi
  # Stale lock file, remove it
  rm -f "$LOCKFILE"
fi

# Write our PID to lockfile
echo $$ > "$LOCKFILE"

# Cleanup on exit
trap "rm -f $LOCKFILE" EXIT INT TERM

# Main loop
while true; do
  sleep $INTERVAL

  # Check if config exists and music is configured
  [ -f "$CONFIG" ] || continue
  SERVICE=$(jq -r '.background.service // "off"' "$CONFIG" 2>/dev/null)
  [ "$SERVICE" = "off" ] && continue

  # Check if bridge exists and needs refresh
  if [ -f "$BRIDGE" ]; then
    BRIDGE_TS=$(jq -r '.timestamp // 0' "$BRIDGE" 2>/dev/null)
    NOW_MS=$(($(date +%s) * 1000))
    AGE_MS=$((NOW_MS - BRIDGE_TS))
    # Skip if bridge was updated recently (< 60s)
    [ "$AGE_MS" -lt 60000 ] && continue
  fi

  # Quick music refresh via Claude CLI
  # Use timeout to prevent hanging
  timeout 30 claude -p --chrome --allowedTools "Read,Write,Bash,mcp__claude-in-chrome__*" -- \
    "Read and follow the hub-refresh-music skill at $SKILL" 2>/dev/null || true
done
