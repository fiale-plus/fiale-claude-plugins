#!/bin/bash
# Claude Code Status Line with Hub Integration
# Combines git status with hub state from /tmp/status-hub.json

# ANSI colors
PURPLE='\033[35m'
CYAN='\033[36m'
YELLOW='\033[33m'
RED='\033[31m'
GREEN='\033[32m'
MAGENTA='\033[95m'
RESET='\033[0m'

# Read Claude Code's context JSON (stdin)
input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // "~"')

# Build base prompt (user@host:dir)
DIM='\033[2m'
BASE="${PURPLE}$(whoami)${DIM}@${YELLOW}$(hostname -s)${DIM}:${CYAN}${cwd}${RESET}"

# Add git branch if in repo
GIT_PART=""
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null || echo 'HEAD')
  GIT_PART=" ${DIM}›${RESET} ${GREEN}${branch}${RESET}"
  git -C "$cwd" --no-optional-locks diff-index --quiet HEAD -- 2>/dev/null || GIT_PART="${GIT_PART}${YELLOW}*${RESET}"
fi

# Check for hub state
FOREGROUND_PART=""
BACKGROUND_PART=""
BRIDGE_FILE="/tmp/status-hub.json"

if [ -f "$BRIDGE_FILE" ]; then
  # Read timestamp from JSON (milliseconds)
  BRIDGE_TS=$(jq -r '.timestamp // 0' "$BRIDGE_FILE" 2>/dev/null)
  NOW_MS=$(($(date +%s) * 1000))
  AGE_MS=$((NOW_MS - BRIDGE_TS))

  # Only use data if fresh (< 300s = 300000ms for display)
  # Note: Hook refreshes at 60s, but we display up to 5min to avoid gaps between prompts
  if [ "$AGE_MS" -lt 300000 ]; then
    # Read foreground array - find first with alert or count them
    FG_COUNT=$(jq -r '.foreground | length' "$BRIDGE_FILE" 2>/dev/null || echo 0)
    HAS_ALERT=$(jq -r '[.foreground[] | select(.hasAlert == true)] | length > 0' "$BRIDGE_FILE" 2>/dev/null || echo false)

    # Get first item with alert, or first item if none have alerts
    if [ "$HAS_ALERT" = "true" ]; then
      FG_ICON=$(jq -r '[.foreground[] | select(.hasAlert == true)][0].icon // empty' "$BRIDGE_FILE" 2>/dev/null)
      FG_TITLE=$(jq -r '[.foreground[] | select(.hasAlert == true)][0].title // empty' "$BRIDGE_FILE" 2>/dev/null)
      FG_DETAIL=$(jq -r '[.foreground[] | select(.hasAlert == true)][0].detail // empty' "$BRIDGE_FILE" 2>/dev/null)
    else
      FG_ICON=$(jq -r '.foreground[0].icon // empty' "$BRIDGE_FILE" 2>/dev/null)
      FG_TITLE=$(jq -r '.foreground[0].title // empty' "$BRIDGE_FILE" 2>/dev/null)
      FG_DETAIL=$(jq -r '.foreground[0].detail // empty' "$BRIDGE_FILE" 2>/dev/null)
    fi

    # Read background (music, etc)
    BG_SITE=$(jq -r '.background.site // empty' "$BRIDGE_FILE" 2>/dev/null)
    BG_ICON=$(jq -r '.background.icon // empty' "$BRIDGE_FILE" 2>/dev/null)
    BG_TITLE=$(jq -r '.background.title // empty' "$BRIDGE_FILE" 2>/dev/null)
    BG_DETAIL=$(jq -r '.background.detail // empty' "$BRIDGE_FILE" 2>/dev/null)

    if [ "$HAS_ALERT" = "true" ] && [ "$FG_COUNT" -gt 0 ]; then
      # ALERT STATE: foreground expanded, background compact
      FOREGROUND_PART=" ${DIM}›${RESET} ${RED}${FG_ICON} ${FG_TITLE} ${FG_DETAIL}${RESET}"
      if [ -n "$BG_SITE" ] && [ -n "$BG_ICON" ]; then
        BACKGROUND_PART=" ${DIM}›${RESET} ${MAGENTA}${BG_ICON}${RESET}"
      fi
    else
      # IDLE STATE: background expanded, foreground compact (count only)
      if [ -n "$BG_SITE" ] && [ -n "$BG_TITLE" ]; then
        TITLE_SHORT=$(echo "$BG_TITLE" | cut -c1-25)
        DETAIL_SHORT=$(echo "$BG_DETAIL" | cut -c1-15)
        BACKGROUND_PART=" ${DIM}›${RESET} ${MAGENTA}${BG_ICON} ${TITLE_SHORT} - ${DETAIL_SHORT}${RESET}"
      fi
      if [ "$FG_COUNT" -gt 0 ]; then
        PR_LABEL="PRs"; [ "$FG_COUNT" = "1" ] && PR_LABEL="PR"
        FOREGROUND_PART=" ${DIM}›${RESET} ${DIM}${FG_COUNT} ${PR_LABEL}${RESET}"
      fi
    fi
  fi
fi

# Combine all parts (order: base prompt > background > foreground - always same order)
printf "${BASE}${GIT_PART}${BACKGROUND_PART}${FOREGROUND_PART} ${CYAN}>${RESET}"
