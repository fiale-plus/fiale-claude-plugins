# vibes

Sentiment-driven musical phrases on Claude Code events — triumphant on success, contemplative when waiting.

## What it does

`vibes` hooks into Claude Code's `Stop` and `Notification` events and plays a short musical phrase synthesized in real time. The phrase reflects the emotional tone of your session:

| Mood | Trigger | Feel |
|------|---------|------|
| **Triumphant** | Session ends with success keywords | Rising fanfare |
| **Oops** | Session ends with error keywords | Gentle descending phrase |
| **Contemplative** | Notification / waiting for input | Unresolved, curious |
| **Neutral** | Session ends without strong signal | Balanced, settled |

Each mood has 3–4 distinct phrase variants picked at random, so it never gets repetitive.

## Mood detection

On `Stop`, the last 4 000 characters of the session transcript are scanned:

- **Oops** if `error / failed / traceback / exception / cannot` appear > 3 times
- **Triumphant** if `complete / success / passed / done / implemented / fixed` appear > 2 times
- **Neutral** otherwise

On `Notification`, mood is always **contemplative**.

## Synthesis

Pure Python — no external audio libraries required. Each note is:

```
signal = sin(2π·f·t)          # fundamental
       + 0.5·sin(2π·2f·t)     # octave
       + 0.25·sin(2π·1.5f·t)  # perfect 5th
```

with an exponential decay envelope and gentle legato overlap between notes. Output is a 16-bit mono 44.1 kHz WAV played via `afplay` (macOS built-in) in a non-blocking subprocess — Claude is never delayed.

## Requirements

- macOS (uses `afplay`)
- Python 3 (standard library only: `json`, `math`, `struct`, `subprocess`, `sys`, `tempfile`, `wave`)

## Installation

```bash
/plugin install vibes
```

## Verification

```bash
# Neutral mood (no transcript signal)
echo '{"hook_event_name":"Stop","transcript_path":"/dev/null","session_id":"test"}' \
  | python3 ~/.claude/plugins/vibes/hooks/sound_hook.py

# Contemplative mood
echo '{"hook_event_name":"Notification","session_id":"test"}' \
  | python3 ~/.claude/plugins/vibes/hooks/sound_hook.py
```

## File layout

```
plugins/vibes/
├── .claude-plugin/
│   └── plugin.json
├── hooks/
│   ├── hooks.json
│   └── sound_hook.py
└── README.md
```
