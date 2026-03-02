---
description: Synthesize pending Claude Code sessions into structured knowledge — project docs, personal atoms, team vault
---

Process pending transcripts, classify insights, and route them to the right layer: project `.brain/` docs, personal `~/brain/atoms/`, and optional team vault.

**Batch limit**: process at most 20 sessions per run. If the queue is larger, process the first 20, then report how many remain.

## Steps

### 1. Read config and pending queue

```bash
cat ~/.claude/brain/config.json
cat ~/.claude/brain/pending.json
```

If `pending.json` is missing or empty, say "No pending sessions." and stop.

If the queue has more than 20 items: "Queue has N sessions — processing first 20. Run /synthesize again for the remainder."
Take only the first 20 paths as the working set.

### 2. For each transcript path in the queue

**a. Extract transcript metadata:**
```bash
python3 -c "
import sys; sys.path.insert(0, '${CLAUDE_PLUGIN_ROOT}/bin')
import synthesize, json
sid, slug, msgs, date = synthesize.parse_transcript('<transcript_path>')
idx = synthesize.read_sessions_index('<transcript_path>')
print(json.dumps({
  'session_id': sid,
  'project_name': synthesize.project_name_from_slug(slug, idx.get('projectPath', '')),
  'project_path': idx.get('projectPath', ''),
  'user_messages': msgs,
  'session_date': date.isoformat(),
  'message_count': idx.get('messageCount', '?'),
  'first_prompt': idx.get('firstPrompt', ''),
  'git_branch': idx.get('gitBranch', '')
}))
"
```

**b. Check idempotency** — skip if already processed:
```bash
grep -rl "<!-- session:<session_id> -->" ~/brain/_sessions/ 2>/dev/null
```
If found, skip this transcript.

**c. Read Polaris context** (if vault configured):
```bash
cat ~/brain/Polaris/top-of-mind.md 2>/dev/null
```

**d. Synthesize** — produce a Knowledge JSON object based on user_messages, first_prompt, project_name, git_branch, and top-of-mind content:

```json
{
  "summary": "1-2 sentence summary of what happened",
  "outcome": "done | in_progress | blocked",
  "suggested_next": "what to do next",
  "primary_theme": "building | debugging | researching | planning | configuring",
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

**Routing guidance:**
- `project` + `decision`: architectural choices that future contributors should know
- `project` + `gotcha`: blockers and their solutions, environment-specific issues
- `project` + `pattern`: recurring conventions established in this project
- `personal` + `insight`: reusable lessons applicable across projects
- `team` + any format: knowledge worth sharing with the team (only if team paths match)

Produce 1-4 knowledge items. Skip sessions where nothing substantive was learned.

**e. Write synthesis to temp file and call vault writer:**
```bash
echo '<knowledge_json>' > /tmp/brain-synthesis.json
python3 ${CLAUDE_PLUGIN_ROOT}/bin/synthesize.py <transcript_path> /tmp/brain-synthesis.json
rm /tmp/brain-synthesis.json
```

**f. Report:** "✓ `<project_name>` · <date> · <theme> · <outcome>"

### 3. Update last_synthesis_at in config

```bash
python3 -c "
import json
from pathlib import Path
from datetime import datetime
cfg_path = Path.home() / '.claude/brain/config.json'
cfg = json.loads(cfg_path.read_text()) if cfg_path.exists() else {}
cfg['last_synthesis_at'] = datetime.now().isoformat()
cfg_path.write_text(json.dumps(cfg, indent=2))
"
```

### 4. Clear processed items from queue

```bash
python3 -c "
import json
from pathlib import Path
q = Path.home() / '.claude/brain/pending.json'
processed = <list of paths processed this run as a Python list literal>
queue = json.loads(q.read_text()) if q.exists() else []
remaining = [p for p in queue if p not in set(processed)]
q.write_text(json.dumps(remaining, indent=2))
print(f'Removed {len(processed)} item(s), {len(remaining)} remain in queue')
"
```

### 5. Summary report

Show:
- Count of sessions processed and their project names
- Knowledge items written per layer (project / personal / team)
- Any project CLAUDE.md files updated with @imports
- If queue still has items: "N sessions remain — run /synthesize again"
