#!/bin/bash
# Lightweight PR refresh - runs from daemon, pure bash (no Claude CLI)

CONFIG="$HOME/.claude/status-config.json"
BRIDGE="/tmp/status-hub.json"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
CONTINUOUS_CHECK_PATTERN="aviator|mergify|merge-when-ready"
LOG_FILE="$HOME/.claude/status-hub.log"

# Resolve merge strategy (priority: repos > orgs > default)
resolve_merge_strategy() {
  local owner=$1 repo=$2 strategy
  strategy=$(jq -r ".github.mergeStrategy.repos[\"$owner/$repo\"] // empty" "$CONFIG" 2>/dev/null)
  [ -z "$strategy" ] && strategy=$(jq -r ".github.mergeStrategy.orgs[\"$owner\"] // empty" "$CONFIG" 2>/dev/null)
  [ -z "$strategy" ] && strategy=$(jq -r '.github.mergeStrategy.default // "squash"' "$CONFIG" 2>/dev/null)
  echo "${strategy:-squash}"
}

# Execute auto-merge for a PR
execute_auto_merge() {
  local owner=$1 repo=$2 number=$3 strategy=$(resolve_merge_strategy "$owner" "$repo") result
  case "$strategy" in
    squash)       result=$(gh pr merge "$number" --repo "$owner/$repo" --squash 2>&1) ;;
    rebase)       result=$(gh pr merge "$number" --repo "$owner/$repo" --rebase 2>&1) ;;
    merge-commit) result=$(gh pr merge "$number" --repo "$owner/$repo" --merge 2>&1) ;;
    aviator)      result=$(gh pr comment "$number" --repo "$owner/$repo" --body "/aviator merge" 2>&1) ;;
    *)            custom=$(jq -r ".github.mergeStrategy.customCommands[\"$owner/$repo\"] // empty" "$CONFIG" 2>/dev/null)
                  [ -n "$custom" ] && result=$(eval "${custom//\{number\}/$number}" 2>&1) || result="Unknown strategy: $strategy" ;;
  esac
  echo "$(date -Iseconds) AUTO_MERGE $owner/$repo#$number via $strategy: ${result:0:100}" >> "$LOG_FILE"
}

# Determine PR icon and detail (priority: worst first)
determine_pr_icon() {
  local state=$1 is_draft=$2 review=$3 mergeable=$4 checks_failed=$5 checks_pending=$6 checks_continuous=$7
  case "$state" in MERGED) echo "M:merged"; return ;; CLOSED) echo "C:closed"; return ;; esac
  [ "$checks_failed" -gt 0 ] && { echo "X:checks failing"; return; }
  [ "$mergeable" = "CONFLICTING" ] && { echo "⚡:conflicts"; return; }
  [ "$review" = "CHANGES_REQUESTED" ] && { echo "!:changes requested"; return; }
  [ "$checks_pending" -gt 0 ] && { echo "~:checks pending"; return; }
  [ "$review" = "REVIEW_REQUIRED" ] || [ -z "$review" ] && { echo "?:review required"; return; }
  [ "$is_draft" = "true" ] && { echo "D:draft"; return; }
  if [ "$review" = "APPROVED" ] && [ "$checks_failed" -eq 0 ] && [ "$mergeable" = "MERGEABLE" ] && [ "$is_draft" = "false" ]; then
    [ "$checks_continuous" -gt 0 ] && { echo "🚀:ready ⏳${checks_continuous}"; return; }
    echo "🚀:ready to merge"; return
  fi
  [ "$review" = "APPROVED" ] && { echo "✓:approved"; return; }
  echo "✓:"
}

# Detect if PR has new activity
detect_alert() {
  local comments=$1 last_comments=$2 review=$3 last_review=$4 state=$5 last_state=$6 pending=$7 last_pending=$8
  [ "$comments" -gt "$last_comments" ] && { echo "true"; return; }
  [ "$review" != "$last_review" ] && [ -n "$last_review" ] && { echo "true"; return; }
  [ "$state" != "$last_state" ] && [ -n "$last_state" ] && { echo "true"; return; }
  [ "$pending" -eq 0 ] && [ "$last_pending" -gt 0 ] && { echo "true"; return; }
  echo "false"
}

# Check config
[ -f "$CONFIG" ] || exit 0
PR_COUNT=$(jq '.foreground | map(select(.owner)) | length' "$CONFIG" 2>/dev/null || echo 0)
[ "$PR_COUNT" -eq 0 ] && exit 0

