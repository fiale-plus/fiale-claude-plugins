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
DIM='\033[2m'

# Constants
ERROR_FILE="/tmp/status-hub-error.txt"
BRIDGE_FILE="/tmp/status-hub.json"
PLAY_ICON="▶"
PAUSE_ICON="⏸"

# Read Claude Code's context JSON (stdin)
input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // "~"')

# Build base prompt (user@host:dir)
BASE="${PURPLE}$(whoami)${DIM}@${YELLOW}$(hostname -s)${DIM}:${CYAN}${cwd}${RESET}"

# Add git branch if in repo
GIT_PART=""
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null || echo 'HEAD')
  GIT_PART=" ${DIM}›${RESET} ${GREEN}${branch}${RESET}"
  git -C "$cwd" --no-optional-locks diff-index --quiet HEAD -- 2>/dev/null || GIT_PART="${GIT_PART}${YELLOW}*${RESET}"
fi

# Check for error file first (highest priority)
if [ -f "$ERROR_FILE" ]; then
  ERROR_MSG=$(cat "$ERROR_FILE" 2>/dev/null)
  if [ -n "$ERROR_MSG" ]; then
    printf '%b' "${BASE}${GIT_PART} ${DIM}›${RESET} ${RED}⚠ ${ERROR_MSG}${RESET} ${CYAN}>${RESET}"
    exit 0
  fi
fi

# Check for hub state
FOREGROUND_PART=""
BACKGROUND_PART=""

if [ -f "$BRIDGE_FILE" ]; then
  # Read timestamp from JSON (milliseconds)
  BRIDGE_TS=$(jq -r '.timestamp // 0' "$BRIDGE_FILE" 2>/dev/null)
  NOW_MS=$(($(date +%s) * 1000))
  AGE_MS=$((NOW_MS - BRIDGE_TS))

  # Check for stale data (> 5 minutes old)
  if [ "$AGE_MS" -ge 300000 ]; then
    printf '%b' "${BASE}${GIT_PART} ${DIM}›${RESET} ${YELLOW}⚠ Status stale${RESET} ${CYAN}>${RESET}"
    exit 0
  fi

  # Data is fresh, process it
  if [ "$AGE_MS" -lt 300000 ]; then
    # Check for refresh errors first
    ERROR_MSG=$(jq -r '.error.message // empty' "$BRIDGE_FILE" 2>/dev/null)
    HAS_ERROR="false"
    if [ -n "$ERROR_MSG" ]; then
      HAS_ERROR="true"
      FOREGROUND_PART=" ${DIM}›${RESET} ${RED}⚠ ${ERROR_MSG}${RESET}"
      # Still show background if available, but skip foreground processing
    fi

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

    if [ "$HAS_ERROR" = "true" ]; then
      # ERROR STATE: error already in FOREGROUND_PART, just add background
      if [ -n "$BG_SITE" ] && [ -n "$BG_TITLE" ]; then
        TITLE_SHORT=$(echo "$BG_TITLE" | cut -c1-25)
        DETAIL_SHORT=$(echo "$BG_DETAIL" | cut -c1-15)
        BACKGROUND_PART=" ${DIM}›${RESET} ${MAGENTA}${BG_ICON} ${TITLE_SHORT} - ${DETAIL_SHORT}${RESET}"
      fi
    elif [ "$HAS_ALERT" = "true" ] && [ "$FG_COUNT" -gt 0 ]; then
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
        # Count PRs specifically (items with site=github-pr)
        PR_COUNT=$(jq -r '[.foreground[] | select(.site == "github-pr")] | length' "$BRIDGE_FILE" 2>/dev/null || echo 0)
        OTHER_COUNT=$((FG_COUNT - PR_COUNT))

        FG_PARTS=""
        if [ "$PR_COUNT" -gt 0 ]; then
          PR_LABEL="PRs"; [ "$PR_COUNT" = "1" ] && PR_LABEL="PR"
          FG_PARTS="${PR_COUNT} ${PR_LABEL}"
        fi
        if [ "$OTHER_COUNT" -gt 0 ]; then
          # Show first non-PR item's icon, title and detail
          OTHER_ICON=$(jq -r '[.foreground[] | select(.site != "github-pr")][0].icon // "•"' "$BRIDGE_FILE" 2>/dev/null)
          OTHER_TITLE=$(jq -r '[.foreground[] | select(.site != "github-pr")][0].title // ""' "$BRIDGE_FILE" 2>/dev/null | cut -c1-10)
          OTHER_DETAIL=$(jq -r '[.foreground[] | select(.site != "github-pr")][0].detail // ""' "$BRIDGE_FILE" 2>/dev/null | cut -c1-20)
          [ -n "$FG_PARTS" ] && FG_PARTS="${FG_PARTS} "
          if [ -n "$OTHER_DETAIL" ]; then
            FG_PARTS="${FG_PARTS}${OTHER_ICON} ${OTHER_TITLE} ${OTHER_DETAIL}"
          else
            FG_PARTS="${FG_PARTS}${OTHER_ICON} ${OTHER_TITLE}"
          fi
        fi
        FOREGROUND_PART=" ${DIM}›${RESET} ${DIM}${FG_PARTS}${RESET}"
      fi
    fi
  fi
fi

# Combine all parts (order: base prompt > background > foreground - always same order)
printf '%b' "${BASE}${GIT_PART}${BACKGROUND_PART}${FOREGROUND_PART} ${CYAN}>${RESET}"
