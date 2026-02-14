#!/usr/bin/env node

import { parseArgs } from 'node:util';

const HELP = `
avanza — CLI for Avanza portfolio, holdings, and transactions

Usage:
  avanza <command> [options]

Commands:
  overview                        Portfolio summary with daily change
  accounts                        List all accounts with balances
  holdings [--account <id>]       Portfolio holdings by instrument
  transactions --account <id>     Recent transactions for an account

Options:
  --json                          Output as JSON instead of markdown
  --account <id>                  Account ID (from 'accounts' command)
  --profile <name>                Chrome profile (default: "Default")
  --timeout <ms>                  Request timeout (default: 30000)
  --limit <n>                     Number of transactions (default: 20)
  -h, --help                      Show help

Examples:
  avanza overview
  avanza accounts --json
  avanza holdings
  avanza holdings --account 1234567
  avanza transactions --account 1234567 --limit 10
`.trim();

async function main() {
  const rawArgs = process.argv.slice(2);

  let args;
  try {
    args = parseArgs({
      args: rawArgs,
      allowPositionals: true,
      options: {
        json:     { type: 'boolean', default: false },
        account:  { type: 'string' },
        profile:  { type: 'string', default: 'Default' },
        timeout:  { type: 'string', default: '30000' },
        limit:    { type: 'string', default: '20' },
        help:     { type: 'boolean', short: 'h', default: false },
      },
    });
  } catch (e) {
    error(e.message);
    process.exit(1);
  }

  const { values, positionals } = args;

  if (values.help || !positionals.length) {
    console.log(HELP);
    process.exit(0);
  }

  const command = positionals[0];
  const opts = {
    profile: values.profile,
    timeout: parseInt(values.timeout, 10),
  };
  const useJson = values.json;

  try {
    let output;

    switch (command) {
      case 'overview': {
        const { getOverview } = await import('./api.js');
        const { formatOverview } = await import('./format.js');
        const data = await getOverview(opts);
        output = formatOverview(data, { json: useJson });
        break;
      }
      case 'accounts': {
        const { getAccounts } = await import('./api.js');
        const { formatAccounts } = await import('./format.js');
        const data = await getAccounts(opts);
        output = formatAccounts(data, { json: useJson });
        break;
      }
      case 'holdings': {
        const { getHoldings } = await import('./api.js');
        const { formatHoldings } = await import('./format.js');
        const data = await getHoldings({ account: values.account, ...opts });
        output = formatHoldings(data, { json: useJson });
        break;
      }
      case 'transactions': {
        if (!values.account) {
          error('--account is required: avanza transactions --account <id>');
          process.exit(1);
        }
        const { getTransactions } = await import('./api.js');
        const { formatTransactions } = await import('./format.js');
        const limit = parseInt(values.limit, 10);
        const data = await getTransactions({ account: values.account, limit, ...opts });
        output = formatTransactions(data, { json: useJson });
        break;
      }
      default:
        error(`Unknown command: ${command}\nRun with --help for usage.`);
        process.exit(1);
    }

    process.stdout.write(output + '\n');
  } catch (e) {
    error(e.message);
    process.exit(1);
  }
}

function error(msg) {
  process.stderr.write(`avanza: ${msg}\n`);
}

main();
