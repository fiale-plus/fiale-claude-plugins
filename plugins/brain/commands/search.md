---
description: Search personal atoms and team vault for relevant knowledge
args: query (optional — keyword or phrase to search)
---

Search across personal atoms (`~/brain/atoms/`) and team vault (`~/brain-team/`) for relevant knowledge. Results are labeled by layer.

## Steps

### 1. Read config and query

```bash
cat ~/.claude/brain/config.json
```

If no query was provided as argument, ask:
> "What are you looking for? Enter keywords or a phrase:"

Call this `QUERY`.

### 2. Search personal atoms

**Option A — using obsidian-cli if available:**
```bash
which obsidian-cli 2>/dev/null && obsidian-cli search --vault ~/brain/atoms "<QUERY>" 2>/dev/null
```

**Option B — grep fallback (always works):**
```bash
grep -rl "<QUERY>" ~/brain/atoms/ 2>/dev/null
```

For each matching file, read it:
```bash
cat <atom_path>
```

Also check atoms-index for keyword matches:
```bash
python3 -c "
import json, re
from pathlib import Path
index = json.loads(Path.home().joinpath('.claude/brain/atoms-index.json').read_text())
query_words = set(re.findall(r'[a-z][a-z0-9_-]{2,}', '<QUERY>'.lower()))
results = []
for atom in index:
    score = len(query_words & set(atom['keywords']))
    if score >= 1:
        results.append((score, atom['slug'], atom['path'], atom.get('reference_count', 1)))
results.sort(reverse=True)
for score, slug, path, rc in results[:10]:
    print(f'{score:3d} matches  [{rc}x referenced]  {slug}  {path}')
"
```

### 3. Search team vault (if enabled)

Check config for `team.enabled`. If true:
```bash
grep -rl "<QUERY>" ~/brain-team/ 2>/dev/null
```

For each matching file, read it.

### 4. Search project .brain/ docs (if in a git repo)

```bash
git rev-parse --show-toplevel 2>/dev/null
```

If in a git repo:
```bash
grep -rl "<QUERY>" <project_root>/.brain/ 2>/dev/null
```

### 5. Present results

Show results grouped by layer:

```
━━ [Personal] ━━━━━━━━━━━━━━━━━━━━━━
<slug> (referenced N times)
<content>

━━ [Team] ━━━━━━━━━━━━━━━━━━━━━━━━━
<filename>
<content>

━━ [Project] ━━━━━━━━━━━━━━━━━━━━━━
<filename>
<content>
```

If no results in a layer, skip that section.

If no results at all: "No matches found for '<QUERY>'. Try broader keywords or run /brain-align to populate .brain/ docs."

### 6. Offer to create atom (if nothing useful found)

If personal layer has no results:
> "No personal atoms match this query. Create one now? [y/n]"

If yes:
- Ask for title and content
- Write atom:
  ```bash
  python3 -c "
  import sys; sys.path.insert(0, '${CLAUDE_PLUGIN_ROOT}/bin')
  import synthesize
  from datetime import datetime
  synthesize.upsert_atom(
      '<vault_path>',
      '<title>',
      '<content>',
      ['manual'],
      'search-manual',
      datetime.now()
  )
  synthesize.build_atoms_index('<vault_path>')
  "
  ```
- Report: "Atom created: ~/brain/atoms/<slug>.md"
