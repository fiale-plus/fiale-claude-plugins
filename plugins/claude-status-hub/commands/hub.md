---
name: hub
description: Universal status hub - track PRs, music, email with custom alerts and actions
argument-hint: <service|pr-url|list|ack|manage|play|off>
---

# Status Hub - Main Router

Parse `$ARGUMENTS` and route to appropriate sub-skill:

| Pattern | Route |
|---------|-------|
| `list` | Use `hub-list` skill |
| `ack` or `ack #N` | Use `hub-ack` skill with argument |
| `manage` | Use `hub-manage` skill |
| `play <query>` | Use `hub-play` skill with query |
| `off`, `clear`, `disable` | Use `hub-off` skill |
| `setup` | Use `hub-setup` skill |
| `custom <service>` | Use `hub-custom` skill |
| GitHub PR URL(s) | Track PR(s) - see below |
| Known service name | Set background - see below |
| Unknown service | Check for custom skill or redirect to `/hub-custom` |

## Initialization (always first)

Before any operation, ensure config files exist:

1. If `~/.claude/status-config.json` doesn't exist, create it:
   ```json
   {
     "background": null,
     "foreground": []
   }
   ```

2. If `/tmp/status-hub.json` doesn't exist, create it:
   ```json
   {"timestamp": null, "background": null, "foreground": []}
   ```

## Track GitHub PR(s)

If argument contains GitHub PR URL(s) (`github.com/.../pull/...`):

1. Parse owner, repo, and PR number from each URL
2. Run gh CLI to get PR status:
```bash
gh pr view <number> --repo <owner>/<repo> --json state,isDraft,reviewDecision,statusCheckRollup,title,number,comments --jq '{
  state,isDraft,reviewDecision,title,number,
  checksCount: (.statusCheckRollup | length),
  checksPassed: ([.statusCheckRollup[] | select(.conclusion == "SUCCESS")] | length),
  checksFailed: ([.statusCheckRollup[] | select(.conclusion == "FAILURE")] | length),
  checksPending: ([.statusCheckRollup[] | select(.conclusion == null or .conclusion == "PENDING")] | length),
  commentsCount: (.comments | length)
}'
```
3. Determine status icon (worst wins):
   - X = Checks failing
   - ~ = Checks pending
   - ! = Changes requested
   - ? = Review required
   - D = Draft
   - ✓ = Approved + all checks pass
4. Read `~/.claude/status-config.json` for lastSeen state
5. Update config with new PR(s) in `foreground` array
6. Write bridge file `/tmp/status-hub.json` - set timestamp at root, preserve `background`, update `foreground` array:
   ```json
   {
     "timestamp": 1705000000000,
     "background": { ... preserve existing ... },
     "foreground": [
       {
         "site": "github-pr",
         "icon": "X",
         "title": "PR #123",
         "detail": "2 failing",
         "hasAlert": true
       }
     ]
   }
   ```
   Note: `hasAlert` drives display mode (expanded vs compact). Foreground is an array supporting multiple tracked items.

   **IMPORTANT:** When writing bridge, always fetch current background status from browser tab first - never use stale/placeholder values.
7. Say "Tracking PR #N: [status]"

## Set Background Service

If argument is a service name (`youtube-music`, `spotify`, `gmail`):

1. Get browser tabs via `mcp__claude-in-chrome__tabs_context_mcp`
2. Find tab for service or navigate to it
3. Extract status using service-specific JavaScript (see extraction details below)
4. Update `~/.claude/status-config.json` with `background.service`, `background.tabId`, and extracted details
5. Write bridge file `/tmp/status-hub.json` - set timestamp at root, update `background`, preserve `foreground`:
   ```json
   {
     "timestamp": 1705000000000,
     "background": {"site": "youtube-music", "icon": ">", "title": "Song", "detail": "Artist"},
     "foreground": [ ... preserve existing array ... ]
   }
   ```
6. Say "Background: [service] - [status]"

## Service Extraction

### youtube-music
```javascript
(() => {
  const title = document.querySelector('ytmusic-player-bar .title')?.textContent || '';
  const artist = document.querySelector('ytmusic-player-bar .byline')?.textContent || '';
  const isPlaying = document.querySelector('ytmusic-player-bar #play-pause-button')?.getAttribute('aria-label')?.toLowerCase().includes('pause') || false;
  return JSON.stringify({
    site: 'youtube-music',
    icon: isPlaying ? '>' : '||',
    title, detail: artist
  });
})()
```

### spotify
```javascript
(() => {
  const track = document.querySelector('[data-testid="now-playing-widget"] [data-testid="context-item-link"]')?.textContent || '';
  const artist = document.querySelector('[data-testid="now-playing-widget"] [data-testid="context-item-info-artist"]')?.textContent || '';
  const isPlaying = document.querySelector('[data-testid="control-button-playpause"]')?.getAttribute('aria-label')?.toLowerCase().includes('pause') || false;
  return JSON.stringify({
    site: 'spotify',
    icon: isPlaying ? '>' : '||',
    title: track, detail: artist
  });
})()
```

### gmail
```javascript
(() => {
  const match = document.title.match(/\(([0-9]+)\)/);
  const unreadCount = match?.[1] || '0';
  const latestSubject = document.querySelector('tr.zE .bog')?.textContent?.substring(0, 30) || '';
  return JSON.stringify({
    site: 'gmail',
    icon: 'M',
    title: unreadCount + ' unread',
    detail: latestSubject
  });
})()
```

## Unknown Service Handling

If the argument doesn't match any known pattern above:

1. Check if a custom skill exists:
   ```bash
   ls ${CLAUDE_PLUGIN_ROOT}/skills/hub-refresh-<service>*.md 2>/dev/null
   ```

2. If skill found (`hub-refresh-<service>.md` or `hub-refresh-<service>.user.md`):
   - Use the skill to set up tracking
   - Add to config and start monitoring

3. If no skill found:
   - **Automatically invoke `/hub-custom` skill** with the user's request
   - Do NOT tell the user to run `/hub-custom` themselves - just do it for them
   - This provides better UX by seamlessly handling unknown services
