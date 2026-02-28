# Claude Status Hub

**Your world at a glance, without leaving the terminal.**

[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-Plugin-blueviolet)](https://docs.anthropic.com/en/docs/claude-code)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](../../LICENSE)

Track PRs, calendar, Slack, stocks, music—all surfaced in your Claude Code statusline.

## The Workflow

Status Hub follows a simple paradigm:

```
/hub-setup          →  Configure statusline integration
       ↓
/hub-<service>      →  Add monitors (PRs, calendar, slack, finance)
       ↓
[statusline alert]  →  Non-blocking notification appears
       ↓
/hub-ack            →  Smart actions based on context
```

**The key insight:** Alerts don't interrupt you. They sit in your statusline until you're ready. When you type `/hub-ack`, you get context-aware actions—not a generic "dismiss" button.

## See It In Action

### PR CI Fails

You're coding. Statusline shows: `X#142`

```
/hub-ack

❌ PR #142 CI Failed - test_auth.py

   [1] Re-run failed checks
   [2] Re-run full CI
   [3] Investigate & fix
   [4] View logs
   [5] 🔄 Fix loop
   [d] Dismiss
```

You pick "Fix loop". Claude reads the logs, patches the code, pushes. CI re-runs. Statusline updates to `~#142` (pending), then `✓#142` (passing).

### Meeting in 5 Minutes

Statusline shows: `📅 Standup 5m`

```
/hub-ack

📅 Team Standup - starting in 5m

   🔗 https://meet.google.com/abc-defg-hij

   [1] Join early
   [2] Remind in 2 min
   [3] DM: "I'll be ~5 min late"
   [c] Custom message
   [d] Dismiss

   📋 Context handoff prints below if you join.
```

You pick "Join now". Claude opens the meet link and shows:
```
📋 Session Context
━━━━━━━━━━━━━━━━━━━━
   Project: ~/repos/my-app
   Recent: Modified auth.ts, user.ts
   Todos: Refactor login flow (in progress)
━━━━━━━━━━━━━━━━━━━━
```

### VIP Slack During Focus

You started `/hub-focus` for 2 hours. Statusline shows: `🔕 Focus 45m | 💬 @boss`

```
/hub-ack

💬 Message from @boss
   2 min ago

   "Quick question about the deploy"

   Reply options:
   [1] "On it!"
   [2] "Let me check and get back to you"
   [3] "Thanks, will follow up"
   [4] "Got it, working on this now"
   [c] Custom reply
   [v] View full thread
   [d] Dismiss
```

You pick option 2. Boss gets the message. You stay in flow.

### Stock Price Alert

Statusline shows: `📈 AAPL +5.2%`

```
/hub-ack

📊 AAPL crossed your 5% alert threshold

   Current: $245.50 (+5.2% today)

   [1] Dismiss
   [2] Update threshold
```

## Quick Start

```bash
# Add marketplace and install
/plugin marketplace add fiale-plus/fiale-claude-plugins
/plugin install claude-status-hub

# Setup statusline
/hub-setup

# Track a PR
/hub https://github.com/owner/repo/pull/123

# Play music
/hub-play daft punk

# See everything
/hub-tree
```

## Services & Features

### GitHub PRs

| Aspect | Details |
|--------|---------|
| **Track** | PR status, CI results, reviews, comments, conflicts |
| **Alert when** | CI fails, conflicts appear, review requested, comments added, ready to merge |
| **Ack actions** | Re-run CI, fix loop (AI fixes + pushes), resolve conflicts, merge, view logs |
| **Setup** | `/hub <pr-url>` or `/hub <pr-url> automerge` |

**Auto-merge:** Add `automerge` to automatically merge when approved + CI passes. Shows `🔁` indicator.

**Status icons:**

| Icon | Meaning |
|------|---------|
| `✓` | Approved and checks passing |
| `?` | Review pending |
| `!` | Changes requested |
| `X` | Checks failing |
| `~` | Checks running |
| `D` | Draft PR |
| `🚀` | Ready to merge |

### Google Calendar

| Aspect | Details |
|--------|---------|
| **Track** | Next meeting, start time, attendees, meeting link |
| **Alert when** | 5-10 min before, meeting starting, meeting overdue |
| **Ack actions** | Join meeting, remind later, DM "running late", context handoff |
| **Setup** | `/hub-setup` (Chrome MCP) or `/hub-setup-gcalendar` (API fallback) |

### Slack

| Aspect | Details |
|--------|---------|
| **Track** | VIP DMs, watched channels |
| **Alert when** | New message from VIP, mention in watched channel |
| **Ack actions** | Smart reply templates, custom reply, view thread, mark read |
| **Setup** | `/hub-setup` (Chrome MCP) or `/hub-setup-slack` (API fallback) |

**Smart replies adapt to context:**
- Question → "Let me check and get back to you"
- Request/task → "On it!" or "Got it, working on this now"
- FYI → "Thanks, will follow up"

### Focus Mode

| Aspect | Details |
|--------|---------|
| **Track** | Focus session duration, break reminders |
| **Alert when** | Break needed (75min+), meeting conflict, VIP message (if allowed) |
| **Ack actions** | Take break (+ set Slack status), snooze, end focus, quick reply to VIP |
| **Setup** | `/hub-focus` |

### Finance

| Aspect | Details |
|--------|---------|
| **Track** | Stock/crypto prices (AAPL, BTC, etc.) |
| **Alert when** | Price moves beyond threshold (default 5%) |
| **Ack actions** | Dismiss, update threshold |
| **Setup** | `/hub-finance` |

*Requires tradingview plugin for market data.*

### Music

| Aspect | Details |
|--------|---------|
| **Track** | Current playing song (YouTube Music or Spotify) |
| **Control** | Play, pause, skip, search |
| **Display** | Always shown in statusline background |
| **Setup** | `/hub-play <query>` |

**Contextual reactions:** Enable `/hub-music` for automatic music control based on events:
- PR merged → celebration 🎉
- CI failed → call to action
- Meeting starting → office chatter
- Focus started/ended → appropriate vibes

### Custom Services

| Aspect | Details |
|--------|---------|
| **Track** | Any MCP service, browser tab, or CLI output |
| **Alert when** | User-defined conditions |
| **Setup** | `/hub-custom` |

If Claude can read it, Status Hub can track it.

### Context & Quota

| Aspect | Details |
|--------|---------|
| **Context bar** | `[████████░░] 82%` — How full your session is |
| **Quota** | `⚡85%` — Estimated daily budget used |
| **Setup** | `/hub-context` and `/hub-quota` |

Colors shift green → yellow → red as usage climbs.

## Commands

| Command | Description |
|---------|-------------|
| `/hub <pr-url>` | Start tracking a GitHub PR |
| `/hub-tree` | Display all tracked items as tree view |
| `/hub-ack` | Smart contextual actions for alerts |
| `/hub-play <query>` | Search and play music (pause/resume/skip) |
| `/hub-music` | Configure contextual music reactions |
| `/hub-focus` | Start focus mode with calendar awareness |
| `/hub-finance` | Track stocks and crypto in statusline |
| `/hub-context` | Configure context window bar display |
| `/hub-quota` | Configure daily quota usage display |
| `/hub-custom` | Track any service via MCP or browser |
| `/hub-manage` | Interactive management interface |
| `/hub-setup` | Configure statusline integration |
| `/hub-setup-gcalendar` | Set up Google Calendar API (no Chrome MCP) |
| `/hub-setup-slack` | Set up Slack API (no Chrome MCP) |
| `/hub-off` | Disable all tracking |

## Requirements

- **Claude Code** — Required
- **GitHub CLI** (`gh`) — For PR tracking
- **Claude in Chrome** MCP — For calendar, music, Slack via browser
- **jq** — For JSON processing

## How It Works

The plugin maintains two files:

| File | Purpose |
|------|---------|
| `~/.claude/status-config.json` | Persistent config (tracked PRs, settings) |
| `/tmp/status-hub.json` | Real-time status bridge for statusline |

A background daemon refreshes data with **adaptive intervals**:
- Light refresh (PRs, music, focus): 90s base, grows to 1h max when idle
- Full refresh (all services): 4.5m base, grows to 3h max when idle

Hooks trigger immediate refreshes when you interact with Claude.

## Troubleshooting

**Statusline not showing?**
```bash
/hub-setup  # Reconfigure statusline
```

**Music not updating?**
- Ensure YouTube Music or Spotify tab is open
- Check Claude in Chrome MCP is connected

**PRs not tracking?**
```bash
gh auth status  # Verify GitHub CLI auth
```

**Calendar/Slack not working?**
- Run `/hub-setup` to auto-detect connections
- Or use `/hub-setup-gcalendar` / `/hub-setup-slack` for API-based setup

## FAQ

**Why isn't the statusline updating instantly?**
Status Hub refreshes when you interact—send any message to trigger an update. It doesn't poll continuously to save resources.

**What does the skull 💀 mean?**
The background daemon hasn't updated in 3+ minutes. Restart Claude Code to respawn it.

**Will setup overwrite my existing statusline?**
No. `/hub-setup` preserves your existing statusline and appends hub data. Use `--replace` to fully replace it.

**How do VIP messages work during focus?**
By default, focus mode silences everything. Enable `allowVipDms` in focus config to let VIP messages through.

## License

MIT
