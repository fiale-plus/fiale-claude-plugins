# Hub Music - Contextual Music Configuration

Configure automatic music reactions to status events like PR merges, meeting alerts, and focus mode.

## Events and Default Actions

| Event | Default Action | Description |
|-------|----------------|-------------|
| `pr_merged` | play "celebration music" (30s) | PR was merged |
| `ci_failed` | pause | CI checks failed |
| `meeting_starting` | pause | Meeting starting soon |
| `focus_started` | play "lo-fi focus music" | Focus mode activated |
| `focus_ended` | resume | Focus mode ended |
| `break_reminder` | pause | Break reminder triggered |

## Step 1: Check Arguments

```bash
ARG="${1:-}"
case "$ARG" in
  enable)  ACTION="enable" ;;
  disable) ACTION="disable" ;;
  status)  ACTION="status" ;;
  *)       ACTION="wizard" ;;
esac
```

## Step 2: Read Current Config

```bash
cat ~/.claude/status-config.json | jq '.music.contextual // {}'
```

Default structure:
```json
{
  "enabled": false,
  "cooldownSeconds": 120,
  "lastActionTimestamp": 0,
  "reactions": {
    "pr_merged": { "action": "play", "query": "celebration music", "duration": 30 },
    "ci_failed": { "action": "pause" },
    "meeting_starting": { "action": "pause" },
    "focus_started": { "action": "play", "query": "lo-fi focus music" },
    "focus_ended": { "action": "resume" },
    "break_reminder": { "action": "pause" }
  }
}
```

## Step 3: Handle Action

### Enable

```bash
jq '.music.contextual.enabled = true | .music.contextual.reactions //= {
  "pr_merged": { "action": "play", "query": "celebration music", "duration": 30 },
  "ci_failed": { "action": "pause" },
  "meeting_starting": { "action": "pause" },
  "focus_started": { "action": "play", "query": "lo-fi focus music" },
  "focus_ended": { "action": "resume" },
  "break_reminder": { "action": "pause" }
}' ~/.claude/status-config.json > /tmp/config.tmp && mv /tmp/config.tmp ~/.claude/status-config.json
```

Output:
```
🎵 Contextual music enabled

Default reactions:
  • PR merged → play celebration music (30s)
  • CI failed → pause
  • Meeting starting → pause
  • Focus started → play lo-fi focus music
  • Focus ended → resume
  • Break reminder → pause

Cooldown: 120 seconds between actions
Run /hub-music to customize reactions.
```

### Disable

```bash
jq '.music.contextual.enabled = false' ~/.claude/status-config.json > /tmp/config.tmp && mv /tmp/config.tmp ~/.claude/status-config.json
```

Output:
```
🎵 Contextual music disabled
```

### Status

Show current configuration in readable format:
```
🎵 Contextual Music: [enabled/disabled]

Reactions:
  • PR merged: [action] [query if play]
  • CI failed: [action]
  • Meeting starting: [action]
  • Focus started: [action] [query if play]
  • Focus ended: [action]
  • Break reminder: [action]

Cooldown: [N] seconds
Last action: [timestamp or "never"]
```

### Wizard

Present interactive configuration:

```json
{
  "questions": [{
    "question": "Configure contextual music reactions?",
    "header": "Music",
    "options": [
      {"label": "Enable defaults", "description": "Turn on with default reactions"},
      {"label": "Customize", "description": "Configure individual events"},
      {"label": "Disable", "description": "Turn off contextual music"}
    ],
    "multiSelect": false
  }]
}
```

If "Customize" selected, show per-event options:

```json
{
  "questions": [{
    "question": "What should happen when a PR is merged?",
    "header": "PR Merged",
    "options": [
      {"label": "Play celebration", "description": "Play 'celebration music' for 30s"},
      {"label": "Skip track", "description": "Skip to next track"},
      {"label": "Do nothing", "description": "No music action"}
    ],
    "multiSelect": false
  }]
}
```

Continue for each event type.

## Step 4: Save Config

After wizard completes:

```bash
jq --argjson config "$NEW_CONFIG" '.music.contextual = $config' \
  ~/.claude/status-config.json > /tmp/config.tmp && mv /tmp/config.tmp ~/.claude/status-config.json
```

## Actions Reference

| Action | Description |
|--------|-------------|
| `play` | Search and play query (optional `duration` seconds, then resume) |
| `pause` | Pause playback |
| `resume` | Resume playback |
| `skip` | Skip to next track |
| `none` | Disabled for this event |

## Requirements

- Music service must be configured (`/hub-setup` → background service)
- Chrome MCP must be available for browser automation (playback control)
- For browser-based players (YouTube Music): `brew install nowplaying-cli` recommended for zero-token status detection
