# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a **Claude Code plugin marketplace repository** containing multiple plugins that extend Claude's capabilities. The plugins integrate with Claude Code to provide terminal-accessible features like PR monitoring, music control, market screening, and custom service tracking.

## Testing

```bash
# Run full test suite
plugins/claude-status-hub/tests/run-tests.sh

# Run individual test
bash plugins/claude-status-hub/tests/test-refresh-prs.sh
bash plugins/claude-status-hub/tests/test-slack.sh
```

Tests use bash assertions with `pass()` and `fail()` functions. Tests backup/restore production files during runs and use fixtures for mock data.

## Architecture

### Plugin Structure

```
plugins/
├── claude-status-hub/       # Primary plugin - statusline monitoring
│   ├── .claude-plugin/      # Plugin manifest (plugin.json)
│   ├── bin/                 # Executable bash scripts
│   ├── commands/            # CLI command entry points (.md files)
│   ├── skills/              # Reusable agent workflows (.md files)
│   ├── hooks/               # Lifecycle hooks (hooks.json + scripts)
│   └── tests/               # Test suite with fixtures
└── tradingview/             # Secondary plugin - market screening
```

### Data Flow

The status hub uses a **bridge file architecture**:
- `~/.claude/status-config.json` - Persistent configuration (tracked items, settings)
- `/tmp/status-hub.json` - Real-time bridge read by statusline, written by skills/daemon
- `/tmp/status-hub-error.txt` - Error state for statusline display

### Command/Skill Pattern

**Commands** (in `commands/`): User-facing entry points with YAML frontmatter defining name, description, and args. Route to skills or execute high-level logic.

**Skills** (in `skills/`): Reusable workflows invoked by commands or other skills. Follow naming convention `hub-<action>.md` or `hub-refresh-<service>.md`.

### Daemon Architecture

- `SessionStart` hook spawns background daemon (`bin/refresh-daemon.sh`)
- Daemon performs light refresh every 90 seconds (PRs + music), full refresh every 6 minutes
- Version-aware lockfile prevents duplicate daemons
- `UserPromptSubmit` hook triggers refresh on user input
- `Stop` hook performs final refresh before session ends

### Connection Hierarchy

Services using browser automation follow a connection hierarchy with automatic fallback:

| Service | Priority 1 | Priority 2 | Priority 3 | Priority 4 |
|---------|------------|------------|------------|------------|
| Google Calendar | Chrome MCP | Playwright | - | - |
| Slack | Slack MCP | Chrome MCP | Playwright | API (legacy) |

Detection logic in `skills/connection-detect.md`. Smart skills reference tool skills for extraction.

### Tool/Smart Skill Separation

**Tool skills** (`tool-<service>.md`): Low-level extraction scripts, connection methods, output formats. Reference, don't modify.

**Smart skills** (`hub-<action>.md`, `hub-refresh-<service>.md`, `hub-ack-<service>.md`): High-level contextual logic that uses tool skills.

Separation principle:
- Tool = HOW to extract data (reusable patterns)
- Smart = WHAT to do with data (contextual actions)

When adding a new service:
1. Create `tool-<service>.md` (if unique extraction needed)
2. Create `hub-refresh-<service>.md` (uses tool skill)
3. Create `hub-setup-<service>.md` (wizard)
4. Create `hub-ack-<service>.md` (contextual actions)
5. Update `connection-detect.md`
6. Update `hub-ack.md` routing
7. Update `hub-refresh.md` step

## Key Conventions

### Data Sanitization

All data written to bridge must be sanitized:
- Escape backslashes (`\` → `\\`)
- Truncate strings (title max 30 chars, detail max 25)
- Strip control characters (newlines, tabs)

### File Naming

- Commands: `<command-name>.md`
- Skills: `hub-<action>.md` or `hub-refresh-<service>.md`
- Scripts: `<action>.sh` in `bin/`
- Tests: `test-<component>.sh`

### Shell Script Headers

```bash
#!/bin/bash
# Purpose: What this does
# Invoked by: How it's called
# Depends on: External tools/files
```

### Markdown Command/Skill Format

```yaml
---
name: command-name
description: One-line description
args: arguments (optional)
---

# Detailed Title

## Step 1: Do this
[Instructions]
```

## External Dependencies

- **GitHub CLI (`gh`)** - PR status queries
- **Claude in Chrome MCP** - Browser automation (music, calendar, Slack)
- **jq** - JSON processing
- **tradingview-mcp-server** - Market screening (via npx)

## Plugin Discovery

Plugins are discovered via `.claude-plugin/marketplace.json` at repo root. Individual plugins have their own `.claude-plugin/plugin.json` manifest.

```bash
/plugin marketplace add fiale-plus/fiale-claude-plugins
/plugin install claude-status-hub
/plugin install tradingview
```

## Version Bumping

When making changes, bump the version in both the marketplace file (`.claude-plugin/marketplace.json`) and the plugin's own manifest (`plugins/<plugin-name>/.claude-plugin/plugin.json`):

- **Patch version** (1.1.x): Default for each PR
- **Minor version** (1.x.0): Bigger features or roadmap milestones
- **Major version** (x.0.0): On explicit request only

## Note on This Document

This CLAUDE.md will evolve with the project. Changes are automatically picked up by Claude Code.
