#!/usr/bin/env python3
"""
synthesize.py — Local Brain vault writer library
Called by the /synthesize command after Claude produces the synthesis JSON.

Usage: python3 synthesize.py <transcript_path> <synthesis_json_path>
  transcript_path    — path to the .jsonl transcript
  synthesis_json_path — path to JSON file containing synthesis result

The synthesis JSON must match:
{
  "summary": "...",
  "what_was_done": "...",
  "outcome": "done|in_progress|blocked",
  "decisions_made": ["..."],
  "learnings": ["..."],
  "primary_theme": "building|debugging|researching|planning|configuring",
  "energy_inferred": "high|medium|low",
  "alignment_with_polaris": "high|medium|low|off-track",
  "unexplored_thread": "...",
  "suggested_next": "..."
}
"""
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path


# ── Config ────────────────────────────────────────────────────────────────────

CONFIG_PATH = Path.home() / ".claude" / "local-brain" / "config.json"
LOG_PATH = Path.home() / ".claude" / "local-brain" / "synthesize.log"


def load_config() -> dict:
    if CONFIG_PATH.exists():
        with open(CONFIG_PATH) as f:
            return json.load(f)
    return {}


def log(msg: str):
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(LOG_PATH, "a") as f:
        f.write(f"[{ts}] {msg}\n")


# ── Transcript parsing ─────────────────────────────────────────────────────────

def parse_transcript(path: str) -> tuple[str, str, list[str], datetime]:
    """
    Returns: (session_id, project_slug, user_messages, session_date)
    user_messages: first 3 + last 2 human-typed messages
    session_date: from transcript timestamps (correct for backfill)
    """
    session_id = Path(path).stem
    project_slug = Path(path).parent.name

    lines = []
    first_ts = None

    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                lines.append(json.loads(line))
            except json.JSONDecodeError:
                continue

    for entry in lines:
        ts_str = entry.get("timestamp")
        if ts_str:
            try:
                first_ts = datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
                break
            except ValueError:
                pass

    session_date = first_ts or datetime.now(timezone.utc)

    user_messages = []
    for entry in lines:
        msg = entry.get("message", {})
        if not isinstance(msg, dict):
            continue
        if msg.get("role") != "user":
            continue
        content = msg.get("content", "")
        if isinstance(content, list):
            texts = [
                c.get("text", "")
                for c in content
                if isinstance(c, dict) and c.get("type") == "text"
            ]
            text = " ".join(texts).strip()
            if not text:
                continue
        elif isinstance(content, str):
            text = content.strip()
            if not text:
                continue
        else:
            continue
        user_messages.append(text[:500])

    if len(user_messages) <= 5:
        selected = user_messages
    else:
        seen = []
        for m in user_messages[:3] + user_messages[-2:]:
            if m not in seen:
                seen.append(m)
        selected = seen

    return session_id, project_slug, selected, session_date


def read_sessions_index(transcript_path: str) -> dict:
    index_path = Path(transcript_path).parent / "sessions-index.json"
    if not index_path.exists():
        return {}
    try:
        with open(index_path) as f:
            data = json.load(f)
        session_id = Path(transcript_path).stem
        for entry in data.get("entries", []):
            if entry.get("sessionId") == session_id:
                return entry
    except (json.JSONDecodeError, KeyError):
        pass
    return {}


def project_name_from_slug(project_slug: str, project_path: str = "") -> str:
    """
    Convert a Claude project slug to a readable project name.
    Uses projectPath from sessions-index when available (accurate).
    Falls back to slug heuristic (drops /Users/<user>/ prefix).
    """
    if project_path:
        # Use the last 2 path components as "org/repo" or just the last one
        parts = [p for p in project_path.rstrip("/").split("/") if p]
        # Drop common boring prefixes
        skip = {"Users", "home", "repos", "workspace"}
        while parts and parts[0] in skip:
            parts.pop(0)
        # Skip single-letter or username-looking segments at the start
        if len(parts) > 1 and len(parts[0]) <= 6:
            parts.pop(0)
        return "/".join(parts[-2:]) if len(parts) >= 2 else (parts[0] if parts else project_slug)

    # Fallback: strip /Users/<username>/ prefix, join rest with hyphens
    parts = project_slug.lstrip("-").split("-")
    start = 2  # skip "Users" + username
    if len(parts) > start and parts[start].lower() in ("repos", "workspace", "code", "dev", "projects"):
        start += 1
    meaningful = [p for p in parts[start:] if p]
    return "-".join(meaningful) if meaningful else project_slug


