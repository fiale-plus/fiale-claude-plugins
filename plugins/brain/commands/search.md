---
name: brain-search
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

### 2. Detect Obsidian CLI

```bash
which obsidian 2>/dev/null && echo "cli-available" || echo "cli-not-found"
```

Store result as `HAS_OBSIDIAN_CLI`. Use CLI when available; fall back to grep + atoms-index otherwise.

### 3. Search personal atoms

**If `HAS_OBSIDIAN_CLI`:**
```bash
VAULT_NAME=$(basename <vault_path>)
obsidian vault="$VAULT_NAME" search query="<QUERY>" limit=20 2>/dev/null
```

If that returns results, read any matching files for full content. If the CLI errors or returns nothing, fall through to grep.

**Grep fallback (always works):**
```bash
grep -ril "<QUERY>" <vault_path>/atoms/ 2>/dev/null
```

For each matching file, read it.

**Also score via atoms-index** (fast keyword match, works regardless of CLI):
```bash
python3 -c "
import json, re
from pathlib import Path
index_path = Path.home() / '.claude/brain/atoms-index.json'
if not index_path.exists():
    exit()
index = json.loads(index_path.read_text())
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

Merge results from CLI/grep and atoms-index, deduplicate by path, sort by relevance.

### 4. Search team vault (if enabled)

Check config for `team.enabled`. If true:

**If `HAS_OBSIDIAN_CLI` and team vault is registered as an Obsidian vault:**
```bash
TEAM_VAULT_NAME=$(basename <team_vault_path>)
obsidian vault="$TEAM_VAULT_NAME" search query="<QUERY>" limit=20 2>/dev/null
```

**Grep fallback:**
```bash
grep -ril "<QUERY>" <team_vault_path>/ 2>/dev/null
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
