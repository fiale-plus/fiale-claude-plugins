---
description: Import and queue historical Claude Code sessions from this or another machine for synthesis
---

Guides you through importing a large backlog of existing transcripts. Designed for first-time setup when you have months or years of accumulated sessions.

## The strategy for large archives

Don't queue everything at once. `/synthesize` runs in a single Claude session — too many transcripts will hit context limits or time out. Instead:

1. **Scan first** — see what you have and how much is eligible
2. **Start recent** — queue the last 30–90 days first (most relevant, fewest sessions)
3. **Run `/synthesize`** — process that batch
4. **Go back further** — repeat with earlier date ranges
5. **Skip the ancient stuff** — sessions from 2+ years ago may not be worth synthesizing. Use `--min-messages` to filter noise.

---

## Steps

### 1. Locate the transcripts

Ask the user:
> "Where are the transcripts?
> 1. This machine (`~/.claude/projects/` — synthesize sessions already captured here)
> 2. Imported from another machine (e.g. `~/.claude/local-brain/import/laptop2/`)"

If another machine, ask for the import directory path. Remind them to copy first if they haven't:
```bash
# On the source machine:
tar czf claude-sessions.tar.gz ~/.claude/projects/
scp claude-sessions.tar.gz <thishost>:~/.claude/local-brain/import/<name>.tar.gz

# On this machine:
mkdir -p ~/.claude/local-brain/import/<name>
tar xzf ~/.claude/local-brain/import/<name>.tar.gz -C ~/.claude/local-brain/import/<name>
```

Call the resolved path `IMPORT_DIR`.

### 2. Show statistics

Run:
```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/backfill.py IMPORT_DIR --stats
```

Show the output. It will display:
- Distribution by month
- Already synthesized / queued count
- Too-short sessions count (below min-messages threshold)
- Total eligible sessions

Based on the stats, recommend a strategy:
- **< 50 eligible**: queue all at once — `--limit 50`
- **50–200 eligible**: batch by month or quarter — start with last 60 days
- **> 200 eligible**: start with last 30 days, work backwards one month at a time

### 3. Ask for scope

> "How far back do you want to go?
> 1. Last 30 days
> 2. Last 90 days
> 3. Last 6 months
> 4. Last year
> 5. Everything
> 6. Custom date range (enter YYYY-MM-DD)"

Calculate the `--since` date from their choice. If "Everything", omit `--since`.

### 4. Ask for batch size

> "How many sessions per batch? Recommended: 20–30 for large archives. More is fine for smaller ones."

Default: 25 if > 100 eligible, else queue all eligible.

### 5. Dry run preview

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/backfill.py IMPORT_DIR \
    --since SINCE_DATE \
    --limit BATCH_SIZE \
    --min-messages 3 \
    --dry-run
```

Show the output. Ask:
> "Queue these N sessions? (Y/n)"

### 6. Queue the batch

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/backfill.py IMPORT_DIR \
    --since SINCE_DATE \
    --limit BATCH_SIZE \
    --min-messages 3
```

### 7. Synthesize

Tell the user:
> "Queued N sessions. Running /synthesize now to process them..."

Then run `/synthesize` (follow that command's steps fully).

### 8. Offer to continue

After `/synthesize` completes, check if more remain:
```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/backfill.py IMPORT_DIR \
    --since SINCE_DATE \
    --limit 1 \
    --dry-run 2>&1 | grep "Eligible:"
```

If eligible count > 0:
> "N more sessions remain in this date range. Queue the next batch? (Y/n)"

If yes, go back to step 4. If no:
> "Done for now. To go further back, run /brain-backfill again and choose an earlier date range."

### 9. Final summary

```
✓ Backfill complete for this batch:
  Processed: N sessions
  Date range: YYYY-MM-DD → YYYY-MM-DD
  Source: IMPORT_DIR
  Notes written to: ~/brain/_AI/sessions/ and ~/brain/_AI/projects/

To process more historical sessions: /brain-backfill
To see patterns across what was imported: /brain-reflect
```
