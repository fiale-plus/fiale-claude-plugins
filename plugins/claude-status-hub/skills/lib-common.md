# Shared Utilities

Common patterns for hub skills. Reference-only - copy code as needed.

## Sanitize

```javascript
const sanitize = (s, max = 30) => (s || '').replace(/[\n\r\t]/g, ' ').replace(/\\/g, '\\\\').substring(0, max).trim();
```
Limits: title 30, detail 25, artist 20.

## Update Bridge After Ack

```bash
FOREGROUND=$(jq -c '.foreground // []' ~/.claude/status-config.json)
BACKGROUND=$(jq -c '.background // {}' /tmp/status-hub.json)
${CLAUDE_PLUGIN_ROOT}/bin/update-bridge.sh \
  "$(echo "$BACKGROUND" | jq -r '.site')" \
  "$(echo "$BACKGROUND" | jq -r '.icon')" \
  "$(echo "$BACKGROUND" | jq -r '.title')" \
  "$(echo "$BACKGROUND" | jq -r '.detail')" \
  --foreground "$FOREGROUND"
```

## Error State

```bash
${CLAUDE_PLUGIN_ROOT}/bin/update-bridge.sh --error "Brief error"
${CLAUDE_PLUGIN_ROOT}/bin/update-bridge.sh --clear-error
```

## Config Update Pattern

Mark alert handled in config, then update bridge:
```bash
jq '.foreground |= map(if .site == "<service>" then .hasAlert = false else . end)' \
  ~/.claude/status-config.json > /tmp/cfg.tmp && mv /tmp/cfg.tmp ~/.claude/status-config.json
# Then: Update Bridge (above)
```
