---
name: phase0-discover
description: Discover a web service's API endpoints via CDP network interception
---

# Phase 0: API Discovery

Use Chrome DevTools Protocol to intercept and record API endpoints while navigating a web service.

## Overview

Launch a headful Chrome browser with authenticated cookies and record all API requests as you navigate through the service's key flows. This creates a comprehensive API map without needing documentation.

## Implementation Steps

### 1. Setup Chrome with Cookie Injection

```javascript
import puppeteer from 'puppeteer';
import { getAuthCookies } from './auth.js';

const { cookieString } = await getAuthCookies('service.com');
const browser = await puppeteer.launch({
  headless: false,
  defaultViewport: null,
  args: ['--start-maximized']
});
```

### 2. Enable CDP Network Interception

```javascript
const page = await browser.newPage();
const client = await page.target().createCDPSession();
await client.send('Network.enable');

const endpoints = [];
```

### 3. Filter and Record Relevant Requests

Listen for `Network.responseReceived` and `Network.loadingFinished` events:

**Filter OUT:**
- Analytics/tracking: `google-analytics`, `sentry.io`, `segment.com`, `amplitude.com`, `datadog.com`, `hotjar.com`
- Static assets: `.css`, `.js`, `.png`, `.jpg`, `.svg`, `.woff`, `.woff2`
- Third-party CDNs

**Capture ONLY:**
- XHR/Fetch requests to the service's own domain
- Responses with `Content-Type: application/json`
- Status codes 200-299 (successful responses)

**Record these fields:**
```javascript
{
  url: 'https://api.service.com/v1/orders',
  method: 'GET',
  status: 200,
  queryParams: { limit: 20, offset: 0 },
  responseSchema: ['data', 'meta', 'pagination'], // top-level keys only
  authHeaders: ['Cookie', 'Authorization'],
  timestamp: Date.now()
}
```

### 4. Parse Response Schema

For each JSON response, extract only the top-level keys:

```javascript
const body = await client.send('Network.getResponseBody', { requestId });
const parsed = JSON.parse(body.body);
const schema = Object.keys(parsed);
```

### 5. Save Discovery Results

Write to `docs/api-discovery.json`:

```javascript
const discovery = {
  discoveredAt: new Date().toISOString(),
  startUrl: 'https://service.com',
  endpointCount: endpoints.length,
  endpoints: endpoints
};

await fs.writeFile(
  'docs/api-discovery.json',
  JSON.stringify(discovery, null, 2)
);
```

### 6. User Navigation Loop

Keep the browser open for manual navigation:

```javascript
console.error('Navigate through the service. Press Ctrl+C to stop and save.');

process.on('SIGINT', async () => {
  await saveDiscovery();
  await browser.close();
  process.exit(0);
});
```

## Tips

- **Run multiple sessions** for different user flows (browse, search, checkout, account settings)
- **Check for pagination** parameters (`limit`, `offset`, `page`, `cursor`)
- **Note auth mechanisms**: Bearer token in Authorization header vs cookies vs custom headers
- **Deduplicate** endpoints with same URL but different query params
- **Group by resource** (orders, products, users) for easier API client organization
- **Record error responses** (4xx, 5xx) separately to understand error schemas

## Output Format

```json
{
  "discoveredAt": "2026-02-14T10:30:00Z",
  "startUrl": "https://service.com",
  "endpointCount": 12,
  "endpoints": [
    {
      "url": "https://api.service.com/v1/orders",
      "method": "GET",
      "status": 200,
      "queryParams": { "limit": 20, "offset": 0 },
      "responseSchema": ["data", "meta", "pagination"],
      "authHeaders": ["Cookie", "Authorization"],
      "timestamp": 1708772400000
    }
  ]
}
```
