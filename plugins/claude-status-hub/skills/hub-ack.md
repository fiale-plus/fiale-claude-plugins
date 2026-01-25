# Hub Ack - Contextual Action Dispatcher

Handle alerts with context-aware actions. This skill is the main dispatcher that routes to service-specific ack skills.

## Overview

The `/hub-ack` paradigm:
1. Alert appears in statusline (single line, non-blocking)
2. User continues working
3. User types `/hub-ack` when ready
4. System evaluates: What alert? What time? What's possible?
5. Smart wizard offers best actions for THIS moment

## Step 1: Clear Any Error State

```bash
${CLAUDE_PLUGIN_ROOT}/bin/update-bridge.sh --clear-error
```

## Step 2: Read Current State

Read the bridge file to find alerting items:

```bash
cat /tmp/status-hub.json
```

Extract:
- `foreground[]` array with items that have `hasAlert: true`
- `background` for music state (if any)

## Step 3: Read Config for Context

```bash
cat ~/.claude/status-config.json
```

Get additional context:
- `foreground[]` item details (owner, repo, number for PRs; tabId for browser items)
- `github.mergeStrategy` for merge preferences
- Service-specific settings

## Step 4: Evaluate Alerts

Check for items with `hasAlert: true` in the bridge file.

**Priority order** (handle most urgent first):
1. `github-pr` with CI failures (icon `X`)
2. `github-pr` with conflicts (icon `⚡`)
3. `github-pr` ready to merge (icon `🚀`)
4. `calendar` meetings (time-sensitive)
5. `focus` break reminders or interruptions
6. `slack` VIP messages
7. `github-pr` with review activity
8. Other alerts

## Step 5: Route to Service-Specific Skill

For each alerting item, check for a service-specific ack skill:

1. **Built-in**: `${CLAUDE_PLUGIN_ROOT}/skills/hub-ack-<service>.md`
2. **User-authored**: `${CLAUDE_PLUGIN_ROOT}/skills/hub-ack-<service>.user.md`

Service mappings:
- `github-pr` → `hub-ack-github-pr.md`
- `calendar` → `hub-ack-calendar.md`
- `focus` → `hub-ack-focus.md`
- `slack` → `hub-ack-slack.md`
- `jira` → `hub-ack-jira.md`
- `finance` → Just dismiss (no contextual actions)

If a skill exists, read and follow it for that item's ack actions.

## Step 6: No Alerts Case

If no items have `hasAlert: true`:

```
✓ No pending alerts

Current status:
<list foreground items with their current state>

[r] Refresh status now
[d] Done
```

## Step 7: Multiple Alerts

If multiple items have alerts, present a selection:

```
📬 You have N alerts:

[1] <icon> <service>: <brief description>
[2] <icon> <service>: <brief description>
...
[a] Handle all sequentially
[d] Dismiss all
```

Let user select which to handle, then route to the appropriate skill.

## Step 8: Update Config and Bridge After Ack

After successfully handling an alert:
1. Update `lastSeen` values in config
2. Set `hasAlert: false` for the item in config
3. Write updated config back to `~/.claude/status-config.json`
4. **CRITICAL**: Update the bridge file immediately so statusline reflects new state

```bash
# Read the updated foreground array from config (with hasAlert: false)
FOREGROUND=$(jq -c '.foreground // []' ~/.claude/status-config.json)

# Read current background from bridge
BACKGROUND=$(jq -c '.background // {}' /tmp/status-hub.json)
BG_SITE=$(echo "$BACKGROUND" | jq -r '.site // "hub"')
BG_ICON=$(echo "$BACKGROUND" | jq -r '.icon // "✓"')
BG_TITLE=$(echo "$BACKGROUND" | jq -r '.title // "Status Hub"')
BG_DETAIL=$(echo "$BACKGROUND" | jq -r '.detail // ""')

# Update bridge with new foreground state
${CLAUDE_PLUGIN_ROOT}/bin/update-bridge.sh "$BG_SITE" "$BG_ICON" "$BG_TITLE" "$BG_DETAIL" --foreground "$FOREGROUND"
```

**Why this matters**: The statusline reads from `/tmp/status-hub.json` (bridge file), not the config. If you only update the config, the alert will persist in the statusline until the next daemon refresh cycle (up to 90 seconds).

## AskUserQuestion Format

Use AskUserQuestion for wizard interactions:

```
{
  "questions": [{
    "question": "<context and options>",
    "header": "Hub Ack",
    "options": [
      {"label": "<action 1>", "description": "<what happens>"},
      {"label": "<action 2>", "description": "<what happens>"},
      {"label": "Dismiss", "description": "Mark as seen"}
    ],
    "multiSelect": false
  }]
}
```

## Error Handling

If any tool call fails:
1. Write error via update-bridge.sh --error
2. Inform user of the failure
3. Offer to retry or dismiss
