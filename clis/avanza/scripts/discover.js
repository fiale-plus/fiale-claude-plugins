#!/usr/bin/env node

/**
 * Phase 0: API Discovery for Avanza
 *
 * Launches a headful Chrome with Avanza cookies, intercepts network requests via CDP,
 * and captures JSON API endpoints. User navigates key flows (accounts, holdings, etc.)
 * while the script records API calls.
 *
 * Usage:
 *   node scripts/discover.js [--profile <name>] [--duration <seconds>]
 *
 * Output: docs/api-discovery.json
 */

import { parseArgs } from 'node:util';
import { writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { getAvanzaAuth } from '../src/auth.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = join(__dirname, '..');

const HELP = `
avanza-discover — Discover Avanza API endpoints via Chrome CDP network interception

Usage:
  node scripts/discover.js [options]

Options:
  --profile <name>     Chrome profile (default: "Default")
  --duration <sec>     Max recording duration in seconds (default: 120)
  --url <url>          Starting URL (default: "https://www.avanza.se/min-ekonomi/konton.html")
  -h, --help           Show help

Navigate through Avanza in the browser that opens. The script captures all API calls.
Press Ctrl+C to stop early. Results saved to docs/api-discovery.json.
`.trim();

async function main() {
  const { values } = parseArgs({
    options: {
      profile:  { type: 'string', default: 'Default' },
      duration: { type: 'string', default: '120' },
      url:      { type: 'string', default: 'https://www.avanza.se/min-ekonomi/konton.html' },
      help:     { type: 'boolean', short: 'h', default: false },
    },
  });

  if (values.help) {
    console.log(HELP);
    process.exit(0);
  }

  const duration = parseInt(values.duration, 10) * 1000;

  console.error('avanza-discover: extracting Chrome cookies...');
  const { cookieString } = await getAvanzaAuth({ profile: values.profile });
  console.error('avanza-discover: cookies extracted');

  let puppeteer;
  try {
    puppeteer = await import('puppeteer');
  } catch {
    console.error('avanza-discover: puppeteer is required. Install with: npm install puppeteer');
    process.exit(1);
  }

  const browser = await puppeteer.default.launch({
    headless: false,
    defaultViewport: null,
    args: ['--window-size=1400,900'],
  });

  const page = await browser.newPage();

  const cookies = cookieString.split('; ').map(c => {
    const [name, ...rest] = c.split('=');
    return { name, value: rest.join('='), domain: '.avanza.se', path: '/' };
  });
  await page.setCookie(...cookies);

  const client = await page.createCDPSession();
  await client.send('Network.enable');

  const endpoints = new Map();
  const IGNORE_PATTERNS = [
    /google-analytics/i,
    /googletagmanager/i,
    /facebook\.com/i,
    /sentry\.io/i,
    /segment\.io/i,
    /amplitude/i,
    /hotjar/i,
    /datadog/i,
    /cloudflare/i,
    /fonts\.(googleapis|gstatic)/i,
    /\.png$/i, /\.jpg$/i, /\.jpeg$/i, /\.gif$/i, /\.svg$/i,
    /\.css$/i, /\.js$/i, /\.woff/i, /\.ico$/i,
  ];

  client.on('Network.responseReceived', async (params) => {
    const { response, requestId, type } = params;
    const url = response.url;

    if (type !== 'XHR' && type !== 'Fetch') return;
    if (!url.includes('avanza.se')) return;
    if (IGNORE_PATTERNS.some(p => p.test(url))) return;

    const contentType = response.headers['content-type'] || response.headers['Content-Type'] || '';
    if (!contentType.includes('json')) return;

    const parsed = new URL(url);
    const endpoint = `${parsed.origin}${parsed.pathname}`;

    let bodyPreview = null;
    try {
      const { body } = await client.send('Network.getResponseBody', { requestId });
      const json = JSON.parse(body);
      if (Array.isArray(json)) {
        bodyPreview = { type: 'array', length: json.length, itemKeys: json[0] ? Object.keys(json[0]) : [] };
      } else {
        bodyPreview = { type: 'object', keys: Object.keys(json) };
      }
    } catch {}

    const existing = endpoints.get(endpoint);
    if (existing) {
      existing.count++;
      existing.lastStatus = response.status;
      if (bodyPreview && !existing.bodyPreview) existing.bodyPreview = bodyPreview;
    } else {
      endpoints.set(endpoint, {
        url: endpoint,
        method: 'GET',
        status: response.status,
        lastStatus: response.status,
        count: 1,
        contentType: contentType.split(';')[0].trim(),
        queryParams: [...new URL(url).searchParams.keys()],
        bodyPreview,
        authHeaders: extractAuthHeaders(response.requestHeaders || {}),
      });
    }

    console.error(`avanza-discover: [${response.status}] ${type} ${endpoint}`);
  });

  client.on('Network.requestWillBeSent', (params) => {
    const { request } = params;
    if (!request.url.includes('avanza.se')) return;
    if (IGNORE_PATTERNS.some(p => p.test(request.url))) return;

    const parsed = new URL(request.url);
    const endpoint = `${parsed.origin}${parsed.pathname}`;
    const existing = endpoints.get(endpoint);
    if (existing) {
      existing.method = request.method;
      existing.authHeaders = extractAuthHeaders(request.headers);
    }
  });

  console.error(`avanza-discover: navigating to ${values.url}`);
  console.error(`avanza-discover: browse Avanza to discover API endpoints (${values.duration}s timeout)`);
  console.error('avanza-discover: press Ctrl+C to stop early\n');

  await page.goto(values.url, { waitUntil: 'networkidle2', timeout: 30000 });

  await new Promise((resolve) => {
    const timer = setTimeout(resolve, duration);
    process.on('SIGINT', () => {
      clearTimeout(timer);
      resolve();
    });
  });

  console.error(`\navanza-discover: captured ${endpoints.size} unique endpoints`);

  const result = {
    discoveredAt: new Date().toISOString(),
    startUrl: values.url,
    endpointCount: endpoints.size,
    endpoints: [...endpoints.values()].sort((a, b) => b.count - a.count),
  };

  const outPath = join(PROJECT_ROOT, 'docs', 'api-discovery.json');
  mkdirSync(join(PROJECT_ROOT, 'docs'), { recursive: true });
  writeFileSync(outPath, JSON.stringify(result, null, 2) + '\n');
  console.error(`avanza-discover: saved to ${outPath}`);

  await browser.close();
}

function extractAuthHeaders(headers) {
  const auth = {};
  for (const [key, value] of Object.entries(headers)) {
    const lower = key.toLowerCase();
    if (lower === 'authorization') auth.authorization = value.substring(0, 30) + '...';
    if (lower === 'x-securitytoken') auth['X-SecurityToken'] = value.substring(0, 30) + '...';
    if (lower === 'cookie') auth.hasCookie = true;
  }
  return Object.keys(auth).length ? auth : null;
}

main().catch(e => {
  console.error(`avanza-discover: ${e.message}`);
  process.exit(1);
});
