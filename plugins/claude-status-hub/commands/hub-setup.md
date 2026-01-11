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

3. Add permission for background refresh (allows hook to update status without prompts):
   ```json
   {
     "permissions": {
       "allow": [
         "Bash(${CLAUDE_PLUGIN_ROOT}/bin/update-bridge.sh:*)"
       ]
     }
   }
   ```

   Note: Replace `${CLAUDE_PLUGIN_ROOT}` with the actual plugin path when writing. Merge with existing permissions if present.

4. Preserve all other settings in the file

5. Write updated settings

6. Ensure config files exist:
   - `~/.claude/status-config.json`: `{"background": null, "foreground": []}`
   - `/tmp/status-hub.json`: `{"timestamp": null, "background": null, "foreground": []}`

7. Say:
   ```
   Status Hub configured! Your statusline will now show:
   - Git branch and dirty state
   - Music playback (via /hub-play)
   - PR status (via /hub <pr-url>)
   - Email count (via /hub gmail)

   Restart Claude Code to apply the new statusline.
   ```
