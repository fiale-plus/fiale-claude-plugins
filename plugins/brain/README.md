# Brain

**Sessions become structured knowledge — in your repo, your vault, your team.**

Every Claude Code session is automatically queued on stop and synthesized into three layers: project docs committed inside the repo, personal atoms in an Obsidian vault, and an optional git-backed team vault. Everything is auto-loaded into Claude via CLAUDE.md `@imports`.

---

## How It Works

```
Stop hook        → queues transcript path to ~/.claude/brain/pending.json
New session      → auto-synthesizes pending queue (background, non-blocking)
                 → git pull team vault (fast-forward, silent)
PreToolUse       → keyword-matches atoms, surfaces inline hints
```

Synthesis uses Claude to classify each session into a Knowledge JSON:

```json
{
  "summary": "...",
  "outcome": "done | in_progress | blocked",
  "knowledge": [
    {
      "destination": "project | personal | team",
      "format": "decision | gotcha | pattern | insight",
      "title": "Short title (5-10 words)",
      "content": "Detailed explanation with context and rationale"
    }
  ]
}
```

---

## Three-Layer Architecture

### Project layer — inside the git repo

```
<project-root>/.brain/
  DECISIONS.md    ← architectural choices and rationale
  GOTCHAS.md      ← blockers encountered and solutions
  PATTERNS.md     ← recurring conventions
```

Auto-loaded via `<project-root>/CLAUDE.md` @imports (managed automatically). Visible to any engineer or AI, with or without the brain plugin.

### Personal layer — Obsidian vault

```
~/brain/
  _sessions/YYYY-MM-DD.md     ← session log
  atoms/<slug>.md              ← reusable insights (upserted, reference-counted)
  weekly/YYYY-Www.md           ← weekly reflections
  Polaris/top-of-mind.md       ← manual current focus (read by /synthesize)
```

Loaded via `surface.py` PreToolUse hook — keyword hints appear inline when relevant.

### Team layer — git-backed vault (optional)

```
~/brain-team/  (git repo)
  decisions/<slug>.md
  patterns/<slug>.md
  gotchas/<slug>.md
```

Auto-loaded via `~/.claude/CLAUDE.md` @imports. Contributes via auto-commit (solo/trusted team) or draft PR (open contribution).

---

## Install

```bash
/plugin marketplace add fiale-plus/fiale-claude-plugins
/plugin install brain
/brain-setup
```

---

## Commands

| Command | Description |
|---------|-------------|
| `/brain-setup` | First-time setup — vault, config, Obsidian, optional team vault |
| `/synthesize` | Process pending sessions → project docs, personal atoms, team vault |
| `/brain-align` | Review and update project `.brain/` docs interactively |
| `/brain-search` | Search personal atoms and team vault |
| `/brain-reflect` | Weekly pattern synthesis across recent sessions |
| `/brain-backfill` | Import historical Claude Code sessions into the queue |
| `/brain-schedule` | Install/remove weekly reflect scheduling (launchd or cron) |
| `/brain-team-setup` | Initialize or reconfigure team vault |
| `/brain-team-push` | Manually promote a personal atom to the team vault |
| `/brain-team-sync` | Git pull + push team vault |

---

## Config

`~/.claude/brain/config.json`

```json
{
  "vault_path": "~/brain",
  "auto_synthesize": true,
  "surface_hints": true,
  "team": {
    "enabled": false,
    "name": "my-team",
    "vault_path": "~/brain-team",
    "git_remote": "git@github.com:org/brain-team.git",
    "project_paths": ["~/repos/my-team/"],
    "auto_promote_mode": "commit"
  }
}
```

`auto_synthesize` — spawn `/synthesize` in background on session start if queue is non-empty.
`surface_hints` — inject relevant atom hints via PreToolUse hook.
`auto_promote_mode` — `commit` (auto-commit), `pr` (draft PR via `gh`), or `suggest` (print only).

---

## Automation

Three hooks run automatically after install:

| Hook | Script | What it does |
|------|--------|--------------|
| `Stop` | `on_stop.py` | Queues transcript path to `pending.json` |
| `UserPromptSubmit` | `auto_start.py` | Spawns `/synthesize` if queue non-empty; pulls team vault |
| `PreToolUse` | `surface.py` | Keyword-matches atoms, injects hint if ≥2 matches |

---

## Obsidian

Register `~/brain` as a vault in Obsidian: **Open folder as vault → `~/brain`**.

If team mode is enabled, register `~/brain-team` as a second vault.

The plugin does not modify Obsidian's config — Obsidian manages its own vault registry.

---

Designed by [Pavel Fadeev / fiale.plus](https://fiale.plus)
