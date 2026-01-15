---
name: hub-finance
description: Track stock/crypto prices in Status Hub via TradingView MCP
---

# Hub Finance Tracking

Set up financial asset tracking in your Status Hub statusline.

## When to Use

This skill is auto-triggered when:
- User mentions tracking stocks, crypto, or financial data
- User runs `/hub-finance`
- User types `/hub AAPL` or similar stock symbol

## Wizard Flow

Use AskUserQuestion to gather configuration:

### Question 1: Symbols to Track

Ask: "Enter symbols to track (comma-separated, e.g., AAPL, GOOGL, BTC)"

Parse the response to extract symbols. For stocks, prefix with exchange if not provided:
- AAPL → NASDAQ:AAPL
- GOOGL → NASDAQ:GOOGL
- TSLA → NASDAQ:TSLA
- BTC → COINBASE:BTCUSD

### Question 2: Alert Threshold

Use AskUserQuestion:
```
question: "Alert when price changes by how much?"
options:
  - label: "3%"
  - label: "5% (Recommended)"
  - label: "10%"
  - label: "Custom"
```

If Custom, ask for the percentage.

### Question 3: Price Targets (Optional)

Use AskUserQuestion:
```
question: "Set price target alerts?"
options:
  - label: "No"
  - label: "Yes - alert when above target"
  - label: "Yes - alert when below target"
```

If yes, ask for the target price.

## Save Configuration

Add to `~/.claude/status-config.json` in the `foreground` array:

```json
{
  "service": "finance",
  "symbols": ["NASDAQ:AAPL", "NASDAQ:GOOGL"],
  "alertThreshold": {
    "changePercent": 5,
    "priceAbove": null,
    "priceBelow": null
  },
  "lastSeen": {}
}
```

## Verify TradingView MCP

Before saving, verify TradingView MCP is available by calling:

```
mcp__tradingview__lookup_symbols(symbols: ["NASDAQ:AAPL"])
```

If this fails, inform user that TradingView MCP server needs to be configured.

## Confirm Setup

After configuration:
1. Run initial data fetch to populate `lastSeen`
2. Update bridge file with current prices
3. Inform user: "Finance tracking configured! Your statusline will show: 📈 AAPL $XXX +X.X%"
