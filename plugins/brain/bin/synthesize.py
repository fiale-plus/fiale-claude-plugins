#!/usr/bin/env python3
"""
synthesize.py — Brain vault writer library
Called by the /synthesize command after Claude produces the Knowledge JSON.

Usage: python3 synthesize.py <transcript_path> <knowledge_json_path>
  transcript_path     — path to the .jsonl transcript
  knowledge_json_path — path to JSON file containing knowledge result

The knowledge JSON must match:
{
  "summary": "...",
  "outcome": "done|in_progress|blocked",
  "suggested_next": "...",
  "primary_theme": "building|debugging|researching|planning|configuring",
  "knowledge": [
    {
      "destination": "project|personal|team",
      "format": "decision|gotcha|pattern|insight",
      "title": "...",
      "content": "..."
    }
  ]
}
"""
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from brain_lib import ATOMS_INDEX_PATH, CONFIG_PATH, load_config, log


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
        selected = list(dict.fromkeys(user_messages[:3] + user_messages[-2:]))

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
        parts = [p for p in project_path.rstrip("/").split("/") if p]
        skip = {"Users", "home", "repos", "workspace"}
        while parts and parts[0] in skip:
            parts.pop(0)
        if len(parts) > 1 and len(parts[0]) <= 6:
            parts.pop(0)
        return "/".join(parts[-2:]) if len(parts) >= 2 else (parts[0] if parts else project_slug)

    parts = project_slug.lstrip("-").split("-")
    start = 2  # skip "Users" + username
    if len(parts) > start and parts[start].lower() in ("repos", "workspace", "code", "dev", "projects"):
        start += 1
    meaningful = [p for p in parts[start:] if p]
    return "-".join(meaningful) if meaningful else project_slug


def project_root_from_path(project_path: str) -> str | None:
    """Return the actual filesystem path for a project."""
    if project_path and Path(project_path).expanduser().exists():
        return str(Path(project_path).expanduser())
    return None


# ── Slug helpers ──────────────────────────────────────────────────────────────

def title_to_slug(title: str) -> str:
    """Convert a title to a filesystem-safe slug."""
    slug = title.lower()
    slug = re.sub(r"[^\w\s-]", "", slug)
    slug = re.sub(r"[\s_]+", "-", slug)
    slug = slug.strip("-")
    return slug[:80] if len(slug) > 80 else slug


def format_to_filename(fmt: str) -> str:
    mapping = {
        "decision": "DECISIONS.md",
        "gotcha": "GOTCHAS.md",
        "pattern": "PATTERNS.md",
    }
    return mapping.get(fmt, "NOTES.md")


# ── Session notes (personal vault) ────────────────────────────────────────────

def format_session_block(session_id, project_name, knowledge_data, session_date, message_count) -> str:
    time_str = session_date.strftime("%H:%M")
    theme = knowledge_data.get("primary_theme", "unknown")
    summary = knowledge_data.get("summary", "")
    outcome = knowledge_data.get("outcome", "unknown")
    suggested_next = knowledge_data.get("suggested_next", "")

    lines = [
        f"<!-- session:{session_id} -->",
        f"## {time_str} · {project_name} · {theme}",
        "",
        summary,
        "",
        f"**Outcome:** {outcome} · {message_count} msgs",
        f"**Next:** {suggested_next}",
        "",
        "---",
        "<!-- end-session -->",
    ]
    return "\n".join(lines)


def write_session_note(vault_path, session_id, project_name, knowledge_data, session_date, message_count):
    sessions_dir = Path(vault_path).expanduser() / "_sessions"
    sessions_dir.mkdir(parents=True, exist_ok=True)

    date_str = session_date.strftime("%Y-%m-%d")
    note_path = sessions_dir / f"{date_str}.md"
    block = format_session_block(session_id, project_name, knowledge_data, session_date, message_count)
    marker = f"<!-- session:{session_id} -->"

    if note_path.exists():
        existing = note_path.read_text()
        if marker in existing:
            return  # idempotent
        content = existing.rstrip("\n") + "\n\n" + block + "\n"
    else:
        content = f"# Sessions — {date_str}\n\n" + block + "\n"

    note_path.write_text(content)


