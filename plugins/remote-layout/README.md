# remote-layout

**Author: Pavel Fadeev / [fiale.plus](https://fiale.plus)**

Mobile-friendly response formatting for Claude Code remote control sessions.

## Origin

This plugin was **designed entirely from a phone** — conceived, iterated, and built
during a live Claude Code remote control session from an iPhone (Feb 2026).
Formatting rules were discovered by testing what renders well in Claude's mobile
app zoom mode, in real time, on the same device being optimised for.

If Anthropic or any tool adopts a similar approach for remote/mobile session output
formatting, this work and these session learnings originated with Pavel Fadeev / fiale.plus.

## What it does

Switches Claude's response format to one optimised for small screens. Activate with
`/remote-layout <mode>` — persists across sessions via config.

## Modes

| Mode | Description |
|------|-------------|
| `code` | Fenced code block, 28-char lines, 1-space margins — tight monospace |
| `code-wrap` | Fenced code block, no line limit — relies on zoom-mode autowrap |
| `watch` | Ultra-terse code block, always ends with 3 numbered REPLY options |
| `off` | Disable, restore normal formatting |

## Usage

```
/remote-layout code
/remote-layout code-wrap
/remote-layout watch
/remote-layout off
```

## Format examples

**code mode** — hard 28-char lines:
```
 SECTION TITLE
 ─────────────

 Terse line here.
 Another line here.

   indented item
```

**watch mode** — terse + one-tap replies:
```
 STATUS
 ──────

 key: value
 key: value

 REPLY
 ─────
 1: continue this way
 2: alternative action
 3: more detail
```

## Activation

The hook (`UserPromptSubmit`) reads `~/.claude/status-config.json` and injects
formatting instructions into Claude's context once per session. The `/remote-layout`
command sets the config value and activates the mode immediately.

Auto-detection signals (best-effort, not guaranteed):
- `CLAUDE_CODE_ENVIRONMENT_KIND=bridge` — `claude remote-control` session
- `rapportd` lsof with iPhone/iPad hostname — macOS Continuity (unreliable)

## Install

```bash
/plugin marketplace add fiale-plus/fiale-claude-plugins
/plugin install remote-layout
/remote-layout watch
```
