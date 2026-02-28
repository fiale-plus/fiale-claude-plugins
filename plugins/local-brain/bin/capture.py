#!/usr/bin/env python3
"""
capture.py — Local Brain leaf capture (no LLM, runs from Stop hook)
Writes a lightweight log entry to ~/brain/Logs/YYYY-MM-DD.md immediately
after each session. Fast, automatic, no API key needed.

Usage: python3 capture.py <transcript_path>
"""
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


CONFIG_PATH = Path.home() / ".claude" / "local-brain" / "config.json"


def load_config() -> dict:
    if CONFIG_PATH.exists():
        try:
            with open(CONFIG_PATH) as f:
                return json.load(f)
        except Exception:
            pass
    return {}


def parse_session(path: str) -> tuple[str, str, list[str], datetime]:
    """
    Returns: (session_id, project_name, first_human_messages[:3], session_date)
    """
    session_id = Path(path).stem
    project_slug = Path(path).parent.name

    entries = []
    first_ts = None

    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError:
                continue

    for e in entries:
        ts = e.get("timestamp")
        if ts:
            try:
                first_ts = datetime.fromisoformat(ts.replace("Z", "+00:00"))
                break
            except ValueError:
                pass

    session_date = first_ts or datetime.now(timezone.utc)

    # Collect real human-typed messages (string content only — most reliable signal)
    messages = []
    for e in entries:
        msg = e.get("message", {})
        if not isinstance(msg, dict) or msg.get("role") != "user":
            continue
        content = msg.get("content", "")
        if isinstance(content, str) and content.strip():
            messages.append(content.strip()[:200])
        if len(messages) >= 3:
            break

    # Derive readable project name
    config = load_config()
    parts = project_slug.lstrip("-").split("-")
    start = 2
    if len(parts) > start and parts[start].lower() in ("repos", "workspace", "code", "dev", "projects"):
        start += 1
    meaningful = [p for p in parts[start:] if p]
    project_name = "-".join(meaningful) if meaningful else project_slug

    return session_id, project_name, messages, session_date


def write_log_entry(vault_path: str, session_id: str, project_name: str,
                    messages: list[str], session_date: datetime):
    logs_dir = Path(vault_path) / "Logs"
    logs_dir.mkdir(parents=True, exist_ok=True)

    date_str = session_date.strftime("%Y-%m-%d")
    time_str = session_date.strftime("%H:%M")
    log_path = logs_dir / f"{date_str}.md"

    marker = f"<!-- session:{session_id} -->"

    # Check idempotency
    if log_path.exists() and marker in log_path.read_text():
        return

    # Build entry
    first_message = messages[0] if messages else "(no message)"
    # Truncate and clean up for display
    if len(first_message) > 150:
        first_message = first_message[:150].rstrip() + "…"

    lines = [
        marker,
        f"## {time_str} — {project_name}",
        "",
        first_message,
        "",
    ]

    # Add subsequent messages as context if they add new info
    for msg in messages[1:]:
        msg_short = msg[:100].rstrip()
        if msg_short and not msg_short.startswith("[") and "tool_result" not in msg_short:
            lines.append(f"> {msg_short}")
            lines.append("")

    entry = "\n".join(lines)

    if log_path.exists():
        existing = log_path.read_text()
        content = existing.rstrip("\n") + "\n\n" + entry + "\n"
    else:
        content = f"# {date_str}\n\n" + entry + "\n"

    log_path.write_text(content)


def main():
    if len(sys.argv) < 2:
        sys.exit(0)

    transcript_path = sys.argv[1]
    if not Path(transcript_path).exists():
        sys.exit(0)

    config = load_config()
    vault_path = config.get("vault_path", str(Path.home() / "brain"))

    try:
        session_id, project_name, messages, session_date = parse_session(transcript_path)
        if messages:  # skip sessions with no real user messages
            write_log_entry(vault_path, session_id, project_name, messages, session_date)
    except Exception:
        pass  # never crash the hook

    sys.exit(0)


if __name__ == "__main__":
    main()
