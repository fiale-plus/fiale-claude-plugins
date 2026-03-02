#!/usr/bin/env python3
"""
brain_lib.py — Shared constants and utilities for brain plugin scripts.
Import via: sys.path.insert(0, str(Path(__file__).parent)); from brain_lib import ...
"""
import json
from datetime import datetime
from pathlib import Path

CONFIG_PATH      = Path.home() / ".claude" / "brain" / "config.json"
QUEUE_PATH       = Path.home() / ".claude" / "brain" / "pending.json"
ATOMS_INDEX_PATH = Path.home() / ".claude" / "brain" / "atoms-index.json"
LOG_PATH         = Path.home() / ".claude" / "brain" / "synthesize.log"


def load_config() -> dict:
    if CONFIG_PATH.exists():
        try:
            with open(CONFIG_PATH) as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError):
            pass
    return {}


def load_queue() -> list:
    if QUEUE_PATH.exists():
        try:
            return json.loads(QUEUE_PATH.read_text())
        except (json.JSONDecodeError, OSError):
            pass
    return []


def log(msg: str):
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(LOG_PATH, "a") as f:
        f.write(f"[{ts}] {msg}\n")
