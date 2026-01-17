#!/bin/bash
# Background daemon - refreshes status hub periodically
# - Light refresh (PRs + music): every 90 seconds
# - Full refresh (all services): every 6 minutes
# Started by SessionStart hook, runs until terminal closes

INTERVAL=90
FULL_REFRESH_EVERY=4  # 4 × 90s = 6 minutes
LOCKFILE="/tmp/status-hub-daemon.lock"
CONFIG="$HOME/.claude/status-config.json"
BRIDGE="/tmp/status-hub.json"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
MUSIC_SKILL="${PLUGIN_ROOT}/skills/hub-refresh-music.md"
FULL_SKILL="${PLUGIN_ROOT}/skills/hub-refresh.md"
PR_SCRIPT="${PLUGIN_ROOT}/bin/refresh-prs.sh"
FULL_ALLOWED="Read,Write,Bash,mcp__claude-in-chrome__*,mcp__plugin_sentry_sentry__*,mcp__tradingview__*"

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
ITERATION=0
while true; do
  sleep $INTERVAL
  ITERATION=$((ITERATION + 1))

  [ -f "$CONFIG" ] || continue

  # Check if bridge needs refresh
  if [ -f "$BRIDGE" ]; then
    BRIDGE_TS=$(jq -r '.timestamp // 0' "$BRIDGE" 2>/dev/null)
    NOW_MS=$(($(date +%s) * 1000))
    AGE_MS=$((NOW_MS - BRIDGE_TS))
    # Skip if bridge was updated recently (< 60s)
    [ "$AGE_MS" -lt 60000 ] && continue
  fi

  # Every Nth iteration: full refresh (all services)
  if [ $((ITERATION % FULL_REFRESH_EVERY)) -eq 0 ]; then
    timeout 120 claude -p --chrome --allowedTools "$FULL_ALLOWED" -- \
      "Read and follow the hub-refresh skill at $FULL_SKILL" 2>/dev/null || true
  else
    # Light refresh: PRs (pure bash, fast)
    if [ -x "$PR_SCRIPT" ]; then
      "$PR_SCRIPT" 2>/dev/null || true
    fi

    # Light refresh: music if configured
    SERVICE=$(jq -r '.background.service // "off"' "$CONFIG" 2>/dev/null)
    if [ "$SERVICE" != "off" ]; then
      timeout 30 claude -p --chrome --allowedTools "Read,Write,Bash,mcp__claude-in-chrome__*" -- \
        "Read and follow the hub-refresh-music skill at $MUSIC_SKILL" 2>/dev/null || true
    fi
  fi

  # Always update timestamp to show daemon is alive (prevents skull)
  NOW_MS=$(($(date +%s) * 1000))
  if [ -f "$BRIDGE" ]; then
    jq --argjson ts "$NOW_MS" '.timestamp = $ts' "$BRIDGE" > "${BRIDGE}.tmp" && mv "${BRIDGE}.tmp" "$BRIDGE"
  else
    echo "{\"timestamp\": $NOW_MS, \"background\": null, \"foreground\": []}" > "$BRIDGE"
  fi
done