# ── Project layer (.brain/ in project repo) ────────────────────────────────────

def write_project_doc(project_root: str, fmt: str, title: str, content: str, session_id: str, session_date: datetime):
    """
    Write a knowledge item to <project_root>/.brain/<FILE>.md.
    Creates the directory and file if missing. Idempotent via session marker.
    """
    brain_dir = Path(project_root) / ".brain"
    brain_dir.mkdir(parents=True, exist_ok=True)

    filename = format_to_filename(fmt)
    doc_path = brain_dir / filename

    marker = f"<!-- session:{session_id} -->"
    date_str = session_date.strftime("%Y-%m-%d")
    entry = f"\n<!-- session:{session_id} -->\n### {date_str} — {title}\n{content}\n"

    if doc_path.exists():
        existing = doc_path.read_text()
        if marker in existing:
            return  # idempotent
        doc_path.write_text(existing.rstrip("\n") + entry)
    else:
        header_title = filename.replace(".md", "").title()
        doc_path.write_text(f"# {header_title}\n{entry}")


def update_project_claude_md(project_root: str):
    """
    Upsert a <!-- brain managed --> block in <project_root>/CLAUDE.md
    with @imports for each .brain/*.md that exists.
    Idempotent.
    """
    brain_dir = Path(project_root) / ".brain"
    if not brain_dir.exists():
        return

    docs = sorted(brain_dir.glob("*.md"))
    if not docs:
        return

    claude_md_path = Path(project_root) / "CLAUDE.md"
    imports = "\n".join(f"@.brain/{d.name}" for d in docs)
    managed_block = f"<!-- brain managed -->\n{imports}\n<!-- end brain managed -->"

    if claude_md_path.exists():
        existing = claude_md_path.read_text()
        # Guard against malformed partial block (opening tag without closing)
        if "<!-- brain managed -->" in existing and "<!-- end brain managed -->" not in existing:
            log(f"update_project_claude_md: malformed brain block in {claude_md_path}, skipping")
            return
        new_content = re.sub(
            r"<!-- brain managed -->.*?<!-- end brain managed -->",
            managed_block,
            existing,
            flags=re.DOTALL,
        )
        if new_content == existing:
            # Block not present yet — append it
            new_content = existing.rstrip("\n") + "\n\n" + managed_block + "\n"
        claude_md_path.write_text(new_content)
    else:
        claude_md_path.write_text(managed_block + "\n")


# ── Personal layer (atoms) ─────────────────────────────────────────────────────

def upsert_atom(vault_path: str, title: str, content: str, tags: list[str], session_id: str, session_date: datetime):
    """
    Create or upsert a personal atom in ~/brain/atoms/<slug>.md.
    Increments reference_count and updates validated_at on update.
    """
    atoms_dir = Path(vault_path).expanduser() / "atoms"
    atoms_dir.mkdir(parents=True, exist_ok=True)

    slug = title_to_slug(title)
    atom_path = atoms_dir / f"{slug}.md"
    date_str = session_date.strftime("%Y-%m-%d")

    if atom_path.exists():
        existing = atom_path.read_text()
        # Update reference_count
        match = re.search(r"reference_count:\s*(\d+)", existing)
        ref_count = int(match.group(1)) + 1 if match else 2
        new_content = re.sub(r"reference_count:\s*\d+", f"reference_count: {ref_count}", existing)
        new_content = re.sub(r"validated_at:\s*[\d-]+", f"validated_at: {date_str}", new_content)
        atom_path.write_text(new_content)
    else:
        tags_str = ", ".join(tags) if tags else ""
        atom_path.write_text(
            f"---\n"
            f"title: {title}\n"
            f"tags: [{tags_str}]\n"
            f"created: {date_str}\n"
            f"validated_at: {date_str}\n"
            f"reference_count: 1\n"
            f"source_session: {session_id}\n"
            f"---\n\n"
            f"{content}\n"
        )


# ── Team layer ─────────────────────────────────────────────────────────────────

