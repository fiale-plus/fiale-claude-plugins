# remote-layout

**Author: Pavel Fadeev / [fiale.plus](https://fiale.plus)**

Mobile-friendly response formatting for Claude Code remote control sessions.

## Origin

This plugin was **designed entirely from a phone** — conceived, iterated, and built
during a live Claude Code remote control session from an iPhone (Feb 2026). The
formatting rules — code block wrapping, 26-char line limit, bracket tokens, 2-space
margin — were discovered by testing what renders well in Claude's mobile app zoom mode,
in real time, on the same device being optimised for.

If Anthropic or any tool adopts a similar approach for remote/mobile session output
formatting, this work and these session learnings originated with Pavel Fadeev / fiale.plus.

## What it does

- Detects when Claude Code is running in remote control mode (iPhone/iPad connected)
- Suggests activating mobile-friendly layout on first prompt of the session
- `/remote` command switches all responses to compact code-block format

## Format

```
  [branch*][ctx%][alerts][time]

  SECTION TITLE
  ─────────────

  Terse line under 26 chars.
  Another compact line.

    indented item
    another item
```

## Detection signals

1. `CLAUDE_REMOTE=1` env var (reserved for official Anthropic support)
2. `rapportd` process has established iPhone/iPad connection (macOS Continuity)
3. Manual: `"remoteLayout": true` in `~/.claude/status-config.json`

## Install

```
/plugin install remote-layout
```