# ── Vault writing ──────────────────────────────────────────────────────────────

def format_session_block(session_id, project_name, synthesis, session_date, message_count) -> str:
    time_str = session_date.strftime("%H:%M")
    theme = synthesis.get("primary_theme", "unknown")
    summary = synthesis.get("summary", "")
    decisions = synthesis.get("decisions_made", [])
    learnings = synthesis.get("learnings", [])
    outcome = synthesis.get("outcome", "unknown")
    alignment = synthesis.get("alignment_with_polaris", "unknown")
    unexplored = synthesis.get("unexplored_thread", "")
    suggested_next = synthesis.get("suggested_next", "")

    decisions_str = "; ".join(decisions) if decisions else "none"
    learnings_str = "; ".join(learnings) if learnings else "none"

    lines = [
        f"<!-- session:{session_id} -->",
        f"## {time_str} · {project_name} · {theme}",
        "",
        summary,
        "",
        f"**Decisions:** {decisions_str}  **Learnings:** {learnings_str}  **Outcome:** {outcome} · {message_count} msgs",
        f"**Alignment:** {alignment}" + (f"  **Unexplored:** {unexplored}" if unexplored else ""),
        f"**Next:** {suggested_next}",
        "",
        "---",
        "<!-- end-session -->",
    ]
    return "\n".join(lines)


def write_session_note(vault_path, session_id, project_name, synthesis, session_date, message_count):
    sessions_dir = Path(vault_path) / "_AI" / "sessions"
    sessions_dir.mkdir(parents=True, exist_ok=True)

    date_str = session_date.strftime("%Y-%m-%d")
    note_path = sessions_dir / f"{date_str}.md"
    block = format_session_block(session_id, project_name, synthesis, session_date, message_count)
    marker = f"<!-- session:{session_id} -->"

    if note_path.exists():
        existing = note_path.read_text()
        if marker in existing:
            return  # idempotent
        content = existing.rstrip("\n") + "\n\n" + block + "\n"
    else:
        content = f"# Sessions — {date_str}\n\n" + block + "\n"

    note_path.write_text(content)


def upsert_project_note(vault_path, project_name, session_id, synthesis, session_date):
    projects_dir = Path(vault_path) / "_AI" / "projects"
    projects_dir.mkdir(parents=True, exist_ok=True)

    safe_name = re.sub(r"[^\w\-]", "-", project_name).strip("-")
    note_path = projects_dir / f"{safe_name}.md"

    marker = f"<!-- session:{session_id} -->"
    date_str = session_date.strftime("%Y-%m-%d %H:%M")
    summary = synthesis.get("summary", "")
    suggested_next = synthesis.get("suggested_next", "")
    outcome = synthesis.get("outcome", "unknown")
    theme = synthesis.get("primary_theme", "unknown")

    entry = (
        f"{marker}\n"
        f"## {date_str} ({theme} · {outcome})\n\n"
        f"{summary}\n\n"
        f"**Next:** {suggested_next}\n\n"
        f"---\n"
    )

    if note_path.exists():
        existing = note_path.read_text()
        if marker in existing:
            return  # idempotent
        if existing.startswith("# "):
            header_end = existing.index("\n") + 1
            content = existing[:header_end] + "\n" + entry + existing[header_end:]
        else:
            content = entry + existing
    else:
        content = f"# {project_name}\n\n" + entry

    note_path.write_text(content)


# ── CLI entry point ────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 3:
        print("Usage: synthesize.py <transcript_path> <synthesis_json_path>", file=sys.stderr)
        sys.exit(1)

    transcript_path = sys.argv[1]
    synthesis_json_path = sys.argv[2]

    config = load_config()
    vault_path = config.get("vault_path", str(Path.home() / "brain"))

    with open(synthesis_json_path) as f:
        synthesis = json.load(f)

    session_id, project_slug, _, session_date = parse_transcript(transcript_path)
    index_entry = read_sessions_index(transcript_path)
    message_count = index_entry.get("messageCount", "?")
    project_name = project_name_from_slug(project_slug, index_entry.get("projectPath", ""))

    write_session_note(vault_path, session_id, project_name, synthesis, session_date, message_count)
    upsert_project_note(vault_path, project_name, session_id, synthesis, session_date)
    log(f"OK: {session_id} → {session_date.strftime('%Y-%m-%d')} · {project_name} · {synthesis.get('primary_theme', '?')} · {synthesis.get('outcome', '?')}")
    print(f"Written: {session_date.strftime('%Y-%m-%d')} · {project_name}")


if __name__ == "__main__":
    main()
