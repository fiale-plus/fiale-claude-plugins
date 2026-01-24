---
name: hub-setup
description: Configure Status Hub statusline integration
args: --replace (optional) Force full replacement, ignore existing statusline
---

# Hub Setup

Configure Claude Code to use Status Hub's statusline.

## Arguments

- `--replace`: Force full replacement, ignoring any existing statusline configuration

## Process

### Step 1: Parse Arguments

Check if `--replace` flag was provided in the command arguments.

### Step 2: Read Current Settings

Read `~/.claude/settings.json` (if exists).

### Step 3: Preserve Existing Statusline (if not --replace)

If `--replace` flag is NOT set, preserve the user's existing statusline:

1. **If `statusLine.type` is `"command"`**:
   - Save to `~/.claude/status-base-config.json`:
     ```json
     {
       "type": "command",
       "value": "<original-command-path>"
     }
     ```
   - Inform user: "Your existing statusline command will be preserved as the base prompt."

2. **If `statusLine.type` is `"text"`**:
   - Save to `~/.claude/status-base-config.json`:
     ```json
     {
       "type": "text",
       "value": "<original-text>"
     }
     ```
   - Inform user: "Your existing statusline text will be preserved as the base prompt."

3. **If no `statusLine` exists**:
   - Detect user's shell from `$SHELL` environment variable
   - Check if it's bash or zsh
   - Try to get the shell prompt:
     - For zsh: Check if PROMPT is set (`zsh -c 'echo $PROMPT'`)
     - For bash: Check if PS1 is set (`bash -c 'echo $PS1'`)
   - If shell prompt is available and non-empty, save:
     ```json
     {
       "type": "shell",
       "value": "PROMPT",
       "shell": "zsh"
     }
     ```
   - If shell prompt is not available, save:
     ```json
     {
       "type": "default"
     }
     ```

4. **If `--replace` flag IS set**:
   - Save to `~/.claude/status-base-config.json`:
     ```json
     {
       "type": "default"
     }
     ```
   - Inform user: "Using default Status Hub base prompt."

### Step 4: Update StatusLine

Update `statusLine` to use the plugin's script:
```json
{
  "statusLine": {
    "type": "command",
    "command": "${CLAUDE_PLUGIN_ROOT}/bin/statusline.sh"
  }
}
```

### Step 5: Add Permissions

Add permissions for background refresh (allows status updates without prompts):
```json
{
  "permissions": {
    "allow": [
      "Read(${HOME}/.claude/status-config.json)",
      "Write(${HOME}/.claude/status-config.json)",
      "Read(${HOME}/.claude/status-base-config.json)",
      "Read(/tmp/status-hub.json)",
      "Write(/tmp/status-hub.json)",
      "Read(${CLAUDE_PLUGIN_ROOT}/skills/*)",
      "Read(${CLAUDE_PLUGIN_ROOT}/bin/*)",
      "Bash(gh pr view:*)",
      "Bash(cat ${HOME}/.claude/status-config.json)",
      "Bash(${CLAUDE_PLUGIN_ROOT}/bin/update-bridge.sh *)",
      "mcp__plugin_sentry_sentry__search_issues",
      "mcp__claude-in-chrome__javascript_tool",
      "mcp__claude-in-chrome__tabs_context_mcp",
      "mcp__claude-in-chrome__navigate",
      "mcp__claude-in-chrome__get_page_text"
    ]
  }
}
```

**IMPORTANT**: When writing permissions, expand all variables to actual paths:
- `${HOME}` → user's home directory (e.g., `/Users/username` or `/home/username`)
- `${CLAUDE_PLUGIN_ROOT}` → actual plugin path

Claude Code permissions require exact path matching - `~` and variables are NOT expanded automatically.

Merge with existing permissions if present (deduplicate).

Explain to user: "These permissions allow the background status refresh to run without interrupting you with prompts."

### Step 6: Preserve Other Settings

Preserve all other settings in the file.

### Step 7: Write Updated Settings

Write the merged settings back to `~/.claude/settings.json`.

### Step 8: Initialize Config Files (with Migration)

Handle config files carefully - **never lose user data**:

#### Status Config (`~/.claude/status-config.json`)

1. **If file doesn't exist**: Create with defaults:
   ```json
   {"background": null, "foreground": []}
   ```

