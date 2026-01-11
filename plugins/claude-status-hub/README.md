# Claude Status Hub

> Universal statusline integration - track GitHub PRs, control music playback, monitor alerts in real-time

[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-Plugin-blueviolet)](https://docs.anthropic.com/en/docs/claude-code)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](../../LICENSE)

## What It Does

Status Hub adds a dynamic statusline to Claude Code showing:

- **GitHub PRs** - Track review status, comments, CI checks
- **Music Playback** - Now playing from YouTube Music or Spotify
- **Smart Alerts** - Get notified when PR state changes

```
pavel@mac:~/project › main* › > Sledgehammer - Peter Gabriel › 2 PRs >
                      ↑ git    ↑ music playing                ↑ tracked PRs
```

## Quick Start

```bash
# Install
/install claude-status-hub@fiale-plus/claude-code-plugins

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
