---
name: hub-finance
description: Track stock and crypto prices in your statusline
allowedTools:
  - AskUserQuestion
  - Read
  - Write
  - Bash
  - mcp__tradingview__lookup_symbols
  - mcp__tradingview__screen_stocks
  - mcp__tradingview__screen_crypto
---

# /hub-finance - Financial Asset Tracking

Set up tracking for stocks, crypto, or other financial assets in your Status Hub.

## Usage

```
/hub-finance              # Start wizard
/hub-finance AAPL         # Quick add single symbol
/hub-finance AAPL,GOOGL   # Quick add multiple symbols
```

## Process

Read and follow the `hub-finance` skill to set up tracking.

The skill will:
1. Ask for symbols to track (if not provided)
2. Ask for alert threshold preferences
3. Optionally set price targets
4. Save configuration to `~/.claude/status-config.json` **in the `foreground[]` array**
5. Verify TradingView MCP is working
6. Update bridge file `/tmp/status-hub.json` with current prices
7. Show initial prices in statusline

**CRITICAL:** Finance items go in `foreground[]`, NOT a separate `finance` object.
