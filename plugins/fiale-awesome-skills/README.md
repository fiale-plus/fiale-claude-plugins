# fiale-awesome-skills

**Author: Pavel Fadeev / [fiale.plus](https://fiale.plus)**

Curated Claude Code skills for developer security and productivity.

**Platform: macOS only** (for now).

## Skills

| Skill | Command | What it does |
|-------|---------|-------------|
| supply-chain-hardening | `/supply-chain-hardening` | Audit and harden your system against supply chain attacks across npm, Python, Go, Rust, and Homebrew |

## Supply Chain Hardening

Prompted by the axios npm RAT and LiteLLM PyPI credential stealer (both March 2026), this skill applies system-level defenses that protect every project on your machine:

**Per-ecosystem hardening:**
- npm: `ignore-scripts=true`, `save-exact=true`, `audit=true` in `~/.npmrc` + Corepack
- Python: `require-virtualenv=true` in `~/.config/pip/pip.conf` + global site-packages cleanup
- Go: verify `sum.golang.org` checksum database is not disabled
- Rust: `cargo-audit` + sparse protocol in `~/.cargo/config.toml`
- Homebrew: third-party tap audit

**System-wide defenses:**
- Outbound firewall (LuLu / Little Snitch) — catches C2 callbacks from any ecosystem
- DNS filtering (NextDNS / 1.1.1.1 for Families) — blocks known malicious domains
- macOS Gatekeeper and SIP verification

All changes require user confirmation. Existing configs are backed up before modification. Rollback instructions included.

## Install

```bash
/plugin marketplace add fiale-plus/fiale-claude-plugins
/plugin install fiale-awesome-skills
/supply-chain-hardening
```

## License

MIT
