# Data Safety Guidelines

This document establishes patterns for safely updating the status hub's data files without data loss.

## Core Principle

**Never overwrite, always merge.** When updating a subset of data (e.g., just PRs or just calendar), preserve items from other services.

## Bridge File Updates (`/tmp/status-hub.json`)

The bridge file has three main sections:
- `timestamp`: Always update on write
- `background`: Music/service status
- `foreground`: Array of tracked items (PRs, calendar, Slack, etc.)

### Correct Pattern: Merge Foreground Items

When refreshing one service, preserve items from other services:

```bash
# Get existing non-PR items before rebuilding PR list
NON_PR_ITEMS=$(jq -c '[.foreground[] | select(.owner | not)]' "$CONFIG" 2>/dev/null || echo '[]')

# After building PR array, merge with non-PR items
echo "$pr_array" | jq --argjson nonpr "$NON_PR_ITEMS" '. + $nonpr'
```

### Wrong Pattern: Full Replacement

```bash
# BAD: This loses Slack, calendar, and other items!
jq '.foreground = $prs' --argjson prs "$PR_ONLY_ARRAY" "$BRIDGE"
```

## Config File Updates (`~/.claude/status-config.json`)

### Correct Pattern: Targeted Updates with `|=`

```bash
# Update specific item by matching criteria
jq '(.foreground[] | select(.number == 123)) |= . + {lastSeen: {...}}' "$CONFIG"

# Update background without touching foreground
jq '.background |= {service: "spotify", tabId: 123}' "$CONFIG"
```

### Wrong Pattern: Full Object Replacement

```bash
# BAD: Replaces entire config, losing other sections!
echo '{"foreground": [...]}' > "$CONFIG"
```

## Adding New Items

When adding a new tracked item:

1. Read existing foreground array
2. Check if item already exists (match by unique key like `owner/repo/number`)
3. If exists: update in place with `|=`
4. If new: append with `+= [$new_item]`

```bash
# Check if PR exists, then add or update
if jq -e ".foreground[] | select(.owner == \"$owner\" and .repo == \"$repo\" and .number == $number)" "$CONFIG" >/dev/null 2>&1; then
  # Update existing
  jq "(.foreground[] | select(.number == $number)) |= . + {lastSeen: {...}}" "$CONFIG"
else
  # Append new
  jq ".foreground += [{owner: \"$owner\", repo: \"$repo\", number: $number}]" "$CONFIG"
fi
```

## Checklist for Skill Authors

Before submitting a skill that modifies hub data:

- [ ] Does it preserve items from other services when updating foreground?
- [ ] Does it use `|=` for targeted updates instead of full replacement?
- [ ] Does it check for existing items before adding new ones?
- [ ] Does it preserve background when only updating foreground (and vice versa)?
- [ ] Does it handle missing files gracefully (create with sensible defaults)?

## Race Condition Prevention

When multiple processes might update the same file:

1. Use atomic writes: write to `.tmp` file first, then `mv` to final location
2. For daemons: use lockfile with ownership verification (version:PID)
3. Check file staleness before modifying

```bash
# Atomic write pattern
jq '...' "$CONFIG" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"
```

## Related Files

- `bin/refresh-prs.sh` - PR-only refresh (preserves non-PR items)
- `bin/update-bridge.sh` - Bridge writer (preserves background/foreground appropriately)
- `bin/refresh-daemon.sh` - Background daemon with lockfile management
- `skills/hub-refresh.md` - Full refresh skill
