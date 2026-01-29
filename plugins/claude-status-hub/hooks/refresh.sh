#!/bin/bash
# Status Hub - User Activity Hook
# ONLY updates lastActivity timestamp for adaptive daemon intervals.
# The daemon handles all refreshes - this hook does NOT spawn Claude CLI.

BRIDGE="/tmp/status-hub.json"

# Update lastActivity timestamp (resets daemon's adaptive interval)
NOW_MS=$(($(date +%s) * 1000))
if [ -f "$BRIDGE" ]; then
  jq --argjson ts "$NOW_MS" '.lastActivity = $ts' "$BRIDGE" > "${BRIDGE}.tmp" && mv "${BRIDGE}.tmp" "$BRIDGE"
fi

exit 0
