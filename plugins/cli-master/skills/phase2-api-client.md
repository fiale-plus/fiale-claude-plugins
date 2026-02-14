---
name: phase2-api-client
description: Build a fetch-based API client from discovered endpoints
---

# Phase 2: API Client

Build a typed, fetch-based API client from discovered endpoints with authentication caching and scraping fallback.

## Overview

Create one exported function per discovered endpoint, handle auth token injection and refresh, and provide graceful degradation to scraping when API calls fail.

## Implementation Steps

### 1. Module Structure

```javascript
// src/api.js
import { getAuthCookies } from './auth.js';

const BASE_URL = 'https://api.service.com/v1'; // From api-discovery.json

// Cache auth at module level, clear on 401/403
let cachedAuth = null;

async function getAuth() {
  if (!cachedAuth) {
    cachedAuth = await getAuthCookies('example.com');
  }
  return cachedAuth;
}

function clearAuth() {
  cachedAuth = null;
}
```

### 2. Request Helper with Auth Injection

```javascript
async function request(endpoint, options = {}) {
  const { token, cookieString } = await getAuth();

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 30000);

  try {
    const response = await fetch(`${BASE_URL}${endpoint}`, {
      ...options,
      headers: {
        'Cookie': cookieString,
        'Authorization': token ? `Bearer ${token}` : undefined,
        'Content-Type': 'application/json',
        ...options.headers
      },
      signal: controller.signal
    });

    // Handle auth failures
    if (response.status === 401 || response.status === 403) {
      clearAuth();
      throw new Error(
        'Authentication failed. Please log in to the service in Chrome and try again.'
      );
    }

    if (!response.ok) {
      throw new Error(`API error: ${response.status} ${response.statusText}`);
    }

    return await response.json();
  } finally {
    clearTimeout(timeout);
  }
}
```

### 3. Endpoint Functions

Create one function per discovered endpoint, named descriptively:

```javascript
// GET /orders?limit=20&offset=0
export async function getOrders({ limit = 20, offset = 0 } = {}) {
  const params = new URLSearchParams({ limit, offset });
  return await request(`/orders?${params}`);
}

// GET /orders/:id
export async function getOrder(orderId) {
  if (!orderId) throw new Error('Order ID is required');
  return await request(`/orders/${orderId}`);
}

// POST /orders/:id/cancel
export async function cancelOrder(orderId) {
  if (!orderId) throw new Error('Order ID is required');
  return await request(`/orders/${orderId}/cancel`, {
    method: 'POST'
  });
}

// GET /search?q=pizza&lat=60.1699&lon=24.9384
export async function search({ query, lat, lon, limit = 20 } = {}) {
  const params = new URLSearchParams({ q: query, lat, lon, limit });
  return await request(`/search?${params}`);
}

// GET /favorites
export async function getFavorites() {
  return await request('/favorites');
}

// POST /favorites/:id
export async function addFavorite(itemId) {
  if (!itemId) throw new Error('Item ID is required');
  return await request(`/favorites/${itemId}`, {
    method: 'POST'
  });
}
```

### 4. Fallback to Scraping

Wrap API functions with a fallback that uses Puppeteer scraping when API fails:

```javascript
export function withFallback(apiFn, scrapeFn) {
  return async function(...args) {
    try {
      return await apiFn(...args);
    } catch (apiError) {
      console.error(
        `API failed (${apiError.message}), falling back to scraping...`
      );

      // Lazy-import scrape.js to avoid loading Puppeteer unless needed
      const { scrape } = await import('./scrape.js');

      try {
        return await scrapeFn(scrape, ...args);
      } catch (scrapeError) {
        throw new Error(
          `Both API and scraping failed:\n` +
          `  API: ${apiError.message}\n` +
          `  Scrape: ${scrapeError.message}`
        );
      }
    }
  };
}

// Example usage
export const getOrdersWithFallback = withFallback(
  getOrders,
  async (scrape, { limit }) => {
    const html = await scrape('/orders');
    // Parse HTML to extract order data
    return parseOrdersFromHtml(html);
  }
);
```

### 5. Response Transformation

Add helpers to transform API responses to CLI-friendly formats:

```javascript
// src/format.js
export function formatOrder(order) {
  return {
    id: order.id,
    status: order.status,
    items: order.items?.length || 0,
    total: formatCurrency(order.total, order.currency),
    createdAt: new Date(order.created_at).toLocaleString()
  };
}

export function formatOrders(response) {
  return response.data.map(formatOrder);
}

function formatCurrency(amount, currency = 'USD') {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency
  }).format(amount / 100); // Assuming cents
}
```

### 6. Pagination Helpers

If the API uses pagination, provide helpers:

```javascript
export async function getAllOrders({ maxPages = 10 } = {}) {
  const allOrders = [];
  let offset = 0;
  const limit = 50;

  for (let page = 0; page < maxPages; page++) {
    const response = await getOrders({ limit, offset });
    allOrders.push(...response.data);

    if (!response.meta?.has_more) break;
    offset += limit;
  }

  return allOrders;
}
```

## API Client Checklist

- [ ] One exported function per endpoint from discovery
- [ ] Descriptive function names (getOrders, not fetchData)
- [ ] Auth token cached at module level
- [ ] Clear auth cache on 401/403
- [ ] AbortController timeout (30s default)
- [ ] Proper error messages for auth failures
- [ ] URL parameters from discovery (limit, offset, etc.)
- [ ] Lazy import of scrape.js in fallback
- [ ] Fallback logged to stderr
- [ ] Response transformers for CLI output
- [ ] Pagination support if applicable

## Example Full API Client

```javascript
// src/api.js
import { getAuthCookies } from './auth.js';

const BASE_URL = 'https://api.example.com/v1';
let cachedAuth = null;

async function getAuth() {
  if (!cachedAuth) {
    cachedAuth = await getAuthCookies('example.com');
  }
  return cachedAuth;
}

function clearAuth() {
  cachedAuth = null;
}

async function request(endpoint, options = {}) {
  const { token, cookieString } = await getAuth();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 30000);

  try {
    const response = await fetch(`${BASE_URL}${endpoint}`, {
      ...options,
      headers: {
        'Cookie': cookieString,
        'Authorization': token ? `Bearer ${token}` : undefined,
        'Content-Type': 'application/json',
        ...options.headers
      },
      signal: controller.signal
    });

    if (response.status === 401 || response.status === 403) {
      clearAuth();
      throw new Error('Auth failed. Log in to the service in Chrome.');
    }

    if (!response.ok) {
      throw new Error(`API error: ${response.status}`);
    }

    return await response.json();
  } finally {
    clearTimeout(timeout);
  }
}

export async function getOrders({ limit = 20, offset = 0 } = {}) {
  const params = new URLSearchParams({ limit, offset });
  return await request(`/orders?${params}`);
}

export async function getOrder(orderId) {
  if (!orderId) throw new Error('Order ID required');
  return await request(`/orders/${orderId}`);
}
```
