#!/usr/bin/env python3
"""
on_stop.py — Brain Stop hook
Appends transcript path to pending queue. Fast exit, no API calls.
"""
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from brain_lib import QUEUE_PATH

try:
    data = json.load(sys.stdin)
except (json.JSONDecodeError, EOFError):
    sys.exit(0)

if data.get("stop_hook_active"):   # CRITICAL: prevents infinite loop
    sys.exit(0)

transcript_path = data.get("transcript_path", "")
if not transcript_path or not os.path.exists(transcript_path):
    sys.exit(0)

QUEUE_PATH.parent.mkdir(parents=True, exist_ok=True)

try:
    queue = json.loads(QUEUE_PATH.read_text()) if QUEUE_PATH.exists() else []
except (json.JSONDecodeError, OSError):
    queue = []

if transcript_path not in queue:
    queue.append(transcript_path)
    QUEUE_PATH.write_text(json.dumps(queue, indent=2))

sys.exit(0)
