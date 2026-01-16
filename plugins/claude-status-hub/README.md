# Claude Status Hub

**Your world at a glance, without leaving the terminal.**

[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-Plugin-blueviolet)](https://docs.anthropic.com/en/docs/claude-code)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](../../LICENSE)

```
~/ [████████░░] 80% › ⚡85% › ▶ Blinding Lights - The Weeknd › ✓#142 !#138 › 📊 1/3 ↑ -0.11% avg › 🔥2 > 

/hub-tree
Status Hub
│
├─ STATS
│  ├─ Context: [████████░░] threshold 90%
│  └─ Quota: ⚡85% threshold 80%
│
├─ FOREGROUND (alerts)
│  ├─ #1  ✓ PR #142 anthropics/claude-code (approved)
│  ├─ #2  ! PR #138 anthropics/claude-code (changes requested)
│  ├─ #3  📊 GOOGL -0.91% | NVDA +1.13% | TSLA -1.70%
│  └─ #4  🔥 Sentry (2 issues)
│
└─ BACKGROUND (ambient)
   └─ #5  ▶ youtube-music: Blinding Lights - The Weeknd
```

Track PRs, play music, watch stocks, monitor Sentry—all surfaced in your Claude Code statusline.

## Why

You're deep in flow, firing off PRs and moving to the next thing. But context overflows. Every alt-tab to check "did CI pass?" becomes a 10-minute detour.

I needed a way to draw the line—important updates in, noise out. This is that tool.

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

## Commands

| Command | Description |
|---------|-------------|
| `/hub <pr-url>` | Start tracking a GitHub PR |
| `/hub-tree` | Display all tracked items as tree view |
| `/hub-play <query>` | Search and play music (pause/resume/skip) |
| `/hub-finance` | Track stocks and crypto in your statusline |
| `/hub-context` | Configure context window bar display |
| `/hub-quota` | Configure daily quota usage display |
| `/hub-ack` | Acknowledge alerts |
| `/hub-custom` | Track any service via MCP or browser |
| `/hub-manage` | Interactive management interface |
| `/hub-setup` | Configure statusline integration |
| `/hub-off` | Disable all tracking |

## Features

### GitHub PR Tracking

Track multiple PRs with at-a-glance status:

| Icon | Meaning |
|------|---------|
| `✓` | Approved and checks passing |
| `?` | Review pending |
| `!` | Changes requested |
| `X` | Checks failing |
| `~` | Checks pending |
| `D` | Draft PR |

Get alerted when:
- New comments appear
- Review status changes
- CI checks fail or pass
- PR state changes (merged, closed)

### Music Control

Control YouTube Music or Spotify directly from Claude:

```bash
/hub-play lofi beats    # Search and play
/hub-play skip          # Next track
/hub-play pause         # Pause
/hub-play resume        # Resume
```

Current track shows in your statusline automatically.

### Context & Quota Awareness

See your session context and daily quota at a glance:

- **Context bar** `[████████░░] 82%` — How full your session is
- **Quota** `⚡85%` — Estimated daily budget used

Colors shift green → yellow → red as usage climbs. Configure with `/hub-context` and `/hub-quota`.

### Track Anything

The built-in trackers are just the start. Use `/hub-custom` to monitor:

- **Any MCP service** — Sentry issues, Linear tasks, email counts
- **Any browser tab** — Dashboards, monitoring pages, anything with DOM

If Claude can read it, Status Hub can track it.

## Requirements

- **Claude Code** — Required
- **GitHub CLI** (`gh`) — For PR tracking
- **Claude in Chrome** MCP — For music and browser features
- **jq** — For JSON processing

## How It Works

The plugin maintains two files:

| File | Purpose |
|------|---------|
| `~/.claude/status-config.json` | Persistent config (tracked PRs, settings) |
| `/tmp/status-hub.json` | Real-time status bridge for statusline |

A `UserPromptSubmit` hook auto-refreshes stale data in the background.

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

## FAQ

**Why isn't the statusline updating instantly?**
Status Hub refreshes when you interact—send any message to trigger an update. It doesn't poll continuously.

**What does the skull 💀 mean?**
The background daemon hasn't updated in 3+ minutes. Restart Claude Code to respawn it.

**Will setup overwrite my existing statusline?**
No. `/hub-setup` preserves your existing statusline and appends hub data. Use `--replace` to fully replace it.

## License

MIT
