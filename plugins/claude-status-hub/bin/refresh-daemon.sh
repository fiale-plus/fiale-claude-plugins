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

LOCKDIR="/tmp/status-hub-daemon.lock.d"
CONFIG="$HOME/.claude/status-config.json"
BRIDGE="/tmp/status-hub.json"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
MUSIC_SKILL="${PLUGIN_ROOT}/skills/hub-refresh-music.md"
FULL_SKILL="${PLUGIN_ROOT}/skills/hub-refresh.md"
PR_SCRIPT="${PLUGIN_ROOT}/bin/refresh-prs.sh"
FULL_ALLOWED="Read,Write,Bash,mcp__claude-in-chrome__*,mcp__plugin_sentry_sentry__*,mcp__tradingview__*"

# Semver comparison: returns 0 if $1 > $2
version_gt() {
  [ "$(printf '%s\n' "$1" "$2" | sort -V | tail -n1)" = "$1" ] && [ "$1" != "$2" ]
}

# Atomic lock acquisition using mkdir (portable to macOS and Linux)
acquire_lock() {
  if mkdir "$LOCKDIR" 2>/dev/null; then
    echo "$$" > "$LOCKDIR/pid"
    echo "$PLUGIN_VERSION" > "$LOCKDIR/version"
    return 0
  fi
  return 1
}

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
  local next_suffix=""

  if [ "$next_meeting_start" -gt "$now_ms" ]; then
    # Meeting is in the future
    local min_until_meeting=$(( (next_meeting_start - now_ms) / 60000 ))
    if [ "$min_until_meeting" -ge 15 ]; then
      local next_title=$(jq -r '.calendar.lastSeen[0].title // ""' "$CONFIG" 2>/dev/null)
      [ -z "$next_title" ] && next_title="meeting"
      next_suffix=" Next: ${next_title} in ${min_until_meeting}m"
    else
      # Meeting too soon - skip break reminder
      return 0
    fi
  fi
  # No meeting or meeting is far enough away - show break reminder

  # Update bridge with focus break alert
  if [ -f "$BRIDGE" ]; then
    local alert_text="☕ ${duration_min}m focus. Break?${next_suffix}"
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

# Prevent multiple daemons (version-aware, atomic locking)
if [ -d "$LOCKDIR" ]; then
  OLD_PID=$(cat "$LOCKDIR/pid" 2>/dev/null)
  OLD_VERSION=$(cat "$LOCKDIR/version" 2>/dev/null)

  if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    if [ "$OLD_VERSION" = "$PLUGIN_VERSION" ]; then
      # Same version daemon running, exit
      exit 0
    fi
    if version_gt "$PLUGIN_VERSION" "$OLD_VERSION"; then
      # We're newer - kill old daemon and take over
      kill "$OLD_PID" 2>/dev/null
      sleep 1
      rm -rf "$LOCKDIR"
    else
      # Old daemon is same or newer version, exit
      exit 0
    fi
  else
    # Stale lock (PID not running) - remove it
    rm -rf "$LOCKDIR"
  fi
fi

# Acquire atomic lock
acquire_lock || exit 0

# Cleanup on exit
trap "rm -rf '$LOCKDIR'" EXIT INT TERM

# Main loop
LAST_FULL_REFRESH=0
while true; do
  # Calculate adaptive intervals based on user activity
  read INTERVAL FULL_INTERVAL <<< $(get_intervals)

  sleep $INTERVAL

  # Self-check: exit if plugin was updated (new version will spawn fresh daemon)
  INSTALLED_VERSION=$(jq -r '.version' "${PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null || echo "unknown")
  if [ "$INSTALLED_VERSION" != "$PLUGIN_VERSION" ]; then
    rm -rf "$LOCKDIR"
    exit 0
  fi

  # Self-check: exit if another daemon took over the lockfile
  # This handles the startup race condition: multiple sessions starting simultaneously
  # all pass the initial lockfile check before any writes its PID. After one sleep cycle,
  # only the last writer survives because all others see a mismatched lockfile.
  # See docs/data-safety-guidelines.md for race condition prevention patterns.
  if [ -f "$LOCKFILE" ]; then
    CURRENT_LOCK=$(cat "$LOCKFILE" 2>/dev/null)
    if [ "$CURRENT_LOCK" != "${PLUGIN_VERSION}:$$" ]; then
      exit 0  # Another daemon owns the lock, gracefully exit
    fi
  else
    exit 0  # Lockfile gone, exit
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
