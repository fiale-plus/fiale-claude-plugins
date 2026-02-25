#!/bin/bash
# remote-layout — detect-remote.sh
# Author: Pavel Fadeev / fiale.plus
# Origin: Live iPhone remote control session, Feb 2026
# Detect remote control mode (Claude mobile app connected)
# Outputs formatting instruction to stdout if detected (once per session).
# Used by UserPromptSubmit hook.

CONFIG="${HOME}/.claude/status-config.json"
# Use grandparent PID (the stable claude session process) for session-scoped flag
CLAUDE_PID=$(ps -p "$PPID" -o ppid= 2>/dev/null | tr -d ' ')
SESSION_FLAG="/tmp/remote-layout-suggested-${CLAUDE_PID:-$PPID}"

# Already notified this session — skip
[ -f "$SESSION_FLAG" ] && exit 0

is_remote() {
  # Signal 1: claude remote-control session active (CLAUDE_CODE_REMOTE set by claude remote-control)
  [ -n "${CLAUDE_CODE_REMOTE:-}" ] && return 0

  # Signal 2: manual env var override
  [ "${CLAUDE_REMOTE:-}" = "1" ] && return 0

  # Signal 3: rapportd has established iPhone/iPad connection (macOS Continuity)
  local pid
  pid=$(pgrep rapportd 2>/dev/null | head -1)
  [ -z "$pid" ] && return 1
  # -n keeps mDNS .local hostnames visible (e.g. pavels-iphone.local)
  lsof -p "$pid" -i -n 2>/dev/null \
    | grep "ESTABLISHED" \
    | grep -qi "iphone\|ipad" && return 0

  return 1
}

# If remoteLayout manually enabled in config — remind Claude
if [ -f "$CONFIG" ] && jq -e '.remoteLayout == true' "$CONFIG" >/dev/null 2>&1; then
  touch "$SESSION_FLAG"
  echo "Note: remote layout is active (mobile session). Apply mobile-friendly formatting to all responses this session."
  exit 0
fi

# Auto-detect remote session
if is_remote; then
  touch "$SESSION_FLAG"
  echo "Note: remote control session detected. Apply mobile-friendly formatting to all responses this session."
fi

exit 0
