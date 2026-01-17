---
description: Run pre-configured stock screening strategies and save results to CSV
---

# Interactive Stock Screening

Run pre-configured screening strategies and save results to CSV.

## Steps:

1. Use `mcp__tradingview__list_presets` to show available strategies

2. Ask user to select a strategy using AskUserQuestion:

   **Question 1 - Stock Screeners:**
   - Quality Stocks → `quality_stocks`
   - Value Stocks → `value_stocks`
   - Dividend Stocks → `dividend_stocks`
   - Momentum Stocks → `momentum_stocks`

   **Question 2 - Advanced:**
   - Growth Stocks → `growth_stocks`
   - Quality Growth → `quality_growth_screener`
   - Market Indexes → `market_indexes`

   User will select EITHER from Question 1 OR Question 2 (one will be selected, the other will be "Other").

3. Get preset configuration with `mcp__tradingview__get_preset`

4. Run the screen:
   - For filter-based presets: Use `mcp__tradingview__screen_stocks` with limit: 50
   - For market_indexes: Use `mcp__tradingview__lookup_symbols` (this is market regime analysis, not stock screening)

5. Display results in a compact table (~80 columns wide), showing first 20 rows:
   - Stock screeners: Symbol, Name, Price, Market Cap, ROE%, P/E, D/E
   - Market indexes: Symbol, Name, Price, Change%, 1Y Perf

6. Save ALL results to CSV:
   - First create directory: `mkdir -p docs/local/screening-runs/`
   - Filename: `{preset_name}_{YYYY-MM-DD_HH-MM-SS}.csv`
   - Location: `docs/local/screening-runs/`

## Important:
- Always create the output directory before writing
- Include all columns from the screening results in CSV
- If no results, explain possible reasons (filters too restrictive, market conditions)
