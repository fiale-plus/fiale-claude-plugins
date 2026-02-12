# mdbrowser Plugin for Claude Code

**Browse any website as markdown, without leaving the terminal.**

[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-Plugin-blueviolet)](https://docs.anthropic.com/en/docs/claude-code)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](../../LICENSE)

```
/browse https://news.ycombinator.com

# Hacker News

- [Show HN: I built a thing](https://example.com) — 142 points
- [Why Rust is eating the world](https://example.com) — 89 points
...
```

One-shot fetch converts any URL to clean markdown. Interactive sessions let you click links, fill forms, and navigate — all through MCP tools.

## Quick Start

```bash
# Add marketplace and install
/plugin marketplace add fiale-plus/fiale-claude-plugins
/plugin install mdbrowser

# Fetch a page as markdown
/browse https://example.com

# Start an interactive session
/browse https://example.com --session
```

## MCP Tools

| Tool | Description |
|------|-------------|
| `mdbrowser_fetch` | One-shot URL to markdown (no browser session) |
| `mdbrowser_open` | Start interactive headless browser session |
| `mdbrowser_click` | Click element by ref number or text |
| `mdbrowser_type` | Type into input field |
| `mdbrowser_read` | Re-read current page |
| `mdbrowser_close` | End browser session |

## Commands

| Command | Description |
|---------|-------------|
| `/browse <url>` | Fetch URL as markdown |
| `/browse <url> --session` | Open interactive browser session |
| `/browse read` | Re-read current page in session |
| `/browse close` | End browser session |

## Options

- `--render` — Use headless Chrome to render JavaScript (requires puppeteer)
- `--chrome` — Use Chrome cookies for authenticated pages
- `--profile <name>` — Chrome profile name (default: "Default")
- `--no-readability` — Skip Readability extraction, convert raw HTML

## Interactive Sessions

After opening a session, interactive elements are listed with ref numbers:

```
[1] link "Documentation"
[2] textbox "Search" = ""
[3] button "Sign in"
```

Use `mdbrowser_click` with `"1"` or `"Sign in"` to interact. Use `mdbrowser_type` with a ref and value to fill inputs.

## Requirements

- **Claude Code** — Required
- **Node.js 18+** — For the MCP server
- **puppeteer** (optional) — Only needed for `--render` and interactive sessions (`npm install puppeteer`)

Dependencies are installed automatically on first use.

## License

MIT
