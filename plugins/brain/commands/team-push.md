---
name: brain-team-push
description: Manually promote a personal atom or insight to the team vault
args: slug (optional — atom slug to promote)
---

Promote a personal atom from `~/brain/atoms/` to the team vault. Use this when you want to share an insight that wasn't auto-routed during synthesis.

## Steps

### 1. Read config

```bash
cat ~/.claude/brain/config.json
```

If `team.enabled` is false, say: "Team vault not configured. Run /brain-team-setup first." and stop.

### 2. Identify atom to promote

**If slug was provided as argument:** look it up directly:
```bash
cat ~/brain/atoms/<slug>.md
```

**If no argument:** list atoms by reference count and ask:
```bash
python3 -c "
import json
from pathlib import Path
index = json.loads(Path.home().joinpath('.claude/brain/atoms-index.json').read_text())
sorted_atoms = sorted(index, key=lambda x: x.get('reference_count', 1), reverse=True)
for a in sorted_atoms[:20]:
    print(f\"{a['reference_count']:3d}x  {a['slug']}\")
"
```

Ask:
> "Which atom to promote? Enter slug or number from list above:"

Read the selected atom file:
```bash
cat ~/brain/atoms/<slug>.md
```

### 3. Choose format and destination

Show the atom content. Ask:
> "Promote as:
> 1. pattern — recurring convention or approach
> 2. decision — architectural or design choice
> 3. gotcha — blocker or non-obvious solution
> [default: pattern]"

### 4. Confirm and promote

Show:
```
Promote to team vault?
  Slug:    <slug>
  Format:  <format>
  Dest:    <team_vault_path>/<format>/<slug>.md
  Mode:    <auto_promote_mode>
```

Ask: "Proceed? [y/n]"

If yes:
```bash
python3 -c "
import sys; sys.path.insert(0, '${CLAUDE_PLUGIN_ROOT}/bin')
import synthesize, json, re
from pathlib import Path

atom_path = Path.home() / 'brain/atoms/<slug>.md'
text = atom_path.read_text()
# Extract title from frontmatter
title_match = re.search(r'title:\s*(.+)', text)
title = title_match.group(1).strip() if title_match else '<slug>'
# Extract content (below frontmatter)
content = re.sub(r'^---\n.*?\n---\n', '', text, flags=re.DOTALL).strip()

config = synthesize.load_config()
synthesize.write_team_doc(
    config['team']['vault_path'],
    '<format>',
    title,
    content,
    config['team'].get('auto_promote_mode', 'commit')
)
print(f'Promoted: {config[\"team\"][\"vault_path\"]}/<format>/<slug>.md')
"
```

### 5. Report

```
✓ Promoted: <slug> → team/<format>/<slug>.md
  Mode: <commit/pr/suggest>
```

If mode was `pr`: show the PR URL if `gh pr create` succeeded.
If mode was `suggest`: show the content and remind: "Run /brain-team-sync to push when ready."
