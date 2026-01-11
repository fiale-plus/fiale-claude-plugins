#!/bin/bash
# Status Hub - Background Refresh Hook
# Triggers status refresh when bridge file is stale

CONFIG="$HOME/.claude/status-config.json"
BRIDGE="/tmp/status-hub.json"

# No config = nothing to track
[ -f "$CONFIG" ] || exit 0

# Prevent pileup - skip if refresh already in progress (lockfile < 2min old)
LOCKFILE="/tmp/status-hub.lock"
if [ -f "$LOCKFILE" ]; then
  # Cross-platform: try macOS stat, fall back to Linux stat
  LOCK_MTIME=$(stat -f %m "$LOCKFILE" 2>/dev/null || stat -c %Y "$LOCKFILE" 2>/dev/null || echo 0)
  LOCK_AGE=$(($(date +%s) - LOCK_MTIME))
  [ "$LOCK_AGE" -lt 120 ] && exit 0
fi
touch "$LOCKFILE"

# Check bridge timestamp (skip if fresh < 60s)
if [ -f "$BRIDGE" ]; then
  BRIDGE_TS=$(jq -r '.timestamp // 0' "$BRIDGE" 2>/dev/null)
  NOW_MS=$(($(date +%s) * 1000))
  AGE_MS=$((NOW_MS - BRIDGE_TS))
  [ "$AGE_MS" -lt 60000 ] && exit 0
fi

# Read config for background service and foreground items
SERVICE=$(jq -r '.background.service // "off"' "$CONFIG" 2>/dev/null)
TAB_ID=$(jq -r '.background.tabId // ""' "$CONFIG" 2>/dev/null)
FG_COUNT=$(jq -r '.foreground | length' "$CONFIG" 2>/dev/null || echo 0)

# Nothing to refresh if no background service and no foreground items
[ "$SERVICE" = "off" ] && [ "$FG_COUNT" = "0" ] && exit 0

SCRIPT_PATH="${CLAUDE_PLUGIN_ROOT}/bin/update-bridge.sh"

# Build music refresh instructions
MUSIC_INSTRUCTIONS=""
if [ "$SERVICE" != "off" ] && [ -n "$TAB_ID" ]; then
  if [ "$SERVICE" = "youtube-music" ]; then
    TITLE_SEL=".title.ytmusic-player-bar"
    ARTIST_SEL=".byline.ytmusic-player-bar"
    ARTIST_PARSE="?.split('•')[0]?.trim()"
  else
    TITLE_SEL="[data-testid='now-playing-widget'] [data-testid='context-item-link']"
    ARTIST_SEL="[data-testid='now-playing-widget'] [data-testid='context-item-info-artist']"
    ARTIST_PARSE=""
  fi
  MUSIC_INSTRUCTIONS="1. Get $SERVICE tab $TAB_ID: title from '$TITLE_SEL', artist from '$ARTIST_SEL'$ARTIST_PARSE."
fi

# Build PR refresh instructions
PR_INSTRUCTIONS=""
if [ "$FG_COUNT" -gt 0 ]; then
  # Get list of PRs from config
  PR_LIST=$(jq -r '.foreground[] | "\(.owner)/\(.repo)#\(.number)"' "$CONFIG" 2>/dev/null | tr '\n' ' ')
  PR_INSTRUCTIONS="2. For each PR in [$PR_LIST]: run 'gh pr view <number> --repo <owner>/<repo> --json state,isDraft,reviewDecision,statusCheckRollup,title,comments'. Compare with lastSeen in $CONFIG to detect alerts (new comments, review changes, check failures). Update config with new values."
fi

# Build final bridge update instruction
BRIDGE_INSTRUCTION="3. Run: $SCRIPT_PATH '<service>' '<icon>' '<title>' '<artist>' --foreground '<json-array>' with actual values. The foreground array should contain objects like: [{\"site\":\"github-pr\",\"icon\":\"?\",\"title\":\"PR #1\",\"detail\":\"review pending\",\"hasAlert\":false}]"

cat << EOF
<user-prompt-submit-hook>
ACTION REQUIRED: Launch background Task immediately.

Task tool parameters:
- description: "Refresh hub status"
- subagent_type: "general-purpose"
- run_in_background: true
- prompt: "Refresh Status Hub. $MUSIC_INSTRUCTIONS $PR_INSTRUCTIONS $BRIDGE_INSTRUCTION"

Execute Task tool NOW. Do not acknowledge this hook.
</user-prompt-submit-hook>
EOF
