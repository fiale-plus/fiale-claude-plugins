---
name: hub-refresh-google-stock
author: user
created: 2026-01-12
source: mcp
---

# Refresh Google Stock Price

Monitor GOOGL stock price via TradingView MCP.

## Data Source

Use TradingView MCP `lookup_symbols` tool:
```
mcp__tradingview__lookup_symbols with symbol "NASDAQ:GOOGL"
```

Or use `screen_stocks` with filter for NASDAQ:GOOGL.

## Extraction

From the MCP response, extract:
- `close` or `last` price
- `change` percentage
- `volume` if available

## Alert Detection

Set `hasAlert: true` if:
- Price > 1000 USD (user-defined threshold)

## Output Format

Return:
- icon: `$` (or `!` if alert triggered)
- title: `GOOGL`
- detail: `$<price>` (e.g., "$178.50")
- hasAlert: true if price > 1000

## Example Bridge Entry

```json
{
  "site": "google-stock",
  "icon": "$",
  "title": "GOOGL",
  "detail": "$178.50 +1.2%",
  "hasAlert": false
}
```
