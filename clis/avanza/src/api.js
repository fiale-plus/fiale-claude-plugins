import { getAvanzaAuth } from './auth.js';

// Avanza's internal API — endpoints discovered via Phase 0
const BASE_URL = 'https://www.avanza.se';

let _auth = null;

async function auth(opts) {
  if (!_auth) {
    _auth = await getAvanzaAuth(opts);
  }
  return _auth;
}

async function request(url, opts = {}) {
  const { token, cookieString } = await auth(opts);

  const headers = {
    'Accept': 'application/json',
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
    'Cookie': cookieString,
    'X-Requested-With': 'XMLHttpRequest',
  };

  if (token) {
    headers['X-SecurityToken'] = token;
  }

  const timeout = opts.timeout || 30000;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeout);

  try {
    const res = await fetch(url, {
      headers,
      signal: controller.signal,
    });

    if (res.status === 401 || res.status === 403) {
      _auth = null;
      throw new Error(
        `Authentication failed (${res.status}). ` +
        'Make sure you are logged into avanza.se in Chrome. BankID may be required.'
      );
    }

    if (!res.ok) {
      throw new Error(`API error: ${res.status} ${res.statusText} for ${url}`);
    }

    return res.json();
  } finally {
    clearTimeout(timer);
  }
}

async function withFallback(apiFn, scrapeFn) {
  try {
    return await apiFn();
  } catch (e) {
    process.stderr.write(`avanza: API failed (${e.message}), trying scrape fallback...\n`);
    return scrapeFn();
  }
}

/**
 * Get portfolio overview — total value, daily change, accounts summary.
 * Avanza: GET /_mobile/account/overview
 */
export async function getOverview(opts = {}) {
  const url = `${BASE_URL}/_mobile/account/overview`;
  return withFallback(() => request(url, opts), async () => {
    const { scrapeOverview } = await import('./scrape.js');
    return scrapeOverview(opts);
  });
}

/**
 * Get all accounts with balances.
 * Avanza: GET /_mobile/account/list
 */
export async function getAccounts(opts = {}) {
  const url = `${BASE_URL}/_mobile/account/list`;
  return withFallback(() => request(url, opts), async () => {
    const { scrapeAccounts } = await import('./scrape.js');
    return scrapeAccounts(opts);
  });
}

/**
 * Get holdings for a specific account or all accounts.
 * Avanza: GET /_mobile/account/{accountId}/positions
 */
export async function getHoldings({ account, ...opts } = {}) {
  if (account) {
    const url = `${BASE_URL}/_mobile/account/${encodeURIComponent(account)}/positions`;
    return withFallback(() => request(url, opts), async () => {
      const { scrapeHoldings } = await import('./scrape.js');
      return scrapeHoldings({ account, ...opts });
    });
  }
  // No account specified — get overview which includes all positions
  const url = `${BASE_URL}/_mobile/account/overview`;
  return withFallback(() => request(url, opts), async () => {
    const { scrapeHoldings } = await import('./scrape.js');
    return scrapeHoldings(opts);
  });
}

/**
 * Get recent transactions for an account.
 * Avanza: GET /_mobile/account/{accountId}/transactions
 */
export async function getTransactions({ account, limit = 20, ...opts } = {}) {
  if (!account) {
    throw new Error('--account is required for transactions command');
  }
  const url = `${BASE_URL}/_mobile/account/${encodeURIComponent(account)}/transactions?from=0&to=${limit}`;
  return withFallback(() => request(url, opts), async () => {
    const { scrapeTransactions } = await import('./scrape.js');
    return scrapeTransactions({ account, limit, ...opts });
  });
}
