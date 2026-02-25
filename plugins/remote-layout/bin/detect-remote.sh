#!/bin/bash
# remote-layout — detect-remote.sh
# Author: Pavel Fadeev / fiale.plus
# Origin: Live iPhone remote control session, Feb 2026
# Detect remote control mode (Claude mobile app connected)
# Outputs suggestion to stdout if detected (once per session).
# Used by UserPromptSubmit hook.

CONFIG="${HOME}/.claude/status-config.json"
# Use grandparent PID (the stable claude session process) for session-scoped flag
CLAUDE_PID=$(ps -p "$PPID" -o ppid= 2>/dev/null | tr -d ' ')
SESSION_FLAG="/tmp/remote-layout-suggested-${CLAUDE_PID:-$PPID}"

# Already active — skip
if [ -f "$CONFIG" ] && jq -e '.remoteLayout == true' "$CONFIG" >/dev/null 2>&1; then
  exit 0
fi

# Already suggested this session — skip
[ -f "$SESSION_FLAG" ] && exit 0

is_remote() {
  # Signal 1: official env var (future Anthropic support)
  [ "${CLAUDE_REMOTE:-}" = "1" ] && return 0

  # Signal 2: rapportd has established iPhone/iPad connection (macOS Continuity)
  local pid
  pid=$(pgrep rapportd 2>/dev/null | head -1)
  [ -z "$pid" ] && return 1
  # -n keeps mDNS .local hostnames visible (e.g. pavels-iphone.local)
  lsof -p "$pid" -i -n 2>/dev/null \
    | grep "ESTABLISHED" \
    | grep -qi "iphone\|ipad" && return 0

  return 1
}

if is_remote; then
  touch "$SESSION_FLAG"
  echo "Note: mobile device detected. Run /remote to activate mobile-friendly layout."
fi

exit 0
