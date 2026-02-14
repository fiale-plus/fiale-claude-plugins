# avanza-cli

CLI for Avanza — portfolio overview, accounts, holdings, and transaction history. Authenticates via Chrome cookies, outputs markdown or JSON. Built for AI agents to shell out to.

## Install

```bash
cd clis/avanza-local
npm install
npm link     # makes 'avanza' available globally
```

## Usage

```bash
avanza overview                              # portfolio summary
avanza accounts                              # all accounts with balances
avanza accounts --json                       # as JSON
avanza holdings                              # all holdings
avanza holdings --account 1234567            # holdings for specific account
avanza transactions --account 1234567        # recent transactions
avanza transactions --account 1234567 --limit 10
```

## Options

| Flag | Description |
|------|-------------|
| `--json` | JSON output instead of markdown |
| `--account <id>` | Account ID (get from `accounts` command) |
| `--profile <name>` | Chrome profile (default: "Default") |
| `--timeout <ms>` | Request timeout (default: 30000) |
| `--limit <n>` | Number of transactions (default: 20) |
| `-h, --help` | Show help |

## How it works

1. Reads cookies from your local Chrome browser (macOS Keychain decryption)
2. Calls Avanza's internal API with cookie auth
3. Falls back to Puppeteer scraping if API fails

## Requirements

- Node.js >= 18
- macOS (Chrome cookie decryption)
- Chrome with active Avanza session (BankID login)

## API Discovery

To re-discover or update API endpoints:

```bash
node scripts/discover.js
```

Opens a headful Chrome — browse Avanza while it captures API calls. Results saved to `docs/api-discovery.json`.
