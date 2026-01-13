---
name: hub-setup
description: Configure Status Hub statusline integration
---

# Hub Setup

Configure Claude Code to use Status Hub's statusline.

## Process

1. Read current `~/.claude/settings.json`

2. Update `statusLine` to use the plugin's script:
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "${CLAUDE_PLUGIN_ROOT}/bin/statusline.sh"
     }
   }
   ```

3. Add permissions for background refresh (allows status updates without prompts):
   ```json
   {
     "permissions": {
       "allow": [
         "Read(${HOME}/.claude/status-config.json)",
         "Write(${HOME}/.claude/status-config.json)",
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

   Merge with existing permissions if present.

   Explain to user: "These permissions allow the background status refresh to run without interrupting you with prompts."

4. Preserve all other settings in the file

5. Write updated settings

6. Ensure config files exist and clear any stale errors:
   - `~/.claude/status-config.json`: `{"background": null, "foreground": []}`
   - `/tmp/status-hub.json`: `{"timestamp": null, "background": null, "foreground": []}`
   - Clear error file: `rm -f /tmp/status-hub-error.txt`

7. Say:
   ```
   Status Hub configured! Your statusline will now show:
   - Git branch and dirty state
   - Music playback (via /hub-play)
   - PR status (via /hub <pr-url>)
   - Email count (via /hub gmail)

   Restart Claude Code to apply the new statusline.
   ```
