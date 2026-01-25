# Hub Refresh - Internal Skill

Refresh status hub background and foreground items efficiently.

## Error Handling

If ANY tool call fails, write error and stop:
```bash
${CLAUDE_PLUGIN_ROOT}/bin/update-bridge.sh --error "Refresh failed: <brief description>"
```

Error is cleared on successful refresh or when user runs `/hub-setup` or `/hub-ack`.

## Data Sanitization

All text fields written to bridge MUST be sanitized:
```javascript
function sanitize(str, maxLen = 30) {
  return (str || '').replace(/[\n\r\t]/g, ' ').replace(/\\/g, '\\\\').substring(0, maxLen).trim();
}
```
Limits: title 30 chars, detail 25 chars, artist 20 chars.

## Step 1: Read Config

```bash
cat ~/.claude/status-config.json
```

Extract: `background.service`, `background.tabId`, `foreground[]`, `calendar` config.

## Step 2: Refresh Background (Music)

If `background.service` has `tabId`, run via javascript_tool:

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

If `calendar.connection === "chrome"` and `calendar.chrome.tabId` exists:
- Follow `hub-refresh-calendar.md`
- Only add to foreground if there's an upcoming meeting (returns non-null)
- No meetings = skip (silence is the signal)

## Step 3: Refresh Foreground Items

For each item in `foreground[]`, check for skill first:
1. Built-in: `${CLAUDE_PLUGIN_ROOT}/skills/hub-refresh-<service>.md`
2. User-authored: `${CLAUDE_PLUGIN_ROOT}/skills/hub-refresh-<service>.user.md`

### GitHub PRs (items with `.owner` field)
```bash
gh pr view <number> --repo <owner>/<repo> --json state,isDraft,reviewDecision,statusCheckRollup,title,comments,mergeable,mergeStateStatus
```

**Alert if:** new comments, state change, review decision change, checks failed, conflicts, or merge-ready.

**Icon priority:** `X` fails, `⚡` conflicts, `!` changes requested, `~` pending, `?` review needed, `D` draft, `🚀` merge-ready, `✓` approved.

### Slack (`.service == "slack"`)
Follow `hub-refresh-slack.md`.

### Sentry (`.service == "sentry"`)
Use `mcp__plugin_sentry_sentry__search_issues` for unresolved issues.

## Step 4: Update Bridge

```bash
${CLAUDE_PLUGIN_ROOT}/bin/update-bridge.sh '<service>' '<icon>' '<title>' '<artist>' --foreground '<json-array>'
```

## Step 5: Write Updated Config

Save changes to `~/.claude/status-config.json` (lastSeen values, hasAlert flags).
