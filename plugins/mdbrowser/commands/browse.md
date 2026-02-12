---
name: browse
description: Browse a URL and convert to markdown, or manage an interactive browser session
args: <url|read|close> [options]
---

# /browse

Route based on the argument:

## URL provided (no flags)
Use `mdbrowser_fetch` with the URL. This does a one-shot fetch and returns markdown.

## URL with `--session` or `--interactive`
Use `mdbrowser_open` with the URL. This starts an interactive headless browser session (requires puppeteer). The response includes page content as markdown plus numbered interactive elements you can click/type.

## `read`
Use `mdbrowser_read` to re-read the current page in an active session.

## `close`
Use `mdbrowser_close` to end the active browser session.

## Options
- `--render` — Use headless Chrome to render JavaScript before converting
- `--chrome` — Use Chrome cookies for authenticated pages
- `--profile <name>` — Chrome profile name (default: "Default")
- `--no-readability` — Skip Readability extraction, convert raw HTML

## Examples
```
/browse https://example.com
/browse https://github.com/notifications --chrome
/browse https://spa-app.com --render
/browse https://example.com --session
/browse read
/browse close
```
