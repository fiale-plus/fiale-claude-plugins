#!/bin/bash
# Update bridge file with background and/or foreground
# Usage: update-bridge.sh <site> <icon> <title> <detail> [--foreground <json-array>]
#        update-bridge.sh --error "Error message"
#        update-bridge.sh --clear-error

BRIDGE="/tmp/status-hub.json"
ERROR_FILE="/tmp/status-hub-error.txt"
TIMESTAMP=$(date +%s)000

# Handle --error flag (write to error file)
if [ "$1" = "--error" ]; then
  echo "$2" > "$ERROR_FILE"
  exit 0
fi

# Handle --clear-error flag
if [ "$1" = "--clear-error" ]; then
  rm -f "$ERROR_FILE" 2>/dev/null
  exit 0
fi

# Sanitize input for JSON safety
sanitize() {
  echo "$1" | sed -e 's/\\/\\\\/g' \
                  -e 's/"/\\"/g' \
                  -e 's/"/"/g' -e 's/"/"/g' \
                  -e "s/'/'/g" -e "s/'/'/g" | tr -d '\n\r\t'
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

# Get foreground: use provided array directly, or preserve existing
if [ -n "$FG_ARG" ]; then
  # Use provided foreground array as-is (hub-refresh passes complete list)
  FG="$FG_ARG"
else
  # No foreground provided - preserve existing
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

# Clear error file on successful write
rm -f "$ERROR_FILE" 2>/dev/null
