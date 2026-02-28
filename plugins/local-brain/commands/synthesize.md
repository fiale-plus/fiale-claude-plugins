---
description: Synthesize pending Claude Code sessions into Obsidian vault notes
---

Process all transcripts queued by the Stop hook and write structured notes to your Obsidian vault.

## Steps

1. **Read config and pending queue**

   Read `~/.claude/local-brain/config.json` and `~/.claude/local-brain/pending.json`.

   If `pending.json` is missing or empty, say "No pending sessions." and stop.

2. **For each transcript path in the queue:**

   a. Read `~/.claude/local-brain/config.json` to get `vault_path` (default: `~/brain`) and confirm it exists.

   b. Run:
      ```bash
      python3 ${CLAUDE_PLUGIN_ROOT}/bin/synthesize.py --parse-only <transcript_path>
      ```
      to extract: session_id, project_name, user_messages, session_date, message_count, first_prompt, git_branch.

      Actually: call the parse function directly via a short inline Python snippet:
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

3. **Clear the queue**

   After processing all transcripts (including skipped ones), write an empty array to `~/.claude/local-brain/pending.json`:
   ```bash
   echo '[]' > ~/.claude/local-brain/pending.json
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
