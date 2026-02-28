---
description: Set this machine's role — source (capture only), aggregator (synthesis), or standalone (both)
---

Configure what this machine does in the local-brain pipeline. Run once per machine, or re-run to change role.

## Roles

| Role | Captures sessions | Synthesizes | Transcripts sync | Vault sync |
|------|:-----------------:|:-----------:|:----------------:|:----------:|
| **source** | ✓ | — | Send Only → server | Receive Only |
| **aggregator** | — | ✓ | Receive Only ← leaves | Send & Receive |
| **standalone** | ✓ | ✓ | — | Send & Receive |

**Source**: a workhorse laptop. Sessions queue via Stop hook. Transcripts sync to the aggregator via Syncthing. Vault notes arrive from the aggregator (receive-only — this machine never writes notes).

**Aggregator**: an always-on machine (server/desktop). Receives transcripts from all leaves, synthesizes them, writes vault notes. Leaves receive the notes via Syncthing.

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
Two Syncthing folders to configure on this machine:

━━━ Folder 1: Transcripts (this machine → server) ━━━

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

━━━ Folder 2: Vault (server → this machine) ━━━

On the SERVER (if not already shared):
  Add Folder:
    Path:        ~/brain
    Label:       brain-vault
    Folder ID:   brain-vault
    Sharing:     tick this machine
    Folder Type: Send & Receive

On THIS machine (accept the share request):
    Local path:  ~/brain
    Advanced → Folder Type: Receive Only
```

Tell the user: "If the server has already shared the brain-vault folder with other devices, you'll just get a share request — accept it with Receive Only and point it to ~/brain."

**Summary:**
```
✓ Role: source
  Machine name: <name>
  Sessions queued via Stop hook → ~/.claude/local-brain/pending.json
  Transcripts sync: ~/.claude/projects → server:~/brain-sources/<name>/ (Send Only)
  Vault sync:       ~/brain ← server (Receive Only)
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
Two Syncthing folders to configure on the aggregator:

━━━ Folder 1: Vault (this machine → all leaves) ━━━

On THIS machine (http://127.0.0.1:8384):
  Add Folder:
    Path:        ~/brain
    Label:       brain-vault
    Folder ID:   brain-vault
    Sharing:     tick each leaf device
    Folder Type: Send & Receive

On each LEAF (accept the share request):
    Local path:  ~/brain
    Advanced → Folder Type: Receive Only

━━━ Folder 2: Transcripts (per leaf machine → this machine) ━━━

For each leaf, the leaf creates its own Syncthing folder. On THIS machine:
  When you get a share request for "transcripts-<machine_name>":
    Accept → Local path: <sources_path>/<machine_name>
    Advanced → Folder Type: Receive Only

Run /brain-role on each leaf to generate the correct share request.
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
