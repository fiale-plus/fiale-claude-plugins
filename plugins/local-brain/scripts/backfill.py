#!/usr/bin/env python3
"""
backfill.py — Queue historical transcripts from another machine for /synthesize to process.

Usage:
    python3 backfill.py <import_dir> [--dry-run]

    import_dir  Path containing .jsonl transcript files (searched recursively).
                Typically: ~/.claude/local-brain/import/<machine-name>/
                or a direct copy of ~/.claude/projects/ from another machine.

    --dry-run   Show what would be queued without modifying pending.json.

Workflow for importing from another laptop:
    1. On the source machine:
           tar czf claude-sessions.tar.gz ~/.claude/projects/
           scp claude-sessions.tar.gz thishost:~/.claude/local-brain/import/laptop2.tar.gz

    2. On this machine:
           mkdir -p ~/.claude/local-brain/import/laptop2
           tar xzf ~/.claude/local-brain/import/laptop2.tar.gz -C ~/.claude/local-brain/import/laptop2
           python3 /path/to/backfill.py ~/.claude/local-brain/import/laptop2

    3. Run /synthesize (or wait for scheduled run) to process the queue.

The script skips transcripts that are already in pending.json or already
synthesized (detected by checking the vault for their session ID).
"""
import argparse
import json
import sys
from pathlib import Path


QUEUE_PATH = Path.home() / ".claude" / "local-brain" / "pending.json"
CONFIG_PATH = Path.home() / ".claude" / "local-brain" / "config.json"


def load_config() -> dict:
    if CONFIG_PATH.exists():
        with open(CONFIG_PATH) as f:
            return json.load(f)
    return {}


def load_queue() -> list:
    if QUEUE_PATH.exists():
        try:
            return json.loads(QUEUE_PATH.read_text())
        except (json.JSONDecodeError, OSError):
            pass
    return []


def find_synthesized_ids(vault_path: str) -> set:
    """Scan vault session notes for already-synthesized session IDs."""
    sessions_dir = Path(vault_path) / "_AI" / "sessions"
    ids = set()
    if not sessions_dir.exists():
        return ids
    for note in sessions_dir.glob("*.md"):
        content = note.read_text()
        import re
        ids.update(re.findall(r"<!-- session:([a-f0-9\-]+) -->", content))
    return ids


def find_transcripts(import_dir: str) -> list[Path]:
    """Find all .jsonl transcript files in the import directory."""
    root = Path(import_dir).expanduser()
    if not root.exists():
        print(f"ERROR: import_dir not found: {root}", file=sys.stderr)
        sys.exit(1)
    transcripts = sorted(root.rglob("*.jsonl"))
    # Filter out sessions-index files (not transcripts)
    transcripts = [t for t in transcripts if not t.name.startswith("sessions-index")]
    return transcripts


def main():
    parser = argparse.ArgumentParser(description="Queue historical transcripts for /synthesize")
    parser.add_argument("import_dir", help="Directory containing .jsonl transcript files")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be queued without modifying pending.json")
    args = parser.parse_args()

    config = load_config()
    vault_path = config.get("vault_path", str(Path.home() / "brain"))

    existing_queue = load_queue()
    existing_queue_set = set(existing_queue)
    synthesized_ids = find_synthesized_ids(vault_path)

    transcripts = find_transcripts(args.import_dir)
    print(f"Found {len(transcripts)} transcript(s) in {args.import_dir}")

    to_add = []
    skipped_queued = 0
    skipped_synthesized = 0

    for t in transcripts:
        session_id = t.stem
        t_str = str(t)

        if t_str in existing_queue_set:
            skipped_queued += 1
            continue

        if session_id in synthesized_ids:
            skipped_synthesized += 1
            continue

        to_add.append(t_str)

    print(f"  Already in queue:      {skipped_queued}")
    print(f"  Already synthesized:   {skipped_synthesized}")
    print(f"  New to queue:          {len(to_add)}")

    if not to_add:
        print("Nothing to add.")
        return

    if args.dry_run:
        print("\n[dry-run] Would add:")
        for p in to_add[:20]:
            print(f"  {p}")
        if len(to_add) > 20:
            print(f"  ... and {len(to_add) - 20} more")
        return

    new_queue = existing_queue + to_add
    QUEUE_PATH.parent.mkdir(parents=True, exist_ok=True)
    QUEUE_PATH.write_text(json.dumps(new_queue, indent=2))
    print(f"\nQueued {len(to_add)} transcript(s) → run /synthesize to process them.")
    print(f"Queue now has {len(new_queue)} item(s) total.")


if __name__ == "__main__":
    main()
