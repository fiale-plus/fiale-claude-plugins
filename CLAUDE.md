# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Repository Overview

A **Claude Code plugin marketplace** with plugins that extend Claude's capabilities via terminal-accessible features: PR monitoring, calendar/Slack integration, music control, finance tracking, and custom alerts.

## Testing

```bash
# Full test suite
plugins/claude-status-hub/tests/run-tests.sh

# Individual tests
bash plugins/claude-status-hub/tests/test-refresh-prs.sh
bash plugins/claude-status-hub/tests/test-slack.sh
bash plugins/claude-status-hub/tests/test-adaptive-intervals.sh
```

Tests use bash assertions (`pass()`/`fail()`), backup/restore production files, and use fixtures for mock data.

## Architecture

### Plugin Structure

```
plugins/
├── claude-status-hub/       # Primary plugin - statusline monitoring
│   ├── .claude-plugin/      # Plugin manifest (plugin.json)
│   ├── bin/                 # Shell scripts (daemon, statusline, bridge)
│   ├── commands/            # User-facing commands (.md with YAML frontmatter)
│   ├── skills/              # Reusable workflows (.md files)
│   ├── hooks/               # Lifecycle hooks (hooks.json + refresh.sh)
│   └── tests/               # Test suite with fixtures
└── tradingview/             # Finance plugin - market screening via MCP
```

### Data Flow

**Bridge file architecture:**
- `~/.claude/status-config.json` - Persistent config (tracked items, connection settings)
- `/tmp/status-hub.json` - Real-time bridge read by statusline, written by daemon/skills
- `/tmp/status-hub-error.txt` - Error state for statusline display

### Daemon Architecture

The background daemon (`bin/refresh-daemon.sh`) uses **adaptive refresh intervals**:

| Refresh Type | Base Interval | Ceiling (max idle) |
|--------------|---------------|-------------------|
| Light (PRs + music + focus) | 90 seconds | 1 hour |
| Full (all services) | 4.5 minutes | 3 hours |

Intervals grow linearly with idle time. Hooks trigger immediate refreshes on user activity.

**Hooks:**
- `SessionStart` - Spawns daemon, sets up statusline
- `UserPromptSubmit` - Triggers refresh, resets idle timer
- `Stop` - Final refresh before session ends

### Connection Hierarchy

Services using browser automation follow a hierarchy with automatic fallback and **auto-open tab recovery**:

| Service | Priority 1 | Priority 2 | Priority 3 | Priority 4 |
|---------|------------|------------|------------|------------|
| Calendar | Chrome MCP | Playwright | - | - |
| Slack | Slack MCP | Chrome MCP | Playwright | API (legacy) |
| Music | Chrome MCP | - | - | - |

When a Chrome tab is not found, the system auto-opens a new tab instead of failing.

### Skill Types

**Tool skills** (`tool-<service>.md`): Low-level extraction scripts and connection methods. Reference-only.

**Smart skills** (`hub-<action>.md`, `hub-refresh-<service>.md`, `hub-ack-<service>.md`): High-level contextual logic that uses tool skills.

**User-authored skills** (`*.user.md`): Custom extensions, not version-controlled.

### Adding a New Service

1. Create `tool-<service>.md` (if unique extraction needed)
2. Create `hub-refresh-<service>.md` (uses tool skill)
3. Create `hub-setup-<service>.md` (wizard)
4. Create `hub-ack-<service>.md` (contextual actions)
5. Update `connection-detect.md` if browser-based
6. Update `hub-ack.md` routing
7. Update `hub-refresh.md` step

## Key Conventions

### Data Sanitization

All data written to bridge must be sanitized:
- Escape backslashes (`\` → `\\`)
- Truncate strings (title max 30 chars, detail max 25)
- Strip control characters

### File Naming

- Commands: `<command-name>.md`
- Skills: `hub-<action>.md` or `hub-refresh-<service>.md`
- Scripts: `<action>.sh` in `bin/`
- Tests: `test-<component>.sh`

### Markdown Format

```yaml
---
name: command-name
description: One-line description
args: arguments (optional)
---

# Title

## Step 1: Do this
[Instructions]
```

## External Dependencies

- **GitHub CLI (`gh`)** - PR status queries
- **Claude in Chrome MCP** - Browser automation (calendar, music, Slack)
- **jq** - JSON processing
- **TradingView MCP** - Market screening (required by tradingview plugin)

## Plugin Installation

```bash
/plugin marketplace add fiale-plus/fiale-claude-plugins
/plugin install claude-status-hub
/plugin install tradingview
```

## Version Bumping

Bump version in both `.claude-plugin/marketplace.json` and `plugins/<name>/.claude-plugin/plugin.json`:

- **Patch** (1.1.x): Default for each PR
- **Minor** (1.x.0): Bigger features
- **Major** (x.0.0): On explicit request
