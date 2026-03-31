---
name: supply-chain-hardening
description: Audit and harden your macOS dev machine against software supply chain attacks across npm, Python/pip/uv, Go, Rust/Cargo, and Homebrew. Applies global config hardening, install-time script blocking, outbound firewall guidance, and DNS filtering. System-level protections, not repo-level. Triggers on "/supply-chain-hardening", "harden supply chain", "supply chain security", "secure my system", "protect against malicious packages", "harden my dev machine".
---

# Supply Chain Hardening (macOS)

System-level defense against software supply chain attacks. Protects every project on the machine by hardening global configs, blocking install-time code execution, and setting up OS-level defenses.

The attack pattern is consistent across ecosystems: compromised maintainer credentials or CI/CD pipeline, poisoned version published, install-time code execution (postinstall in npm, .pth files in Python, build.rs in Rust, init() functions in Go), payload delivery. The defenses mirror this: block install-time execution globally, pin versions, detect anomalous outbound connections, filter known-bad domains.

**Announce at start:** "Using supply-chain-hardening to audit and secure your system."

## Step 1: Audit current state

Run these checks in parallel to detect installed ecosystems and existing hardening:

```bash
# Package managers
which npm node yarn pnpm bun 2>/dev/null
which python3 pip3 uv uvx pipx 2>/dev/null
which go 2>/dev/null
which cargo rustup 2>/dev/null
which brew 2>/dev/null
```

```bash
# Existing hardening
cat ~/.npmrc 2>/dev/null
cat ~/.config/pip/pip.conf 2>/dev/null || cat ~/.pip/pip.conf 2>/dev/null
go env GONOSUMDB GOFLAGS GOMODCACHE 2>/dev/null
cat ~/.cargo/config.toml 2>/dev/null
corepack --version 2>/dev/null
ls /Applications/LuLu.app /Applications/Little\ Snitch.app 2>/dev/null
spctl --status 2>/dev/null
csrutil status 2>/dev/null
pip3 list --user --format=columns 2>/dev/null | wc -l
brew tap 2>/dev/null
```

Present findings as a status table:

| Layer | Status | Issues |
|-------|--------|--------|
| npm global config | hardened / exposed / N/A | details |
| Python pip config | hardened / exposed / N/A | details |
| Go module verification | hardened / exposed / N/A | details |
| Rust/Cargo | hardened / exposed / N/A | details |
| Corepack | enabled / disabled / N/A | details |
| Outbound firewall | installed / missing | details |
| Global Python packages | count (0 = clean) | details |
| macOS Gatekeeper/SIP | enabled / disabled | details |

## Step 2: Apply hardening per ecosystem

**Before writing any config file**, show the user the exact content and path. If the file already exists, show a diff. Ask for confirmation before applying. Never overwrite without consent — the user may have custom settings.

**Backup existing configs** before modifying — always verify the backup was created before proceeding:
```bash
cp ~/.npmrc ~/.npmrc.backup.$(date +%s) 2>/dev/null && echo "backup created" || echo "no existing file"
```

### npm / Node.js

**File**: `~/.npmrc`

```ini
# Block lifecycle scripts globally (postinstall, preinstall, install)
# Override per-project: add ignore-scripts=false to a project's local .npmrc
ignore-scripts=true

# Pin exact versions on install
save-exact=true

# Auto-audit on install
audit=true
```

**Corepack** — pins the package manager binary:
```bash
corepack enable
```

**Trade-offs — explain to the user before applying**: `ignore-scripts=true` breaks packages that need postinstall (esbuild, electron, sharp). The user must choose:
1. Per-project `.npmrc` with `ignore-scripts=false` in trusted repos (lower friction, opt-in risk)
2. Global off, manual `npm rebuild <pkg>` when needed (more secure, higher friction)

Let the user decide — do not choose for them.

**Verify**:
```bash
npm config get ignore-scripts  # should be true
npm config get save-exact      # should be true
corepack --version             # should return version
```

### Python / pip / uv

**Detect active pip config location first** — the legacy `~/.pip/pip.conf` takes precedence if it exists, so operate on whichever file is active:
```bash
PIP_CONF=$([ -f ~/.pip/pip.conf ] && echo ~/.pip/pip.conf || echo ~/.config/pip/pip.conf)
echo "Active pip config: $PIP_CONF"
```

**Backup first** (using the detected path):
```bash
cp "$PIP_CONF" "${PIP_CONF}.backup.$(date +%s)" 2>/dev/null && echo "backup created" || echo "no existing file"
```

**File**: write to the detected `$PIP_CONF` path (create parent directory if needed: `mkdir -p "$(dirname "$PIP_CONF")")`)

