#!/usr/bin/env python3
"""
surface.py — Brain PreToolUse hook
Keyword-matches atoms index against tool input. Outputs a hint if ≥2 keywords
match and the atom was validated within 180 days. Silent otherwise.
Fast: no Claude calls, <1 second.
"""
import json
import re
import sys
from datetime import date, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from brain_lib import ATOMS_INDEX_PATH, load_config

MAX_AGE_DAYS = 180

try:
    data = json.load(sys.stdin)
except (json.JSONDecodeError, EOFError):
    sys.exit(0)

config = load_config()
if not config.get("surface_hints", True):
    sys.exit(0)

if not ATOMS_INDEX_PATH.exists():
    sys.exit(0)

try:
    index = json.loads(ATOMS_INDEX_PATH.read_text())
except (json.JSONDecodeError, OSError):
    sys.exit(0)

# Extract text from hook payload — tool input is in data["tool_input"]
tool_input = data.get("tool_input", {})
text_to_search = ""
if isinstance(tool_input, dict):
    text_to_search = " ".join(str(v) for v in tool_input.values())

if not text_to_search:
    sys.exit(0)

words = set(re.findall(r"\b[a-z][a-z0-9_-]{2,}\b", text_to_search.lower()))

today = date.today()
best_match = None
best_score = 0

for atom in index:
    validated_at = atom.get("validated_at", "")
    if validated_at:
        try:
            va_date = datetime.strptime(validated_at, "%Y-%m-%d").date()
            if (today - va_date).days > MAX_AGE_DAYS:
                continue
        except ValueError:
            pass

    score = len(words & set(atom.get("keywords", [])))
    if score >= 2 and score > best_score:
        best_score = score
        best_match = atom

if best_match:
    slug = best_match["slug"]
    print(f"[Brain] Related atom: {slug} ({best_score} keyword matches) — {best_match['path']}")

sys.exit(0)
