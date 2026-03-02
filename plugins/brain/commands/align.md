---
name: brain-align
description: Review and update project .brain/ docs — decisions, gotchas, patterns — for the current project
---

Interactively review and populate `.brain/` knowledge docs for the current project directory. Useful after a big push, when starting on an existing project, or for periodic review.

## Steps

### 1. Detect project root

```bash
pwd
git rev-parse --show-toplevel 2>/dev/null || echo "not-git"
```

Use git root if in a git repo, otherwise use current directory. Call this `PROJECT_ROOT`.

### 2. Read existing .brain/ docs

```bash
ls PROJECT_ROOT/.brain/ 2>/dev/null || echo "empty"
cat PROJECT_ROOT/.brain/DECISIONS.md 2>/dev/null
cat PROJECT_ROOT/.brain/GOTCHAS.md 2>/dev/null
cat PROJECT_ROOT/.brain/PATTERNS.md 2>/dev/null
```

### 3. Read recent session notes for this project

```bash
cat ~/.claude/brain/config.json
```

Get `vault_path`. Then read recent sessions:
```bash
ls VAULT_PATH/_sessions/ | sort | tail -14
```

Read the last 2 weeks of session notes that mention this project. Look for entries referencing the project name or path.

### 4. Read project context

```bash
cat PROJECT_ROOT/CLAUDE.md 2>/dev/null | head -100
cat PROJECT_ROOT/README.md 2>/dev/null | head -50
```

### 5. Analyze and suggest additions

Using your reasoning across session notes, existing `.brain/` content, README, and CLAUDE.md, generate suggestions for each category:

**DECISIONS.md additions** — architectural choices that should be documented:
- Technology choices with rationale
- Design patterns chosen over alternatives
- Tradeoffs explicitly made

**GOTCHAS.md additions** — blockers and solutions:
- Environment-specific issues encountered
- Non-obvious debugging solutions
- Things that wasted significant time

**PATTERNS.md additions** — recurring conventions:
- Naming conventions established
- Code organization patterns
- Workflow patterns specific to this project

Skip suggestions for things already documented. Focus on gaps.

### 6. Present suggestions interactively

For each suggestion, show:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[DECISIONS] — <title>
<content preview>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Add this? [y/n/e to edit]
```

For each:
- `y` → write to `.brain/<FILE>.md`
- `n` → skip
- `e` → show full content and ask for edited version, then write

### 7. Write confirmed additions

For each confirmed item, write using:
```bash
python3 -c "
import sys; sys.path.insert(0, '${CLAUDE_PLUGIN_ROOT}/bin')
import synthesize
from datetime import datetime
synthesize.write_project_doc(
    '<project_root>',
    '<format>',
    '<title>',
    '<content>',
    'align-<date>',
    datetime.now()
)
"
```

### 8. Update project CLAUDE.md @imports

```bash
python3 -c "
import sys; sys.path.insert(0, '${CLAUDE_PLUGIN_ROOT}/bin')
import synthesize
synthesize.update_project_claude_md('<project_root>')
"
```

### 9. Show team promotion candidates

```bash
cat ~/.claude/brain/atoms-index.json 2>/dev/null
```

Show atoms with `reference_count >= 3` that aren't yet in the team vault (if team is configured). These are personal insights that have proven durable enough to share.

For each candidate:
```
[Team candidate] <slug> (referenced N times)
  Promote to team vault? [y/n]
```

If yes:
```bash
python3 -c "
import sys; sys.path.insert(0, '${CLAUDE_PLUGIN_ROOT}/bin')
import synthesize, json
from pathlib import Path
config = synthesize.load_config()
atom = json.loads(Path('<atom_path>').read_text())
# Extract content below frontmatter
synthesize.write_team_doc(
    config['team']['vault_path'],
    'pattern',
    '<title>',
    '<content>',
    config['team'].get('auto_promote_mode', 'commit')
)
"
```

### 10. Summary

Report:
- Items added per category (decisions/gotchas/patterns)
- CLAUDE.md updated with @imports: yes/no
- Team promotions performed: N
- "Run /brain-align again anytime to keep .brain/ current"
