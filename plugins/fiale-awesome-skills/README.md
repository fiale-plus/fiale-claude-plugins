# fiale-awesome-skills

**Author: Pavel Fadeev / [fiale.plus](https://fiale.plus)**

Curated Claude Code skills for developer security and productivity.

## Skills

| Skill | Command | What it does |
|-------|---------|-------------|
| supply-chain-hardening | `/supply-chain-hardening` | Audit and harden your system against supply chain attacks across npm, Python, Go, Rust, and Homebrew |
| xurl | `/xurl` | Cost-optimized X/Twitter workflows via xurl CLI with local sandbox testing |

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

## xurl

Post, reply, search, and engage on X/Twitter through [xurl](https://github.com/xdevplatform/xurl) — the official X CLI — with pay-per-use cost awareness baked in.

**Two operating modes:**

| Mode | Cost | How |
|------|------|-----|
| **Sandbox** | $0 | Local [playground](https://github.com/xdevplatform/playground) server simulates the full X API v2 |
| **Live** | Real credits | Compose → confirm → post. Spending guardrails with configurable limits |

**Cost optimization features:**
- Defaults to sandbox when playground is running — unlimited free testing
- Cost preview: see what sandbox operations would cost before going live
- Configurable session spending limits (default $0.25)
- Estimated cost shown before every live write operation
- Real usage tracking via X API's `/2/usage/tweets` endpoint
- 24h UTC deduplication awareness (same resource = 1 charge per day)

**Pay-per-use pricing** (community-sourced estimates, check Developer Console for authoritative rates):

| Operation | Cost |
|-----------|------|
| Post read | $0.005 |
| User lookup | $0.010 |
| Post write | $0.010 |
| DM send | $0.015 |
| Like / follow / repost | $0.015 |

**Prerequisites:**
- [xurl](https://github.com/xdevplatform/xurl) CLI installed (`brew install --cask xdevplatform/tap/xurl`)
- X Developer account with app credentials (registered manually)
- Optional: [playground](https://github.com/xdevplatform/playground) for free sandbox testing

## Install

```bash
/plugin marketplace add fiale-plus/fiale-claude-plugins
/plugin install fiale-awesome-skills
/supply-chain-hardening
/xurl
```

## License

MIT
