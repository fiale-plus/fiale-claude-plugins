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

**CRITICAL: Finance items MUST go in the `foreground[]` array to appear in the statusline.**

Do NOT create a separate `finance` object at the root level - that will not work.

Read `~/.claude/status-config.json`, then append this item to the `foreground[]` array:

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

**Correct config structure:**
```json
{
  "contextDisplay": "bar",
  "foreground": [
    {
      "service": "finance",
      "symbols": ["NASDAQ:AAPL"],
      "alertThreshold": { "changePercent": 5 }
    }
  ],
  "background": { ... }
}
```

**WRONG - do not do this:**
```json
{
  "finance": { "symbols": [...] }  // ❌ Will NOT appear in statusline
}
```

## Verify TradingView MCP

Before saving, verify TradingView MCP is available by calling:

```
mcp__tradingview__lookup_symbols(symbols: ["NASDAQ:AAPL"])
```

If this fails, display:

```
⚠️ TradingView MCP not available

Finance tracking requires the TradingView plugin. Install it with:

  /plugin install tradingview

Then run /hub-finance again.
```

Do NOT proceed with setup if the MCP is unavailable.

## Confirm Setup

After configuration:
1. Run initial data fetch via `mcp__tradingview__lookup_symbols`
2. Update `lastSeen` in config with current prices
3. **Update bridge file `/tmp/status-hub.json`** - set root `timestamp` and add to `foreground[]`:

   **CRITICAL:** Always set root `timestamp` to current time in milliseconds: `$(($(date +%s) * 1000))`

   ```json
   {
     "timestamp": <current_time_ms>,
     "foreground": [
       {
         "site": "finance",
         "icon": "📈",
         "title": "AAPL",
         "detail": "$255.53 +1.2%",
         "hasAlert": false
       }
     ]
   }
   ```
4. Inform user: "Finance tracking configured! Your statusline will show: 📈 AAPL $XXX +X.X%"

**Both files must be updated:**
- `~/.claude/status-config.json` - persistent config (foreground[] array)
- `/tmp/status-hub.json` - bridge file for statusline display (foreground[] array)
