#!/usr/bin/env bash
# work_state.sh — maps Claude tool use to vibes music modes
# Called by PreToolUse and UserPromptSubmit hooks

STATE_FILE="$HOME/.claude/vibes.json"

# Fast exit if state file doesn't exist or vibes is disabled
if [[ ! -f "$STATE_FILE" ]]; then
    exit 0
fi

enabled=$(python3 -c "
import sys, json
try:
    d = json.load(open('$STATE_FILE'))
    print(d.get('enabled', False))
except Exception:
    print(False)
" 2>/dev/null || echo "False")

if [[ "$enabled" != "True" ]]; then
    exit 0
fi

# Determine new mode
if [[ "${1:-}" == "--reset" ]]; then
    new_mode="flow"
else
    # Read tool_name from stdin JSON
    tool_name=$(python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_name', ''))
except Exception:
    print('')
" 2>/dev/null || echo "")

    case "$tool_name" in
        Read|Glob|Grep|WebSearch|WebFetch)
            new_mode="flow"
            ;;
        Edit|Write|NotebookEdit)
            new_mode="focus"
            ;;
        Bash|Task)
            new_mode="drive"
            ;;
        *)
            # Unknown tool — no change
            exit 0
            ;;
    esac
fi

# Atomically update mode in state file
now=$(date +%s)
tmp=$(mktemp)
python3 -c "
import sys, json
try:
    d = json.load(open('$STATE_FILE'))
except Exception:
    d = {}
d['mode'] = '$new_mode'
d['updated_at'] = $now
json.dump(d, open('$tmp', 'w'))
" 2>/dev/null && mv "$tmp" "$STATE_FILE" || rm -f "$tmp"

exit 0
