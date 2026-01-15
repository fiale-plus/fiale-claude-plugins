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
│
├─ STATUSLINE
│  ├─ Context: bar [████████░░] threshold 90%
│  └─ Quota: number ⚡ threshold 80% (Max 5hrs)
│
├─ FOREGROUND
│  ├─ #1  ✓ PR #142 anthropics/claude-code (approved)
│  ├─ #2  ! PR #138 anthropics/claude-code (changes requested)
│  ├─ #3  📊 finance: GOOGL -0.91% | YOU +1.13% | ATAT -1.70%
│  └─ #4  🔥 Sentry (2 issues)
│
└─ BACKGROUND
   └─ #5  ▶ youtube-music: Blinding Lights - The Weeknd
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
/hub-tree
```

## Commands

| Command | Description |
|---------|-------------|
| `/hub <pr-url>` | Start tracking a GitHub PR |
| `/hub-tree` | Display all tracked items as tree view |
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

### Context & Quota Awareness

Optional: See your session context and daily quota usage at a glance.

```
❯ › [████████░░] 82% › ⚡85% › ⏸ Bad Dream - Cannons › 📊 1/3 ↑ -0.5% avg >
     └─ context ──┘    └ quota    └─ music ─────────┘    └─ stocks ──────┘
```

- **Context bar** `[████████░░] 82%` - How full your session is (compaction coming soon)
- **Quota** `⚡85%` - Estimated daily budget used (based on real tokens)

Configure with `/hub-context` and `/hub-quota`. Colors shift green → yellow → red as usage climbs.

*Note: Quota is an estimate based on context window tokens. Check [console.anthropic.com](https://console.anthropic.com) for actual usage.*

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

## FAQ

### Why is the statusline not updating instantly?

Status Hub uses Claude Code's hook system - it refreshes on:
- **UserPromptSubmit**: When you send a message
- **Stop**: When Claude finishes responding

It does NOT poll continuously. Send any message to trigger a refresh.

### Why does it show "Status stale" or old information?

This happens when:
1. No interaction for >5 minutes (data ages out)
2. Background refresh failed silently

**Fix**: Send any message to trigger refresh. If it persists, run `/hub-ack` to clear errors.

### What does the error indication mean?

Red text or error icon means a background refresh failed. Common causes:
- Network issues (GitHub/Sentry API unreachable)
- Browser tab closed (music service disconnected)
- MCP server not responding

**Fix**: Run `/hub-ack` to acknowledge and clear, then send a message to retry.

### What does the skull 💀 mean?

The skull icon appears when the background refresh daemon hasn't updated in over 3 minutes. This usually means:
- The daemon process died (terminal was closed and reopened)
- System went to sleep and daemon didn't recover
- Daemon crashed due to an error

**Fix**: Restart Claude Code to respawn the daemon, or run any command to trigger a manual refresh.

### I installed a new MCP or skill but statusline doesn't pick it up

Claude Code caches plugin configurations at startup.

**Fix**: Restart Claude Code (`Ctrl+C` then `claude`) to reload plugins and MCP connections.

### Will setup overwrite my existing statusline?

No! By default, `/hub-setup` preserves your existing statusline as the "base prompt" and appends Status Hub data to it. If you had a custom statusline command, it will still run first.

Use `/hub-setup --replace` if you want to fully replace your statusline with Status Hub's default.

## License

MIT
