---
name: hub-play
description: Control music playback via browser
argument-hint: <query|skip|pause|resume>
---

# Hub Play - Music Control

Control music playback on YouTube Music or Spotify.

## Parse Argument

- `play <query>` - Search and play
- `skip` or `next` - Skip to next track
- `pause` - Pause playback
- `resume` or `unpause` - Resume playback

## Get Music Tab

1. Read `~/.claude/status-config.json` for `background.service` and `background.tabId`
2. If no background service, check browser tabs for music.youtube.com or open.spotify.com
3. If no music tab found, open a new tab with YouTube Music (default) or ask user preference

## Play Query

1. Navigate to search on the music service:
   - YouTube Music: `https://music.youtube.com/search?q=<encoded-query>`
   - Spotify: `https://open.spotify.com/search/<encoded-query>`
2. Wait for page load
3. Click first result or shuffle play button
4. Update status and say "Playing: [result]"

## Skip Track

Execute on music tab:
```javascript
// YouTube Music
document.querySelector('.next-button')?.click();

// Spotify
document.querySelector('[data-testid="control-button-skip-forward"]')?.click();
```

## Pause/Resume

Execute on music tab:
```javascript
// YouTube Music
document.querySelector('#play-pause-button')?.click();

// Spotify
document.querySelector('[data-testid="control-button-playpause"]')?.click();
```

## Update Status

After any action:

1. **Ensure config exists** - if `~/.claude/status-config.json` doesn't exist, create:
   ```json
   {"background": null, "foreground": []}
   ```

2. **Update config** with background service:
   ```json
   {
     "background": {
       "service": "youtube-music",  // or "spotify"
       "tabId": <tab-id>
     }
   }
   ```

3. **Get playback info** via JavaScript:
   ```javascript
   // YouTube Music
   ({
     title: document.querySelector('.title.ytmusic-player-bar')?.textContent,
     artist: document.querySelector('.byline.ytmusic-player-bar')?.textContent,
     isPlaying: document.querySelector('#play-pause-button')?.getAttribute('aria-label')?.includes('Pause')
   })
   ```

4. **Write bridge file** using helper script:
   ```bash
   # Use ▶ for playing, ⏸ for paused
   ${CLAUDE_PLUGIN_ROOT}/bin/update-bridge.sh "youtube-music" "▶" "<song title>" "<artist>"
   ```
