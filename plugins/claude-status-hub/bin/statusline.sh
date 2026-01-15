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
BASE_CONFIG="${HOME}/.claude/status-base-config.json"
HUB_CONFIG="${HOME}/.claude/status-config.json"
QUOTA_FILE="/tmp/status-hub-quota.json"
PLAY_ICON="▶"
PAUSE_ICON="⏸"

# Read Claude Code's context JSON (stdin)
input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // "~"')

# Extract context window usage
# Calculate against USABLE space (excluding autocompact buffer) to show proximity to compaction
ctx_percent=0
ctx_available="false"
USAGE=$(echo "$input" | jq '.context_window.current_usage')
ctx_size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
# Autocompact buffer is ~22.5% of context - calculate usable space
buffer=$((ctx_size * 225 / 1000))
usable_size=$((ctx_size - buffer))

if [ "$USAGE" != "null" ] && [ -n "$USAGE" ]; then
  # Calculate from current_usage fields (as per docs)
  ctx_used=$(echo "$USAGE" | jq -r '.input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens // 0')
  if [ "$usable_size" -gt 0 ] 2>/dev/null && [ "$ctx_used" -gt 0 ] 2>/dev/null; then
    ctx_percent=$((ctx_used * 100 / usable_size))
    [ "$ctx_percent" -gt 100 ] && ctx_percent=100  # Cap at 100%
    ctx_available="true"
  fi
else
  # Fallback: use total_input_tokens (cumulative, not ideal but something)
  ctx_used=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
  if [ "$usable_size" -gt 0 ] 2>/dev/null && [ "$ctx_used" -gt 0 ] 2>/dev/null; then
    ctx_percent=$((ctx_used * 100 / usable_size))
    [ "$ctx_percent" -gt 100 ] && ctx_percent=100  # Cap at 100%
    ctx_available="true"
  fi
fi

# Default base prompt function
get_default_prompt() {
    echo "${PURPLE}$(whoami)${DIM}@${YELLOW}$(hostname -s)${DIM}:${CYAN}${cwd}${RESET}"
}

# Dynamic base prompt loader
get_base_prompt() {
    if [[ ! -f "$BASE_CONFIG" ]]; then
        get_default_prompt
        return
    fi

    local type=$(jq -r '.type // "default"' "$BASE_CONFIG" 2>/dev/null)
    local value=$(jq -r '.value // ""' "$BASE_CONFIG" 2>/dev/null)

    case "$type" in
        command)
            # Run user's original statusline command, pass through context
            local result=$(echo "$input" | eval "$value" 2>/dev/null)
            if [ -n "$result" ]; then
                echo "$result"
            else
                get_default_prompt
            fi
            ;;
        text)
            # Use static text directly
            echo "$value"
            ;;
        shell)
            # Evaluate shell prompt variable
            local shell_type=$(jq -r '.shell // "bash"' "$BASE_CONFIG" 2>/dev/null)
            local prompt_result=""
            if [[ "$shell_type" == "zsh" ]]; then
                prompt_result=$(zsh -c 'print -P "$PROMPT"' 2>/dev/null)
            else
                prompt_result=$(bash -c 'echo -e "$PS1"' 2>/dev/null)
            fi
            if [ -n "$prompt_result" ]; then
                echo "$prompt_result"
            else
                get_default_prompt
            fi
            ;;
        *)
            get_default_prompt
            ;;
    esac
}

# Build base prompt (dynamic or default)
BASE=$(get_base_prompt)

# Check if base config uses "command" type (skip git since original command likely includes it)
BASE_TYPE="default"
if [[ -f "$BASE_CONFIG" ]]; then
  BASE_TYPE=$(jq -r '.type // "default"' "$BASE_CONFIG" 2>/dev/null)
fi

# Add git branch if in repo AND not using a preserved command (which likely already has git)
GIT_PART=""
if [[ "$BASE_TYPE" != "command" ]] && git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null || echo 'HEAD')
  GIT_PART=" ${DIM}›${RESET} ${GREEN}${branch}${RESET}"
  git -C "$cwd" --no-optional-locks diff-index --quiet HEAD -- 2>/dev/null || GIT_PART="${GIT_PART}${YELLOW}*${RESET}"
fi

# Build context display part
CONTEXT_PART=""
if [ -f "$HUB_CONFIG" ]; then
  CTX_DISPLAY=$(jq -r '.contextDisplay // "off"' "$HUB_CONFIG" 2>/dev/null)
  CTX_THRESHOLD=$(jq -r '.contextAlertThreshold // 80' "$HUB_CONFIG" 2>/dev/null)
else
  CTX_DISPLAY="off"
  CTX_THRESHOLD=80
fi

