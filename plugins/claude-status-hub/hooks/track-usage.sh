#!/bin/bash
# Track token usage via PostToolUse hook
# Estimates tokens from tool input/output and updates quota file

QUOTA_FILE="/tmp/status-hub-quota.json"
CONFIG="$HOME/.claude/status-config.json"

# Always track if plugin config exists (display is separate from tracking)
[ ! -f "$CONFIG" ] && exit 0

# Get tool input/output from environment (set by Claude Code hooks)
TOOL_INPUT="${TOOL_INPUT:-}"
TOOL_OUTPUT="${TOOL_OUTPUT:-}"

# Estimate tokens: roughly 4 chars per token
INPUT_CHARS=${#TOOL_INPUT}
OUTPUT_CHARS=${#TOOL_OUTPUT}
TOTAL_CHARS=$((INPUT_CHARS + OUTPUT_CHARS))
ESTIMATED_TOKENS=$((TOTAL_CHARS / 4))

# Minimum 10 tokens per tool call
[ "$ESTIMATED_TOKENS" -lt 10 ] && ESTIMATED_TOKENS=10

# Initialize quota file if it doesn't exist
if [ ! -f "$QUOTA_FILE" ]; then
  SESSION_ID="${SESSION_ID:-$(date +%s)}"
  NOW_MS=$(($(date +%s) * 1000))
  echo "{\"sessionId\":\"$SESSION_ID\",\"startTime\":$NOW_MS,\"tokensUsed\":0,\"estimatedLimit\":45000,\"toolCalls\":0}" > "$QUOTA_FILE"
fi

# Read current values
CURRENT_TOKENS=$(jq -r '.tokensUsed // 0' "$QUOTA_FILE" 2>/dev/null)
CURRENT_CALLS=$(jq -r '.toolCalls // 0' "$QUOTA_FILE" 2>/dev/null)
SESSION_ID=$(jq -r '.sessionId // ""' "$QUOTA_FILE" 2>/dev/null)
START_TIME=$(jq -r '.startTime // 0' "$QUOTA_FILE" 2>/dev/null)
ESTIMATED_LIMIT=$(jq -r '.estimatedLimit // 45000' "$QUOTA_FILE" 2>/dev/null)

# Update values
NEW_TOKENS=$((CURRENT_TOKENS + ESTIMATED_TOKENS))
NEW_CALLS=$((CURRENT_CALLS + 1))

# Write updated quota file
NOW_MS=$(($(date +%s) * 1000))
cat > "$QUOTA_FILE" << EOF
{
  "sessionId": "$SESSION_ID",
  "startTime": $START_TIME,
  "tokensUsed": $NEW_TOKENS,
  "estimatedLimit": $ESTIMATED_LIMIT,
  "toolCalls": $NEW_CALLS,
  "lastUpdate": $NOW_MS
}
EOF