def write_team_doc(team_vault_path: str, fmt: str, title: str, content: str, auto_promote_mode: str = "commit"):
    """
    Write a knowledge item to ~/brain-team/<format>/<slug>.md.
    Idempotent (skips if slug already exists).
    auto_promote_mode: commit | pr | suggest
    """
    team_path = Path(team_vault_path).expanduser()
    if not team_path.exists():
        return

    fmt_dir = team_path / fmt
    fmt_dir.mkdir(parents=True, exist_ok=True)

    slug = title_to_slug(title)
    doc_path = fmt_dir / f"{slug}.md"

    if doc_path.exists():
        return  # already exists, don't overwrite

    date_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    doc_path.write_text(
        f"---\n"
        f"title: {title}\n"
        f"format: {fmt}\n"
        f"created: {date_str}\n"
        f"---\n\n"
        f"{content}\n"
    )

    if auto_promote_mode == "commit":
        try:
            r = subprocess.run(
                ["git", "-C", str(team_path), "add", str(doc_path)],
                capture_output=True, timeout=10,
            )
            if r.returncode != 0:
                log(f"write_team_doc: git add failed: {r.stderr.decode().strip()}")
            r = subprocess.run(
                ["git", "-C", str(team_path), "commit", "-m", f"brain: add {fmt}/{slug}"],
                capture_output=True, timeout=15,
            )
            if r.returncode != 0:
                log(f"write_team_doc: git commit failed: {r.stderr.decode().strip()}")
        except (subprocess.TimeoutExpired, FileNotFoundError) as e:
            log(f"write_team_doc: commit mode error: {e}")
    elif auto_promote_mode == "pr":
        branch = f"brain-{slug[:40]}"
        # Capture current branch so we can restore it after PR creation
        orig = subprocess.run(
            ["git", "-C", str(team_path), "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True, text=True, timeout=5,
        )
        orig_branch = orig.stdout.strip() or "main"
        try:
            # Use checkout instead of checkout -b if branch already exists
            exists = subprocess.run(
                ["git", "-C", str(team_path), "show-ref", "--verify", f"refs/heads/{branch}"],
                capture_output=True, timeout=5,
            )
            checkout_cmd = ["checkout", branch] if exists.returncode == 0 else ["checkout", "-b", branch]
            subprocess.run(["git", "-C", str(team_path)] + checkout_cmd, capture_output=True, timeout=10)
            subprocess.run(
                ["git", "-C", str(team_path), "add", str(doc_path)],
                capture_output=True, timeout=10,
            )
            subprocess.run(
                ["git", "-C", str(team_path), "commit", "-m", f"brain: add {fmt}/{slug}"],
                capture_output=True, timeout=15,
            )
            subprocess.run(
                ["git", "-C", str(team_path), "push", "-u", "origin", branch],
                capture_output=True, timeout=30,
            )
            subprocess.run(
                ["gh", "pr", "create", "--draft",
                 "--title", f"brain: {title}",
                 "--body", f"Auto-generated knowledge item from brain plugin.\n\n**Format:** {fmt}\n\n{content}"],
                cwd=str(team_path), capture_output=True, timeout=30,
            )
        except (subprocess.TimeoutExpired, FileNotFoundError) as e:
            log(f"write_team_doc: pr mode error: {e}")
        finally:
            # Always restore original branch
            subprocess.run(
                ["git", "-C", str(team_path), "checkout", orig_branch],
                capture_output=True, timeout=10,
            )


# ── Atoms index ───────────────────────────────────────────────────────────────

def _extract_keywords(text: str) -> list[str]:
    """Simple word extraction for keyword matching."""
    words = re.findall(r"\b[a-z][a-z0-9_-]{2,}\b", text.lower())
    # Filter common stop words
    stop = {"the", "and", "for", "that", "this", "with", "from", "are", "was",
            "not", "but", "use", "can", "you", "your", "will", "its", "via"}
    return [w for w in words if w not in stop]


def build_atoms_index(vault_path: str):
    """
    Scan ~/brain/atoms/ and write ~/.claude/brain/atoms-index.json.
    Per atom: slug, path, keywords, validated_at, reference_count.
    """
    atoms_dir = Path(vault_path).expanduser() / "atoms"
    if not atoms_dir.exists():
        ATOMS_INDEX_PATH.parent.mkdir(parents=True, exist_ok=True)
        ATOMS_INDEX_PATH.write_text(json.dumps([], indent=2))
        return

    index = []
    for atom_path in sorted(atoms_dir.glob("*.md")):
        try:
            text = atom_path.read_text()
        except OSError:
            continue

        # Parse frontmatter
        validated_at = ""
        ref_count = 1
        fm_match = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
        if fm_match:
            fm = fm_match.group(1)
            va = re.search(r"validated_at:\s*([\d-]+)", fm)
            rc = re.search(r"reference_count:\s*(\d+)", fm)
            if va:
                validated_at = va.group(1)
            if rc:
                ref_count = int(rc.group(1))

        keywords = _extract_keywords(text)
        # Deduplicate while preserving order
        seen: set[str] = set()
        unique_kw = []
        for kw in keywords:
            if kw not in seen:
                seen.add(kw)
                unique_kw.append(kw)

        index.append({
            "slug": atom_path.stem,
            "path": str(atom_path),
            "keywords": unique_kw[:40],
            "validated_at": validated_at,
            "reference_count": ref_count,
        })

    ATOMS_INDEX_PATH.parent.mkdir(parents=True, exist_ok=True)
    ATOMS_INDEX_PATH.write_text(json.dumps(index, indent=2))


# ── CLI entry point ────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 3:
        print("Usage: synthesize.py <transcript_path> <knowledge_json_path>", file=sys.stderr)
        sys.exit(1)

    transcript_path = sys.argv[1]
    knowledge_json_path = sys.argv[2]

    config = load_config()
    vault_path = config.get("vault_path", str(Path.home() / "brain"))

    with open(knowledge_json_path) as f:
        knowledge_data = json.load(f)

    session_id, project_slug, _, session_date = parse_transcript(transcript_path)
    index_entry = read_sessions_index(transcript_path)
    message_count = index_entry.get("messageCount", "?")
    project_path = index_entry.get("projectPath", "")
    project_name = project_name_from_slug(project_slug, project_path)
    project_root = project_root_from_path(project_path)

    # 1. Write personal session note
    write_session_note(vault_path, session_id, project_name, knowledge_data, session_date, message_count)

    # 2. Route knowledge items
    project_docs_written = False
    team_cfg = config.get("team", {})
    team_enabled = team_cfg.get("enabled", False)
    team_vault = team_cfg.get("vault_path", str(Path.home() / "brain-team"))
    team_project_paths = team_cfg.get("project_paths", [])
    auto_promote_mode = team_cfg.get("auto_promote_mode", "commit")

    # Determine if this project matches team routing
    team_route = False
    if team_enabled and project_path:
        for tp in team_project_paths:
            expanded = str(Path(tp).expanduser())
            if project_path.startswith(expanded):
                team_route = True
                break

    for item in knowledge_data.get("knowledge", []):
        dest = item.get("destination", "personal")
        fmt = item.get("format", "insight")
        title = item.get("title", "")
        content = item.get("content", "")

        if not title or not content:
            continue

        if dest == "project" and project_root:
            write_project_doc(project_root, fmt, title, content, session_id, session_date)
            project_docs_written = True

        elif dest == "personal":
            tags = [knowledge_data.get("primary_theme", ""), fmt]
            upsert_atom(vault_path, title, content, [t for t in tags if t], session_id, session_date)

        elif dest == "team" and team_route:
            write_team_doc(team_vault, fmt, title, content, auto_promote_mode)

    # 3. Update project CLAUDE.md @imports if project docs were written
    if project_docs_written and project_root:
        update_project_claude_md(project_root)

    # 4. Rebuild atoms index
    build_atoms_index(vault_path)

    log(f"OK: {session_id} → {session_date.strftime('%Y-%m-%d')} · {project_name} · {knowledge_data.get('primary_theme', '?')} · {knowledge_data.get('outcome', '?')}")
    print(f"Written: {session_date.strftime('%Y-%m-%d')} · {project_name}")


if __name__ == "__main__":
    main()
