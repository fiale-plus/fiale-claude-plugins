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
      "mcp__plugin_sentry_sentry__search_issues"
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

### Step 9: Confirm Setup

Say:
```
Status Hub configured!

Base prompt: <describe what was preserved or "default">

Your statusline will now show:
- Git branch and dirty state
- Music playback (via /hub-play)
- PR status (via /hub <pr-url>)
- Custom services (via /hub-custom)

Restart Claude Code to apply the new statusline.
```
