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

Each machine plays one of three roles:

| Role | Captures sessions | Synthesizes | Transcripts sync |
|------|:-----------------:|:-----------:|:----------------:|
| **source** | ✓ | — | Send Only → server |
| **aggregator** | — | ✓ | Receive Only ← leaves |
| **standalone** | ✓ | ✓ | — (local only) |

Run `/brain-role` on each machine to configure its role.

Each machine keeps its own independent `~/brain` vault. The server's `~/brain` is where synthesized notes land — open Obsidian there to see them. No vault sync between machines.

---

### Syncthing setup

**One Syncthing folder, one direction:**

```
Leaf machines (laptops)          Server (aggregator)
~/.claude/projects/  ──────────→  ~/brain-sources/<machine-name>/
                     Send Only      Receive Only
```

Transcripts flow **leaf → server** only. The server synthesizes and writes to its own `~/brain`. Each machine's `~/brain` stays independent.

---

#### Step 1 — Install Syncthing on every machine

**macOS:**
```bash
brew install syncthing
brew services start syncthing
```

**Linux (systemd):**
```bash
sudo apt install syncthing
systemctl --user enable --now syncthing
```

**Linux (no systemd / server):**
```bash
# Add to crontab:
@reboot syncthing --no-browser
```

#### Step 2 — Pair all machines

Do this once between each pair (leaf ↔ server):

1. On each machine open **http://127.0.0.1:8384**
2. On the server: **Actions → Show ID** — copy the Device ID
3. On the leaf: **Add Remote Device** → paste server Device ID, name it `server`
4. On the server: accept the incoming connection request from the leaf, name it (e.g. `macbook`)

Repeat for every leaf.

#### Step 3 — Share transcripts (leaf → server, one folder per leaf)

**On the leaf machine:**
1. Web UI → **Add Folder**
2. Folder Path: `~/.claude/projects`
3. Folder Label: `transcripts-<machine-name>` (e.g. `transcripts-macbook`)
4. Folder ID: `transcripts-macbook` (set manually — must be unique per leaf)
5. **Sharing** tab → tick the server device
6. **Advanced** tab → Folder Type: **Send Only**
7. Save

**On the server:**
1. A notification appears: "leaf wants to share folder transcripts-macbook"
2. Click **Add** → set local path to `~/brain-sources/macbook`
3. **Advanced** tab → Folder Type: **Receive Only**
4. Save

Repeat for each leaf, using a unique folder ID and subfolder name each time.

#### Step 4 — Configure the aggregator

Tell `/brain-role` where received transcripts live so `backfill.py` knows where to scan:

```json
{
  "vault_path": "~/brain",
  "role": "aggregator",
  "sources_path": "~/brain-sources"
}
```

The aggregator's scheduled job becomes:
```bash
# Scan all received transcript dirs and queue new ones
python3 /path/to/backfill.py ~/brain-sources --min-messages 3
# Then synthesize
claude -p "/synthesize"
```

`backfill.py` scans `~/brain-sources/*/` recursively, so new leaves are picked up automatically just by setting up their Syncthing folder.

#### Verify

```bash
# On a leaf — end a Claude Code session, then check:
ls ~/.claude/projects/ | tail -5

# On the server (after Syncthing syncs):
ls ~/brain-sources/macbook/ | tail -5   # transcripts should appear
```

---

### First-time historical backfill

If a leaf has months of accumulated sessions, use `/brain-backfill` on the server after Syncthing has finished copying the transcripts:

```bash
# Check sync progress on server
ls ~/brain-sources/macbook/ | wc -l   # count transcripts received

# Once synced, run interactive backfill:
/brain-backfill
# → choose ~/brain-sources/macbook as source
# → start with last 90 days, batch of 25
# → repeat for earlier dates
```

See `/brain-backfill` for the full guided workflow.

### Installing the plugin on a new leaf machine

```bash
git clone https://github.com/fiale-plus/fiale-claude-plugins ~/repos/fiale-plus/fiale-claude-plugins
# Register in installed_plugins.json, restart Claude Code, then:
/brain-setup   # creates local config
/brain-role    # set as source, configure Syncthing folders
```

`/brain-setup` skips creating vault files that already exist — safe to run on a machine that already has `~/brain/` from Syncthing.

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
