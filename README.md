# Claude Code Plugins

Plugins for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Compatible-blueviolet)](https://docs.anthropic.com/en/docs/claude-code)

## Plugins

| Plugin | What it does |
|--------|-------------|
| [Status Hub](#status-hub) | Track PRs, calendar, Slack, stocks, music in your statusline |
| [TradingView](#tradingview) | AI-powered market screening via 75+ indicators |
| [Brain](#brain) | Three-layer knowledge capture: project docs, personal vault, optional team vault |
| [mdbrowser](#mdbrowser) | Browse any URL as clean markdown |
| [Vibes](#vibes) | Sentiment-driven musical phrases on task completion |
| [Remote Layout](#remote-layout) | Mobile-friendly response formatting for remote sessions |

---

## Status Hub

**Your world at a glance, without leaving the terminal.**

Track PRs, calendar, Slack, stocks, and music — all surfaced in your Claude Code statusline.

Alerts appear non-blocking; `/hub-ack` gives smart context-aware actions (merge PR, join meeting, reply to Slack).

```
/hub-setup          →  Configure statusline integration
       ↓
/hub-<service>      →  Add monitors (PRs, calendar, Slack, finance)
       ↓
[statusline alert]  →  Non-blocking notification appears
       ↓
/hub-ack            →  Smart actions based on context
```

**Install:**
```bash
/plugin marketplace add fiale-plus/fiale-claude-plugins
/plugin install claude-status-hub
/hub-setup
```

→ [Full documentation](plugins/claude-status-hub)

---

## TradingView

**AI-powered market screening, without leaving the terminal.**

Screen stocks, forex, crypto, and ETFs using TradingView's 75+ fundamental and technical indicators. Check market regime across global indexes before running a screening strategy.

```
/market-regime

┌─────────────────────┬──────────┬──────────┬───────────┬────────┐
│ Index               │ Price    │ ATH      │ Drawdown  │ Status │
├─────────────────────┼──────────┼──────────┼───────────┼────────┤
│ Nasdaq Composite    │ 19,864   │ 20,173   │ -1.53%    │ 🟢     │
│ OMX Stockholm 30    │ 2,547    │ 2,601    │ -2.08%    │ 🟢     │
│ Nikkei 225          │ 38,026   │ 42,426   │ -10.37%   │ 🔴     │
└─────────────────────┴──────────┴──────────┴───────────┴────────┘
```

**Install:**
```bash
/plugin marketplace add fiale-plus/fiale-claude-plugins
/plugin install tradingview
/market-regime
```

→ [Full documentation](plugins/tradingview)

---

## Brain

**Sessions become structured knowledge — in your repo, your vault, your team.**

Every Claude Code session is automatically queued on stop and synthesized into three layers: project decisions/gotchas/patterns committed inside the repo (visible to any engineer or AI), personal atoms in an Obsidian vault, and an optional git-backed team vault shared across teammates. Knowledge is auto-loaded into Claude via CLAUDE.md `@imports` — no manual steps.

```
Stop hook    → queues transcript to pending.json
New session  → auto-synthesizes pending (background, non-blocking)
              → git pull team vault (fast-forward, silent)
PreToolUse   → surfaces relevant atoms as inline hints
```

> **Everyone in the repo benefits — plugin or not.**
> Brain commits knowledge into `.brain/` inside your git repo, auto-loaded via
> `CLAUDE.md @imports`. Any Claude working in that repo sees it immediately.
> Install the plugin yourself → your whole team gets smarter for free.

**Free (just work in a brain-powered repo):** project decisions, gotchas, and
patterns auto-loaded into every Claude session in that repo.

**Install Brain:** add your personal atom vault (surfaced as inline hints) +
optional team vault with cross-project wisdom from everyone on the team.

**Install:**
```bash
/plugin marketplace add fiale-plus/fiale-claude-plugins
/plugin install brain
/brain-setup
```

→ [Full documentation](plugins/brain)

---

## mdbrowser

**Browse any website as markdown, without leaving the terminal.**

One-shot fetch converts any URL to clean markdown. Interactive sessions let you click links, fill forms, and navigate — all through Claude's tool calls.

```
/browse https://news.ycombinator.com

# Hacker News

- [Show HN: I built a thing](https://example.com) — 142 points
- [Why Rust is eating the world](https://example.com) — 89 points
```

**Install:**
```bash
/plugin marketplace add fiale-plus/fiale-claude-plugins
/plugin install mdbrowser
/browse https://example.com
```

→ [Full documentation](plugins/mdbrowser)

---

## Vibes

**Your session's emotional arc, in sound.**

Plays a short musical phrase whenever Claude finishes a task or needs your attention. Mood is inferred from the transcript: triumphant on success, gentle descent on errors, unresolved on notifications. Pure-Python synthesis — no audio files, no dependencies. Requires macOS (`afplay`).

**Install:**
```bash
/plugin marketplace add fiale-plus/fiale-claude-plugins
/plugin install vibes
```

→ [Full documentation](plugins/vibes)

---

## Remote Layout

**Mobile-friendly responses for Claude Code remote control sessions.**

Switch Claude's response format for small screens. Persists across sessions via `/remote-layout <mode>`.

| Mode | Description |
|------|-------------|
| `code` | Fenced code block, 28-char lines — tight monospace |
| `code-wrap` | Fenced code block, no line limit — zoom-mode autowrap |
| `watch` | Ultra-terse, always ends with 3 numbered REPLY options |
| `off` | Disable, restore normal formatting |

**Install:**
```bash
/plugin marketplace add fiale-plus/fiale-claude-plugins
/plugin install remote-layout
/remote-layout watch
```

→ [Full documentation](plugins/remote-layout)

---

## License

MIT
