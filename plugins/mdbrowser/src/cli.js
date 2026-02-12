#!/usr/bin/env node

import { parseArgs } from 'node:util';
import { writeFileSync } from 'node:fs';
import { fetchPage } from './fetch.js';
import { htmlToMarkdown } from './convert.js';

const HELP = `
mdbrowser - Convert any webpage to clean markdown

Usage:
  mdbrowser <url> [options]           Fetch page as markdown (read-only)
  mdbrowser open <url> [options]      Start browser session, return state
  mdbrowser click <ref|"text">        Click element by ref number or text
  mdbrowser type <ref|"text"> <value> Type into input field
  mdbrowser read                      Re-read current page state
  mdbrowser close                     End browser session

Options:
  --render             Use headless Puppeteer for JS-rendered pages
  --chrome             Use Chrome cookies for authentication
  --profile <name>     Chrome profile name (default: "Default")
  -o, --output <file>  Write to file instead of stdout
  --no-readability     Skip Readability, convert raw HTML
  --timeout <ms>       Fetch/render timeout (default: 30000)
  -h, --help           Show help
  -v, --version        Show version

Examples:
  mdbrowser https://example.com
  mdbrowser https://example.com -o page.md
  mdbrowser https://github.com --chrome
  mdbrowser https://some-spa.com --render
  mdbrowser open https://example.com
  mdbrowser click 1
  mdbrowser click "Sign in"
  mdbrowser type 3 "hello@example.com"
  mdbrowser read
  mdbrowser close
`.trim();

async function main() {
  // Pre-process --no-readability since parseArgs negation support varies by Node version
  const rawArgs = process.argv.slice(2);
  const noReadability = rawArgs.includes('--no-readability');
  const filteredArgs = rawArgs.filter(a => a !== '--no-readability');

  let args;
  try {
    args = parseArgs({
      args: filteredArgs,
      allowPositionals: true,
      options: {
        render:       { type: 'boolean', default: false },
        chrome:       { type: 'boolean', default: false },
        profile:      { type: 'string', default: 'Default' },
        output:       { type: 'string', short: 'o' },
        timeout:      { type: 'string', default: '30000' },
        help:         { type: 'boolean', short: 'h', default: false },
        version:      { type: 'boolean', short: 'v', default: false },
      },
    });
  } catch (e) {
    error(e.message);
    process.exit(1);
  }

  const useReadability = !noReadability;

  const { values, positionals } = args;

  if (values.help) {
    console.log(HELP);
    process.exit(0);
  }

  if (values.version) {
    const { createRequire } = await import('node:module');
    const require = createRequire(import.meta.url);
    const pkg = require('../package.json');
    console.log(pkg.version);
    process.exit(0);
  }

  // --- Subcommand routing ---
  const subcommand = positionals[0];
  const SUBCOMMANDS = ['open', 'click', 'type', 'read', 'close'];

  if (SUBCOMMANDS.includes(subcommand)) {
    const { actOpen, actClick, actType, actRead, actClose } = await import('./act.js');
    const timeout = parseInt(values.timeout, 10);

    try {
      let result;
      switch (subcommand) {
        case 'open': {
          const url = positionals[1];
          if (!url) { error('URL is required: mdbrowser open <url>'); process.exit(1); }
          let parsed;
          try { parsed = new URL(url.startsWith('http') ? url : `https://${url}`); }
          catch { error(`Invalid URL: ${url}`); process.exit(1); }

          let cookies;
          if (values.chrome) {
            const { getChromeCoookies } = await import('./cookies.js');
            cookies = await getChromeCoookies(parsed.href, { profile: values.profile });
            if (!cookies) { error('No cookies found for this domain.'); process.exit(1); }
          }
          result = await actOpen(parsed.href, { cookies, timeout });
          break;
        }
        case 'click': {
          const target = positionals[1];
          if (!target) { error('Target is required: mdbrowser click <ref|"text">'); process.exit(1); }
          result = await actClick(target);
          break;
        }
        case 'type': {
          const target = positionals[1];
          const value = positionals[2];
          if (!target || !value) { error('Usage: mdbrowser type <ref|"text"> <value>'); process.exit(1); }
          result = await actType(target, value);
          break;
        }
        case 'read':
          result = await actRead();
          break;
        case 'close':
          result = await actClose();
          break;
      }

      if (values.output) {
        writeFileSync(values.output, result + '\n');
      } else {
        process.stdout.write(result + '\n');
      }
    } catch (e) {
      error(e.message);
      process.exit(1);
    }
    process.exit(0);
  }

  // --- Existing fetch/render flow ---
  const url = positionals[0];
  if (!url) {
    error('URL is required.\n\nUsage: mdbrowser <url> [options]\nRun with --help for full usage.');
    process.exit(1);
  }

  // Validate URL
  let parsed;
  try {
    parsed = new URL(url.startsWith('http') ? url : `https://${url}`);
  } catch {
    error(`Invalid URL: ${url}`);
    process.exit(1);
  }
  const fullUrl = parsed.href;
  const timeout = parseInt(values.timeout, 10);

  try {
    // Get cookies if --chrome
    let cookies;
    if (values.chrome) {
      const { getChromeCoookies } = await import('./cookies.js');
      cookies = await getChromeCoookies(fullUrl, { profile: values.profile });
      if (!cookies) {
        error('No cookies found for this domain.');
        process.exit(1);
      }
    }

    // Fetch HTML
    let html;
    if (values.render) {
      const { renderPage } = await import('./render.js');
      html = await renderPage(fullUrl, { cookies, timeout });
    } else {
      html = await fetchPage(fullUrl, { cookies, timeout });
    }

    // Convert to markdown
    const md = htmlToMarkdown(html, fullUrl, { useReadability });

    // Output
    if (values.output) {
      writeFileSync(values.output, md + '\n');
    } else {
      process.stdout.write(md + '\n');
    }
  } catch (e) {
    error(e.message);
    process.exit(1);
  }
}

function error(msg) {
  process.stderr.write(`mdbrowser: ${msg}\n`);
}

main();
