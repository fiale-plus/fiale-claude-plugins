---
name: hub-ack
description: Acknowledge hub alerts
argument-hint:
---

# Hub Ack - Acknowledge Alerts

Clear hub error state.

## Action

1. Delete the error file if it exists:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/update-bridge.sh --clear-error
   ```

2. Confirm: "Hub error cleared"
