# Claude Code Plugins

Community plugins and extensions for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) - Anthropic's AI-powered coding assistant CLI.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Compatible-blueviolet)](https://docs.anthropic.com/en/docs/claude-code)

> Extend Claude Code with custom commands, agents, skills, and hooks

## Available Plugins

| Plugin | Description |
|--------|-------------|
| [claude-status-hub](plugins/claude-status-hub) | Statusline integration - track GitHub PRs, control music, monitor alerts |

## Quick Install

```bash
/install claude-status-hub@fiale-plus/claude-code-plugins
```

## What Are Claude Code Plugins?

Plugins extend Claude Code with:

- **Commands** - Custom slash commands (`/hub`, `/hub-play`)
- **Agents** - Specialized AI agents for specific tasks
- **Skills** - Reusable capabilities Claude can invoke
- **Hooks** - Event-driven automation (on session start, before tools, etc.)

## Browse Plugins

| Plugin | Features | Install |
|--------|----------|---------|
| [claude-status-hub](plugins/claude-status-hub/README.md) | PR tracking, music control, custom alerts | `/install claude-status-hub@fiale-plus/claude-code-plugins` |

## Resources

- [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code)
- [Plugin Development Guide](https://docs.anthropic.com/en/docs/claude-code/plugins)

## License

MIT
