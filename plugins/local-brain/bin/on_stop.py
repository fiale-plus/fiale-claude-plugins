#!/usr/bin/env python3
"""
on_stop.py — Local Brain Stop hook
Appends transcript path to pending queue. Fast exit, no API calls.
"""
import json, os, subprocess, sys
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

# Spawn local log capture (writes to ~/brain/Logs/) — no LLM, fast
plugin_root = os.environ.get("CLAUDE_PLUGIN_ROOT", os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
capture = os.path.join(plugin_root, "bin", "capture.py")
if os.path.exists(capture):
    subprocess.Popen(
        ["python3", capture, transcript_path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

sys.exit(0)
