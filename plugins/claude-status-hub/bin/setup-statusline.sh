#!/bin/bash
# Status Hub - Session Setup
# Ensures config files exist on session start

CONFIG="$HOME/.claude/status-config.json"
BRIDGE="/tmp/status-hub.json"

# Ensure status config exists
if [ ! -f "$CONFIG" ]; then
  echo '{"background": null, "foreground": []}' > "$CONFIG"
fi

# Ensure bridge file exists
if [ ! -f "$BRIDGE" ]; then
  echo '{"timestamp": null, "background": null, "foreground": []}' > "$BRIDGE"
fi

echo "Success"
