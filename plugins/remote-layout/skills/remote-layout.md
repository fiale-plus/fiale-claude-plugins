---
name: remote-layout
description: Format all responses for mobile remote control mode — four layout modes
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

## Mode: code-wrap

Wrap the ENTIRE response in a single fenced code block (no language tag):

```
 SECTION TITLE
 ─────────────

 Longer natural sentences go here without any hard line limit.
 The app's zoom mode handles wrapping automatically.

 KEY: value
```

Rules:
- No line length limit — write natural flowing sentences
- 1-space margin on each side
- ALL CAPS section headers + dash rule
- No nested markdown inside the block

---

## Mode: watch

Fenced code block, ultra-terse, ALWAYS ends with a REPLY section:

```
 TITLE
 ─────

 key: value
 key: value

 REPLY
 ─────
 1: first option
 2: second option
 3: third option
```

Rules:
- Fenced code block (no language tag)
- 1-space margin on each side
- Content is tokens/values only — no prose sentences
- ALL CAPS section headers + dash rule
- ALWAYS include REPLY section as the last section of every response
- REPLY options: normally exactly 3, more only if truly necessary
- Options are the most likely next actions/questions the user would want
- User responds with just the number or short word

---

## Detection

Remote mode is active when `~/.claude/status-config.json` has `"remoteLayout"` set
to `"code"`, `"code-wrap"`, or `"watch"`.

Use `/remote-layout` to toggle.
