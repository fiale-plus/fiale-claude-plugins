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

emit_mode_instruction() {
  local mode="$1"
  case "$mode" in
    code)
      echo "Note: remote layout [code] active. Wrap ALL responses in a single fenced code block (no language tag), max 28 chars/line, 1-space margin each side, ALL CAPS section headers with dash rule. No exceptions."
      ;;
    quote)
      echo "Note: remote layout [quote] active. Prefix EVERY line of ALL responses with '> ' (markdown blockquote). ALL CAPS section headers. Terse prose, natural line wrap. No exceptions."
      ;;
    compact)
      echo "Note: remote layout [compact] active. Format ALL responses as: bold title on first line, tight bullet/key-value lines with · separators, no blank lines between items. No exceptions."
      ;;
    *)
      echo "Note: remote layout active (mobile session). Apply mobile-friendly formatting to all responses this session."
      ;;
  esac
}

is_remote() {
  # Signal 1: claude remote-control session (bridge mode — CLAUDE_CODE_ENVIRONMENT_KIND=bridge)
  [ "${CLAUDE_CODE_ENVIRONMENT_KIND:-}" = "bridge" ] && return 0

  # Signal 2: rapportd has established iPhone/iPad connection (macOS Continuity)
  local pid
  pid=$(pgrep rapportd 2>/dev/null | head -1)
  [ -z "$pid" ] && return 1
  # Without -n so hostnames (e.g. pavels-iphone.local) are resolved
  lsof -p "$pid" -i 2>/dev/null \
    | grep "ESTABLISHED" \
    | grep -qi "iphone\|ipad" && return 0

  return 1
}

# If remoteLayout manually enabled in config — remind Claude with mode-specific instruction
if [ -f "$CONFIG" ]; then
  MODE=$(jq -r '.remoteLayout // false' "$CONFIG" 2>/dev/null)
  if [ "$MODE" != "false" ] && [ "$MODE" != "null" ] && [ -n "$MODE" ]; then
    touch "$SESSION_FLAG"
    emit_mode_instruction "$MODE"
    exit 0
  fi
fi

# Auto-detect remote session (defaults to code mode)
if is_remote; then
  touch "$SESSION_FLAG"
  emit_mode_instruction "code"
fi

exit 0
