---
description: Run pre-configured stock screening strategies and save results to CSV
---

1. Use `mcp__tradingview__list_presets` to show available strategies
2. Ask user to select a preset (quality_stocks, value_stocks, dividend_stocks, momentum_stocks, growth_stocks, quality_growth_screener, market_indexes)
3. Use `mcp__tradingview__get_preset` to get the configuration
4. Use `mcp__tradingview__screen_stocks` (or `lookup_symbols` for market_indexes) with limit 50
5. Display results and save to `docs/local/screening-runs/{preset}_{timestamp}.csv`
