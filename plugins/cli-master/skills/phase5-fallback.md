---
name: phase5-fallback
description: Build Puppeteer scraping fallback for when API calls fail
---

# Phase 5: Scraping Fallback

Build robust Puppeteer-based scraping fallbacks for when API calls fail (auth issues, rate limits, API changes).

## Architecture Pattern

Two-layer fallback strategy:
1. **First**: Intercept XHR/Fetch responses during page load
2. **Second**: Fall back to DOM scraping if interception fails

Lazy-load puppeteer to keep startup fast when API works.

## Shared Browser Helper

Create a `launchWithCookies()` helper in `src/scrape.js`:

```js
import { getServiceAuth } from './auth.js';

export async function launchWithCookies() {
  const puppeteer = await import('puppeteer');
  const { cookieString } = await getServiceAuth();

  const browser = await puppeteer.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });

  const page = await browser.newPage();

  // Parse and inject cookies
  const cookies = cookieString.split('; ').map(pair => {
    const [name, value] = pair.split('=');
    return {
      name,
      value,
      domain: '.service.com', // adjust per service
      path: '/'
    };
  });

  await page.setCookie(...cookies);

  return { browser, page };
}
```

## Two-Layer Scraping Strategy

### Layer 1: XHR Interception

Try to intercept the API response during page load:

```js
export async function scrapeOrders() {
  const { browser, page } = await launchWithCookies();

  try {
    let apiData = null;

    // Intercept API responses
    page.on('response', async (response) => {
      const url = response.url();
      if (url.includes('/api/orders') || url.includes('/orders.json')) {
        try {
          apiData = await response.json();
        } catch {}
      }
    });

    // Navigate and wait for API call
    await page.goto('https://service.com/orders', { waitUntil: 'networkidle2' });

    if (apiData) return apiData;

    // Fall through to DOM scraping
    return await scrapeOrdersFromDOM(page);

  } finally {
    await browser.close();
  }
}
```

### Layer 2: DOM Scraping

Fall back to parsing the rendered DOM:

```js
async function scrapeOrdersFromDOM(page) {
  // Wait for content to render
  await page.waitForSelector('[data-test-id="order-item"]', { timeout: 5000 })
    .catch(() => {}); // Don't fail if selector missing

  return page.evaluate(() => {
    const orders = [];

    // Try data-test-id first (most stable)
    let items = document.querySelectorAll('[data-test-id="order-item"]');

    // Fall back to class patterns
    if (items.length === 0) {
      items = document.querySelectorAll('.order-card, .order-row');
    }

    items.forEach(el => {
      const order = {
        id: el.querySelector('[data-test-id="order-id"]')?.textContent?.trim(),
        date: el.querySelector('[data-test-id="order-date"]')?.textContent?.trim(),
        venue: el.querySelector('[data-test-id="venue-name"]')?.textContent?.trim(),
        total: el.querySelector('[data-test-id="order-total"]')?.textContent?.trim()
      };

      if (order.id) orders.push(order);
    });

    return orders;
  });
}
```

## Wire into API Module

Add `withFallback()` wrapper in `src/api.js`:

```js
async function withFallback(apiFn, scrapeFn) {
  try {
    return await apiFn();
  } catch (e) {
    process.stderr.write(`servicename: API failed (${e.message}), trying scrape fallback...\n`);

    // Lazy-import scrape module only when needed
    const scrape = await import('./scrape.js');
    return scrapeFn(scrape);
  }
}

export async function fetchOrders() {
  return withFallback(
    () => apiRequest('/api/orders'),
    (scrape) => scrape.scrapeOrders()
  );
}
```

## Scrape Functions per Endpoint

Create one scrape function for each API endpoint that has a web equivalent:

- `scrapeOrders()` — order history page
- `scrapeOrder(id)` — order detail page
- `scrapeFavorites()` — favorites page
- `scrapeRestaurants(lat, lon)` — browse/map page
- `scrapeSearch(query)` — search results page

Not all APIs need fallbacks. Skip if no web page exists (e.g., internal-only APIs).

## Best Practices

- Always close browser in `finally` block
- Set reasonable timeouts (5-10 seconds)
- Don't fail if selector missing — return empty array
- Use semantic selectors when possible (role, aria-label)
- Prefer data-test-id over class names (more stable)
- Keep scraping logic simple — detailed parsing happens in format.js
- Log to stderr when falling back so user knows API is broken

## File Structure

```
src/
  scrape.js   # launchWithCookies + all scrape functions
  api.js      # withFallback wrapper + fallback-wrapped exports
```

## Dependencies

Add puppeteer as optional dependency:

```json
{
  "optionalDependencies": {
    "puppeteer": "^23.0.0"
  }
}
```

Users only pay install/download cost if they need fallback mode.
