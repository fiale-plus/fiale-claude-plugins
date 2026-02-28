---
description: Set this machine's role — source (capture only), aggregator (synthesis), or standalone (both)
---

Configure what this machine does in the local-brain pipeline. Run once per machine, or re-run to change role.

## Roles

| Role | Captures sessions | Synthesizes | Transcripts sync |
|------|:-----------------:|:-----------:|:----------------:|
| **source** | ✓ | — | Send Only → server |
| **aggregator** | — | ✓ | Receive Only ← leaves |
| **standalone** | ✓ | ✓ | — (local only) |

**Source**: a workhorse laptop. Sessions queue via Stop hook. Transcripts sync to the aggregator via Syncthing. No synthesis runs here. Each machine keeps its own independent `~/brain` — synthesized notes live on the server only.

**Aggregator**: an always-on machine (server/desktop). Receives transcripts from all leaves, synthesizes them, writes to its own `~/brain`. Open Obsidian on the server to see the notes.

**Standalone**: single machine does everything. No transcript sync needed.

---

## Steps

### 1. Read current config

```bash
cat ~/.claude/local-brain/config.json 2>/dev/null || echo "{}"
```

Show current role if set.

### 2. Ask for role

> "What role should this machine play?
> 1. **source** — capture sessions only, transcripts sync to aggregator
> 2. **aggregator** — receive transcripts from leaves, synthesize, write vault
> 3. **standalone** — capture and synthesize on this machine"

### 3. Apply role

---

#### If **source**:

Ask for a short machine name (used as folder label in Syncthing, e.g. `macbook`, `linux-laptop1`).

Update config:
```json
{
  "vault_path": "<existing vault_path>",
  "role": "source",
  "machine_name": "<name>"
}
```

Remove any existing synthesis scheduling:
```bash
crontab -l 2>/dev/null | grep -q "local-brain:" && echo "found" || echo "none"
```
If found, ask: "Remove existing synthesis scheduling from this machine? (Y/n)" — if yes, run remove-all logic from `/brain-schedule`.

**Print Syncthing setup instructions for source:**

```
One Syncthing folder to configure on this machine:

━━━ Transcripts (this machine → server) ━━━

On THIS machine (http://127.0.0.1:8384):
  Add Folder:
    Path:        ~/.claude/projects
    Label:       transcripts-<machine_name>
    Folder ID:   transcripts-<machine_name>   ← set manually, must be unique
    Sharing:     tick the server device
    Advanced → Folder Type: Send Only

On the SERVER (accept the share request):
    Local path:  ~/brain-sources/<machine_name>
    Advanced → Folder Type: Receive Only
```

**Summary:**
```
✓ Role: source
  Machine name: <name>
  Sessions queued via Stop hook → ~/.claude/local-brain/pending.json
  Transcripts sync: ~/.claude/projects → server:~/brain-sources/<name>/ (Send Only)
  ~/brain on this machine: your personal vault (Polaris, manual notes) — untouched
  Synthesized session notes live on the server's ~/brain only.
  No local synthesis or scheduling.
```

---

#### If **aggregator**:

Ask: "Where will received transcripts be stored? Default: ~/brain-sources"

Update config:
```json
{
  "vault_path": "<existing vault_path>",
  "role": "aggregator",
  "sources_path": "<sources_path>"
}
```

Create the sources directory:
```bash
mkdir -p <sources_path>
```

**Print Syncthing setup instructions for aggregator:**

```
One Syncthing folder per leaf to accept on this machine:

━━━ Transcripts (leaves → this machine) ━━━

For each leaf, the leaf creates its own Syncthing folder. On THIS machine:
  When you get a share request for "transcripts-<machine_name>":
    Accept → Local path: <sources_path>/<machine_name>
    Advanced → Folder Type: Receive Only

Run /brain-role on each leaf to generate the correct share request.
Each leaf's transcripts land in a separate subdir — no conflicts possible.
```

Tell the user to run `/brain-schedule` to set up synthesis scheduling.

**Summary:**
```
✓ Role: aggregator
  Received transcripts: <sources_path>/<machine-name>/  (one dir per leaf)
  Vault: ~/brain → all leaves via Syncthing (Send & Receive)
  Next: run /brain-schedule to set up synthesis cron
  Synthesis will scan <sources_path>/ for new transcripts automatically.
```

---

#### If **standalone**:

Update config:
```json
{
  "vault_path": "<existing vault_path>",
  "role": "standalone"
}
```

Tell the user: "Vault sync is Send & Receive (the Syncthing default) — no special config needed."

Tell the user to run `/brain-schedule` to set up synthesis scheduling.

**Summary:**
```
✓ Role: standalone
  Captures and synthesizes on this machine.
  Vault: Send & Receive (share with other devices as desired).
  Next: run /brain-schedule to set up synthesis scheduling.
```
