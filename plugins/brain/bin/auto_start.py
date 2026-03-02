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
from datetime import datetime, timezone
from pathlib import Path
from subprocess import DEVNULL

sys.path.insert(0, str(Path(__file__).parent))
from brain_lib import load_config, load_queue, log

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

sys.exit(0)