# Build foreground array
build_foreground() {
  local result="[" first=true updates=""
  while IFS= read -r pr_json; do
    [ -z "$pr_json" ] && continue
    owner=$(echo "$pr_json" | jq -r '.owner'); repo=$(echo "$pr_json" | jq -r '.repo'); number=$(echo "$pr_json" | jq -r '.number')

    pr_data=$(gh pr view "$number" --repo "$owner/$repo" --json state,isDraft,reviewDecision,statusCheckRollup,mergeable,comments 2>/dev/null)
    [ -z "$pr_data" ] && continue

    state=$(echo "$pr_data" | jq -r '.state')
    is_draft=$(echo "$pr_data" | jq -r '.isDraft')
    review=$(echo "$pr_data" | jq -r '.reviewDecision // "REVIEW_REQUIRED"')
    mergeable=$(echo "$pr_data" | jq -r '.mergeable')
    comments_count=$(echo "$pr_data" | jq '.comments | length')
    checks_failed=$(echo "$pr_data" | jq '[.statusCheckRollup[]? | select(.conclusion == "FAILURE")] | length')
    checks_pending=$(echo "$pr_data" | jq --arg p "$CONTINUOUS_CHECK_PATTERN" '[.statusCheckRollup[]? | select(.conclusion == null or .conclusion == "PENDING") | select(.name | test($p; "i") | not)] | length')
    checks_continuous=$(echo "$pr_data" | jq --arg p "$CONTINUOUS_CHECK_PATTERN" '[.statusCheckRollup[]? | select(.conclusion == null or .conclusion == "PENDING") | select(.name | test($p; "i"))] | length')

    last_comments=$(echo "$pr_json" | jq -r '.lastSeen.commentsCount // 0')
    last_review=$(echo "$pr_json" | jq -r '.lastSeen.reviewDecision // ""')
    last_state=$(echo "$pr_json" | jq -r '.lastSeen.state // ""')
    last_pending=$(echo "$pr_json" | jq -r '.lastSeen.checksPending // 0')
    last_failed=$(echo "$pr_json" | jq -r '.lastSeen.checksFailed // 0')
    last_auto=$(echo "$pr_json" | jq -r '.lastSeen.autoMergeAttempted // false')
    auto_merge=$(echo "$pr_json" | jq -r '.autoMerge // false')

    icon_detail=$(determine_pr_icon "$state" "$is_draft" "$review" "$mergeable" "$checks_failed" "$checks_pending" "$checks_continuous")
    icon="${icon_detail%%:*}"; detail="${icon_detail#*:}"
    has_alert=$(detect_alert "$comments_count" "$last_comments" "$review" "$last_review" "$state" "$last_state" "$checks_pending" "$last_pending")

    # Contextual music events
    [ "$state" = "MERGED" ] && [ "$last_state" != "MERGED" ] && [ -n "$last_state" ] && \
      "${PLUGIN_ROOT}/bin/music-event.sh" "pr_merged" &
    [ "$checks_failed" -gt 0 ] && [ "$last_failed" -eq 0 ] && \
      "${PLUGIN_ROOT}/bin/music-event.sh" "ci_failed" &

    # Auto-merge when ready and not attempted
    auto_merge_attempted="false"
    if [ "$auto_merge" = "true" ] && [[ "$icon" == "🚀"* ]] && [ "$last_auto" != "true" ]; then
      execute_auto_merge "$owner" "$repo" "$number"
      auto_merge_attempted="true"
    fi

    [ "$first" = "true" ] || result+=","
    first=false
    result+="{\"site\":\"github-pr\",\"icon\":\"$icon\",\"title\":\"PR #$number\",\"detail\":\"$detail\",\"hasAlert\":$has_alert,\"autoMerge\":$auto_merge}"

    [ -n "$updates" ] && updates+=" | "
    updates+="(.foreground[] | select(.number == $number)) |= (.lastSeen = {commentsCount: $comments_count, reviewDecision: \"$review\", state: \"$state\", checksPending: $checks_pending, checksFailed: $checks_failed, autoMergeAttempted: $auto_merge_attempted})"
  done < <(jq -c '.foreground[] | select(.owner)' "$CONFIG" 2>/dev/null)

  [ -n "$updates" ] && jq "$updates" "$CONFIG" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"

  # Preserve non-PR foreground items (Slack, Calendar, etc.) - see docs/data-safety-guidelines.md
  NON_PR_ITEMS=$(jq -c '[.foreground[] | select(.owner | not)]' "$CONFIG" 2>/dev/null || echo '[]')
  if [ "$NON_PR_ITEMS" != "[]" ] && [ "$NON_PR_ITEMS" != "null" ]; then
    echo "${result}]" | jq --argjson nonpr "$NON_PR_ITEMS" '. + $nonpr'
  else
    echo "${result}]"
  fi
}

FOREGROUND=$(build_foreground)

# Preserve background from bridge
if [ -f "$BRIDGE" ]; then
  BG_SITE=$(jq -r '.background.site // "off"' "$BRIDGE")
  BG_ICON=$(jq -r '.background.icon // ""' "$BRIDGE")
  BG_TITLE=$(jq -r '.background.title // ""' "$BRIDGE")
  BG_DETAIL=$(jq -r '.background.detail // ""' "$BRIDGE")
else
  BG_SITE="off"; BG_ICON=""; BG_TITLE=""; BG_DETAIL=""
fi

"${PLUGIN_ROOT}/bin/update-bridge.sh" "$BG_SITE" "$BG_ICON" "$BG_TITLE" "$BG_DETAIL" --foreground "$FOREGROUND"
