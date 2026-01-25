---
name: hub-setup
description: Configure Status Hub statusline integration
args: --replace (optional) Force full replacement, ignore existing statusline
---

# Hub Setup

Configure Claude Code to use Status Hub's statusline.

## Step 1: Parse Arguments

Check if `--replace` flag was provided.

## Step 2: Preserve Existing Statusline

If NOT `--replace`, save existing statusline to `~/.claude/status-base-config.json`:
- `statusLine.type == "command"`: save `{ "type": "command", "value": "<path>" }`
- `statusLine.type == "text"`: save `{ "type": "text", "value": "<text>" }`
- No statusLine: detect shell prompt or use `{ "type": "default" }`

If `--replace`: save `{ "type": "default" }`.

## Step 3: Update Settings

Update `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "${CLAUDE_PLUGIN_ROOT}/bin/statusline.sh"
  }
}
```

## Step 4: Add Permissions

Add to `permissions.allow` (expand all variables to actual paths):
```
Read(${HOME}/.claude/status-config.json)
Write(${HOME}/.claude/status-config.json)
Read(${HOME}/.claude/status-base-config.json)
Read(/tmp/status-hub.json)
Write(/tmp/status-hub.json)
Read(${CLAUDE_PLUGIN_ROOT}/skills/*)
Read(${CLAUDE_PLUGIN_ROOT}/bin/*)
Bash(gh pr view:*)
Bash(${CLAUDE_PLUGIN_ROOT}/bin/update-bridge.sh *)
mcp__claude-in-chrome__javascript_tool
mcp__claude-in-chrome__tabs_context_mcp
```

Merge with existing permissions (deduplicate).

## Step 5: Initialize Config Files

### Status Config (`~/.claude/status-config.json`)
- If missing: create `{"background": null, "foreground": []}`
- If corrupt: restore from `.bak` or create fresh
- If exists: migrate schema (add contextDisplay, calendar if missing)
- Always backup before modifying

### Bridge File (`/tmp/status-hub.json`)
Create: `{"timestamp": null, "background": null, "foreground": []}`

### Legacy Daemon Cleanup
If `/tmp/status-hub-daemon.lock` contains old format (just PID, no VERSION:):
- `kill -9 <pid>` and remove lockfile
- New daemon spawns via SessionStart hook

## Step 6: Configure Calendar (Optional)

Detect available methods, then present consolidated wizard:

```json
{
  "question": "Enable Google Calendar meeting alerts?",
  "header": "Calendar",
  "options": [
    {"label": "Chrome browser tab", "description": "<dynamic status>"},
    {"label": "Playwright (headless)", "description": "<dynamic status>"},
    {"label": "Skip for now", "description": "Configure later with /hub-setup-gcalendar"}
  ]
}
```

If Chrome/Playwright selected and installed:
1. Set up tab/session
2. Ask alert timing (5min, 10min, custom)
3. Save to `config.calendar`

If not installed: show brief instructions, set `calendar.connection: "disabled"`.

## Step 7: Confirm Setup

```
Status Hub configured!

Base prompt: <preserved|default>
<if legacy daemon killed: "Cleaned up legacy daemon">
<Calendar: Enabled via Chrome/Playwright | Disabled>

Your statusline will show: Git branch, music, PR status, meeting alerts.

Restart Claude Code to apply.
```
