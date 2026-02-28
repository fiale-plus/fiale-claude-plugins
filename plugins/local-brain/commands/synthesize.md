---
description: Synthesize pending Claude Code sessions into Obsidian vault notes
---

Process pending transcripts and write structured notes to your Obsidian vault. Works on any machine — standalone, leaf (source), or aggregator — as long as `pending.json` has entries.

**Batch limit**: process at most 20 sessions per run. If the queue is larger, process the first 20, then report how many remain. This prevents context exhaustion on large backlogs — run `/synthesize` again for the next batch.

## Steps

1. **Read config and pending queue**

   Read `~/.claude/local-brain/config.json` and `~/.claude/local-brain/pending.json`.

   If `pending.json` is missing or empty, say "No pending sessions." and stop.

   If the queue has more than 20 items, note: "Queue has N sessions — processing first 20. Run /synthesize again for the remainder."
   Take only the first 20 paths as the working set for this run.

2. **For each transcript path in the queue:**

   a. Read `~/.claude/local-brain/config.json` to get `vault_path` (default: `~/brain`) and confirm it exists.

   b. Extract transcript metadata via inline Python:
      ```bash
      python3 -c "
      import sys; sys.path.insert(0, '${CLAUDE_PLUGIN_ROOT}/bin')
      import synthesize, json
      sid, slug, msgs, date = synthesize.parse_transcript('<transcript_path>')
      idx = synthesize.read_sessions_index('<transcript_path>')
      print(json.dumps({
        'session_id': sid,
        'project_name': synthesize.project_name_from_slug(slug, idx.get('projectPath', '')),
        'user_messages': msgs,
        'session_date': date.isoformat(),
        'message_count': idx.get('messageCount', '?'),
        'first_prompt': idx.get('firstPrompt', ''),
        'git_branch': idx.get('gitBranch', '')
      }))
      "
      ```

   c. Check if session is already in vault (idempotency):
      ```bash
      grep -l "<!-- session:<session_id> -->" <vault_path>/_AI/sessions/*.md 2>/dev/null
      ```
      If found, skip this transcript and continue to next.

   d. Read `<vault_path>/Polaris/top-of-mind.md` if it exists.

   e. **Synthesize** — using your own reasoning, produce a JSON object:
      ```json
      {
        "summary": "1-2 sentence summary",
        "what_was_done": "concrete work description",
        "outcome": "done | in_progress | blocked",
        "decisions_made": ["..."],
        "learnings": ["..."],
        "primary_theme": "building | debugging | researching | planning | configuring",
        "energy_inferred": "high | medium | low",
        "alignment_with_polaris": "high | medium | low | off-track",
        "unexplored_thread": "optional thread worth reflecting on",
        "suggested_next": "what to do next"
      }
      ```
      Base this on: user_messages, first_prompt, project_name, git_branch, top-of-mind content.

   f. Write synthesis to a temp file, then call the vault writer:
      ```bash
      echo '<synthesis_json>' > /tmp/local-brain-synthesis.json
      python3 ${CLAUDE_PLUGIN_ROOT}/bin/synthesize.py <transcript_path> /tmp/local-brain-synthesis.json
      rm /tmp/local-brain-synthesis.json
      ```

   g. Report: "✓ `<project_name>` · <date> · <theme> · <outcome>"

3. **Clear processed items from the queue**

   Remove only the transcripts that were processed in this run (the working set of up to 20). Leave any remaining items in place:
   ```bash
   python3 -c "
   import json
   from pathlib import Path
   q = Path.home() / '.claude/local-brain/pending.json'
   processed = <list of paths processed this run as a Python list literal>
   queue = json.loads(q.read_text()) if q.exists() else []
   remaining = [p for p in queue if p not in set(processed)]
   q.write_text(json.dumps(remaining, indent=2))
   print(f'Removed {len(processed)} item(s), {len(remaining)} remain in queue')
   "
   ```

4. **Show scheduling recommendations**

   Print this at the end:

   ---
   **Scheduling options** (pick one, or run `/synthesize` manually whenever you like):

   **macOS launchd** (runs daily at 9am):
   ```xml
   <!-- ~/Library/LaunchAgents/com.local-brain.synthesize.plist -->
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0"><dict>
     <key>Label</key><string>com.local-brain.synthesize</string>
     <key>ProgramArguments</key>
     <array>
       <string>/path/to/claude</string>
       <string>-p</string>
       <string>/synthesize</string>
     </array>
     <key>StartCalendarInterval</key>
     <dict><key>Hour</key><integer>9</integer><key>Minute</key><integer>0</integer></dict>
     <key>RunAtLoad</key><false/>
   </dict></plist>
   ```
   Then: `launchctl load ~/Library/LaunchAgents/com.local-brain.synthesize.plist`

   **cron** (Linux/Mac, runs at 9am daily):
   ```
   0 9 * * * /path/to/claude -p "/synthesize" >> ~/.claude/local-brain/cron.log 2>&1
   ```

   **Shell alias** (manual, on demand):
   ```bash
   alias brain-sync='claude -p "/synthesize"'
   ```

   Replace `/path/to/claude` with the output of `which claude`.
   ---
