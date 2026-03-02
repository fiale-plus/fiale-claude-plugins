---
description: Set up Brain plugin — personal vault, auto-synthesize, surface hints, and optional team vault
---

First-time setup for the brain plugin. Run once. Covers vault creation, config, Obsidian registration, and team setup.

## Steps

### 1. Detect environment

```bash
uname -s
echo $HOME
python3 --version
which claude
```

Report OS, home directory, Python version, and claude path.

### 2. Personal vault path

Ask:
> "Where should your personal brain vault live? Default is `~/brain`. Press Enter to accept or type a path."

If they press Enter or say "default", use `~/brain`. Expand `~` to real home path. Call this `VAULT_PATH`.

### 3. Create vault structure

```bash
mkdir -p VAULT_PATH/_sessions
mkdir -p VAULT_PATH/atoms
mkdir -p VAULT_PATH/weekly
mkdir -p VAULT_PATH/Polaris
```

Create placeholder files only if they don't already exist:

**`VAULT_PATH/Polaris/top-of-mind.md`** (if missing):
```markdown
# Top of Mind

What matters most right now. The /synthesize command reads this to assess session alignment.

## Current focus


## Active projects


## What I'm trying to figure out


## What I want more of


## What I want less of

```

**`VAULT_PATH/Polaris/life-razor.md`** (if missing):
```markdown
# Life Razor

Principles I use to make decisions quickly.

## If in doubt...


## I always...


## I never...


## My barometer for a good day:

```

Report which files were created vs already existed.

### 4. Auto-synthesize on session start?

Ask:
> "Auto-synthesize pending sessions when you start a new Claude Code session? [Y/n]"

Default: yes. Store as `auto_synthesize` in config (bool).

### 5. Surface hints in session?

Ask:
> "Surface related personal atoms when you're working on relevant tasks? [Y/n]"

Default: yes. Store as `surface_hints` in config (bool).

If no, explain: "You can still run /brain-search manually to find relevant atoms."

### 6. Write config

```bash
mkdir -p ~/.claude/brain
```

Write `~/.claude/brain/config.json`:
```json
{
  "vault_path": "VAULT_PATH",
  "auto_synthesize": true,
  "surface_hints": true,
  "team": {
    "enabled": false
  }
}
```

### 7. Team mode?

Ask:
> "Set up a team knowledge vault? [y/N]"

If no: skip to step 8.

If yes, run the team setup flow:

a. **Team name:**
   > "Short team name (e.g. `fiale-plus`):"

b. **Team vault path:**
   > "Team vault path? Default: `~/brain-team`"

c. **Git remote URL:**
   > "Git remote URL for team vault? (blank = local-only, no sharing)"

d. **Project paths to auto-route:**
   > "Which project paths should auto-route knowledge to the team vault? (e.g. `~/repos/fiale-plus/`)"
   Accept comma-separated list or blank.

e. **Auto-promote mode:**
   > "When knowledge is routed to team vault, how to save it?
   > 1. commit — auto-commit immediately (solo or trusted team) [default]
   > 2. pr — create draft PR for review
   > 3. suggest — print suggestion, don't write automatically"

f. **Init or clone team repo:**

   If remote URL provided:
   ```bash
   # Check if vault path already exists
   ls ~/brain-team 2>/dev/null
   ```
   - If exists with .git: "Team vault already exists at ~/brain-team"
   - If blank dir: `git init ~/brain-team && git remote add origin <remote_url>`
   - If doesn't exist: `git clone <remote_url> ~/brain-team`

   If no remote (local-only):
   ```bash
   mkdir -p ~/brain-team/{decisions,patterns,gotchas}
   git init ~/brain-team
   ```

g. **Add @imports to ~/.claude/CLAUDE.md:**

   Check if `~/.claude/CLAUDE.md` exists:
   ```bash
   cat ~/.claude/CLAUDE.md 2>/dev/null
   ```

   Upsert this block (idempotent):
   ```
   <!-- brain-team managed -->
   @~/brain-team/decisions/active.md
   @~/brain-team/patterns/core.md
   <!-- end brain-team managed -->
   ```

   Create placeholder files if missing:
   ```bash
   touch ~/brain-team/decisions/active.md
   touch ~/brain-team/patterns/core.md
   ```

h. Update config with team settings:
   ```json
   {
     "vault_path": "VAULT_PATH",
     "auto_synthesize": true,
     "surface_hints": true,
     "team": {
       "enabled": true,
       "name": "<team_name>",
       "vault_path": "~/brain-team",
       "git_remote": "<remote_url_or_empty>",
       "project_paths": ["<path1>", "..."],
       "auto_promote_mode": "commit"
     }
   }
   ```

i. Obsidian: print instruction to register team vault:
   > "In Obsidian: Open folder as vault → `~/brain-team`"

### 8. Obsidian vault registration

On macOS, check if Obsidian is installed:
```bash
ls ~/Library/Application\ Support/obsidian/obsidian.json 2>/dev/null && echo "found" || echo "not found"
```

If found:
> "To open the vault in Obsidian: `open -a Obsidian VAULT_PATH` or open Obsidian → Open folder as vault → select `VAULT_PATH`"

On Linux:
> "In Obsidian: File → Open Folder as Vault → select `VAULT_PATH`"

Don't modify obsidian.json — Obsidian manages it.

### 9. Scheduling for /brain-reflect

Ask:
> "Schedule weekly /brain-reflect? Default: Monday 9am
> 1. launchd (macOS, recommended)
> 2. cron
> 3. Skip"

If launchd:
```bash
CLAUDE_PATH=$(which claude)
HOME_PATH=$HOME
```

Write `~/Library/LaunchAgents/com.brain.reflect.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.brain.reflect</string>
  <key>ProgramArguments</key>
  <array>
    <string>CLAUDE_PATH</string>
    <string>-p</string>
    <string>/brain-reflect</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Weekday</key><integer>1</integer>
    <key>Hour</key><integer>9</integer>
    <key>Minute</key><integer>0</integer>
  </dict>
  <key>StandardOutPath</key><string>HOME_PATH/.claude/brain/cron.log</string>
  <key>StandardErrorPath</key><string>HOME_PATH/.claude/brain/cron.log</string>
  <key>RunAtLoad</key><false/>
</dict></plist>
```

Then:
```bash
launchctl load ~/Library/LaunchAgents/com.brain.reflect.plist
```

If cron: add via `crontab -e`:
```
0 9 * * 1 CLAUDE_PATH -p "/brain-reflect" >> HOME_PATH/.claude/brain/cron.log 2>&1  # brain:reflect
```

### 10. Summary

Print:
```
✓ Brain plugin ready

  Vault:          VAULT_PATH
  Config:         ~/.claude/brain/config.json
  Auto-synthesize: yes/no
  Surface hints:  yes/no
  Team:           enabled/disabled

Next steps:
  1. Fill in VAULT_PATH/Polaris/top-of-mind.md with your current focus
  2. End a Claude Code session — the Stop hook queues it automatically
  3. New sessions will auto-run /synthesize if pending queue is non-empty
  4. Open Obsidian → Open folder as vault → VAULT_PATH

Commands:
  /synthesize     — process pending sessions now
  /brain-reflect  — weekly pattern synthesis
  /brain-align    — review and update project .brain/ docs
  /brain-search   — search atoms and team vault
  /brain-backfill — import historical sessions
  /brain-team-setup — init/update team vault settings
```
