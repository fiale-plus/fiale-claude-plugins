---
name: remote-layout
description: Set mobile-friendly response format for remote/phone sessions
argument-hint: code|code-wrap|watch|off
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

## code-wrap
- Run: `[ -f ~/.claude/status-config.json ] || echo '{}' > ~/.claude/status-config.json && jq '.remoteLayout = "code-wrap"' ~/.claude/status-config.json > /tmp/rl.json && mv /tmp/rl.json ~/.claude/status-config.json`
- Apply **code-wrap** format this session: wrap entire response in a single fenced code block, no line limit (relies on zoom-mode autowrap), ALL CAPS section headers with dash rule
- Confirm with first response in that format

## watch
- Run: `[ -f ~/.claude/status-config.json ] || echo '{}' > ~/.claude/status-config.json && jq '.remoteLayout = "watch"' ~/.claude/status-config.json > /tmp/rl.json && mv /tmp/rl.json ~/.claude/status-config.json`
- Apply **watch** format this session: fenced code block, ultra-terse content (tokens/values only, no prose), ALWAYS end every response with a REPLY section offering 1-3 numbered continuations (more only if truly necessary)
- Confirm with first response in that format

## no argument / unknown
- Show current mode from config: `jq -r '.remoteLayout // "off"' ~/.claude/status-config.json`
