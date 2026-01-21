#!/bin/bash
# Lightweight PR refresh - runs from daemon, pure bash (no Claude CLI)
# Reads tracked PRs from config, fetches status via gh, updates bridge foreground

CONFIG="$HOME/.claude/status-config.json"
BRIDGE="/tmp/status-hub.json"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"

# Pattern for continuous/eternal checks (merge services that run until triggered)
# These are non-blocking - PR can be "ready" even while they run
CONTINUOUS_CHECK_PATTERN="aviator|mergify|merge-when-ready"

# Determine PR icon and detail based on state (priority: worst first)
# Returns: "icon:detail"
determine_pr_icon() {
  local state=$1 is_draft=$2 review=$3 mergeable=$4 checks_failed=$5 checks_pending=$6 checks_continuous=$7

  case "$state" in
    MERGED) echo "M:merged"; return ;;
    CLOSED) echo "C:closed"; return ;;
  esac

  # Open PR - check conditions in priority order
  [ "$checks_failed" -gt 0 ] && { echo "X:checks failing"; return; }
  [ "$mergeable" = "CONFLICTING" ] && { echo "⚡:conflicts"; return; }
  [ "$review" = "CHANGES_REQUESTED" ] && { echo "!:changes requested"; return; }
  [ "$checks_pending" -gt 0 ] && { echo "~:checks pending"; return; }
  [ "$review" = "REVIEW_REQUIRED" ] || [ -z "$review" ] && { echo "?:review required"; return; }
  [ "$is_draft" = "true" ] && { echo "D:draft"; return; }

  # Ready to merge: approved + no failures + mergeable + not draft
  if [ "$review" = "APPROVED" ] && [ "$checks_failed" -eq 0 ] && [ "$mergeable" = "MERGEABLE" ] && [ "$is_draft" = "false" ]; then
    if [ "$checks_continuous" -gt 0 ]; then
      echo "🚀:ready ⏳${checks_continuous}"; return
    fi
    echo "🚀:ready to merge"; return
  fi

  [ "$review" = "APPROVED" ] && { echo "✓:approved"; return; }
  echo "✓:"
}

# Detect if PR has new activity since last seen
# Returns: "true" or "false"
detect_alert() {
  local comments_count=$1 last_comments=$2 review=$3 last_review=$4 state=$5 last_state=$6
  local checks_pending=$7 last_checks_pending=$8

  [ "$comments_count" -gt "$last_comments" ] && { echo "true"; return; }
  [ "$review" != "$last_review" ] && [ -n "$last_review" ] && { echo "true"; return; }
  [ "$state" != "$last_state" ] && [ -n "$last_state" ] && { echo "true"; return; }
  # Alert when blocking checks finish (transition from pending to ready)
  [ "$checks_pending" -eq 0 ] && [ "$last_checks_pending" -gt 0 ] && { echo "true"; return; }
  echo "false"
}

# Check if config exists and has PRs
[ -f "$CONFIG" ] || exit 0

# Get PR count
PR_COUNT=$(jq '.foreground | map(select(.owner)) | length' "$CONFIG" 2>/dev/null || echo 0)
[ "$PR_COUNT" -eq 0 ] && exit 0

# Build foreground array from tracked PRs
build_foreground() {
  local result="["
  local first=true
  local updates=""  # Collect lastSeen updates for batch write

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
      continue  # gh failed, skip this PR
    fi

    # Parse PR data
    state=$(echo "$pr_data" | jq -r '.state')
    is_draft=$(echo "$pr_data" | jq -r '.isDraft')
    review=$(echo "$pr_data" | jq -r '.reviewDecision // "REVIEW_REQUIRED"')
    mergeable=$(echo "$pr_data" | jq -r '.mergeable')
    comments_count=$(echo "$pr_data" | jq '.comments | length')
    checks_failed=$(echo "$pr_data" | jq '[.statusCheckRollup[]? | select(.conclusion == "FAILURE")] | length')
    # Separate blocking checks from continuous/eternal checks (like Aviator)
    checks_pending=$(echo "$pr_data" | jq --arg pattern "$CONTINUOUS_CHECK_PATTERN" \
      '[.statusCheckRollup[]? | select(.conclusion == null or .conclusion == "PENDING") | select(.name | test($pattern; "i") | not)] | length')
    checks_continuous=$(echo "$pr_data" | jq --arg pattern "$CONTINUOUS_CHECK_PATTERN" \
      '[.statusCheckRollup[]? | select(.conclusion == null or .conclusion == "PENDING") | select(.name | test($pattern; "i"))] | length')

    # Get lastSeen from config for alert detection
    last_comments=$(echo "$pr_json" | jq -r '.lastSeen.commentsCount // 0')
    last_review=$(echo "$pr_json" | jq -r '.lastSeen.reviewDecision // ""')
    last_state=$(echo "$pr_json" | jq -r '.lastSeen.state // ""')
    last_checks_pending=$(echo "$pr_json" | jq -r '.lastSeen.checksPending // 0')

    # Determine icon and detail
    icon_detail=$(determine_pr_icon "$state" "$is_draft" "$review" "$mergeable" "$checks_failed" "$checks_pending" "$checks_continuous")
    icon="${icon_detail%%:*}"
    detail="${icon_detail#*:}"

    # Detect alerts
    has_alert=$(detect_alert "$comments_count" "$last_comments" "$review" "$last_review" "$state" "$last_state" "$checks_pending" "$last_checks_pending")

    # Build JSON entry
    [ "$first" = "true" ] || result+=","
    first=false
    result+="{\"site\":\"github-pr\",\"icon\":\"$icon\",\"title\":\"PR #$number\",\"detail\":\"$detail\",\"hasAlert\":$has_alert}"

    # Collect lastSeen update for batch write
    [ -n "$updates" ] && updates+=" | "
    updates+="(.foreground[] | select(.number == $number)) |= (.lastSeen = {commentsCount: $comments_count, reviewDecision: \"$review\", state: \"$state\", checksPending: $checks_pending})"

  done < <(jq -c '.foreground[] | select(.owner)' "$CONFIG" 2>/dev/null)

  # Batch update all lastSeen values in one write
  if [ -n "$updates" ]; then
    jq "$updates" "$CONFIG" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"
  fi

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
