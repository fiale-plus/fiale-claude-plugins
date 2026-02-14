---
name: use-avanza
description: How to use the avanza CLI — accounts, holdings, and transaction history
---

# use-avanza

The `avanza` CLI provides read-only access to Avanza portfolio data through Chrome cookie authentication. Query your accounts, holdings, transactions, and portfolio overview without storing credentials.

## Prerequisites

- **Node.js** >= 18
- **macOS** (Chrome cookie decryption is macOS-specific)
- **Active Avanza session** in Chrome — you must be logged into [avanza.se](https://avanza.se) in your default Chrome profile

## Installation

```bash
cd clis/avanza
npm install
npm link
```

After linking, the `avanza` command will be available globally in your terminal.

## Commands

### `avanza accounts`

List all your Avanza accounts with their type, account number, and total value.

**Example output (markdown table):**

| Account          | Type                | Value      |
|------------------|---------------------|------------|
| Investeringskonto| ISK                 | 125,430 kr |
| Kapitalförsäkring| KF                  | 89,200 kr  |
| Sparkonto        | Savings account     | 50,000 kr  |
| Depå             | Securities account  | 35,800 kr  |

**JSON output:**
```bash
avanza accounts --json
```

Returns an array of account objects with `id`, `name`, `type`, and `value` fields.

---

### `avanza holdings [--account <id>]`

Display portfolio holdings across all accounts or filter by a specific account.

**Columns:**
- Instrument name
- Quantity
- Average purchase price
- Current price
- Change % (daily)
- Market value

**Example output (markdown table):**

| Instrument         | Quantity | Avg Price | Current Price | Change % | Market Value |
|--------------------|----------|-----------|---------------|----------|--------------|
| Vanguard S&P 500   | 150      | 780 kr    | 825 kr        | +1.2%    | 123,750 kr   |
| Avanza Zero        | 200      | 245 kr    | 248 kr        | +0.5%    | 49,600 kr    |
| Tesla Inc          | 10       | 1,850 kr  | 1,920 kr      | -2.1%    | 19,200 kr    |

**Filter by account:**
```bash
avanza holdings --account 123456
```

**JSON output:**
```bash
avanza holdings --json
avanza holdings --account 123456 --json
```

---

### `avanza transactions [--account <id>] [--limit N]`

Show recent transaction history — purchases, sales, dividends, deposits, and withdrawals.

**Columns:**
- Date
- Type (Buy, Sell, Dividend, Deposit, Withdrawal)
- Instrument
- Quantity
- Price
- Amount

**Example output (markdown table):**

| Date       | Type     | Instrument       | Quantity | Price   | Amount     |
|------------|----------|------------------|----------|---------|------------|
| 2026-02-10 | Buy      | Vanguard S&P 500 | 5        | 825 kr  | -4,125 kr  |
| 2026-02-05 | Dividend | Investor AB      | —        | —       | +450 kr    |
| 2026-02-01 | Sell     | Tesla Inc        | 2        | 1,920 kr| +3,840 kr  |

**Default limit:** 20 transactions

**Custom limit:**
```bash
avanza transactions --limit 50
```

**Filter by account:**
```bash
avanza transactions --account 123456 --limit 10
```

**JSON output:**
```bash
avanza transactions --json
avanza transactions --account 123456 --limit 5 --json
```

---

### `avanza overview`

Display a high-level portfolio summary with total value, daily change, and year-to-date (YTD) performance.

**Example output:**

```
Portfolio Overview
Total Value:      300,230 kr
Daily Change:     +2,450 kr (+0.82%)
YTD Return:       +18,320 kr (+6.5%)
```

**JSON output:**
```bash
avanza overview --json
```

Returns an object with `totalValue`, `dailyChange`, `dailyChangePercent`, `ytdReturn`, and `ytdReturnPercent`.

---

### Global Options

All commands support:

- **`--json`** — Output machine-readable JSON instead of formatted tables
- **`--profile <name>`** — Use a specific Chrome profile (default: your default profile)

**Examples:**
```bash
avanza accounts --profile "Profile 2"
avanza holdings --json --profile Work
```

---

## Agent Usage Patterns

AI agents can use the `avanza` CLI to answer questions about portfolio state, performance, and transactions.

### Example Workflow: Get Account Details, Then Holdings

```bash
# Step 1: List all accounts
avanza accounts --json

# Step 2: Get holdings for a specific account (e.g., ISK account ID 123456)
avanza holdings --account 123456 --json

# Step 3: Get recent transactions for that account
avanza transactions --account 123456 --limit 5 --json
```

### Example: Daily Portfolio Check

```bash
# Get overview
avanza overview --json

# Get all holdings
avanza holdings --json

# Check recent activity
avanza transactions --limit 10 --json
```

### Example: Answer "How is my portfolio performing today?"

```bash
avanza overview
```

Parse the output to extract daily change amount and percentage.

### Example: Answer "What are my top 3 holdings?"

```bash
avanza holdings --json | jq 'sort_by(.marketValue) | reverse | .[0:3]'
```

---

## Troubleshooting

### "No cookies found" or "Authentication failed"

**Cause:** You're not logged into [avanza.se](https://avanza.se) in Chrome, or the session has expired.

**Solution:**
1. Open Chrome
2. Navigate to [avanza.se](https://avanza.se)
3. Log in with your username and password (BankID authentication may be required)
4. Keep the Chrome window open (you can minimize it)
5. Run the `avanza` command again

---

### "Command not found: avanza"

**Cause:** The CLI hasn't been linked globally.

**Solution:**
```bash
cd clis/avanza
npm link
```

Verify it works:
```bash
avanza --help
```

---

### Session expires frequently

**Cause:** Avanza sessions may timeout after inactivity or require periodic BankID re-authentication.

**Solution:**
- Keep Chrome open with an active Avanza session
- Re-authenticate via BankID when prompted
- If you're using a non-default Chrome profile, specify it with `--profile`

---

### macOS-specific cookie decryption issues

**Cause:** The CLI uses macOS Keychain to decrypt Chrome cookies. Permission dialogs may appear.

**Solution:**
- Grant permission when macOS prompts you to allow access to Chrome's cookie store
- If cookies still can't be read, verify Chrome is closed during the first run (some systems require this)

---

## Security Notes

- **Read-only access** — the CLI never modifies your portfolio or places trades
- **Local data only** — all queries run locally; no third-party services are involved
- **No credential storage** — the CLI uses your existing Chrome session cookies; it never stores passwords or BankID credentials
- **Cookie encryption** — Chrome cookies are encrypted using macOS Keychain; the CLI decrypts them on-the-fly
- **Session persistence** — cookies are read fresh on each command; no persistent authentication tokens are stored by the CLI

---

## Notes

- All monetary values are in SEK (Swedish Krona)
- Market data reflects real-time or near-real-time values depending on Avanza's API
- Holdings include stocks, funds, ETFs, and other instruments available on Avanza
- Transaction history includes all activity: trades, dividends, deposits, withdrawals, fees
- The CLI respects Avanza's rate limits; avoid rapid repeated requests
