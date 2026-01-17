#!/bin/bash
# Status Hub - Session Setup
# Ensures config files exist on session start

CONFIG="$HOME/.claude/status-config.json"
BRIDGE="/tmp/status-hub.json"

# Ensure status config exists
if [ ! -f "$CONFIG" ]; then
  echo '{"background": null, "foreground": []}' > "$CONFIG"
fi

# Ensure bridge file exists with valid timestamp
if [ ! -f "$BRIDGE" ]; then
  NOW_MS=$(($(date +%s) * 1000))
  echo "{\"timestamp\": $NOW_MS, \"background\": null, \"foreground\": []}" > "$BRIDGE"
else
  # Migration: fix null/missing timestamp in existing bridge files (pre-v1.0.2)
  EXISTING_TS=$(jq -r '.timestamp // "null"' "$BRIDGE" 2>/dev/null)
  if [ "$EXISTING_TS" = "null" ] || [ -z "$EXISTING_TS" ]; then
    NOW_MS=$(($(date +%s) * 1000))
    # Preserve existing state, just add valid timestamp
    jq --argjson ts "$NOW_MS" '.timestamp = $ts' "$BRIDGE" > "${BRIDGE}.tmp" && mv "${BRIDGE}.tmp" "$BRIDGE"
  fi
fi

echo "Success"
