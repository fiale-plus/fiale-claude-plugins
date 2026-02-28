# local-brain

Auto-captures Claude Code sessions and synthesizes them into Obsidian vault notes. Zero manual steps for capture. Scheduled or on-demand synthesis. Knowledge compounds over time.

---

## What it does

```
Claude Code session ends
  → Stop hook queues the transcript path       (automatic, <100ms)
  → /synthesize processes the queue            (scheduled or manual)
      → reads transcript + top-of-mind.md
      → Claude synthesizes: summary, decisions, learnings, theme, alignment
      → writes ~/brain/_AI/sessions/YYYY-MM-DD.md
      → updates ~/brain/_AI/projects/<name>.md
  → /brain-reflect reads a week of sessions   (run weekly)
      → identifies patterns, wins, blockers
      → writes ~/brain/_AI/insights/YYYY-Www.md
      → suggests Polaris updates
```

---

## Prerequisites

- Claude Code installed
- Python 3 (`python3 --version`)
- Obsidian installed (for reading notes — not required for capture)
- `fiale-claude-plugins` cloned locally

---

## Installation (first machine)

### 1. Clone the plugin repo (if not already)

```bash
git clone https://github.com/fiale-plus/fiale-claude-plugins ~/repos/fiale-plus/fiale-claude-plugins
```

### 2. Register the plugin

Add to `~/.claude/plugins/installed_plugins.json` under `"plugins"`:

```json
"local-brain@fiale-claude-plugins": [{
  "scope": "user",
  "installPath": "/Users/you/repos/fiale-plus/fiale-claude-plugins/plugins/local-brain",
  "version": "1.0.0",
  "installedAt": "2026-01-01T00:00:00.000Z",
  "lastUpdated": "2026-01-01T00:00:00.000Z"
}]
```

### 3. Restart Claude Code

The plugin loads at session start. Restart to pick it up.

### 4. Run setup

```
/brain-setup
```

This creates the vault structure, writes `~/.claude/local-brain/config.json`, and optionally sets up scheduling.

### 5. Fill in your Polaris docs

Edit `~/brain/Polaris/top-of-mind.md` — what matters most right now. The `/synthesize` command reads this to assess each session's alignment with your goals. Keep it current.

---

## Full cycle

```
Day-to-day:
  Work in Claude Code as normal
  ↓ each session end: transcript queued automatically
  ↓ scheduled /synthesize (9am daily): notes appear in Obsidian

Weekly:
  /brain-reflect
  ↓ reads last 7 days of session notes
  ↓ writes _AI/insights/YYYY-Www.md with patterns and wins
  ↓ suggests updates to Polaris/top-of-mind.md

When starting a new project or major focus shift:
  Update Polaris/top-of-mind.md manually
  ↓ future sessions will be assessed against the new context
```

---

## Commands

| Command | What it does |
|---------|--------------|
| `/brain-setup` | First-time setup: vault structure, config, scheduling |
| `/brain-role` | Set machine role (source / aggregator / standalone), configure sync direction and scheduling |
| `/brain-schedule` | Install or remove synthesis/reflect scheduling (cron or launchd) |
| `/synthesize` | Process pending transcripts → Obsidian session notes |
| `/brain-reflect` | Weekly pattern synthesis → insight note + Polaris suggestions |
| `/brain-backfill` | Import transcripts from another machine into the queue |

---

## Config

`~/.claude/local-brain/config.json`:

```json
{
  "vault_path": "/Users/you/brain"
}
```

That's it. No API keys — `/synthesize` uses Claude's own inference.

---

## Vault structure

```
~/brain/
├── Polaris/
│   ├── top-of-mind.md      ← edit this manually, keep it current
│   └── life-razor.md       ← your decision principles
├── Logs/                   ← personal daily scratchpad (manual)
├── Commonplace/            ← atomic thought notes (manual)
├── Outputs/                ← writing to share (manual)
├── Utilities/              ← templates, images (manual)
└── _AI/                    ← written by local-brain, don't edit
    ├── sessions/
    │   └── YYYY-MM-DD.md   ← all sessions from that day
    ├── projects/
    │   └── <name>.md       ← running history per project
    └── insights/
        └── YYYY-Www.md     ← weekly reflections from /brain-reflect
```

