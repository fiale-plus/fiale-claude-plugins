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

#### 9.1 Detect Available Connection Methods

Before presenting options, check what's installed:

```javascript
// Check Chrome MCP
let chromeStatus = { installed: false, ready: false };
try {
  const context = await mcp__claude-in-chrome__tabs_context_mcp({ createIfEmpty: false });
  chromeStatus = { installed: true, ready: !context.error };
} catch (e) {
  // Not installed or not responding
  chromeStatus = { installed: false, ready: false };
}

// Check Playwright MCP
let playwrightStatus = { installed: false, ready: false };
try {
  const result = await mcp__playwright__browser_navigate({ url: 'about:blank' });
  playwrightStatus = { installed: true, ready: !result.error };
} catch (e) {
  playwrightStatus = { installed: false, ready: false };
}
```

#### 9.2 Present Consolidated Calendar Wizard

Show ALL connection methods with dynamic status indicators:

```json
{
  "questions": [{
    "question": "Would you like to enable Google Calendar meeting alerts?\n\nThis shows upcoming meetings in your statusline and lets you take actions (join, send 'running late' messages) via /hub-ack.",
    "header": "Calendar",
    "options": [
      {
        "label": "Chrome browser tab",
        "description": "<dynamic: '✓ Ready - uses open Calendar tab' if chromeStatus.installed, else '⚠️ Requires Claude-in-Chrome extension'>"
      },
      {
        "label": "Playwright (headless)",
        "description": "<dynamic: '✓ Ready - works in background' if playwrightStatus.installed, else '⚠️ Requires Playwright MCP server'>"
      },
      {
        "label": "Skip for now",
        "description": "Configure later with /hub-setup-gcalendar"
      }
    ],
    "multiSelect": false
  }]
}
```

Build the actual AskUserQuestion call with computed descriptions:

```javascript
const chromeDesc = chromeStatus.installed
  ? "✓ Ready - uses open Calendar tab"
  : "⚠️ Requires Claude-in-Chrome extension";

const playwrightDesc = playwrightStatus.installed
  ? "✓ Ready - works in background"
  : "⚠️ Requires Playwright MCP server";
```

#### 9.3 Handle User Selection

**If user selects Chrome:**

- **If Chrome is installed:**
  1. Ask user to open Google Calendar in Chrome
  2. Use `mcp__claude-in-chrome__tabs_context_mcp` to find the tab
  3. Store tab ID and proceed to alert timing (9.4)

- **If Chrome is NOT installed:**
  Show installation guidance:
  ```
  📦 Installing Claude-in-Chrome Extension

  The Claude-in-Chrome extension is required for this option.

  1. Install from Chrome Web Store (search "Claude in Chrome")
  2. Click the extension icon and sign in
  3. Restart Claude Code session

  After installing, run /hub-setup again to continue calendar setup.
  ```
  Set `calendar.connection: "disabled"` and continue to Step 10.

**If user selects Playwright:**

- **If Playwright is installed:**
  1. Prompt user to log in via Playwright browser if needed
  2. Verify login state with `mcp__playwright__browser_navigate`
  3. Proceed to alert timing (9.4)

- **If Playwright is NOT installed:**
  Show installation guidance:
  ```
  📦 Installing Playwright MCP

  The Playwright MCP server is required for this option.

  1. Add to your Claude Code MCP settings:
     {
       "mcpServers": {
         "playwright": {
           "command": "npx",
           "args": ["@playwright/mcp@latest"]
         }
       }
     }

  2. Restart Claude Code session

  After installing, run /hub-setup again to continue calendar setup.
  ```
  Set `calendar.connection: "disabled"` and continue to Step 10.

**If user selects Skip:**
- Set `calendar.connection: "disabled"`
- Continue to Step 10

#### 9.4 Configure Alert Timing (After Connection Success)

Only show this if a connection method was successfully configured:

```json
{
  "questions": [{
    "question": "When should calendar alerts appear?",
    "header": "Alerts",
    "options": [
      {"label": "5 minutes before", "description": "Standard reminder (Recommended)"},
      {"label": "10 minutes before", "description": "More time to wrap up"},
      {"label": "Custom", "description": "Set your own timing"}
    ],
    "multiSelect": false
  }]
}
```

If "Custom" selected, ask for minutes:
```json
{
  "questions": [{
    "question": "How many minutes before meetings should alerts appear?",
    "header": "Minutes",
    "options": [
      {"label": "3 minutes", "description": "Quick heads-up"},
      {"label": "15 minutes", "description": "Plenty of preparation time"},
      {"label": "30 minutes", "description": "Early warning"}
    ],
    "multiSelect": false
  }]
}
```

#### 9.5 Save Calendar Configuration

```javascript
config.calendar = {
  connection: "<selected-method>",  // "chrome", "playwright", or "disabled"
  chrome: { tabId: <found-tab-id-or-null> },
  playwright: { profile: "default", headless: false },
  alertMinutesBefore: <selected-minutes>,  // 5, 10, or custom
  alertWithDocsBefore: <selected-minutes + 5>,
  lateMessageTo: "organizer"
};
```

#### 9.6 Confirm Calendar Setup

If successfully configured:
```
Calendar configured!

Connection: <Chrome tab | Playwright>
<if Chrome: Tab ID: <id>>
Alerts: <X> minutes before meetings

Keep the calendar tab open for best results.
```

If skipped or installation needed:
```
Calendar setup skipped.

Run /hub-setup-gcalendar anytime to configure calendar integration.
```

### Step 10: Confirm Setup

Say:
```
Status Hub configured!

Base prompt: <describe what was preserved or "default">
<if legacy daemon was killed: "Cleaned up legacy daemon (pre-auto-death version)">
<if calendar enabled: "Calendar: Enabled via <Chrome|Playwright> (alerts <X>min before meetings)">
<if calendar disabled: "Calendar: Disabled (enable anytime with /hub-setup-gcalendar)">

Your statusline will now show:
- Git branch and dirty state
- Music playback (via /hub-play)
- PR status (via /hub <pr-url>)
- Meeting alerts (via /hub-ack) [if calendar enabled]
- Custom services (via /hub-custom)

Restart Claude Code to apply the new statusline.
```
