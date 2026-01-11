---
name: hub-off
description: Disable all hub tracking
---

# Hub Off - Clear All Tracking

Stop all status tracking and clean up files.

## Process

1. Delete config file:
```bash
rm -f ~/.claude/status-config.json
```

2. Delete bridge file:
```bash
rm -f /tmp/status-hub.json
```

3. Say "Status tracking disabled. Status line will show git info only."

## Aliases

This skill handles: `off`, `clear`, `disable`, `stop`
