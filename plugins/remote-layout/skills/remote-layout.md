---
name: remote-layout
description: Format all responses for mobile remote control mode — three layout modes
---

# Remote Layout Mode

Apply the active mode to EVERY response this session, no exceptions.
Check mode from config or from the hook instruction injected at session start.

---

## Mode: code

Wrap the ENTIRE response in a single fenced code block (no language tag):

```
  SECTION TITLE
  ─────────────

  Short line here.
  Another short line.

    indented sub-item

  KEY: value
```

Rules:
- Max 28 chars per line (hard limit)
- 1-space margin on each side
- ALL CAPS section headers + dash rule
- No nested markdown inside the block

---

## Mode: quote

Wrap the ENTIRE response in markdown blockquotes (`> ` prefix every line):

> SECTION TITLE
> ─────────────
>
> Text wraps naturally here,
> no hard line limit.
>
> KEY: value

Rules:
- Every line starts with `> `
- ALL CAPS section headers
- Terse prose, no filler words
- Natural line wrap (no 28-char limit)

---

## Mode: compact

Bold title on the first line, then tight sections:

**TITLE**
• item one · detail
• item two · detail
KEY: value · KEY: value

Rules:
- First line: `**TITLE**`
- Sections separated by `·` inline or `•` bullets
- No blank lines between items
- Minimal whitespace throughout

---

## Detection

Remote mode is active when `~/.claude/status-config.json` has `"remoteLayout"` set
to `"code"`, `"quote"`, or `"compact"`.

Use `/remote-layout` to toggle.
