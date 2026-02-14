# cli-master

Claude Code plugin that guides you through turning anything into a standalone CLI. Web services, APIs, local tools, databases — if it can be called from a shell, cli-master helps you wrap it.

## What it does

Provides skills and commands that walk Claude through a phased approach:

1. **Discover** — intercept network traffic to map API endpoints
2. **Auth** — extract Chrome cookies and tokens
3. **API Client** — build a fetch-based client with auth
4. **CLI** — parseArgs entry point with command routing
5. **Format** — markdown tables and JSON output
6. **Fallback** — Puppeteer scraping when APIs break
7. **Test** — verify everything works end-to-end

## Commands

### `/cli-create <name> <base-url> "<description>"`

Scaffold a new CLI in `clis/<name>/` from templates. Sets up the full directory structure, installs dependencies, and tells you what to do next.

### `/cli-discover <name> <url>`

Launch a headful browser with Chrome cookies, intercept network traffic, and save discovered API endpoints to `docs/api-discovery.json`.

## Skills

| Skill | Phase | Purpose |
|-------|-------|---------|
| `phase0-discover` | 0 | CDP network interception methodology |
| `phase1-auth` | 1 | Chrome cookie extraction and decryption |
| `phase2-api-client` | 2 | Build fetch-based API client |
| `phase3-cli` | 3 | parseArgs CLI entry point |
| `phase4-format` | 4 | Markdown/JSON output formatting |
| `phase5-fallback` | 5 | Puppeteer scraping safety net |
| `phase6-test` | 6 | End-to-end verification |
| `use-avanza` | — | Avanza CLI usage guide |

## Output structure

CLIs live in `clis/<name>/` — pure standalone Node.js, no plugin overhead:

```
clis/<name>/
├── src/cli.js        # entry point
├── src/auth.js       # cookie extraction
├── src/api.js        # API client
├── src/format.js     # output formatting
├── src/scrape.js     # puppeteer fallback
├── scripts/discover.js
├── docs/api-discovery.json
└── package.json
```

Agents call them via bash: `avanza accounts --json` — zero context consumption.
