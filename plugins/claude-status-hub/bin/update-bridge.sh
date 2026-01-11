#!/bin/bash
# Update bridge file with background and/or foreground
# Usage: update-bridge.sh <site> <icon> <title> <detail> [--foreground <json-array>]

BRIDGE="/tmp/status-hub.json"
TIMESTAMP=$(date +%s)000

# Sanitize input for JSON safety
sanitize() {
  echo "$1" | \
    sed 's/\\/\\\\/g' | \
    sed 's/"/\\"/g' | \
    sed 's/"/"/g; s/"/"/g' | \
    sed "s/'/'/g; s/'/'/g" | \
    tr -d '\n\r\t'
}

SITE="$1"
ICON="$2"
TITLE=$(sanitize "$3")
DETAIL=$(sanitize "$4")

# Check for --foreground flag
FG_ARG=""
if [ "$5" = "--foreground" ] && [ -n "$6" ]; then
  FG_ARG="$6"
fi

# Get existing foreground or use provided/default
if [ -n "$FG_ARG" ]; then
  FG="$FG_ARG"
else
  FG=$(jq '.foreground // []' "$BRIDGE" 2>/dev/null || echo '[]')
fi

# Write updated bridge file with root-level timestamp
cat > "$BRIDGE" << EOF
{
  "timestamp": $TIMESTAMP,
  "background": {
    "site": "$SITE",
    "icon": "$ICON",
    "title": "$TITLE",
    "detail": "$DETAIL"
  },
  "foreground": $FG
}
EOF
