/**
 * Puppeteer scraping fallback for when Avanza API calls fail.
 * Lazy-loads puppeteer. Injects Chrome cookies for authentication.
 */

import { getAvanzaAuth } from './auth.js';

const SCRAPE_URLS = {
  overview: 'https://www.avanza.se/start',
  accounts: 'https://www.avanza.se/min-ekonomi/konton.html',
  holdings: 'https://www.avanza.se/min-ekonomi/innehav.html',
};

async function launchWithCookies(opts = {}) {
  let puppeteer;
  try {
    puppeteer = await import('puppeteer');
  } catch {
    throw new Error(
      'Scraping fallback requires puppeteer.\n' +
      'Install it with: npm install puppeteer'
    );
  }

  const { cookieString } = await getAvanzaAuth(opts);

  const browser = await puppeteer.default.launch({ headless: true });
  const page = await browser.newPage();
  page.setDefaultTimeout(opts.timeout || 30000);

  const cookies = cookieString.split('; ').map(c => {
    const [name, ...rest] = c.split('=');
    return { name, value: rest.join('='), domain: '.avanza.se', path: '/' };
  });
  await page.setCookie(...cookies);

  return { browser, page };
}

/**
 * Scrape portfolio overview.
 */
export async function scrapeOverview(opts = {}) {
  const { browser, page } = await launchWithCookies(opts);

  try {
    let apiData = null;
    page.on('response', async (res) => {
      const url = res.url();
      if (url.includes('/account/overview') || url.includes('/_mobile/account')) {
        try {
          const ct = res.headers()['content-type'] || '';
          if (ct.includes('json')) {
            apiData = await res.json();
          }
        } catch {}
      }
    });

    await page.goto(SCRAPE_URLS.overview, { waitUntil: 'networkidle2' });
    if (apiData) return apiData;

    return await page.evaluate(() => {
      const totalEl = document.querySelector('[class*="total"], [data-e2e*="total"]');
      const changeEl = document.querySelector('[class*="change"], [data-e2e*="change"]');
      return {
        totalValue: totalEl?.textContent?.trim(),
        changeToday: changeEl?.textContent?.trim(),
      };
    });
  } finally {
    await browser.close().catch(() => {});
  }
}

/**
 * Scrape accounts list.
 */
export async function scrapeAccounts(opts = {}) {
  const { browser, page } = await launchWithCookies(opts);

  try {
    let apiData = null;
    page.on('response', async (res) => {
      const url = res.url();
      if (url.includes('/account/list') || url.includes('/accounts')) {
        try {
          const ct = res.headers()['content-type'] || '';
          if (ct.includes('json')) {
            apiData = await res.json();
          }
        } catch {}
      }
    });

    await page.goto(SCRAPE_URLS.accounts, { waitUntil: 'networkidle2' });
    if (apiData) return apiData;

    return await page.evaluate(() => {
      const rows = document.querySelectorAll('table tbody tr, [class*="AccountRow"], [class*="account-row"]');
      return Array.from(rows).map(row => {
        const cells = row.querySelectorAll('td, [class*="cell"]');
        const name = cells[0]?.textContent?.trim();
        const type = cells[1]?.textContent?.trim();
        const value = cells[2]?.textContent?.trim();
        return { name, accountType: type, totalValue: value };
      }).filter(a => a.name);
    });
  } finally {
    await browser.close().catch(() => {});
  }
}

/**
 * Scrape holdings.
 */
export async function scrapeHoldings(opts = {}) {
  const { browser, page } = await launchWithCookies(opts);

  try {
    let apiData = null;
    page.on('response', async (res) => {
      const url = res.url();
      if (url.includes('/positions') || url.includes('/holdings')) {
        try {
          const ct = res.headers()['content-type'] || '';
          if (ct.includes('json')) {
            apiData = await res.json();
          }
        } catch {}
      }
    });

    await page.goto(SCRAPE_URLS.holdings, { waitUntil: 'networkidle2' });
    if (apiData) return apiData;

    return await page.evaluate(() => {
      const rows = document.querySelectorAll('table tbody tr, [class*="PositionRow"], [class*="position-row"]');
      return Array.from(rows).map(row => {
        const cells = row.querySelectorAll('td, [class*="cell"]');
        const name = cells[0]?.textContent?.trim();
        const qty = cells[1]?.textContent?.trim();
        const price = cells[2]?.textContent?.trim();
        const value = cells[3]?.textContent?.trim();
        return { name, volume: qty, lastPrice: price, value };
      }).filter(p => p.name);
    });
  } finally {
    await browser.close().catch(() => {});
  }
}

/**
 * Scrape transactions for an account.
 */
export async function scrapeTransactions({ account, ...opts } = {}) {
  const { browser, page } = await launchWithCookies(opts);

  try {
    let apiData = null;
    page.on('response', async (res) => {
      const url = res.url();
      if (url.includes('/transactions') || url.includes(account)) {
        try {
          const ct = res.headers()['content-type'] || '';
          if (ct.includes('json')) {
            apiData = await res.json();
          }
        } catch {}
      }
    });

    await page.goto(`https://www.avanza.se/min-ekonomi/konton/${encodeURIComponent(account)}/transaktioner.html`, {
      waitUntil: 'networkidle2',
    });
    if (apiData) return apiData;

    return await page.evaluate(() => {
      const rows = document.querySelectorAll('table tbody tr');
      return Array.from(rows).map(row => {
        const cells = row.querySelectorAll('td');
        return {
          date: cells[0]?.textContent?.trim(),
          transactionType: cells[1]?.textContent?.trim(),
          description: cells[2]?.textContent?.trim(),
          amount: cells[3]?.textContent?.trim(),
        };
      }).filter(t => t.date);
    });
  } finally {
    await browser.close().catch(() => {});
  }
}
