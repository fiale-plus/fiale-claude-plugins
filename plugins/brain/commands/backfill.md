---
name: brain-backfill
description: Import and queue historical Claude Code sessions for synthesis
args: options (optional — passed to backfill.py)
---

Queue historical Claude Code transcripts from this or another machine for synthesis. Runs backfill.py which scans for `.jsonl` files and filters by date, length, and already-processed status.

## Usage

- `/brain-backfill` — queue from default `~/.claude/projects/`, last 30 days, max 50
- `/brain-backfill --stats` — show statistics without modifying the queue
- `/brain-backfill --since 2026-01-01 --limit 50` — queue specific date range
- `/brain-backfill --dry-run` — show what would be queued

## Steps

### 1. Check config

```bash
cat ~/.claude/brain/config.json
```

Confirm vault_path exists.

### 2. Run with no arguments (default)

If no arguments were given, run stats first then prompt:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/bin/backfill.py ~/.claude/projects --stats
```

Show the output. Then ask:
> "Queue transcripts from how many days back? Default: 30. Enter a number or 'all'."

And:
> "Max transcripts to queue per run? Default: 50."

Then run:
```bash
python3 ${CLAUDE_PLUGIN_ROOT}/bin/backfill.py ~/.claude/projects --since <SINCE_DATE> --limit <LIMIT>
```

### 3. Run with explicit arguments

If arguments were provided (e.g. `--since 2026-01-01 --stats`), pass them directly:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/bin/backfill.py <ARGS>
```

Show the complete output.

### 4. After queuing

If transcripts were queued, report:
- How many were queued and their date range
- How many remain in queue total
- "Run /synthesize to process them, or they will be auto-processed on your next session start."

### Importing from another machine

To import transcripts from another machine:

**On the source machine:**
```bash
tar czf claude-sessions.tar.gz ~/.claude/projects/
scp claude-sessions.tar.gz thishost:~/.claude/brain/import/laptop2.tar.gz
```

**On this machine:**
```bash
mkdir -p ~/.claude/brain/import/laptop2
tar xzf ~/.claude/brain/import/laptop2.tar.gz -C ~/.claude/brain/import/laptop2
```

Then:
```bash
python3 ${CLAUDE_PLUGIN_ROOT}/bin/backfill.py ~/.claude/brain/import/laptop2 --stats
python3 ${CLAUDE_PLUGIN_ROOT}/bin/backfill.py ~/.claude/brain/import/laptop2 --since 2026-01-01 --limit 50
```

Run `/synthesize` between batches for large archives.
