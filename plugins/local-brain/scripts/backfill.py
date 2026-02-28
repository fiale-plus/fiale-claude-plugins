#!/usr/bin/env python3
"""
backfill.py — Queue historical transcripts for /synthesize to process.

Usage:
    python3 backfill.py <import_dir> [options]

Options:
    --since YYYY-MM-DD    Only include transcripts from this date onwards
    --until YYYY-MM-DD    Only include transcripts up to this date
    --limit N             Queue at most N transcripts (oldest-first within range)
    --min-messages N      Skip transcripts with fewer than N user messages (default: 3)
    --dry-run             Show what would be queued without modifying pending.json
    --stats               Show statistics about the transcripts found, then exit

Examples:
    # Queue last 30 days, max 50 at a time
    python3 backfill.py ~/.claude/projects --since 2026-01-28 --limit 50

    # See what's available before committing
    python3 backfill.py ~/.claude/projects --stats

    # Import from another machine, last 90 days
    python3 backfill.py ~/.claude/local-brain/import/laptop2/projects --since 2025-11-28 --limit 100

    # Everything, no filter (careful with large archives)
    python3 backfill.py ~/.claude/local-brain/import/laptop2/projects --min-messages 2

Workflow for importing from another machine:
    1. On the source machine:
           tar czf claude-sessions.tar.gz ~/.claude/projects/
           scp claude-sessions.tar.gz thishost:~/.claude/local-brain/import/laptop2.tar.gz

    2. On this machine:
           mkdir -p ~/.claude/local-brain/import/laptop2
           tar xzf ~/.claude/local-brain/import/laptop2.tar.gz -C ~/.claude/local-brain/import/laptop2
           python3 backfill.py ~/.claude/local-brain/import/laptop2 --stats
           python3 backfill.py ~/.claude/local-brain/import/laptop2 --since 2026-01-01 --limit 50

    3. Run /synthesize (or wait for scheduled run) to process the queue.
       Repeat with earlier date ranges as needed.
"""
import argparse
import json
import sys
from collections import defaultdict
from datetime import datetime, timezone, date
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
    import re
    sessions_dir = Path(vault_path) / "_AI" / "sessions"
    ids = set()
    if not sessions_dir.exists():
        return ids
    for note in sessions_dir.glob("*.md"):
        content = note.read_text()
        ids.update(re.findall(r"<!-- session:([a-f0-9\-]+) -->", content))
    return ids


def get_transcript_date(path: Path) -> datetime | None:
    """Read first timestamp from transcript. Returns None if unreadable."""
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                    ts = entry.get("timestamp")
                    if ts:
                        return datetime.fromisoformat(ts.replace("Z", "+00:00"))
                except (json.JSONDecodeError, ValueError):
                    continue
    except OSError:
        pass
    return None


def count_user_messages(path: Path) -> int:
    """Count human-typed user messages (not tool results)."""
    count = 0
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                    msg = entry.get("message", {})
                    if not isinstance(msg, dict) or msg.get("role") != "user":
                        continue
                    content = msg.get("content", "")
                    if isinstance(content, str) and content.strip():
                        count += 1
                    elif isinstance(content, list):
                        # Only count if has text blocks (not just tool_results)
                        has_text = any(
                            c.get("type") == "text" and c.get("text", "").strip()
                            for c in content if isinstance(c, dict)
                        )
                        if has_text:
                            count += 1
                except json.JSONDecodeError:
                    continue
    except OSError:
        pass
    return count


def find_transcripts(import_dir: str) -> list[Path]:
    """Find all .jsonl transcript files recursively, excluding index files."""
    root = Path(import_dir).expanduser()
    if not root.exists():
        print(f"ERROR: import_dir not found: {root}", file=sys.stderr)
        sys.exit(1)
    transcripts = sorted(root.rglob("*.jsonl"))
    return [t for t in transcripts if not t.name.startswith("sessions-index")]


