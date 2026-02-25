---
name: remote
description: Toggle remote-friendly mobile layout (on/off)
argument-hint: [off]
---

# Remote Layout

If `$ARGUMENTS` is `off`:
- Run: `jq '.remoteLayout = false' ~/.claude/status-config.json > /tmp/rl.json && mv /tmp/rl.json ~/.claude/status-config.json`
- Confirm deactivation in plain text

Otherwise (activate):
- Run: `jq '.remoteLayout = true' ~/.claude/status-config.json > /tmp/rl.json && mv /tmp/rl.json ~/.claude/status-config.json`
- Use the `remote-layout` skill to apply formatting for the rest of this session
- First response must use the new format as confirmation of activation
