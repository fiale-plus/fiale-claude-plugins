# Claude Code Plugins

Plugins for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Compatible-blueviolet)](https://docs.anthropic.com/en/docs/claude-code)

## Status Hub

**Your world at a glance, without leaving the terminal.**

```
Status Hub
│
├─ CONTEXT
│  ├─ Bar: [████████░░] threshold 90%
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

Track PRs, play music, watch stocks, monitor Sentry—all surfaced in your statusline.

**Install:**
```bash
/plugin marketplace add fiale-plus/fiale-claude-plugins
/plugin install claude-status-hub
/hub-setup
```

→ [Full documentation](plugins/claude-status-hub)

## License

MIT
