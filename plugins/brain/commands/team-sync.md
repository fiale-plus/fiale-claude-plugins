---
name: brain-team-sync
description: Sync team vault — git pull latest changes and optionally push local commits
---

Pull latest changes from the team vault remote, and optionally push any local commits.

## Steps

### 1. Read config

```bash
cat ~/.claude/brain/config.json
```

If `team.enabled` is false, say: "Team vault not configured. Run /brain-team-setup first." and stop.

Get `team.vault_path` and `team.git_remote`.

If `git_remote` is empty, say: "Team vault is local-only — no remote to sync with. To add a remote: /brain-team-setup." and stop.

### 2. Check git status

```bash
git -C <team_vault_path> status --short
git -C <team_vault_path> log --oneline origin/main..HEAD 2>/dev/null | head -5
```

Show current state:
- Any uncommitted changes
- Any local commits not yet pushed

### 3. Pull latest

```bash
git -C <team_vault_path> pull --ff-only origin main
```

If `--ff-only` fails (diverged history):
```bash
git -C <team_vault_path> fetch origin
git -C <team_vault_path> log --oneline HEAD..origin/main | head -10
```

Show what would be merged and ask:
> "Remote has diverged. Use rebase? [y/n]"

If yes: `git -C <team_vault_path> pull --rebase origin main`
If no: show manual resolution instructions.

### 4. Show what's new

After pull, list recently changed files:
```bash
git -C <team_vault_path> log --oneline --name-only -10
```

Show new/changed knowledge items with a brief summary.

### 5. Push local commits (if any)

If there are local commits not yet on remote:
> "Push N local commit(s) to remote? [y/n]"

If yes:
```bash
git -C <team_vault_path> push origin main
```

### 6. Report

```
✓ Team vault synced
  Pulled: <N new commits> from remote
  Pushed: <N commits | nothing to push>
  Vault:  <team_vault_path>
  Remote: <git_remote>
```
