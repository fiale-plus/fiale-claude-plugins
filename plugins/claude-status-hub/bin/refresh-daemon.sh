#!/bin/bash
# Background daemon - refreshes status hub periodically
# - Light refresh (PRs + music + focus check): starts at 90s, grows with idle
# - Full refresh (all services): starts at 270s, grows with idle
# Started by SessionStart hook, runs until terminal closes

# Interval bounds for adaptive refresh
BASE_LIGHT=90           # 1.5 min base
BASE_FULL=270           # 4.5 min base (3x light)
CEILING_LIGHT=3600      # 1 hour ceiling
CEILING_FULL=10800      # 3 hours ceiling

LOCKFILE="/tmp/status-hub-daemon.lock"
CONFIG="$HOME/.claude/status-config.json"
BRIDGE="/tmp/status-hub.json"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
MUSIC_SKILL="${PLUGIN_ROOT}/skills/hub-refresh-music.md"
FULL_SKILL="${PLUGIN_ROOT}/skills/hub-refresh.md"
PR_SCRIPT="${PLUGIN_ROOT}/bin/refresh-prs.sh"
FULL_ALLOWED="Read,Write,Bash,mcp__claude-in-chrome__*,mcp__plugin_sentry_sentry__*,mcp__tradingview__*"

# Calculate intervals based on idle time (grows linearly from base to ceiling)
get_intervals() {
  local now_ms=$(($(date +%s) * 1000))
  local last_activity=$(jq -r '.lastActivity // 0' "$BRIDGE" 2>/dev/null || echo 0)
  local idle_ms=$((now_ms - last_activity))
  local idle_min=$((idle_ms / 60000))

  # Grow linearly: base + idle_minutes * growth_rate, capped at ceiling
  # Growth rates chosen so ceiling is reached after ~2 hours idle
  local light=$((BASE_LIGHT + idle_min * 29))
  local full=$((BASE_FULL + idle_min * 88))

  [ $light -gt $CEILING_LIGHT ] && light=$CEILING_LIGHT
  [ $full -gt $CEILING_FULL ] && full=$CEILING_FULL

  echo "$light $full"
}

# Check if focus mode needs a break reminder
check_focus_break() {
  [ -f "$CONFIG" ] || return 0

  local focus_active=$(jq -r '.focus.active // false' "$CONFIG" 2>/dev/null)
  [ "$focus_active" = "true" ] || return 0

  local start_time=$(jq -r '.focus.startTime // 0' "$CONFIG" 2>/dev/null)
  local break_after=$(jq -r '.focus.breakAfterMinutes // 75' "$CONFIG" 2>/dev/null)
  local last_reminder=$(jq -r '.focus.lastBreakReminder // 0' "$CONFIG" 2>/dev/null)
  local now_ms=$(($(date +%s) * 1000))
  local duration_min=$(( (now_ms - start_time) / 60000 ))

  # Skip if we haven't been focusing long enough
  [ "$duration_min" -ge "$break_after" ] || return 0

  # Skip if we already reminded recently (within 15 min)
  if [ "$last_reminder" -gt 0 ]; then
    local since_reminder=$(( (now_ms - last_reminder) / 60000 ))
    [ "$since_reminder" -ge 15 ] || return 0
  fi

  # Check for gap before next meeting (need at least 15 min)
  local next_meeting_start=$(jq -r '.calendar.lastSeen[0].startTime // 0' "$CONFIG" 2>/dev/null)
  if [ "$next_meeting_start" -gt 0 ]; then
    local min_until_meeting=$(( (next_meeting_start - now_ms) / 60000 ))
    [ "$min_until_meeting" -ge 15 ] || return 0
  fi

  # Trigger break reminder alert
  local next_title=$(jq -r '.calendar.lastSeen[0].title // "nothing"' "$CONFIG" 2>/dev/null)
  local min_until=${min_until_meeting:-"∞"}

  # Update bridge with focus break alert
  if [ -f "$BRIDGE" ]; then
    local alert_text="☕ ${duration_min}m focus. Break? Next: ${next_title} in ${min_until}m"
    jq --arg alert "$alert_text" \
       '.foreground = [{"service": "focus", "icon": "☕", "title": "Break reminder", "detail": $alert, "hasAlert": true}] + .foreground' \
       "$BRIDGE" > "${BRIDGE}.tmp" && mv "${BRIDGE}.tmp" "$BRIDGE"

    # Update last reminder time in config
    jq --argjson ts "$now_ms" '.focus.lastBreakReminder = $ts' "$CONFIG" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"

    # Contextual music event
    "${PLUGIN_ROOT}/bin/music-event.sh" "break_reminder" &
  fi
}

# Get plugin version for staleness detection
PLUGIN_VERSION=$(jq -r '.version' "${PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null || echo "unknown")

# Prevent multiple daemons (version-aware)
if [ -f "$LOCKFILE" ]; then
  LOCK_CONTENT=$(cat "$LOCKFILE" 2>/dev/null)
  OLD_VERSION="${LOCK_CONTENT%%:*}"
  OLD_PID="${LOCK_CONTENT##*:}"

  if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    if [ "$OLD_VERSION" = "$PLUGIN_VERSION" ]; then
      exit 0  # Same version daemon running, all good
    fi
    # Version mismatch - kill old daemon so we can start fresh
    kill "$OLD_PID" 2>/dev/null
    sleep 1
  fi
  rm -f "$LOCKFILE"
fi

# Write our version:PID to lockfile
echo "${PLUGIN_VERSION}:$$" > "$LOCKFILE"

# Cleanup on exit
trap "rm -f $LOCKFILE" EXIT INT TERM

# Main loop
LAST_FULL_REFRESH=0
while true; do
  # Calculate adaptive intervals based on user activity
  read INTERVAL FULL_INTERVAL <<< $(get_intervals)

  sleep $INTERVAL

  # Self-check: exit if plugin was updated (new version will spawn fresh daemon)
  INSTALLED_VERSION=$(jq -r '.version' "${PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null || echo "unknown")
  if [ "$INSTALLED_VERSION" != "$PLUGIN_VERSION" ]; then
    rm -f "$LOCKFILE"
    exit 0
  fi

  [ -f "$CONFIG" ] || continue

  # Check if bridge needs refresh
  NOW_SEC=$(date +%s)
  if [ -f "$BRIDGE" ]; then
    BRIDGE_TS=$(jq -r '.timestamp // 0' "$BRIDGE" 2>/dev/null)
    NOW_MS=$((NOW_SEC * 1000))
    AGE_MS=$((NOW_MS - BRIDGE_TS))
    # Skip if bridge was updated recently (< 60s)
    [ "$AGE_MS" -lt 60000 ] && continue
  fi

  # Full refresh if enough time has passed since last one
  SINCE_FULL=$((NOW_SEC - LAST_FULL_REFRESH))
  if [ "$SINCE_FULL" -ge "$FULL_INTERVAL" ]; then
    LAST_FULL_REFRESH=$NOW_SEC
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

    # Light refresh: check if focus mode needs break reminder
    check_focus_break
  fi

  # Always update timestamp to show daemon is alive (prevents skull)
  NOW_MS=$(($(date +%s) * 1000))
  if [ -f "$BRIDGE" ]; then
    jq --argjson ts "$NOW_MS" '.timestamp = $ts' "$BRIDGE" > "${BRIDGE}.tmp" && mv "${BRIDGE}.tmp" "$BRIDGE"
  else
    echo "{\"timestamp\": $NOW_MS, \"background\": null, \"foreground\": []}" > "$BRIDGE"
  fi
done