if [ "$CTX_DISPLAY" != "off" ] && [ "$ctx_available" = "true" ]; then
  # Determine color based on usage
  if [ "$ctx_percent" -ge 80 ]; then
    CTX_COLOR="$RED"
  elif [ "$ctx_percent" -ge 60 ]; then
    CTX_COLOR="$YELLOW"
  else
    CTX_COLOR="$GREEN"
  fi

  case "$CTX_DISPLAY" in
    bar)
      # Build 10-char progress bar: [████░░░░░░ 42%]
      filled=$((ctx_percent / 10))
      # Cap at 10 to prevent overflow
      [ "$filled" -gt 10 ] && filled=10
      empty=$((10 - filled))
      BAR=""
      for ((i=0; i<filled; i++)); do BAR="${BAR}█"; done
      for ((i=0; i<empty; i++)); do BAR="${BAR}░"; done
      CONTEXT_PART=" ${DIM}›${RESET} ${CTX_COLOR}[${BAR}]${RESET} ${DIM}${ctx_percent}%${RESET}"
      ;;
    percent)
      CONTEXT_PART=" ${DIM}›${RESET} ${CTX_COLOR}${ctx_percent}%${RESET}"
      ;;
    threshold)
      # Only show if above threshold
      if [ "$ctx_percent" -ge "$CTX_THRESHOLD" ]; then
        CONTEXT_PART=" ${DIM}›${RESET} ${CTX_COLOR}⚠ ${ctx_percent}%${RESET}"
      fi
      ;;
  esac
fi

# Build quota display part (from PostToolUse tracking)
QUOTA_PART=""
if [ -f "$HUB_CONFIG" ] && [ -f "$QUOTA_FILE" ]; then
  QUOTA_DISPLAY=$(jq -r '.quota.displayFormat // "off"' "$HUB_CONFIG" 2>/dev/null)
  QUOTA_THRESHOLD=$(jq -r '.quota.alertThreshold // 80' "$HUB_CONFIG" 2>/dev/null)

  if [ "$QUOTA_DISPLAY" != "off" ]; then
    TOKENS_USED=$(jq -r '.tokensUsed // 0' "$QUOTA_FILE" 2>/dev/null)
    ESTIMATED_LIMIT=$(jq -r '.estimatedLimit // 45000' "$QUOTA_FILE" 2>/dev/null)

    if [ "$ESTIMATED_LIMIT" -gt 0 ] 2>/dev/null; then
      QUOTA_PERCENT=$((TOKENS_USED * 100 / ESTIMATED_LIMIT))

      # Determine color
      if [ "$QUOTA_PERCENT" -ge 90 ]; then
        QUOTA_COLOR="$RED"
      elif [ "$QUOTA_PERCENT" -ge 75 ]; then
        QUOTA_COLOR="$YELLOW"
      else
        QUOTA_COLOR="$GREEN"
      fi

      case "$QUOTA_DISPLAY" in
        bar)
          filled=$((QUOTA_PERCENT / 10))
          [ "$filled" -gt 10 ] && filled=10
          empty=$((10 - filled))
          BAR=""
          for ((i=0; i<filled; i++)); do BAR="${BAR}█"; done
          for ((i=0; i<empty; i++)); do BAR="${BAR}░"; done
          QUOTA_PART=" ${DIM}›${RESET} ${QUOTA_COLOR}⚡[${BAR}]${RESET}"
          ;;
        number)
          QUOTA_PART=" ${DIM}›${RESET} ${QUOTA_COLOR}⚡${QUOTA_PERCENT}%${RESET}"
          ;;
        compact)
          QUOTA_PART=" ${DIM}›${RESET} ${QUOTA_COLOR}⚡${QUOTA_PERCENT}${RESET}"
          ;;
      esac
    fi
  fi
fi

# Check for error file first (highest priority)
if [ -f "$ERROR_FILE" ]; then
  ERROR_MSG=$(cat "$ERROR_FILE" 2>/dev/null)
  if [ -n "$ERROR_MSG" ]; then
    printf '%b' "${BASE}${GIT_PART}${CONTEXT_PART}${QUOTA_PART} ${DIM}›${RESET} ${RED}⚠ ${ERROR_MSG}${RESET} ${CYAN}>${RESET}"
    exit 0
  fi
fi

# Check for hub state
FOREGROUND_PART=""
BACKGROUND_PART=""
DAEMON_STALE_PART=""

if [ -f "$BRIDGE_FILE" ]; then
  # Read timestamp from JSON (milliseconds)
  BRIDGE_TS=$(jq -r '.timestamp // 0' "$BRIDGE_FILE" 2>/dev/null)
  NOW_MS=$(($(date +%s) * 1000))
  AGE_MS=$((NOW_MS - BRIDGE_TS))

  # Check if daemon is stale (no update in >3 minutes = 180000ms)
  if [ "$AGE_MS" -gt 180000 ]; then
    DAEMON_STALE_PART=" ${DIM}›${RESET} ${RED}💀${RESET}"
  fi

  # Process hub data (no stale warning - just show last known status)
  if true; then
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

# Combine all parts (order: base > git > context > quota > daemon-stale > background > foreground)
printf '%b' "${BASE}${GIT_PART}${CONTEXT_PART}${QUOTA_PART}${DAEMON_STALE_PART}${BACKGROUND_PART}${FOREGROUND_PART} ${CYAN}>${RESET}"
