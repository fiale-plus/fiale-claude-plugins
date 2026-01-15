---
name: hub-refresh-tradingview
description: Refresh TradingView financial data for Status Hub
---

# Refresh TradingView Financial Data

Called by hub-refresh.md when processing items with `service == "tradingview"`.

## Config Structure

Each TradingView item in `foreground[]`:
```json
{
  "service": "tradingview",
  "symbols": ["NASDAQ:AAPL", "NASDAQ:GOOGL"],
  "alertThreshold": {
    "changePercent": 5,
    "priceAbove": null,
    "priceBelow": null
  },
  "lastSeen": {
    "NASDAQ:AAPL": { "price": 189.50, "change": 2.3 }
  }
}
```

## Refresh Process

### Step 1: Fetch Current Data

Call TradingView MCP:
```
mcp__tradingview__lookup_symbols(
  symbols: item.symbols,
  columns: ["close", "change", "change_abs", "volume", "name"]
)
```

### Step 2: Process Results

For each symbol in results:
- Extract: `close` (current price), `change` (% change)
- Compare to `lastSeen[symbol]`

### Step 3: Alert Detection

Set `hasAlert: true` if ANY symbol:
- `|change| >= alertThreshold.changePercent`
- `close >= alertThreshold.priceAbove` (if set)
- `close <= alertThreshold.priceBelow` (if set)

### Step 4: Build Output

**Single symbol:**
```json
{
  "site": "tradingview",
  "icon": "📈",
  "title": "AAPL",
  "detail": "$189.50 +2.3%",
  "hasAlert": false
}
```

**Multiple symbols:**
```json
{
  "site": "tradingview",
  "icon": "📊",
  "title": "3/5 ↑",
  "detail": "+1.2% avg",
  "hasAlert": false
}
```

- Count how many symbols are up vs down
- Calculate average change
- If alert, show the symbol that triggered it

**Alert state:**
```json
{
  "site": "tradingview",
  "icon": "🔥",
  "title": "NVDA",
  "detail": "$890 +8.5%!",
  "hasAlert": true
}
```

### Step 5: Update lastSeen

Save current prices to config:
```json
"lastSeen": {
  "NASDAQ:AAPL": { "price": 189.50, "change": 2.3 },
  "NASDAQ:GOOGL": { "price": 178.20, "change": -0.5 }
}
```

## Icon Reference

- `📈` - Single symbol, positive change
- `📉` - Single symbol, negative change
- `📊` - Multiple symbols
- `🔥` - Alert triggered (threshold exceeded)