---

## How knowledge compounds

Each mechanism builds on the previous:

**Session level** (`_AI/sessions/`): every session captured — decisions, learnings, outcome, alignment signal. Searchable in Obsidian.

**Project level** (`_AI/projects/`): each project file prepends a new entry on every session. Over months it becomes a full history of how a project evolved — what was decided, what was learned, what got stuck.

**Weekly level** (`_AI/insights/`): `/brain-reflect` reads a week of sessions and finds cross-session patterns. Recurring blockers surface. Theme distribution shows where time actually went vs where you thought it went. Durable learnings get extracted from the noise.

**Polaris feedback loop**: `/brain-reflect` suggests specific edits to `top-of-mind.md` based on what you actually worked on. When you apply them, future session alignment assessments become more accurate. The system learns your actual priorities, not your stated ones.

**The compounding effect**: after 3–4 weeks, project notes have real history. After 2–3 months, insight notes reveal multi-week patterns. After a year, you have a searchable record of every significant decision and learning across all your work.

---

## Multi-machine setup

### Machine roles

Each machine in your fleet plays one of three roles:

| Role | Captures | Synthesizes | Vault sync | Best for |
|------|:--------:|:-----------:|:----------:|---------|
| **source** | ✓ | — | Receive Only | workhorse laptops |
| **aggregator** | — | ✓ | Send & Receive | always-on desktop or server |
| **standalone** | ✓ | ✓ | Send & Receive | single-machine setup |

Run `/brain-role` on each machine to configure its role. The command sets `config.json`, configures Syncthing direction, and wires up scheduling (or removes it for source machines).

**Source machines** queue sessions silently via the Stop hook. The vault is receive-only — they read notes but never write them. The aggregator pulls their transcripts and does all synthesis.

**Aggregator** runs `/synthesize` on a schedule, rsyncs transcripts from each source machine first, writes all vault notes. Other machines get the notes via Syncthing.

**Standalone** is the simplest: one machine does everything. No rsync needed.

### Syncthing vault sync (recommended)

Install the plugin on each machine. Each machine independently captures sessions and writes to its local `~/brain/` copy. Syncthing keeps the vault identical across all machines with no cloud involvement — notes from laptop A appear on laptop B automatically.

#### Install Syncthing

**macOS:**
```bash
brew install syncthing
brew services start syncthing   # runs in background, survives reboots
```

**Linux (systemd):**
```bash
sudo apt install syncthing      # or: snap install syncthing
systemctl --user enable --now syncthing
```

**Linux (no systemd):**
```bash
syncthing &   # or add to ~/.profile / crontab @reboot
```

#### Configure the shared folder (do this once on the first machine)

1. Open the web UI: **http://127.0.0.1:8384**
2. Click **Add Folder**
3. Set **Folder Path** to `~/brain` (the full path, e.g. `/Users/pavel/brain`)
4. Give it a **Folder Label** like `brain`
5. Leave **Folder ID** as-is (auto-generated) — you'll need it when adding other devices
6. Click **Save**

#### Add each additional machine as a device

On **machine A** (already configured):
1. Web UI → **Add Remote Device**
2. Enter the **Device ID** from machine B (find it on machine B: web UI → Actions → Show ID, or run `syncthing --device-id`)
3. Give it a name (e.g. `linux-laptop`)
4. Click **Save**

On **machine B** (new machine):
1. Install and start Syncthing (see above)
2. Open web UI → a notification appears: "Device X wants to connect" → click **Add Device**
3. Another notification: "Device X wants to share folder brain" → click **Add** → set local path to `~/brain`
4. Click **Save**

