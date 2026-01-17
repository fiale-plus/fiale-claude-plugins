# TradingView Plugin for Claude Code

**AI-powered market screening, without leaving the terminal.**

[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-Plugin-blueviolet)](https://docs.anthropic.com/en/docs/claude-code)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](../../LICENSE)

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

Screen stocks, forex, crypto, and ETFs using TradingView's 75+ fundamental and technical indicators via the [tradingview-mcp-server](https://github.com/fiale-plus/tradingview-mcp-server).

## Quick Start

```bash
# Add marketplace and install
/plugin marketplace add fiale-plus/fiale-claude-plugins
/plugin install tradingview

# Check market conditions
/market-regime

# Run a screening strategy
/run-screener
```

## Commands

| Command | Description |
|---------|-------------|
| `/market-regime` | Check market regime by analyzing major global indexes relative to ATH |
| `/run-screener` | Run pre-configured screening strategies and save results to CSV |

## Requirements

- **Claude Code** — Required
- **Node.js** — For npx (MCP server runs via `npx tradingview-mcp-server`)

The MCP server is installed automatically via npx on first use.

## License

MIT
