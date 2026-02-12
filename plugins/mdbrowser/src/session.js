import { readFileSync, writeFileSync, unlinkSync, existsSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const SESSION_FILE = join(tmpdir(), 'mdbrowser-session.json');

async function importPuppeteer() {
  try {
    return await import('puppeteer');
  } catch {
    throw new Error(
      'Browser session requires puppeteer.\n' +
      'Install it with: npm install puppeteer'
    );
  }
}

async function launchDetachedBrowser() {
  const puppeteer = await importPuppeteer();
  const execPath = puppeteer.default.executablePath();

  // Spawn Chrome directly as a detached process
  const args = [
    '--headless',
    '--disable-gpu',
    '--remote-debugging-port=0',
    '--remote-debugging-address=127.0.0.1',
  ];
  const proc = spawn(execPath, args, {
    detached: true,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  proc.unref();

  // Read stderr to find the DevTools WebSocket URL
  const wsEndpoint = await new Promise((resolve, reject) => {
    let stderr = '';
    const onData = (chunk) => {
      stderr += chunk.toString();
      const match = stderr.match(/DevTools listening on (ws:\/\/[^\s]+)/);
      if (match) {
        proc.stderr.removeListener('data', onData);
        proc.stdout.unref();
        proc.stderr.unref();
        resolve(match[1]);
      }
    };
    proc.stderr.on('data', onData);
    proc.on('error', reject);
    setTimeout(() => reject(new Error('Browser failed to start')), 10000);
  });

  return { wsEndpoint, pid: proc.pid, puppeteer };
}

export async function openSession(url, { cookies, timeout = 30000 } = {}) {
  const { wsEndpoint, pid, puppeteer } = await launchDetachedBrowser();
  writeFileSync(SESSION_FILE, JSON.stringify({ wsEndpoint, pid }), { mode: 0o600 });

  const browser = await puppeteer.default.connect({ browserWSEndpoint: wsEndpoint });
  const page = await browser.newPage();
  page.setDefaultTimeout(timeout);

  if (cookies) {
    const { hostname } = new URL(url);
    const cookieObjects = cookies.split('; ').map(c => {
      const [name, ...rest] = c.split('=');
      return { name, value: rest.join('='), domain: `.${hostname}`, path: '/' };
    });
    await page.setCookie(...cookieObjects);
  }

  await page.goto(url, { waitUntil: 'networkidle2', timeout });

  // Save target ID so we can find this page later
  const targetId = page.target()._targetId;
  writeFileSync(SESSION_FILE, JSON.stringify({ wsEndpoint, targetId, pid }), { mode: 0o600 });

  return { browser, page };
}

export async function getSession() {
  if (!existsSync(SESSION_FILE)) {
    throw new Error('No active session. Run: mdbrowser open <url>');
  }

  const { wsEndpoint } = JSON.parse(readFileSync(SESSION_FILE, 'utf8'));
  const puppeteer = await importPuppeteer();

  let browser;
  try {
    browser = await puppeteer.default.connect({ browserWSEndpoint: wsEndpoint });
  } catch {
    unlinkSync(SESSION_FILE);
    throw new Error('No active session. Run: mdbrowser open <url>');
  }

  const { targetId } = JSON.parse(readFileSync(SESSION_FILE, 'utf8'));
  const pages = await browser.pages();
  // Find the page we opened, fall back to last non-blank page
  const page = pages.find(p => p.target()._targetId === targetId)
    || pages.find(p => p.url() !== 'about:blank' && !p.url().startsWith('chrome://'))
    || pages[pages.length - 1];
  return { browser, page };
}

export async function closeSession() {
  if (!existsSync(SESSION_FILE)) {
    throw new Error('No active session.');
  }

  const { wsEndpoint } = JSON.parse(readFileSync(SESSION_FILE, 'utf8'));
  const puppeteer = await importPuppeteer();

  try {
    const browser = await puppeteer.default.connect({ browserWSEndpoint: wsEndpoint });
    await browser.close();
  } catch {
    // browser already dead, just clean up
  }

  unlinkSync(SESSION_FILE);
}
