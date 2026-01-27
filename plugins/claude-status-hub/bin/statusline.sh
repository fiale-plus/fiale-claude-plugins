#!/bin/bash
# Claude Code Status Line with Hub Integration

# ANSI colors
PURPLE='\033[35m' CYAN='\033[36m' YELLOW='\033[33m' RED='\033[31m'
GREEN='\033[32m' MAGENTA='\033[95m' RESET='\033[0m' DIM='\033[2m'

# Files
ERROR_FILE="/tmp/status-hub-error.txt"
BRIDGE_FILE="/tmp/status-hub.json"
BASE_CONFIG="${HOME}/.claude/status-base-config.json"
HUB_CONFIG="${HOME}/.claude/status-config.json"

# Read context JSON (stdin)
input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // "~"')

# Extract context window usage (calculate against usable space excluding autocompact buffer)
ctx_percent=0; ctx_available="false"
USAGE=$(echo "$input" | jq '.context_window.current_usage')
ctx_size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
usable_size=$((ctx_size - ctx_size * 225 / 1000))

if [ "$USAGE" != "null" ] && [ -n "$USAGE" ]; then
  ctx_used=$(echo "$USAGE" | jq -r '.input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens // 0')
else
  ctx_used=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
fi
if [ "$usable_size" -gt 0 ] 2>/dev/null && [ "$ctx_used" -gt 0 ] 2>/dev/null; then
  ctx_percent=$((ctx_used * 100 / usable_size))
  [ "$ctx_percent" -gt 100 ] && ctx_percent=100
  ctx_available="true"
fi

# Default base prompt
get_default_prompt() { echo "${PURPLE}$(whoami)${DIM}@${YELLOW}$(hostname -s)${DIM}:${CYAN}${cwd}${RESET}"; }

# Dynamic base prompt loader
get_base_prompt() {
  [ ! -f "$BASE_CONFIG" ] && { get_default_prompt; return; }
  local type=$(jq -r '.type // "default"' "$BASE_CONFIG" 2>/dev/null)
  local value=$(jq -r '.value // ""' "$BASE_CONFIG" 2>/dev/null)
  case "$type" in
    command) result=$(echo "$input" | eval "$value" 2>/dev/null); [ -n "$result" ] && echo "$result" || get_default_prompt ;;
    text) echo "$value" ;;
    shell) local sh=$(jq -r '.shell // "bash"' "$BASE_CONFIG" 2>/dev/null)
           [ "$sh" = "zsh" ] && result=$(zsh -c 'print -P "$PROMPT"' 2>/dev/null) || result=$(bash -c 'echo -e "$PS1"' 2>/dev/null)
           [ -n "$result" ] && echo "$result" || get_default_prompt ;;
    *) get_default_prompt ;;
  esac
}

BASE=$(get_base_prompt)
BASE_TYPE="default"; [ -f "$BASE_CONFIG" ] && BASE_TYPE=$(jq -r '.type // "default"' "$BASE_CONFIG" 2>/dev/null)

# Git branch (skip if command type - likely includes git)
GIT_PART=""
if [[ "$BASE_TYPE" != "command" ]] && git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null || echo 'HEAD')
  GIT_PART=" ${DIM}›${RESET} ${GREEN}${branch}${RESET}"
  git -C "$cwd" --no-optional-locks diff-index --quiet HEAD -- 2>/dev/null || GIT_PART="${GIT_PART}${YELLOW}*${RESET}"
fi

# Build progress bar helper
build_bar() {
  local pct=$1
  local filled=$((pct / 10)); [ "$filled" -gt 10 ] && filled=10
  local bar=""; for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=filled; i<10; i++)); do bar+="░"; done
  echo "$bar"
}

# Color by percentage
pct_color() { [ "$1" -ge 80 ] && echo "$RED" || { [ "$1" -ge 60 ] && echo "$YELLOW" || echo "$GREEN"; }; }

