---
description: Check market regime by analyzing major global indexes relative to their all-time highs
---

Use `mcp__tradingview__lookup_symbols` with symbols `["TVC:IXIC", "OMXSTO:OMXS30", "TVC:NI225"]` and columns `["name", "close", "all_time_high", "price_52_week_high", "change", "Perf.Y", "RSI"]`.

Calculate drawdown from ATH for each index and show status: 🟢 (0 to -5%), 🟡 (-5 to -10%), 🔴 (< -10%).
