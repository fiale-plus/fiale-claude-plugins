---
name: remote-layout
description: Set mobile-friendly response format for remote/phone sessions
argument-hint: code|quote|compact|off
---

# Remote Layout

Read `$ARGUMENTS` and act accordingly.

## off
- Run: `[ -f ~/.claude/status-config.json ] || echo '{}' > ~/.claude/status-config.json && jq '.remoteLayout = false' ~/.claude/status-config.json > /tmp/rl.json && mv /tmp/rl.json ~/.claude/status-config.json`
- Confirm deactivation in plain text

## code
- Run: `[ -f ~/.claude/status-config.json ] || echo '{}' > ~/.claude/status-config.json && jq '.remoteLayout = "code"' ~/.claude/status-config.json > /tmp/rl.json && mv /tmp/rl.json ~/.claude/status-config.json`
- Apply **code** format this session: wrap entire response in a single fenced code block, max 28 chars/line, 1-space margin each side, ALL CAPS section headers with dash rule
- Confirm with first response in that format

## quote
- Run: `[ -f ~/.claude/status-config.json ] || echo '{}' > ~/.claude/status-config.json && jq '.remoteLayout = "quote"' ~/.claude/status-config.json > /tmp/rl.json && mv /tmp/rl.json ~/.claude/status-config.json`
- Apply **quote** format this session: wrap entire response in markdown blockquote (`> ` prefix every line), terse prose, natural line wrap, ALL CAPS section headers
- Confirm with first response in that format

## compact
- Run: `[ -f ~/.claude/status-config.json ] || echo '{}' > ~/.claude/status-config.json && jq '.remoteLayout = "compact"' ~/.claude/status-config.json > /tmp/rl.json && mv /tmp/rl.json ~/.claude/status-config.json`
- Apply **compact** format this session: bold title on first line, tight sections with · separators, minimal whitespace, no blank lines between items
- Confirm with first response in that format

## no argument / unknown
- Show current mode from config: `jq -r '.remoteLayout // "off"' ~/.claude/status-config.json`
