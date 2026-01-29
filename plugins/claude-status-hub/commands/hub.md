---
name: hub
description: Universal status hub - track PRs, music, email with custom alerts and actions
argument-hint: <service|pr-url|list|ack|manage|play|off>
---

# Status Hub - Main Router

Parse `$ARGUMENTS` and route:

| Pattern | Route |
|---------|-------|
| `list` | `hub-tree` |
| `ack [#N]` | `hub-ack` |
| `manage` | `hub-manage` |
| `play <query>` | `hub-play` |
| `off`/`clear`/`disable` | `hub-off` |
| `setup` | `hub-setup` |
| `custom <service>` | `hub-custom` |
| GitHub PR URL(s) | Track PR(s) |
| Known service | Set background |
| Unknown | Check for custom skill or invoke `/hub-custom` |

## Init

Ensure `~/.claude/status-config.json` and `/tmp/status-hub.json` exist with default structure.

## Track GitHub PR(s)

If URL contains `github.com/.../pull/...`:

```bash
gh pr view <number> --repo <owner>/<repo> --json state,isDraft,reviewDecision,statusCheckRollup,title,number,comments --jq '{
  state,isDraft,reviewDecision,title,number,
  checksCount: (.statusCheckRollup | length),
  checksPassed: ([.statusCheckRollup[] | select(.conclusion == "SUCCESS")] | length),
  checksFailed: ([.statusCheckRollup[] | select(.conclusion == "FAILURE")] | length),
  checksPending: ([.statusCheckRollup[] | select(.conclusion == null or .conclusion == "PENDING")] | length)
}'
```

Icon priority: `X` fails, `~` pending, `!` changes requested, `?` review needed, `D` draft, `🚀` merge-ready, `✓` approved.

Update config foreground array, write bridge with timestamp: `$(($(date +%s) * 1000))`.

## Set Background Service

Get browser tab via `mcp__claude-in-chrome__tabs_context_mcp`, extract status via JavaScript.

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

**Gmail:** Extract unread count from `document.title.match(/\(([0-9]+)\)/)?.[1]`.

Update background in config and bridge.

## Unknown Service

Check for `${CLAUDE_PLUGIN_ROOT}/skills/hub-refresh-<service>.md` or `.user.md`. If found, use it. Otherwise, invoke `/hub-custom` automatically.