# Context display
CONTEXT_PART=""
CTX_DISPLAY="off"; CTX_THRESHOLD=80
[ -f "$HUB_CONFIG" ] && { CTX_DISPLAY=$(jq -r '.contextDisplay // "off"' "$HUB_CONFIG" 2>/dev/null); CTX_THRESHOLD=$(jq -r '.contextAlertThreshold // 80' "$HUB_CONFIG" 2>/dev/null); }
if [ "$CTX_DISPLAY" != "off" ] && [ "$ctx_available" = "true" ]; then
  CTX_COLOR=$(pct_color "$ctx_percent")
  case "$CTX_DISPLAY" in
    bar) CONTEXT_PART=" ${DIM}›${RESET} ${CTX_COLOR}[$(build_bar $ctx_percent)]${RESET} ${DIM}${ctx_percent}%${RESET}" ;;
    percent) CONTEXT_PART=" ${DIM}›${RESET} ${CTX_COLOR}${ctx_percent}%${RESET}" ;;
    threshold) [ "$ctx_percent" -ge "$CTX_THRESHOLD" ] && CONTEXT_PART=" ${DIM}›${RESET} ${CTX_COLOR}⚠ ${ctx_percent}%${RESET}" ;;
  esac
fi

# Quota display
QUOTA_PART=""
if [ -f "$HUB_CONFIG" ]; then
  QUOTA_DISPLAY=$(jq -r '.quota.displayFormat // "off"' "$HUB_CONFIG" 2>/dev/null)
  DAILY_LIMIT=$(($(jq -r '.quota.dailyLimit // 45' "$HUB_CONFIG" 2>/dev/null) * 1000))
  if [ "$QUOTA_DISPLAY" != "off" ] && [ "$ctx_used" -gt 0 ] 2>/dev/null && [ "$DAILY_LIMIT" -gt 0 ] 2>/dev/null; then
    QUOTA_PCT=$((ctx_used * 100 / DAILY_LIMIT))
    QUOTA_COLOR=$([ "$QUOTA_PCT" -ge 90 ] && echo "$RED" || { [ "$QUOTA_PCT" -ge 75 ] && echo "$YELLOW" || echo "$GREEN"; })
    case "$QUOTA_DISPLAY" in
      bar) QUOTA_PART=" ${DIM}›${RESET} ${QUOTA_COLOR}⚡[$(build_bar $QUOTA_PCT)]${RESET}" ;;
      number) QUOTA_PART=" ${DIM}›${RESET} ${QUOTA_COLOR}⚡${QUOTA_PCT}%${RESET}" ;;
      compact) QUOTA_PART=" ${DIM}›${RESET} ${QUOTA_COLOR}⚡${QUOTA_PCT}${RESET}" ;;
    esac
  fi
fi

# Error file check (highest priority)
if [ -f "$ERROR_FILE" ]; then
  ERROR_MSG=$(cat "$ERROR_FILE" 2>/dev/null)
  [ -n "$ERROR_MSG" ] && { printf '%b' "${BASE}${GIT_PART}${CONTEXT_PART}${QUOTA_PART} ${DIM}›${RESET} ${RED}⚠ ${ERROR_MSG}${RESET} ${CYAN}>${RESET}"; exit 0; }
fi

