---
name: browse-site
description: Multi-step website browsing with interactive sessions - navigate, click, fill forms, extract data
---

# Browse Site Workflow

Use this workflow when you need to interact with a website beyond a single page fetch — navigating links, filling forms, logging in, or extracting data across multiple pages.

## Session Lifecycle

1. **Open** — `mdbrowser_open` with the target URL. Returns markdown content + numbered interactive elements.
2. **Interact** — Use `mdbrowser_click` (by ref number or text) and `mdbrowser_type` (ref + value) to navigate.
3. **Read** — `mdbrowser_read` to get updated page state after interactions.
4. **Close** — Always `mdbrowser_close` when done to clean up the headless browser process.

## Element References

After `open` or `read`, interactive elements are listed at the bottom:
```
[1] link "Documentation"
[2] textbox "Search" = ""
[3] button "Sign in"
```

Use the ref number: `mdbrowser_click` with target `"1"` clicks the Documentation link.
Use text: `mdbrowser_click` with target `"Sign in"` clicks by visible text.

## Authentication

For sites requiring login cookies, use `chrome: true` with `mdbrowser_open`. This reads cookies from your local Chrome browser. Specify `profile` if using a non-default Chrome profile.

## Form Filling Pattern

1. Open the page with `mdbrowser_open`
2. Find the input field ref number in the elements list
3. `mdbrowser_type` with the ref and value
4. `mdbrowser_click` the submit button
5. `mdbrowser_read` to see the result

## Error Recovery

- If a click doesn't navigate, try `mdbrowser_read` to see current state
- If the session is lost, `mdbrowser_open` starts a fresh one
- If elements aren't found by ref, try clicking by text content instead
- Always close sessions when done — stale sessions hold browser processes

## One-Shot vs Session

Use `mdbrowser_fetch` (no session) when you just need to read a single page.
Use `mdbrowser_open` (session) when you need to click links, fill forms, or navigate.
