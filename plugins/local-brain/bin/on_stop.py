#!/usr/bin/env python3
"""
on_stop.py — Local Brain Stop hook
Appends transcript path to pending queue. Fast exit, no API calls.
"""
import json, os, sys
from pathlib import Path

data = json.load(sys.stdin)

if data.get("stop_hook_active"):   # CRITICAL: prevents infinite loop
    sys.exit(0)

transcript_path = data.get("transcript_path", "")
if not transcript_path or not os.path.exists(transcript_path):
    sys.exit(0)

queue_path = Path.home() / ".claude" / "local-brain" / "pending.json"
queue_path.parent.mkdir(parents=True, exist_ok=True)

# Load existing queue
if queue_path.exists():
    try:
        queue = json.loads(queue_path.read_text())
    except (json.JSONDecodeError, OSError):
        queue = []
else:
    queue = []

# Append if not already queued
if transcript_path not in queue:
    queue.append(transcript_path)
    queue_path.write_text(json.dumps(queue, indent=2))

sys.exit(0)
