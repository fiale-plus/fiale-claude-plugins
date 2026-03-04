#!/usr/bin/env python3
"""
auto_start.py — Brain UserPromptSubmit hook
Runs once per session. Spawns /synthesize if pending queue is non-empty
and it hasn't run recently. Also does a silent git pull on team vault.
"""
import json
import os
import subprocess
import sys
from datetime import datetime, timedelta, timezone
import re
from pathlib import Path
from subprocess import DEVNULL

sys.path.insert(0, str(Path(__file__).parent))
from brain_lib import QUEUE_PATH, load_config, load_queue, log

try:
    data = json.load(sys.stdin)
except (json.JSONDecodeError, EOFError):
    data = {}

# Per-session guard — run only once per shell session
guard = Path(f"/tmp/brain-started-{os.getppid()}")
if guard.exists():
    sys.exit(0)
guard.touch()

config = load_config()
if not config:
    sys.exit(0)  # not configured yet

# Spawn synthesize if pending queue non-empty, auto_synthesize enabled, and not run recently
pending = load_queue()
if pending and config.get("auto_synthesize", True):
    last_synth = config.get("last_synthesis_at", "")
    should_run = True
    if last_synth:
        try:
            last_dt = datetime.fromisoformat(last_synth)
            if last_dt.tzinfo is None:
                last_dt = last_dt.replace(tzinfo=timezone.utc)
            elapsed = (datetime.now(timezone.utc) - last_dt).total_seconds()
            if elapsed < 1800:  # 30 minutes cooldown
                should_run = False
        except (ValueError, TypeError):
            pass

    if should_run:
        subprocess.Popen(
            ["claude", "-p", "/synthesize"],
            start_new_session=True,
            stdout=DEVNULL,
            stderr=DEVNULL,
        )

# Silent git pull on team vault if enabled
team = config.get("team", {})
if team.get("enabled"):
    team_path = Path(team.get("vault_path", str(Path.home() / "brain-team"))).expanduser()
    if team_path.exists() and (team_path / ".git").exists():
        try:
            subprocess.run(
                ["git", "-C", str(team_path), "pull", "--ff-only", "-q"],
                capture_output=True,
                timeout=10,
            )
        except (subprocess.TimeoutExpired, FileNotFoundError) as e:
            log(f"auto_start: git pull failed: {e}")

# Surface project brain docs hint
try:
    project_dir = Path(os.environ.get("CLAUDE_PROJECT_PATH", os.getcwd()))
    brain_dir = project_dir / ".brain"
    if brain_dir.is_dir():
        docs = sorted(f.stem for f in brain_dir.glob("*.md") if f.stat().st_size > 10)
        if docs:
            print(
                f"[Brain] Project context: .brain/{{{','.join(docs)}}} auto-loaded "
                f"— check these for decisions, gotchas, and patterns specific to this repo.",
                flush=True,
            )
except Exception:
    pass  # never block the session

# Catch-up scan: auto-queue sessions missed due to Ctrl-C (Stop hook not triggered)
try:
    current_transcript = data.get("transcript_path", "")
    projects_dir = Path.home() / ".claude" / "projects"

    if projects_dir.exists():
        catch_up_days = config.get("catch_up_days", 7)
        cutoff = datetime.now(timezone.utc) - timedelta(days=catch_up_days)

        # Find already-synthesized session IDs to avoid re-queuing processed sessions
        vault_path = config.get("vault_path", str(Path.home() / "brain"))
        synthesized_ids: set[str] = set()
        sessions_dir = Path(vault_path).expanduser() / "_sessions"
        if sessions_dir.exists():
            for note in sessions_dir.glob("*.md"):
                try:
                    synthesized_ids.update(
                        re.findall(r"<!-- session:([a-f0-9-]+) -->", note.read_text())
                    )
                except OSError:
                    pass

        current_queue_set = set(load_queue())
        missed = []

        for transcript in sorted(projects_dir.rglob("*.jsonl")):
            if transcript.name.startswith("sessions-index"):
                continue
            if str(transcript) == current_transcript:
                continue  # skip the active session
            if str(transcript) in current_queue_set:
                continue  # already queued
            if transcript.stem in synthesized_ids:
                continue  # already synthesized
            try:
                mtime = datetime.fromtimestamp(transcript.stat().st_mtime, tz=timezone.utc)
                if mtime < cutoff:
                    continue  # outside catch-up window
                if (datetime.now(timezone.utc) - mtime).total_seconds() < 300:
                    continue  # too recent — might still be an active session
            except OSError:
                continue
            missed.append(str(transcript))

        if missed:
            queue = load_queue()
            added = 0
            for path in missed:
                if path not in queue:
                    queue.append(path)
                    added += 1
            if added:
                QUEUE_PATH.write_text(json.dumps(queue, indent=2))
                log(f"auto_start: catch-up queued {added} missed session(s)")
                print(f"[Brain] Catch-up: queued {added} missed session(s) for synthesis.", flush=True)
except Exception:
    pass  # never block the session

sys.exit(0)
