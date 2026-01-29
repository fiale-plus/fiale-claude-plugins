# Hub Refresh - Internal Skill

Refresh status hub efficiently.

## Error Handling

On failure: `${CLAUDE_PLUGIN_ROOT}/bin/update-bridge.sh --error "Brief error"`. Cleared on next successful refresh.

## Data Sanitization

See `lib-common.md`. Limits: title 30, detail 25, artist 20.

## Data Preservation

**See `docs/data-safety-guidelines.md` for merge patterns.**

Key rules:
- Never overwrite entire foreground array
- When refreshing one service, preserve items from other services
- Use `jq` merge operators (`+`, `|=`) not full replacement

## Step 1: Read Config

```bash
cat ~/.claude/status-config.json
```

Extract: `background.service`, `background.tabId`, `foreground[]`, `calendar`.

## Step 2: Refresh Background (Music)

Auto-recover tab if needed (see `connection-detect.md`).

**YouTube Music:**
```javascript
({ title: document.querySelector('.title.ytmusic-player-bar')?.textContent || '',
   artist: (document.querySelector('.byline.ytmusic-player-bar')?.textContent || '').split('•')[0].trim(),
   isPlaying: document.querySelector('#play-pause-button')?.getAttribute('aria-label')?.toLowerCase().includes('pause') })
```

**Spotify:**
```javascript
({ title: document.querySelector('[data-testid="context-item-link"]')?.textContent || '',
   artist: document.querySelector('[data-testid="context-item-info-artist"]')?.textContent || '',
   isPlaying: document.querySelector('[data-testid="control-button-playpause"]')?.getAttribute('aria-label')?.toLowerCase().includes('pause') })
```

Icon: `▶` playing, `⏸` paused.

## Step 2.5: Refresh Calendar

If `calendar.connection === "chrome"`: follow `hub-refresh-calendar.md`. Add to foreground only if upcoming meeting.

## Step 3: Refresh Foreground

For each item, check for skill: `${CLAUDE_PLUGIN_ROOT}/skills/hub-refresh-<service>.md` or `.user.md`.

### GitHub PRs

```bash
gh pr view <number> --repo <owner>/<repo> --json state,isDraft,reviewDecision,statusCheckRollup,title,comments,mergeable
```

Alert if: new comments, state change, checks failed, conflicts, or merge-ready.

Icon priority: `X` `⚡` `!` `~` `?` `D` `🚀` `✓`.

### Slack/Sentry

Follow respective `hub-refresh-*.md` skills.

## Step 4: Update Bridge

```bash
${CLAUDE_PLUGIN_ROOT}/bin/update-bridge.sh '<service>' '<icon>' '<title>' '<artist>' --foreground '<json-array>'
```

## Step 5: Write Config

Save `lastSeen` values and `hasAlert` flags.
