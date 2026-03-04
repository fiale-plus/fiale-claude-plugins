---
name: brain-team-setup
description: Initialize or update team vault settings — git-backed shared knowledge vault
---

Set up or reconfigure the team knowledge vault. The team vault is a git-backed directory that holds decisions, patterns, and gotchas shared across the team.

## Steps

### 1. Read current config

```bash
cat ~/.claude/brain/config.json
```

If team is already configured, show current settings and ask:
> "Team vault already configured. What would you like to do?
> 1. Update settings
> 2. Re-clone or reinitialize vault
> 3. Disable team mode
> 4. Exit"

### 2. Team vault configuration

**Team name:**
> "Short team name (e.g. `fiale-plus`, used for identification):"

**Team vault path:**
> "Team vault path? Default: `~/brain-team`"

**Create team repo on GitHub:**

After team name is entered, suggest a naming convention and offer to create the repo:
> "For a dedicated team brain repo, the convention is:
>   `<org>/<org>-brain`   (e.g., `fiale-plus/fiale-plus-brain`)
>   `<org>/<team>-brain`  (e.g., `acme/platform-brain`)
>
> Create it now? [Y/n] (requires `gh` CLI + appropriate GitHub permissions)"

If Y and `gh` is available:
- Ask: "Repo name? (e.g., `fiale-plus/fiale-plus-brain`)" — pre-fill with `<team_name>/<team_name>-brain`
- Run: `gh repo create <name> --private --description "Team knowledge vault"`
- Use the returned clone URL as the git remote (skip the manual URL prompt below)

If N or `gh` not available:
- Continue to the manual URL prompt

**Git remote URL:**
> "Git remote URL? (blank = local-only, no remote sharing)"

Skip this prompt if the GitHub repo was just created above.

**Project paths for auto-routing:**
> "Which project paths should auto-route knowledge to team vault?
> Enter comma-separated paths (e.g. `~/repos/fiale-plus/`, `~/work/`)
> or blank to route manually only."

**Auto-promote mode:**
> "When knowledge is routed, how to save it?
> 1. commit — auto-commit immediately [default for solo/trusted team]
> 2. pr — create draft PR for review [for open contribution]
> 3. suggest — print suggestion only, don't write [manual review]"

### 3. Initialize or clone team vault

Check current state:
```bash
ls -la <team_vault_path>/.git 2>/dev/null && echo "git-repo" || echo "not-git"
```

**If remote URL provided:**

- Doesn't exist: `git clone <remote_url> <team_vault_path>`
- Exists with .git: `git -C <team_vault_path> remote set-url origin <remote_url>`
- Exists without .git: `git init <team_vault_path> && git -C <team_vault_path> remote add origin <remote_url>`

**If no remote (local-only):**
```bash
mkdir -p <team_vault_path>/{decisions,patterns,gotchas}
git init <team_vault_path>
```

Create placeholder files if missing:
```bash
touch <team_vault_path>/decisions/active.md
touch <team_vault_path>/patterns/core.md
touch <team_vault_path>/gotchas/common.md
```

Add initial commit if new repo:
```bash
cd <team_vault_path>
git add .
git commit -m "brain: initialize team vault"
```

### 4. Update ~/.claude/CLAUDE.md with @imports

Check if `~/.claude/CLAUDE.md` exists:
```bash
cat ~/.claude/CLAUDE.md 2>/dev/null
```

Upsert this block (idempotent):
```
<!-- brain-team managed -->
@<team_vault_path>/decisions/active.md
@<team_vault_path>/patterns/core.md
<!-- end brain-team managed -->
```

If `~/.claude/CLAUDE.md` doesn't exist, create it with this block.

### 5. Update config

Write updated team config:
```bash
python3 -c "
import json
from pathlib import Path
cfg_path = Path.home() / '.claude/brain/config.json'
cfg = json.loads(cfg_path.read_text()) if cfg_path.exists() else {}
cfg['team'] = {
    'enabled': True,
    'name': '<team_name>',
    'vault_path': '<team_vault_path>',
    'git_remote': '<remote_url_or_empty>',
    'project_paths': [<project_paths_list>],
    'auto_promote_mode': '<mode>'
}
cfg_path.write_text(json.dumps(cfg, indent=2))
print('Config updated')
"
```

### 6. Test team routing (optional)

If there are atoms in `~/brain/atoms/`, offer to test team routing:
> "Test team routing with a sample atom? [y/n]"

If yes, promote one high-reference-count atom as a test.

### 7. Obsidian registration

Print:
> "To view team vault in Obsidian: Open Obsidian → Open folder as vault → `<team_vault_path>`"

### 8. Summary

```
✓ Team vault configured

  Team:         <team_name>
  Vault:        <team_vault_path>
  Remote:       <remote_url or 'local-only'>
  Project paths: <paths>
  Auto-promote: <mode>
  CLAUDE.md:    ~/.claude/CLAUDE.md updated with @imports

Commands:
  /brain-team-push  — manually promote a personal atom to team vault
  /brain-team-sync  — git pull + push team vault
  /brain-align      — review project .brain/ and see team promotion candidates
```