def main():
    parser = argparse.ArgumentParser(
        description="Queue historical transcripts for /synthesize",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("import_dir", help="Directory containing .jsonl transcript files")
    parser.add_argument("--since", metavar="YYYY-MM-DD", help="Only include transcripts from this date onwards")
    parser.add_argument("--until", metavar="YYYY-MM-DD", help="Only include transcripts up to this date")
    parser.add_argument("--limit", type=int, metavar="N", help="Queue at most N transcripts")
    parser.add_argument("--min-messages", type=int, default=3, metavar="N",
                        help="Skip transcripts with fewer than N user messages (default: 3)")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be queued without modifying pending.json")
    parser.add_argument("--stats", action="store_true", help="Show statistics and exit without modifying queue")
    args = parser.parse_args()

    since_date = datetime.fromisoformat(args.since).replace(tzinfo=timezone.utc) if args.since else None
    until_date = datetime.fromisoformat(args.until).replace(tzinfo=timezone.utc) if args.until else None
    # until is inclusive end of day
    if until_date:
        from datetime import timedelta
        until_date = until_date.replace(hour=23, minute=59, second=59)

    config = load_config()
    vault_path = config.get("vault_path", str(Path.home() / "brain"))

    existing_queue = load_queue()
    existing_queue_set = set(existing_queue)
    synthesized_ids = find_synthesized_ids(vault_path)

    print(f"Scanning {args.import_dir}...")
    all_transcripts = find_transcripts(args.import_dir)
    print(f"Found {len(all_transcripts)} transcript file(s)")

    if args.stats:
        # Show distribution by month and filter preview
        by_month: dict[str, int] = defaultdict(int)
        skippable = 0
        unreadable = 0
        already_done = 0

        for t in all_transcripts:
            ts = get_transcript_date(t)
            if ts is None:
                unreadable += 1
                continue
            month = ts.strftime("%Y-%m")
            by_month[month] += 1
            if t.stem in synthesized_ids or str(t) in existing_queue_set:
                already_done += 1
            elif count_user_messages(t) < args.min_messages:
                skippable += 1

        print(f"\nDistribution by month:")
        for month in sorted(by_month):
            print(f"  {month}: {by_month[month]} sessions")
        print(f"\nAlready synthesized or queued: {already_done}")
        print(f"Too short (<{args.min_messages} messages):   {skippable}")
        print(f"Unreadable:                   {unreadable}")
        eligible = len(all_transcripts) - already_done - skippable - unreadable
        print(f"Eligible for synthesis:       {eligible}")
        print(f"\nSuggested approach:")
        if eligible > 200:
            print(f"  Large archive. Start recent: --since <90 days ago> --limit 50")
            print(f"  Run /synthesize between batches. Work backwards.")
        elif eligible > 50:
            print(f"  Medium archive. Use --limit 30-50 per batch.")
        else:
            print(f"  Small archive. Queue all at once or use --limit 20.")
        return

    # Build candidate list with dates
    candidates = []
    skipped_done = 0
    skipped_short = 0
    skipped_date = 0
    unreadable = 0

    for t in all_transcripts:
        t_str = str(t)
        session_id = t.stem

        if t_str in existing_queue_set or session_id in synthesized_ids:
            skipped_done += 1
            continue

        ts = get_transcript_date(t)
        if ts is None:
            unreadable += 1
            continue

        if since_date and ts < since_date:
            skipped_date += 1
            continue
        if until_date and ts > until_date:
            skipped_date += 1
            continue

        msg_count = count_user_messages(t)
        if msg_count < args.min_messages:
            skipped_short += 1
            continue

        candidates.append((ts, t_str))

    # Sort oldest-first so history builds in order
    candidates.sort(key=lambda x: x[0])

    to_add = [path for _, path in candidates]
    if args.limit:
        to_add = to_add[:args.limit]

    print(f"\nFilter results:")
    print(f"  Already done:        {skipped_done}")
    print(f"  Too short:           {skipped_short}")
    print(f"  Outside date range:  {skipped_date}")
    print(f"  Unreadable:          {unreadable}")
    print(f"  Eligible:            {len(candidates)}")
    print(f"  Queuing:             {len(to_add)}"
          + (f" (limited from {len(candidates)})" if args.limit and len(candidates) > args.limit else ""))

    if not to_add:
        print("\nNothing to add.")
        return

    if to_add:
        first_ts = get_transcript_date(Path(to_add[0]))
        last_ts = get_transcript_date(Path(to_add[-1]))
        print(f"  Date range:          {first_ts.strftime('%Y-%m-%d') if first_ts else '?'}"
              f" → {last_ts.strftime('%Y-%m-%d') if last_ts else '?'}")

    if args.dry_run:
        print("\n[dry-run] Would queue:")
        for p in to_add[:10]:
            ts = get_transcript_date(Path(p))
            print(f"  {ts.strftime('%Y-%m-%d') if ts else '?':12s}  {Path(p).name}")
        if len(to_add) > 10:
            print(f"  ... and {len(to_add) - 10} more")
        remaining = len(candidates) - len(to_add)
        if remaining > 0:
            print(f"\n{remaining} more eligible transcript(s) remain after this batch.")
        return

    new_queue = existing_queue + to_add
    QUEUE_PATH.parent.mkdir(parents=True, exist_ok=True)
    QUEUE_PATH.write_text(json.dumps(new_queue, indent=2))

    remaining = len(candidates) - len(to_add)
    print(f"\nQueued {len(to_add)} transcript(s) → run /synthesize to process them.")
    if remaining > 0:
        print(f"{remaining} more eligible transcript(s) remain — run backfill again for the next batch.")
    print(f"Queue total: {len(new_queue)} item(s)")


if __name__ == "__main__":
    main()
