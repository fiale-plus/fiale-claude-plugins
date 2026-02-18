#!/usr/bin/env bash
# vibes.sh — control plane for the continuous rhythmic music engine
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
    # $1 = JSON string
    echo "$1" > "$STATE_FILE"
}

case "${1:-}" in
    on)
        # Serialize check-and-spawn across concurrent sessions (mkdir is atomic on macOS)
        LOCK_DIR="/tmp/vibes-spawn.lock.d"
        if ! mkdir "$LOCK_DIR" 2>/dev/null; then
            sleep 0.4  # another session is spawning — wait, then fall through to PID check
        fi
        trap 'rmdir "$LOCK_DIR" 2>/dev/null; trap - EXIT' EXIT

        state=$(_read_state)
        pid=$(echo "$state" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('daemon_pid',''))" 2>/dev/null || true)

        # Check if daemon is already running
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            printf '\033[90m♪ vibes already running\033[0m\n'
            exit 0
        fi

        # Write initial state
        now=$(date +%s)
        _write_state "{\"enabled\":true,\"daemon_pid\":0,\"mode\":\"flow\",\"updated_at\":$now}"

        # Spawn daemon detached
        nohup python3 "$DAEMON" > /dev/null 2>&1 &
        daemon_pid=$!
        disown "$daemon_pid" 2>/dev/null || true

        # Update state with actual PID
        now=$(date +%s)
        _write_state "{\"enabled\":true,\"daemon_pid\":$daemon_pid,\"mode\":\"flow\",\"updated_at\":$now}"

        printf '\033[90m♪ vibes on\033[0m\n'
        ;;

    off)
        state=$(_read_state)
        pid=$(echo "$state" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('daemon_pid',''))" 2>/dev/null || true)

        # Write disabled state
        now=$(date +%s)
        mode=$(echo "$state" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('mode','flow'))" 2>/dev/null || echo "flow")
        _write_state "{\"enabled\":false,\"daemon_pid\":${pid:-0},\"mode\":\"$mode\",\"updated_at\":$now}"

        # Kill daemon's afplay children first (they'd otherwise orphan and keep playing)
        if [[ -n "$pid" ]]; then
            pgrep -P "$pid" 2>/dev/null | xargs kill 2>/dev/null || true
            kill "$pid" 2>/dev/null || true
        fi

        echo 'vibes off'
        ;;

    "")
        state=$(_read_state)
        enabled=$(echo "$state" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('enabled',False))" 2>/dev/null || echo "False")
        mode=$(echo "$state" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('mode','flow'))" 2>/dev/null || echo "flow")

        if [[ "$enabled" == "True" ]]; then
            printf '\033[90m♪ vibes on · mode: %s\033[0m\n' "$mode"
        else
            echo 'vibes off'
        fi
        ;;

    *)
        echo "Usage: vibes [on|off]" >&2
        exit 1
        ;;
esac
