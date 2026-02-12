#!/usr/bin/env node

import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');
const CLI = join(ROOT, 'src', 'cli.js');

function runMdbrowser(args) {
  try {
    const stdout = execFileSync('node', [CLI, ...args], {
      cwd: ROOT,
      maxBuffer: 10 * 1024 * 1024,
      timeout: 120_000,
      encoding: 'utf8',
    });
    return { content: [{ type: 'text', text: stdout }] };
  } catch (err) {
    const msg = err.stderr?.trim() || err.stdout?.trim() || err.message;
    return { content: [{ type: 'text', text: msg }], isError: true };
  }
}

const server = new McpServer({
  name: 'mdbrowser',
  version: '1.0.0',
});

// --- mdbrowser_fetch: one-shot URL → markdown ---
server.tool(
  'mdbrowser_fetch',
  'Fetch a URL and convert to markdown (no browser session)',
  {
    url: z.string().describe('URL to fetch'),
    render: z.boolean().optional().describe('Use headless Chrome to render JS (requires puppeteer)'),
    chrome: z.boolean().optional().describe('Use Chrome cookies for authentication'),
    profile: z.string().optional().describe('Chrome profile name (default: "Default")'),
    noReadability: z.boolean().optional().describe('Skip Readability, convert raw HTML'),
    timeout: z.number().optional().describe('Timeout in ms (default: 30000)'),
  },
  async ({ url, render, chrome, profile, noReadability, timeout }) => {
    const args = [url];
    if (render) args.push('--render');
    if (chrome) args.push('--chrome');
    if (profile) args.push('--profile', profile);
    if (noReadability) args.push('--no-readability');
    if (timeout) args.push('--timeout', String(timeout));
    return runMdbrowser(args);
  }
);

// --- mdbrowser_open: start interactive session ---
server.tool(
  'mdbrowser_open',
  'Open a URL in an interactive headless browser session (requires puppeteer)',
  {
    url: z.string().describe('URL to open'),
    chrome: z.boolean().optional().describe('Use Chrome cookies for authentication'),
    profile: z.string().optional().describe('Chrome profile name (default: "Default")'),
    timeout: z.number().optional().describe('Timeout in ms (default: 30000)'),
  },
  async ({ url, chrome, profile, timeout }) => {
    const args = ['open', url];
    if (chrome) args.push('--chrome');
    if (profile) args.push('--profile', profile);
    if (timeout) args.push('--timeout', String(timeout));
    return runMdbrowser(args);
  }
);

// --- mdbrowser_click: click element ---
server.tool(
  'mdbrowser_click',
  'Click an element by ref number or text in the active browser session',
  {
    target: z.string().describe('Element ref number (e.g. "3") or text to click (e.g. "Sign in")'),
  },
  async ({ target }) => runMdbrowser(['click', target])
);

// --- mdbrowser_type: type into input ---
server.tool(
  'mdbrowser_type',
  'Type into an input field by ref number or text in the active browser session',
  {
    target: z.string().describe('Element ref number (e.g. "3") or label text'),
    value: z.string().describe('Text to type into the field'),
  },
  async ({ target, value }) => runMdbrowser(['type', target, value])
);

// --- mdbrowser_read: re-read page ---
server.tool(
  'mdbrowser_read',
  'Re-read the current page in the active browser session',
  {},
  async () => runMdbrowser(['read'])
);

// --- mdbrowser_close: end session ---
server.tool(
  'mdbrowser_close',
  'Close the active browser session',
  {},
  async () => runMdbrowser(['close'])
);

// Start
const transport = new StdioServerTransport();
await server.connect(transport);
