# Hub Refresh - Internal Skill

Refresh status hub background and foreground items efficiently.

## Error Handling

If ANY tool call fails (permission denied, timeout, etc.):

1. Write error to dedicated error file using the update script:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/update-bridge.sh --error "Refresh failed: <brief description>"
   ```

2. Stop processing - don't continue with partial data.

The statusline script checks the error file (`/tmp/status-hub-error.txt`) FIRST, before the bridge file, and displays errors in red.

**Error is cleared when:**
- Refresh completes successfully (automatic)
- User runs `/hub-setup`
- User runs `/hub-ack`

## Data Sanitization

All text fields written to the bridge file MUST be sanitized:

1. **Escape backslashes** - The statusline uses `printf '%b'` which interprets escape sequences:
   - `\` → `\\` (literal backslash)
   - `\n`, `\t` etc. would be interpreted as escapes

2. **Truncate long strings** - Keep titles/details reasonable:
   - `title`: max 30 chars
   - `detail`: max 25 chars
   - `artist`: max 20 chars

3. **Strip control characters** - Remove newlines, tabs, and non-printable chars

Example sanitization in JavaScript:
```javascript
function sanitize(str, maxLen = 30) {
  return (str || '')
    .replace(/[\n\r\t]/g, ' ')
    .replace(/\\/g, '\\\\')
    .substring(0, maxLen)
    .trim();
}
```

Example in bash/jq:
```bash
# When building JSON, escape backslashes in values
echo "$value" | sed 's/\\/\\\\/g' | tr -d '\n\r' | cut -c1-30
```

## Step 1: Read Config

```bash
cat ~/.claude/status-config.json
```

Extract:
- `background.service` (youtube-music, spotify, or null)
- `background.tabId` (browser tab ID)
- `foreground[]` array (PRs, Slack workspaces, etc.)
- `calendar` config (connection type, tabId, alert thresholds)

## Step 2: Refresh Background (Music)

If `background.service` exists and has a `tabId`:

### YouTube Music
```javascript
// Run via javascript_tool on background.tabId
({
  title: document.querySelector('.title.ytmusic-player-bar')?.textContent || '',
  artist: (document.querySelector('.byline.ytmusic-player-bar')?.textContent || '').split('•')[0].trim(),
  isPlaying: document.querySelector('#play-pause-button')?.getAttribute('aria-label')?.toLowerCase().includes('pause')
})
```

### Spotify
```javascript
({
  title: document.querySelector('[data-testid="context-item-link"]')?.textContent || '',
  artist: document.querySelector('[data-testid="context-item-info-artist"]')?.textContent || '',
  isPlaying: document.querySelector('[data-testid="control-button-playpause"]')?.getAttribute('aria-label')?.toLowerCase().includes('pause')
})
```

Icon: `▶` if playing, `⏸` if paused.

## Step 2.5: Refresh Calendar (if enabled)

Check if calendar is configured:
```javascript
if (config.calendar && config.calendar.connection === "chrome" && config.calendar.chrome?.tabId) {
  // Calendar is enabled, refresh it
}
```

If calendar is enabled:
1. Read and follow `${CLAUDE_PLUGIN_ROOT}/skills/hub-refresh-calendar.md`
2. The calendar skill will return a foreground item to add to the bridge

If calendar refresh fails (tab not found, etc.):
- Log error but continue with other refreshes
- Don't add calendar to foreground items

## Step 3: Refresh Foreground Items

For each item in `foreground[]`:

### Check for Custom Skill First

Before using built-in logic, check if a service-specific skill exists:
1. Built-in: `${CLAUDE_PLUGIN_ROOT}/skills/hub-refresh-<service>.md`
2. User-authored: `${CLAUDE_PLUGIN_ROOT}/skills/hub-refresh-<service>.user.md`

If found, read and follow that skill for this item's refresh logic.

### Built-in Service Types

If no custom skill exists, use the built-in logic based on item type:

### Calendar

Calendar is handled separately in Step 2.5 (not in foreground[] array).
See `hub-refresh-calendar.md` for browser-based calendar refresh via Chrome MCP.

### GitHub PRs (items with `.owner` field)

For each PR item:
```bash
gh pr view <number> --repo <owner>/<repo> --json state,isDraft,reviewDecision,statusCheckRollup,title,comments,mergeable,mergeStateStatus --jq '{
  state, isDraft, reviewDecision, title, mergeable, mergeStateStatus,
  commentsCount: (.comments | length),
  checksCount: (.statusCheckRollup | length),
  checksPassed: ([.statusCheckRollup[] | select(.conclusion == "SUCCESS")] | length),
  checksFailed: ([.statusCheckRollup[] | select(.conclusion == "FAILURE")] | length)
}'
```

**Alert Detection** - set `hasAlert: true` if ANY:
- `commentsCount > lastSeen.commentsCount`
- `state != lastSeen.state`
- `reviewDecision != lastSeen.reviewDecision`
- Checks failed when they weren't before
- `mergeable` changed to "CONFLICTING" (new conflicts!)
- PR became merge-ready (approved + checks pass + no conflicts)

**Status Icon Priority (worst wins):**
1. `X` = checks failing
2. `⚡` = merge conflicts (`mergeable == "CONFLICTING"`)
3. `!` = changes requested
4. `~` = checks pending
5. `?` = review required
6. `D` = draft
7. `🚀` = ready to merge (approved + all checks pass + `mergeable == "MERGEABLE"` + not draft)
8. `✓` = approved (but not all conditions for merge-ready)

**Merge-Ready Detection:**
A PR is merge-ready when ALL conditions are met:
- `state == "OPEN"`
- `isDraft == false`
- `reviewDecision == "APPROVED"`
- `checksFailed == 0` and `checksCount > 0` and all checks passed
- `mergeable == "MERGEABLE"`

When merge-ready, show `🚀` icon and optionally trigger alert.

Update the item's fields in config (preserve other items).

### Slack (items with `.service == "slack"`)

For each Slack item:
```javascript
// Run via javascript_tool on item.tabId
parseInt(document.querySelector('.p-team_sidebar__mentions_badge')?.textContent || '0', 10)
```

**Alert Detection:**
- `hasAlert: true` if `unreadCount > lastSeen.unreadCount`

Update `lastSeen.unreadCount` in config.

### Sentry (items with `.service == "sentry"`)

For each Sentry item:
```
mcp__plugin_sentry_sentry__search_issues(
  organizationSlug: item.organizationSlug,
  projectSlugOrId: item.projectSlug,
  regionUrl: item.regionUrl,
  naturalLanguageQuery: "unresolved issues from last 24 hours",
  limit: 10
)
```

From results:
- Count total unresolved issues
- Get the most recent issue title (truncated)

**Alert Detection:**
- `hasAlert: true` if `issueCount > lastSeen.issueCount`

**Status Icon:**
- `🔥` = has unresolved issues
- `✓` = no issues

**Bridge output:**
```json
{
  "site": "sentry",
  "icon": "🔥",
  "title": "<count> issues",
  "detail": "<project or latest issue>",
  "hasAlert": <true if new issues>
}
```

Update `lastSeen.issueCount` in config.

## Step 4: Update Bridge

Build foreground array for bridge (ALL items):
```json
[
  {"site": "github-pr", "icon": "?", "title": "PR #N", "detail": "status", "hasAlert": false},
  {"site": "slack", "icon": "💬", "title": "workspace", "detail": "N unreads", "hasAlert": true}
]
```

Run update script:
```bash
${CLAUDE_PLUGIN_ROOT}/bin/update-bridge.sh '<service>' '<icon>' '<title>' '<artist>' --foreground '<json-array>'
```

Where:
- `<service>` = background service name (or "off")
- `<icon>` = `▶` (playing) or `⏸` (paused)
- `<title>` = song/track title
- `<artist>` = artist name
- `<json-array>` = stringified foreground array

## Step 5: Write Updated Config

Save any changes to `~/.claude/status-config.json` (update lastSeen values, hasAlert flags).
