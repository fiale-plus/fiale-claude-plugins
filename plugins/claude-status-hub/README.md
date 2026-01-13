# Claude Status Hub

> Monitor whatever - right in your statusline

[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-Plugin-blueviolet)](https://docs.anthropic.com/en/docs/claude-code)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](../../LICENSE)

**Morning chill**
```
› main* › ▶ Lo-Fi Beats - ChillHop › 📧 3 unread
```

**PR needs attention**
```
› main* › ! PR #42 checks failed › ▶
```

**VIP email lands**
```
› main* › 📧 from: investor@acme.vc "Term sheet" › ▶
```

**Market + production**
```
› main* › 📈 ACME +3.2% › 🔥 2 Sentry › ▶
```

`PRs • Music • Email • Stocks • Sentry • Any MCP service • Any browser tab*`

```
Status Hub
├─ Background
│  └─ ▶ Blinding Lights - The Weeknd
└─ Foreground
   ├─ ✓ PR #42 anthropics/claude-code (approved)
   ├─ 📈 ACME $142.50 (+3.2%)
   ├─ 📧 Gmail (3 unread)
   └─ 🔥 Sentry (2 issues)
```

<sub>*Use responsibly - respect site terms and rate limits</sub>

## Why

Firing off PRs and moving on to new code - that's the flow. But my personal context overflows easily, and every alt-tab to check on things would distract me with something else. I needed a way to draw the line - important updates in, noise out. So this little tool came to be. Hope you find it useful!

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
/hub-list
```

## Commands

| Command | Description |
|---------|-------------|
| `/hub <pr-url>` | Start tracking a GitHub PR |
| `/hub-list` | Display all tracked items as tree view |
| `/hub-play <query>` | Search and play music |
| `/hub-play pause` | Pause current track |
| `/hub-play resume` | Resume playback |
| `/hub-play skip` | Skip to next track |
| `/hub-ack` | Acknowledge all alerts |
| `/hub-ack #N` | Acknowledge specific alert |
| `/hub-manage` | Interactive management interface |
| `/hub-off` | Disable all tracking |
| `/hub-setup` | Configure statusline integration |

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

### Smart Statusline

The statusline adapts based on what needs attention:

**Idle state** - Background info expanded:
```
› > Song Title - Artist › 3 PRs
```

**Alert state** - Foreground expanded:
```
› ! PR #123 needs review › >
```

## Requirements

- **Claude Code** - The AI coding assistant CLI
- **GitHub CLI** (`gh`) - For PR tracking (`brew install gh`)
- **Claude in Chrome** MCP - For browser integration (music control)
- **jq** - For JSON processing (`brew install jq`)

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

## License

MIT