```ini
[global]
# Refuse to install outside a virtualenv
# .pth files in site-packages execute on EVERY python3 invocation (LiteLLM attack vector)
require-virtualenv = true
```

**Clean up global site-packages** if `pip3 list --user` shows packages:
```bash
pip3 list --user --format=columns

# Migrate CLI tools to isolated venvs:
uv tool install <tool>   # preferred if uv is available
# or: pipx install <tool>

# Then remove from global:
pip3 uninstall <package>
```

**Verify**:
```bash
pip3 config get global.require-virtualenv  # should return: true
pip3 list --user       # should be empty or minimal
```

### Go

Go has the strongest supply chain defaults — `sum.golang.org` verifies module checksums automatically. Verify no one has weakened them:

```bash
go env GONOSUMDB      # MUST be empty — a non-empty value exempts modules from checksum verification
go env GOFLAGS        # must NOT contain -insecure
```

**Fix if weakened**:
```bash
go env -w GONOSUMDB=""
```

If `GONOSUMDB` is scoped to specific private patterns (e.g., `company.internal/*`), that's legitimate — just verify it's not wildcarded.

### Rust / Cargo

**Install cargo-audit** for vulnerability scanning:
```bash
cargo install cargo-audit
```

**`~/.cargo/config.toml`** (create if needed):
```toml
[net]
# Route git fetches through system git binary (better SSH/proxy auth support)
git-fetch-with-cli = true

[registries.crates-io]
# Sparse protocol — faster and avoids cloning the full crates.io index
protocol = "sparse"
```

**Verify**:
```bash
cargo audit --version  # should return version
```

### Homebrew

Homebrew-core formulas are code-reviewed, but third-party taps are not.

**Audit taps**:
```bash
brew tap
```

Anything beyond `homebrew/core` and `homebrew/cask` deserves scrutiny. Prefer casks over formulas when both exist — casks install pre-built binaries without running build scripts.

## Step 3: System-wide defenses

These protect across ALL ecosystems.

### Outbound firewall

Every supply chain payload needs to call home. An outbound firewall catches this regardless of ecosystem.

- **LuLu** (free, open-source): https://objective-see.org/products/lulu.html
- **Little Snitch** (paid, polished UI)

**Install via Homebrew** (if no outbound firewall detected in audit):
```bash
brew install --cask lulu
open /Applications/LuLu.app
```

After install the user must manually approve in System Settings:
1. **System Extension** — Privacy & Security > scroll down > Allow
2. **Network Filter** — click Allow when prompted

Configure to alert on new outbound connections from `node`, `python3`, `cargo`, `go`, `bun`. Approve known destinations (registry.npmjs.org, pypi.org, crates.io, proxy.golang.org, github.com).

### DNS filtering

Blocks known malicious domains at the network layer.

- **NextDNS** (free tier): https://nextdns.io — enable "Threat Intelligence Feeds" and "Newly Registered Domains"
- **1.1.1.1 for Families** (free, zero setup): Cloudflare's malware-blocking DNS at `1.1.1.3`

### macOS integrity

```bash
spctl --status     # Gatekeeper — should say "assessments enabled"
csrutil status     # SIP — should say "enabled"
```

If either is disabled, flag as a critical issue.

## Step 4: Verify and report

Re-run the audit from Step 1 and present before/after comparison.

```bash
npm config get ignore-scripts  # expect: true
pip3 config get global.require-virtualenv  # expect: true
go env GONOSUMDB  # expect: empty
corepack --version  # expect: version number
```

## Final report format

```markdown
## Supply Chain Hardening Report — [date]

### Applied
- [x] npm: ignore-scripts, save-exact, audit
- [x] Python: require-virtualenv
- [x] Go: sumdb verification confirmed intact
- [x] Corepack: enabled
- [x] Cargo: cargo-audit installed, sparse protocol enabled

### Requires manual approval (after automated install)
- [ ] Approve LuLu System Extension + Network Filter in System Settings
- [ ] Configure DNS filtering (NextDNS or 1.1.1.3)
- [ ] Migrate N global pip packages to `uv tool install`

### Not applicable
- [ ] Rust: not installed on this system
```

## Rollback

```bash
# Restore backed-up configs (check actual filenames with: ls ~/.npmrc.backup.* )
cp ~/.npmrc.backup.<timestamp> ~/.npmrc
cp ~/.config/pip/pip.conf.backup.<timestamp> ~/.config/pip/pip.conf

# Or remove entirely to revert to defaults
rm ~/.npmrc
rm ~/.config/pip/pip.conf
corepack disable
go env -u GONOSUMDB
```

Tell the user about rollback options before applying any changes.

## Maintenance

Re-run `/supply-chain-hardening` quarterly or after major ecosystem incidents.
