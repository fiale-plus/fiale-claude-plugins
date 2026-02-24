#!/usr/bin/env bash
# vibes.sh — control plane for the two-mode rhythmic music engine
#
# Commands:
#   vibes jazzy        — start jazzy dinner-jazz mode (62 BPM)
#   vibes cafe         — start cafe del mar Balearic chill mode (74 BPM)
#   vibes off          — stop music with graceful fade
#   vibes              — show current status
#
# Session hook flags (called by hooks.json):
#   vibes --auto-start — resume last mode if enabled=true (SessionStart)
#   vibes --fade-stop  — signal daemon to fade out (Stop)

set -euo pipefail

STATE_FILE="$HOME/.claude/vibes.json"
DAEMON="$(dirname "$(dirname "$0")")/hooks/rhythm_daemon.py"

_read_state() {
    if [[ -f "$STATE_FILE" ]]; then
        cat "$STATE_FILE"
    else
        echo '{}'
    fi
}

_write_state() {
    echo "$1" > "$STATE_FILE"
}

_get_field() {
    # $1=json_string  $2=field  $3=default
    python3 -c "
import sys, json
try:
    d = json.loads(sys.argv[1])
    print(d.get(sys.argv[2], sys.argv[3]))
except Exception:
    print(sys.argv[3])
" "$1" "$2" "$3" 2>/dev/null || echo "$3"
}

_is_daemon_running() {
    local pid="$1"
    [[ -n "$pid" ]] && [[ "$pid" != "0" ]] && kill -0 "$pid" 2>/dev/null
}

_spawn_daemon() {
    # Atomic spawn guard (mkdir is atomic on macOS/Linux)
    if ! mkdir /tmp/vibes-spawn.lock.d 2>/dev/null; then
        sleep 0.4   # another session spawning — wait
    fi
    trap 'rmdir /tmp/vibes-spawn.lock.d 2>/dev/null; trap - EXIT' EXIT

    # Re-check after lock
    local state pid
    state=$(_read_state)
    pid=$(_get_field "$state" "daemon_pid" "")
    if _is_daemon_running "$pid"; then
        return 0
    fi

    nohup python3 "$DAEMON" > /dev/null 2>&1 &
    local daemon_pid=$!
    disown "$daemon_pid" 2>/dev/null || true

    # Update PID in state (mode/enabled already written by caller)
    local now
    now=$(date +%s)
    python3 -c "
import json, sys
try:
    with open('$STATE_FILE') as f: s = json.load(f)
except Exception: s = {}
s['daemon_pid'] = $daemon_pid
s['updated_at'] = $now
with open('$STATE_FILE', 'w') as f: json.dump(s, f)
" 2>/dev/null || true
}

_start_mode() {
    local mode="$1"
    local state pid now

    state=$(_read_state)
    pid=$(_get_field "$state" "daemon_pid" "")
    now=$(date +%s)

    # Always write new mode + enabled=true
    python3 -c "
import json, sys
try:
    with open('$STATE_FILE') as f: s = json.load(f)
except Exception: s = {}
s['enabled'] = True
s['mode']    = '$mode'
s['updated_at'] = $now
with open('$STATE_FILE', 'w') as f: json.dump(s, f)
" 2>/dev/null || true

    if _is_daemon_running "$pid"; then
        # Daemon already running — it will pick up mode change on next bar
        printf '\033[90m♪ vibes → %s\033[0m\n' "$mode"
    else
        _spawn_daemon
        printf '\033[90m♪ vibes on · %s\033[0m\n' "$mode"
    fi
}

_stop_daemon() {
    local state pid now mode
    state=$(_read_state)
    pid=$(_get_field "$state" "daemon_pid" "")
    mode=$(_get_field "$state" "mode" "jazzy")
    now=$(date +%s)

    # Signal daemon to stop (it will fade out and exit)
    python3 -c "
import json
try:
    with open('$STATE_FILE') as f: s = json.load(f)
except Exception: s = {}
s['enabled']    = False
s['updated_at'] = $now
with open('$STATE_FILE', 'w') as f: json.dump(s, f)
" 2>/dev/null || true

    # Give daemon time to fade (≤1s), then force-kill if still alive
    if _is_daemon_running "$pid"; then
        sleep 1.0
        if _is_daemon_running "$pid"; then
            pgrep -P "$pid" 2>/dev/null | xargs kill 2>/dev/null || true
            kill "$pid" 2>/dev/null || true
        fi
    fi
}

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------

case "${1:-}" in

    jazzy|cafe)
        _start_mode "$1"
        ;;

    off)
        _stop_daemon
        echo 'vibes off'
        ;;

    "")
        state=$(_read_state)
        enabled=$(_get_field "$state" "enabled" "False")
        mode=$(_get_field "$state" "mode" "jazzy")
        pid=$(_get_field "$state" "daemon_pid" "")

        if [[ "$enabled" == "True" ]] && _is_daemon_running "$pid"; then
            printf '\033[90m♪ vibes on · %s\033[0m\n' "$mode"
        else
            echo 'vibes off'
        fi
        ;;

    --auto-start)
        # Called by SessionStart hook — resume last mode if enabled
        state=$(_read_state)
        enabled=$(_get_field "$state" "enabled" "False")
        mode=$(_get_field "$state" "mode" "jazzy")
        pid=$(_get_field "$state" "daemon_pid" "")

        if [[ "$enabled" != "True" ]]; then
            exit 0
        fi
        if _is_daemon_running "$pid"; then
            exit 0   # already running in another session
        fi
        if [[ "$mode" != "jazzy" && "$mode" != "cafe" ]]; then
            mode="jazzy"
        fi
        _spawn_daemon
        ;;

    --question)
        # Called manually before AskUserQuestion — sets question one-shot variant
        python3 -c "
import json, time
try:
    with open('$STATE_FILE') as f: s = json.load(f)
except Exception: s = {}
s['one_shot']    = 'question'
s['updated_at']  = int(time.time())
with open('$STATE_FILE', 'w') as f: json.dump(s, f)
" 2>/dev/null || true
        ;;

    --fade-stop)
        # Called by Stop hook — signal daemon to fade, then return quickly
        state=$(_read_state)
        enabled=$(_get_field "$state" "enabled" "False")

        if [[ "$enabled" != "True" ]]; then
            exit 0
        fi

        now=$(date +%s)
        python3 -c "
import json
try:
    with open('$STATE_FILE') as f: s = json.load(f)
except Exception: s = {}
s['enabled']    = False
s['updated_at'] = $now
with open('$STATE_FILE', 'w') as f: json.dump(s, f)
" 2>/dev/null || true
        # Don't wait — hook has limited timeout; daemon fades on its own
        ;;

    *)
        echo "Usage: vibes [jazzy|cafe|off]" >&2
        exit 1
        ;;

esac
