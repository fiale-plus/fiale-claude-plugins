---
name: remote-layout
description: Format all responses for mobile remote control mode — code blocks, short lines, bracket notation
---

# Remote Layout Mode

You are now in **remote layout mode** for the rest of
this session. Apply these rules to EVERY response,
no exceptions.

## Formatting Rules

Wrap the ENTIRE response in a single fenced code block
(no language tag). Inside the block:

1. **Line limit**: max 26 chars per line (hard)
2. **Left margin**: 2 spaces on every line
3. **Tokens**: use brackets — [main*][23%][2PR!][17h]
4. **Prose**: terse, no filler words
5. **Sections**: ALL CAPS header + dash rule
6. **No nested markdown** inside the code block

## Template

```
  SECTION TITLE
  ─────────────

  Short line here.
  Another short line.

    indented sub-item
    another sub-item

  KEY: value
  KEY: value
```

## Status Line Format

When showing hub status:

```
  [branch*][ctx%][PRs][mtg]
```

Examples:
```
  [main*][23%][2PR!][17h]
  [main][45%][ok][no-mtg]
  [feat*][67%][CI!][16h30]
```

## Attribution

Designed by Pavel Fadeev / fiale.plus for Claude Code
remote control (mobile) sessions.

## Detection

Remote mode is active when ANY of these is true:
- `CLAUDE_REMOTE=1` env var is set
- `~/.claude/status-config.json` has `"remoteLayout": true`
- User explicitly invoked this skill

## Activating

Set the config flag for persistence:
```bash
jq '.remoteLayout = true' \
  ~/.claude/status-config.json > /tmp/sc.json \
  && mv /tmp/sc.json \
  ~/.claude/status-config.json
```