Syncing starts immediately. Changes on any machine propagate to all others within seconds (when online) or on next connect (when offline).

#### Verify sync is working

```bash
# On machine A: create a test file
echo "sync test" > ~/brain/_AI/test-sync.md

# On machine B (after a few seconds):
cat ~/brain/_AI/test-sync.md   # should print "sync test"

# Clean up
rm ~/brain/_AI/test-sync.md
```

#### Conflict handling

If the same file is edited on two machines while offline, Syncthing creates a conflict copy named `filename.sync-conflict-YYYYMMDD-HHMMSS-DEVICEID.md`. Since `/synthesize` writes to daily files and uses session ID markers for idempotency, conflicts are rare — two machines would have to synthesize different sessions into the same daily file simultaneously. If a conflict file appears, open both in Obsidian, merge manually, and delete the conflict copy.

Each machine runs its own `/synthesize` schedule. No central server needed.

### Historical import (transcripts from another laptop)

If a machine has existing Claude Code sessions you want to synthesize:

**Step 1 — Copy transcripts from the source machine:**
```bash
# On the source machine
tar czf claude-sessions.tar.gz ~/.claude/projects/
scp claude-sessions.tar.gz thishost:~/.claude/local-brain/import/laptop2.tar.gz
```

**Step 2 — Extract on this machine:**
```bash
mkdir -p ~/.claude/local-brain/import/laptop2
tar xzf ~/.claude/local-brain/import/laptop2.tar.gz \
    -C ~/.claude/local-brain/import/laptop2
```

**Step 3 — Queue for synthesis:**
```bash
python3 /path/to/plugins/local-brain/scripts/backfill.py \
    ~/.claude/local-brain/import/laptop2

# Preview without modifying:
python3 scripts/backfill.py ~/.claude/local-brain/import/laptop2 --dry-run
```

**Step 4 — Synthesize:**
```
/synthesize
```

Notes land on the correct historical dates (dates come from transcript timestamps, not today).

### Installing the plugin on a second machine

```bash
# Clone the repo
git clone https://github.com/fiale-plus/fiale-claude-plugins ~/repos/fiale-plus/fiale-claude-plugins

# Register plugin in installed_plugins.json (same as step 2 of installation)
# Then restart Claude Code and run:
/brain-setup
```

If `~/brain/` is already synced via Syncthing, `/brain-setup` will detect the existing files and skip creating them — it just writes the local config.

---

## Scheduling

The `/brain-setup` command offers to configure this. Options:

**macOS launchd** (recommended — runs even without a terminal open):
```bash
# After /brain-setup writes the plist:
launchctl load ~/Library/LaunchAgents/com.local-brain.synthesize.plist
```

**cron** (Mac and Linux):
```bash
crontab -e
# Add:
0 9 * * * /path/to/claude -p "/synthesize" >> ~/.claude/local-brain/cron.log 2>&1
```

**Shell alias** (manual):
```bash
echo "alias brain-sync='claude -p \"/synthesize\"'" >> ~/.zshrc
```

---

## Logs and troubleshooting

```bash
# Check what's queued
cat ~/.claude/local-brain/pending.json

# Check synthesis log
tail -50 ~/.claude/local-brain/synthesize.log

# Check what was written today
cat ~/brain/_AI/sessions/$(date +%Y-%m-%d).md
```

**Queue has entries but /synthesize does nothing:** Run `/synthesize` in a Claude Code session (not from a plain shell).

**Sessions not being queued:** Check the Stop hook is firing — end a session and verify `pending.json` updates. The hook requires `fiale-claude-plugins` to be registered and Claude Code restarted after registration.

---

## Phase 2 (not yet built)

- **Server synthesis**: deploy `/synthesize` on an always-on server via Syncthing + cron — no local scheduling needed
- **`/brain-search`**: query the vault via natural language during a session
- **`mcp-obsidian`**: Claude reads its own brain notes mid-session for continuity
- **obsidian-git**: auto-commit vault as version history
