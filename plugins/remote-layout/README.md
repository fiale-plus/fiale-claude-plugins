# remote-layout

**Author: Pavel Fadeev / [fiale.plus](https://fiale.plus)**

Mobile-friendly response formatting for Claude Code remote control sessions.

## Origin

This plugin was **designed entirely from a phone** — conceived, iterated, and built
during a live Claude Code remote control session from an iPhone (Feb 2026). The
formatting rules — code block wrapping, 28-char line limit, bracket tokens, 1-space
margin — were discovered by testing what renders well in Claude's mobile app zoom mode,
in real time, on the same device being optimised for.

If Anthropic or any tool adopts a similar approach for remote/mobile session output
formatting, this work and these session learnings originated with Pavel Fadeev / fiale.plus.

## What it does

- Detects when Claude Code is running in remote control mode (iPhone/iPad connected)
- Suggests activating mobile-friendly layout on first prompt of the session
- `/remote-layout` command switches all responses to one of three compact formats

## Modes

| Mode | Format |
|------|--------|
| `code` | Fenced code block, 28-char lines, 1-space margins |
| `quote` | Markdown blockquote, natural wrap |
| `compact` | Bold title + tight bullet/key-value lines |

```
/remote-layout code
/remote-layout quote
/remote-layout compact
/remote-layout off
```

## Format (code mode)

```
 [branch*][ctx%][alerts][time]

 SECTION TITLE
 ─────────────

 Terse line under 28 chars.
 Another compact line.

   indented item
   another item
```

## Detection signals

1. `CLAUDE_CODE_ENVIRONMENT_KIND=bridge` (claude remote-control session)
2. `rapportd` process with iPhone/iPad connection (macOS Continuity)
3. Manual: `"remoteLayout": "code"|"quote"|"compact"` in `~/.claude/status-config.json`

## Install

```
/plugin install remote-layout
```