2. **If file exists but is empty/corrupt**:
   - Check if backup exists (`~/.claude/status-config.json.bak`)
   - If backup exists, restore from it
   - If no backup, create fresh with defaults
   - Warn user: "Config was empty/corrupt, initialized fresh"

3. **If file exists and valid**: Run migration to ensure schema is current:
   ```javascript
   // Migration: ensure all required fields exist
   config.foreground = config.foreground || [];
   config.background = config.background || { service: null, tabId: null };

   // v1.0 → v1.1: Add contextDisplay if missing
   if (!config.contextDisplay) {
     config.contextDisplay = "bar";
     config.contextAlertThreshold = 80;
   }

   // v1.1 → v1.2: Add calendar config if missing
   if (!config.calendar) {
     config.calendar = {
       connection: "disabled",
       chrome: { tabId: null },
       alertMinutesBefore: 5,
       alertWithDocsBefore: 10,
       lateMessageTo: "organizer"
     };
   }

   // Preserve all existing foreground items and their lastSeen state
   ```

4. **Always backup before modifying**:
   ```bash
   cp ~/.claude/status-config.json ~/.claude/status-config.json.bak
   ```

#### Bridge File (`/tmp/status-hub.json`)

- Always safe to recreate (ephemeral)
- `{"timestamp": null, "background": null, "foreground": []}`

#### Error File

- Clear stale errors: `rm -f /tmp/status-hub-error.txt`

#### Legacy Daemon Cleanup

Old daemons (pre-v1.0.4) don't have auto-death and will run forever. Detect and kill them:

1. Read `/tmp/status-hub-daemon.lock` if it exists
2. Check the format:
   - **New format**: `VERSION:PID` (e.g., `1.0.4:12345`) - has auto-death, leave alone
   - **Old format**: just `PID` (e.g., `12345`) - needs cleanup
3. If old format (content matches `^[0-9]+$` with no colon):
   - Kill the process with `kill -9 <pid>` (regular `kill` doesn't work on these)
   - Remove the lockfile: `rm -f /tmp/status-hub-daemon.lock`
   - Track that cleanup happened for the confirmation message
4. The new daemon will spawn automatically via SessionStart hook

### Step 9: Configure Calendar (Optional)

Ask if user wants calendar meeting alerts:

```
Would you like to enable Google Calendar meeting alerts?

This will show upcoming meetings in your statusline and let you
take actions (join, send "running late" messages) via /hub-ack.

[1] Yes, set up calendar (Recommended)
[2] Skip for now
```

If user selects "Yes":

1. **Check Chrome MCP availability**:
   - Verify `mcp__claude-in-chrome__tabs_context_mcp` is available
   - If not: "Calendar requires the Claude in Chrome extension. Install it first, then run /hub-setup again."

2. **Get calendar tab**:
   ```
   Please open Google Calendar in Chrome, then press Enter.

   (The calendar tab should show your schedule view - day, week, or month)
   ```

3. **Find the calendar tab**:
   - Use `mcp__claude-in-chrome__tabs_context_mcp` to list tabs
   - Look for tab with URL containing `calendar.google.com`
   - If not found, ask user to confirm it's open

4. **Store tab ID and enable calendar**:
   ```javascript
   config.calendar = {
     connection: "chrome",
     chrome: { tabId: <found-tab-id> },
     alertMinutesBefore: 5,
     alertWithDocsBefore: 10,
     lateMessageTo: "organizer"
   };
   ```

5. **Confirm**:
   ```
   Calendar configured! Tab ID: <id>

   You'll get alerts for meetings starting in 5 minutes
   (10 minutes for meetings with attachments to review).
   ```

If user selects "Skip":
- Keep `calendar.connection: "disabled"` (set during migration)
- Inform: "You can enable calendar later with /hub-setup"

### Step 10: Confirm Setup

Say:
```
Status Hub configured!

Base prompt: <describe what was preserved or "default">
<if legacy daemon was killed: "Cleaned up legacy daemon (pre-auto-death version)">
<if calendar enabled: "Calendar: Enabled (alerts 5min before meetings)">
<if calendar disabled: "Calendar: Disabled (enable anytime with /hub-setup)">

Your statusline will now show:
- Git branch and dirty state
- Music playback (via /hub-play)
- PR status (via /hub <pr-url>)
- Meeting alerts (via /hub-ack) [if calendar enabled]
- Custom services (via /hub-custom)

Restart Claude Code to apply the new statusline.
```