# Hub state
FOREGROUND_PART="" BACKGROUND_PART="" DAEMON_STALE_PART=""
if [ -f "$BRIDGE_FILE" ]; then
  BRIDGE_CONTENT=$(cat "$BRIDGE_FILE" 2>/dev/null)
  BRIDGE_TS=$(echo "$BRIDGE_CONTENT" | jq -r '.timestamp // 0')
  FG_COUNT=$(echo "$BRIDGE_CONTENT" | jq -r '.foreground | length')
  HAS_ALERT=$(echo "$BRIDGE_CONTENT" | jq -r '[.foreground[] | select(.hasAlert == true)] | length > 0')

  # Smart stale daemon check: only show skull if user is active but daemon is stale
  # With adaptive intervals, long refresh gaps are expected during idle periods
  NOW_MS=$(( $(date +%s) * 1000 ))
  LAST_ACTIVITY=$(echo "$BRIDGE_CONTENT" | jq -r '.lastActivity // 0')
  ACTIVITY_AGE=$((NOW_MS - LAST_ACTIVITY))
  TIMESTAMP_AGE=$((NOW_MS - BRIDGE_TS))
  # Skull only when: user active (< 3 min) AND timestamp stale (> 3 min)
  [ "$ACTIVITY_AGE" -lt 180000 ] && [ "$TIMESTAMP_AGE" -gt 180000 ] && DAEMON_STALE_PART=" ${DIM}›${RESET} ${RED}💀${RESET}"

  # Background data
  IFS=$'\t' read -r BG_SITE BG_ICON BG_TITLE BG_DETAIL <<< "$(echo "$BRIDGE_CONTENT" | jq -r '[.background.site, .background.icon, .background.title, .background.detail] | @tsv')"

  ERROR_MSG=$(echo "$BRIDGE_CONTENT" | jq -r '.error.message // empty')
  if [ -n "$ERROR_MSG" ]; then
    # ERROR STATE
    FOREGROUND_PART=" ${DIM}›${RESET} ${RED}⚠ ${ERROR_MSG}${RESET}"
    [ -n "$BG_SITE" ] && [ -n "$BG_TITLE" ] && BACKGROUND_PART=" ${DIM}›${RESET} ${MAGENTA}${BG_ICON} ${BG_TITLE:0:25} - ${BG_DETAIL:0:15}${RESET}"
  elif [ "$HAS_ALERT" = "true" ] && [ "$FG_COUNT" -gt 0 ]; then
    # ALERT STATE
    IFS=$'\t' read -r FG_ICON FG_TITLE FG_DETAIL FG_AUTO <<< "$(echo "$BRIDGE_CONTENT" | jq -r '([.foreground[] | select(.hasAlert == true)][0] // {}) | [.icon, .title, .detail, (.autoMerge // false | tostring)] | @tsv')"
    [ "$FG_AUTO" = "true" ] && FG_ICON="${FG_ICON}🔁"
    FOREGROUND_PART=" ${DIM}›${RESET} ${RED}${FG_ICON} ${FG_TITLE} ${FG_DETAIL}${RESET}"
    [ -n "$BG_ICON" ] && [ "$BG_ICON" != "off" ] && [ "$BG_SITE" != "off" ] && [ "$BG_SITE" != "--background" ] && BACKGROUND_PART=" ${DIM}›${RESET} ${MAGENTA}${BG_ICON}${RESET}"
  else
    # IDLE STATE
    [ -n "$BG_SITE" ] && [ "$BG_SITE" != "off" ] && [ "$BG_SITE" != "--background" ] && [ -n "$BG_TITLE" ] && BACKGROUND_PART=" ${DIM}›${RESET} ${MAGENTA}${BG_ICON} ${BG_TITLE:0:25} - ${BG_DETAIL:0:15}${RESET}"
    if [ "$FG_COUNT" -gt 0 ]; then
      PR_COUNT=$(echo "$BRIDGE_CONTENT" | jq -r '[.foreground[] | select(.site == "github-pr")] | length')
      PR_AUTO=$(echo "$BRIDGE_CONTENT" | jq -r '[.foreground[] | select(.site == "github-pr" and .autoMerge == true)] | length')
      OTHER=$((FG_COUNT - PR_COUNT))
      FG_PARTS=""
      if [ "$PR_COUNT" -gt 0 ]; then
        LBL="PRs"; [ "$PR_COUNT" = "1" ] && LBL="PR"
        [ "$PR_AUTO" -gt 0 ] && FG_PARTS="${PR_COUNT}🔁 ${LBL}" || FG_PARTS="${PR_COUNT} ${LBL}"
      fi
      if [ "$OTHER" -gt 0 ]; then
        IFS=$'\t' read -r O_ICON O_TITLE O_DETAIL <<< "$(echo "$BRIDGE_CONTENT" | jq -r '([.foreground[] | select(.site != "github-pr")][0] // {}) | [.icon // "•", .title // "", .detail // ""] | @tsv')"
        [ -n "$FG_PARTS" ] && FG_PARTS+=" "
        [ -n "$O_DETAIL" ] && FG_PARTS+="${O_ICON} ${O_TITLE:0:10} ${O_DETAIL:0:20}" || FG_PARTS+="${O_ICON} ${O_TITLE:0:10}"
      fi
      FOREGROUND_PART=" ${DIM}›${RESET} ${DIM}${FG_PARTS}${RESET}"
    fi
  fi

  # Notification (green, expires)
  NOTIF_MSG=$(echo "$BRIDGE_CONTENT" | jq -r '.notification.message // empty')
  NOTIF_EXP=$(echo "$BRIDGE_CONTENT" | jq -r '.notification.expires // 0')
  NOW_MS=$(($(date +%s) * 1000))
  [ -n "$NOTIF_MSG" ] && [ "$NOTIF_EXP" -gt "$NOW_MS" ] 2>/dev/null && FOREGROUND_PART+=" ${DIM}›${RESET} ${GREEN}${NOTIF_MSG}${RESET}"
fi

printf '%b' "${BASE}${GIT_PART}${CONTEXT_PART}${QUOTA_PART}${DAEMON_STALE_PART}${BACKGROUND_PART}${FOREGROUND_PART} ${CYAN}>${RESET}"
