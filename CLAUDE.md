# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Structure

This is a Claude Code plugin marketplace repository containing plugins for the Claude Code CLI. The marketplace format allows users to install plugins via `/plugin marketplace add fiale-plus/fiale-claude-plugins`.

```
.claude-plugin/marketplace.json    # Marketplace manifest - lists all plugins
plugins/
  <plugin-name>/
    .claude-plugin/plugin.json     # Plugin manifest
    commands/*.md                  # Slash commands (markdown with YAML frontmatter)
    hooks/hooks.json               # Hook definitions
    bin/*.sh                       # Shell scripts
```

## Plugin Architecture: claude-status-hub

The status hub plugin integrates with Claude Code's statusline to display live status (PRs, music, alerts).

### Data Flow

1. **Config file** (`~/.claude/status-config.json`) - Persistent state: tracked PRs, background service, tab IDs
2. **Bridge file** (`/tmp/status-hub.json`) - Real-time status with timestamp for staleness detection
3. **Statusline script** (`bin/statusline.sh`) - Reads bridge file, formats output for Claude Code

### Key Mechanisms

- **Staleness**: Bridge data older than 300s is ignored by statusline, 60s triggers refresh via hook
- **Hooks**: `SessionStart` initializes files; `UserPromptSubmit` triggers background refresh when stale
- **Commands**: Markdown files with YAML frontmatter route to sub-skills (`hub.md` → `hub-list.md`, etc.)

### PR Status Icons

| Icon | Meaning |
|------|---------|
| `✓` | Approved + checks pass |
| `?` | Review pending |
| `!` | Changes requested |
| `X` | Checks failing |
| `~` | Checks pending |
| `D` | Draft |

## Commands

```bash
# Test statusline script
echo '{"workspace":{"current_dir":"~/test"}}' | ./plugins/claude-status-hub/bin/statusline.sh

# Update bridge manually
./plugins/claude-status-hub/bin/update-bridge.sh "youtube-music" ">" "Song Title" "Artist Name"

# Check PR status via gh CLI
gh pr view <number> --repo <owner>/<repo> --json state,isDraft,reviewDecision,statusCheckRollup,title,comments
```

## Dependencies

- `jq` - JSON processing in shell scripts
- `gh` - GitHub CLI for PR tracking
- Claude in Chrome MCP - Browser automation for music control
