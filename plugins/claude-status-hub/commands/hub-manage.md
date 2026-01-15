---
name: hub-manage
description: Interactive hub management via AskUserQuestion
---

# Hub Manage - Interactive UI

Present an interactive interface using AskUserQuestion for managing tracked items.

## Process

1. Read `~/.claude/status-config.json`
2. If empty, say "Nothing to manage. Use `/hub <service>` or `/hub <pr-url>` to start tracking."
3. Build options from tracked items

## AskUserQuestion Structure

```
question: "What would you like to do?"
header: "Manage"
options:
  - label: "View all (#N items)"
    description: "Show detailed status of all tracked items"
  - label: "Statusline settings..."
    description: "Configure context/quota display"
  - label: "Acknowledge alerts"
    description: "Mark new items as seen"
  - label: "Remove item..."
    description: "Stop tracking a specific item"
```

## Follow-up: Statusline Settings

If user selects "Statusline settings...", show:

```
question: "What to configure?"
header: "Statusline"
options:
  - label: "Context display"
    description: "Currently: <bar/percent/threshold/off>"
  - label: "Quota display"
    description: "Currently: <bar/number/compact/off>"
  - label: "Turn both off"
    description: "Disable context and quota from statusline"
```

Based on selection:
- "Context display" → Run `/hub-context`
- "Quota display" → Run `/hub-quota`
- "Turn both off" → Set `contextDisplay: null` and `quota.displayFormat: "off"` in config

## Follow-up: Remove Item

If user selects "Remove item...", show second question:

```
question: "Which item to remove?"
header: "Remove"
options:
  - label: "#1 PR #17163"
    description: "anthropics/claude-code"
  - label: "#2 YouTube Music"
    description: "Background music"
  - label: "#3 Gmail"
    description: "Email notifications"
```

## Actions

Based on selection:

| Selection | Action |
|-----------|--------|
| View all | Run `/hub list` |
| Acknowledge | Run `/hub ack all` |
| Remove #N | Remove from config, update bridge (see below), say "Stopped tracking [item]" |
| Clear all | Run `/hub off` |

## Updating Bridge After Changes

**IMPORTANT:** When modifying foreground (add/remove items), always refresh the **entire bridge** with current live data:

1. Fetch current background status from browser tab (if service configured)
2. Build foreground array from config
3. Call update-bridge.sh with **actual live values** for both background AND foreground

Never use placeholders - always fetch real data to keep bridge consistent.
