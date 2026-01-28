# Claude Code Plugins

Plugins for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Compatible-blueviolet)](https://docs.anthropic.com/en/docs/claude-code)

## Status Hub

**Your world at a glance, without leaving the terminal.**

```
~/ [████████░░] 80% › ⚡85% › ▶ Blinding Lights - The Weeknd › 📅 Standup 5m › ✓#142 !#138 › 💬 @boss >

/hub-tree
Status Hub
│
├─ STATS
│  ├─ Context: [████████░░] threshold 90%
│  └─ Quota: ⚡85% threshold 80%
│
├─ FOREGROUND (alerts)
│  ├─ #1  📅 Team Standup in 5m
│  ├─ #2  ✓ PR #142 anthropics/claude-code (approved)
│  ├─ #3  ! PR #138 anthropics/claude-code (changes requested)
│  ├─ #4  💬 slack: @boss (1 DM)
│  └─ #5  📊 finance: AAPL +5.2%
│
└─ BACKGROUND (ambient)
   └─ #6  ▶ youtube-music: Blinding Lights - The Weeknd
```

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

## License

MIT
