# Claude Code Plugins

Plugins for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Compatible-blueviolet)](https://docs.anthropic.com/en/docs/claude-code)

## Status Hub

**Your world at a glance, without leaving the terminal.**

![Status Hub Demo](plugins/claude-status-hub/assets/demo.gif)

Track PRs, calendar, Slack, stocks, music—all in your statusline.

**The flow:** `/hub-setup` → add monitors → alerts appear → `/hub-ack` for smart actions (merge PR, join meeting, reply to Slack).

**Install:**
```bash
/plugin marketplace add fiale-plus/fiale-claude-plugins
/plugin install claude-status-hub
/hub-setup
```

→ [Full documentation](plugins/claude-status-hub) — workflow examples, all services, commands

## TradingView

**AI-powered market screening, without leaving the terminal.**

```
/market-regime

┌─────────────────────┬──────────┬──────────┬───────────┬────────┐
│ Index               │ Price    │ ATH      │ Drawdown  │ Status │
├─────────────────────┼──────────┼──────────┼───────────┼────────┤
│ Nasdaq Composite    │ 19,864   │ 20,173   │ -1.53%    │ 🟢     │
│ OMX Stockholm 30    │ 2,547    │ 2,601    │ -2.08%    │ 🟢     │
│ Nikkei 225          │ 38,026   │ 42,426   │ -10.37%   │ 🔴     │
└─────────────────────┴──────────┴──────────┴───────────┴────────┘

Overall: 2/3 indexes in normal range
```

Screen stocks, forex, crypto, and ETFs using TradingView's 75+ fundamental and technical indicators.

**Install:**
```bash
/plugin marketplace add fiale-plus/fiale-claude-plugins
/plugin install tradingview
/market-regime
```

→ [Full documentation](plugins/tradingview)

## Vibes

**Your session's emotional arc, in sound.**

Plays a short musical phrase whenever Claude finishes a task or needs your attention. Mood is inferred from the transcript: triumphant on success, gentle descend on errors, unresolved on notifications, settled when neutral.

Pure-Python synthesis — no audio files, no dependencies. Requires macOS (`afplay`).

**Install:**
```bash
/plugin marketplace add fiale-plus/fiale-claude-plugins
/plugin install vibes
```

→ [Full documentation](plugins/vibes)

## License

MIT
