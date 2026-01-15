#!/bin/bash
# Reset quota tracking on session start

QUOTA_FILE="/tmp/status-hub-quota.json"
CONFIG="$HOME/.claude/status-config.json"

# Get estimated limit from config (based on plan tier)
ESTIMATED_LIMIT=45000
if [ -f "$CONFIG" ]; then
  PLAN=$(jq -r '.quota.plan // "pro"' "$CONFIG" 2>/dev/null)
  case "$PLAN" in
    pro)
      ESTIMATED_LIMIT=45000
      ;;
    max5)
      ESTIMATED_LIMIT=150000
      ;;
    max20)
      ESTIMATED_LIMIT=600000
      ;;
    *)
      # Custom limit
      CUSTOM_LIMIT=$(jq -r '.quota.dailyLimit // 45' "$CONFIG" 2>/dev/null)
      ESTIMATED_LIMIT=$((CUSTOM_LIMIT * 1000))
      ;;
  esac
fi

# Generate new session ID
SESSION_ID="session-$(date +%s)"

# Reset quota file
cat > "$QUOTA_FILE" << EOF
{
  "sessionId": "$SESSION_ID",
  "startTime": $(date +%s%3N),
  "tokensUsed": 0,
  "estimatedLimit": $ESTIMATED_LIMIT,
  "toolCalls": 0,
  "lastUpdate": $(date +%s%3N)
}
EOF
