#!/usr/bin/env python3
"""
surface.py — Brain PreToolUse hook
Keyword-matches atoms index against user message. Outputs a hint if ≥2 keywords
match and the atom was validated within 180 days. Silent otherwise.
Fast: no Claude calls, <1 second.
"""
import json
import re
import sys
from datetime import date, datetime
from pathlib import Path

ATOMS_INDEX_PATH = Path.home() / ".claude" / "brain" / "atoms-index.json"
CONFIG_PATH = Path.home() / ".claude" / "brain" / "config.json"
MAX_AGE_DAYS = 180


def load_config() -> dict:
    if CONFIG_PATH.exists():
        try:
            with open(CONFIG_PATH) as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError):
            pass
    return {}


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

# Extract keywords from the current tool input
words = set(re.findall(r"\b[a-z][a-z0-9_-]{2,}\b", text_to_search.lower()))

today = date.today()
best_match = None
best_score = 0

for atom in index:
    # Check age
    validated_at = atom.get("validated_at", "")
    if validated_at:
        try:
            va_date = datetime.strptime(validated_at, "%Y-%m-%d").date()
            age_days = (today - va_date).days
            if age_days > MAX_AGE_DAYS:
                continue
        except ValueError:
            pass

    atom_keywords = set(atom.get("keywords", []))
    score = len(words & atom_keywords)
    if score >= 2 and score > best_score:
        best_score = score
        best_match = atom

if best_match:
    slug = best_match["slug"]
    # Output as a hint comment visible in the session
    print(f"[Brain] Related atom: {slug} ({best_score} keyword matches) — ~/brain/atoms/{slug}.md")

sys.exit(0)
