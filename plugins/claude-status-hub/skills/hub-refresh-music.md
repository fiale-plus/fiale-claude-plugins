---
name: hub-refresh-music
description: Lightweight music-only refresh for background daemon
---

# Hub Refresh Music (Lightweight)

Quick refresh that ONLY updates music/background status. Used by the 90-second daemon.

## Process

### Step 1: Read Config

```bash
cat ~/.claude/status-config.json
```

Extract:
- `background.service` - "youtube-music", "spotify", or "off"
- `background.tabId` - browser tab number

If service is "off" or not configured, exit immediately.

### Step 2: Get Music Status

Use the appropriate JavaScript based on service:

**YouTube Music:**
```javascript
{
  title: document.querySelector('.title.ytmusic-player-bar')?.textContent?.trim() || '',
  artist: document.querySelector('.byline.ytmusic-player-bar')?.textContent?.split('•')[0]?.trim() || '',
  isPlaying: document.querySelector('#play-pause-button')?.getAttribute('aria-label')?.toLowerCase().includes('pause')
}
```

**Spotify:**
```javascript
{
  title: document.querySelector('[data-testid="context-item-link"]')?.textContent?.trim() || '',
  artist: document.querySelector('[data-testid="context-item-info-artist"]')?.textContent?.trim() || '',
  isPlaying: document.querySelector('[data-testid="control-button-playpause"]')?.getAttribute('aria-label')?.toLowerCase().includes('pause')
}
```

### Step 3: Read Existing Bridge

```bash
cat /tmp/status-hub.json
```

Preserve the `foreground` array - we're only updating `background`.

### Step 4: Update Bridge

Run the update script with music data:

```bash
${CLAUDE_PLUGIN_ROOT}/bin/update-bridge.sh '<service>' '<icon>' '<title>' '<artist>' --foreground '<preserved-foreground-json>'
```

- Icon: `▶` if playing, `⏸` if paused
- Truncate title to 30 chars, artist to 25 chars
- Sanitize: escape backslashes, remove control characters

### Important

- This is a FAST refresh - no PR checks, no Sentry, no finance
- If Chrome tab is not accessible, fail silently
- Preserve foreground array exactly as-is
- Update timestamp so statusline knows data is fresh
