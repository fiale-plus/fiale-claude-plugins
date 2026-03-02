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
from datetime import datetime
from pathlib import Path
from subprocess import DEVNULL

# Read hook payload (UserPromptSubmit passes data via stdin)
try:
    data = json.load(sys.stdin)
except (json.JSONDecodeError, EOFError):
    data = {}

# Per-session guard — run only once per shell session
guard = Path(f"/tmp/brain-started-{os.getppid()}")
if guard.exists():
    sys.exit(0)
guard.touch()

CONFIG_PATH = Path.home() / ".claude" / "brain" / "config.json"
PENDING_PATH = Path.home() / ".claude" / "brain" / "pending.json"


def load_config() -> dict:
    if CONFIG_PATH.exists():
        try:
            with open(CONFIG_PATH) as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError):
            pass
    return {}


config = load_config()
if not config:
    sys.exit(0)  # not configured yet

# Spawn synthesize if pending queue non-empty and not run recently
if PENDING_PATH.exists():
    try:
        pending = json.loads(PENDING_PATH.read_text())
    except (json.JSONDecodeError, OSError):
        pending = []

    if pending:
        last_synth = config.get("last_synthesis_at", "")
        should_run = True
        if last_synth:
            try:
                last_dt = datetime.fromisoformat(last_synth)
                elapsed = (datetime.now() - last_dt).total_seconds()
                if elapsed < 1800:  # 30 minutes cooldown
                    should_run = False
            except ValueError:
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
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass

sys.exit(0)
