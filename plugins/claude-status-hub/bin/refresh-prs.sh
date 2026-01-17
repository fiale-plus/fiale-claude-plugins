#!/bin/bash
# Lightweight PR refresh - runs from daemon, pure bash (no Claude CLI)
# Reads tracked PRs from config, fetches status via gh, updates bridge foreground

CONFIG="$HOME/.claude/status-config.json"
BRIDGE="/tmp/status-hub.json"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"

# Check if config exists and has PRs
[ -f "$CONFIG" ] || exit 0

# Get PR count
PR_COUNT=$(jq '.foreground | map(select(.owner)) | length' "$CONFIG" 2>/dev/null || echo 0)
[ "$PR_COUNT" -eq 0 ] && exit 0

# Build foreground array from tracked PRs
build_foreground() {
  local result="["
  local first=true

  # Read each PR from config
  while IFS= read -r pr_json; do
    [ -z "$pr_json" ] && continue

    owner=$(echo "$pr_json" | jq -r '.owner')
    repo=$(echo "$pr_json" | jq -r '.repo')
    number=$(echo "$pr_json" | jq -r '.number')

    # Fetch PR status via gh
    pr_data=$(gh pr view "$number" --repo "$owner/$repo" \
      --json state,isDraft,reviewDecision,statusCheckRollup,mergeable,comments 2>/dev/null)

    if [ -z "$pr_data" ]; then
      # gh failed, skip this PR
      continue
    fi

    # Parse PR data
    state=$(echo "$pr_data" | jq -r '.state')
    is_draft=$(echo "$pr_data" | jq -r '.isDraft')
    review=$(echo "$pr_data" | jq -r '.reviewDecision // "REVIEW_REQUIRED"')
    mergeable=$(echo "$pr_data" | jq -r '.mergeable')
    comments_count=$(echo "$pr_data" | jq '.comments | length')
    checks_failed=$(echo "$pr_data" | jq '[.statusCheckRollup[]? | select(.conclusion == "FAILURE")] | length')
    checks_pending=$(echo "$pr_data" | jq '[.statusCheckRollup[]? | select(.conclusion == null or .conclusion == "PENDING")] | length')
    checks_total=$(echo "$pr_data" | jq '.statusCheckRollup | length')

    # Get lastSeen from config for alert detection
    last_comments=$(echo "$pr_json" | jq -r '.lastSeen.commentsCount // 0')
    last_review=$(echo "$pr_json" | jq -r '.lastSeen.reviewDecision // ""')
    last_state=$(echo "$pr_json" | jq -r '.lastSeen.state // ""')

    # Determine icon (priority: worst first)
    icon="✓"
    detail=""

    if [ "$state" = "MERGED" ]; then
      icon="M"
      detail="merged"
    elif [ "$state" = "CLOSED" ]; then
      icon="C"
      detail="closed"
    elif [ "$checks_failed" -gt 0 ]; then
      icon="X"
      detail="checks failing"
    elif [ "$mergeable" = "CONFLICTING" ]; then
      icon="⚡"
      detail="conflicts"
    elif [ "$review" = "CHANGES_REQUESTED" ]; then
      icon="!"
      detail="changes requested"
    elif [ "$checks_pending" -gt 0 ]; then
      icon="~"
      detail="checks pending"
    elif [ "$review" = "REVIEW_REQUIRED" ] || [ "$review" = "" ]; then
      icon="?"
      detail="review required"
    elif [ "$is_draft" = "true" ]; then
      icon="D"
      detail="draft"
    elif [ "$review" = "APPROVED" ] && [ "$checks_failed" -eq 0 ] && [ "$mergeable" = "MERGEABLE" ] && [ "$is_draft" = "false" ]; then
      icon="🚀"
      detail="ready to merge"
    elif [ "$review" = "APPROVED" ]; then
      icon="✓"
      detail="approved"
    fi

    # Detect alerts
    has_alert="false"
    if [ "$comments_count" -gt "$last_comments" ]; then
      has_alert="true"
    elif [ "$review" != "$last_review" ] && [ -n "$last_review" ]; then
      has_alert="true"
    elif [ "$state" != "$last_state" ] && [ -n "$last_state" ]; then
      has_alert="true"
    fi

    # Build JSON entry
    [ "$first" = "true" ] || result+=","
    first=false
    result+="{\"site\":\"github-pr\",\"icon\":\"$icon\",\"title\":\"PR #$number\",\"detail\":\"$detail\",\"hasAlert\":$has_alert}"

    # Update lastSeen in config (fire and forget)
    jq --argjson num "$number" --argjson cc "$comments_count" --arg rd "$review" --arg st "$state" \
      '(.foreground[] | select(.number == $num)) |= (.lastSeen = {commentsCount: $cc, reviewDecision: $rd, state: $st})' \
      "$CONFIG" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"

  done < <(jq -c '.foreground[] | select(.owner)' "$CONFIG" 2>/dev/null)

  result+="]"
  echo "$result"
}

# Get foreground JSON
FOREGROUND=$(build_foreground)

# Preserve existing background from bridge
if [ -f "$BRIDGE" ]; then
  BG_SITE=$(jq -r '.background.site // "off"' "$BRIDGE")
  BG_ICON=$(jq -r '.background.icon // ""' "$BRIDGE")
  BG_TITLE=$(jq -r '.background.title // ""' "$BRIDGE")
  BG_DETAIL=$(jq -r '.background.detail // ""' "$BRIDGE")
else
  BG_SITE="off"
  BG_ICON=""
  BG_TITLE=""
  BG_DETAIL=""
fi

# Update bridge with new foreground, preserving background
"${PLUGIN_ROOT}/bin/update-bridge.sh" "$BG_SITE" "$BG_ICON" "$BG_TITLE" "$BG_DETAIL" --foreground "$FOREGROUND"
