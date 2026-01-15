# Plan: Make fiale-plus/claude-code-plugins Baseline OSS Ready

## Current State Audit

**Repository:** https://github.com/fiale-plus/claude-code-plugins

### What's Present
- [x] Public visibility
- [x] MIT License
- [x] README.md (minimal)
- [x] Description set
- [x] Issues enabled
- [x] Dependabot alerts enabled
- [x] Security advisories enabled

### What's Missing/Not Configured

| Category | Item | Status |
|----------|------|--------|
| **Branch Protection** | Main branch protection | ❌ Not configured |
| **Discoverability** | Repository topics | ❌ Not set |
| **Community** | Code of Conduct | ❌ Missing |
| **Community** | CONTRIBUTING.md | ❌ Missing |
| **Community** | Issue templates | ❌ Missing |
| **Community** | PR template | ❌ Missing |
| **Community** | Discussions | ❌ Disabled |
| **Security** | SECURITY.md | ❌ Missing |
| **Security** | Private vulnerability reporting | ❌ Disabled |
| **Security** | Secret scanning | ❌ Disabled |

---

## Implementation Plan (Settings Only)

### 1. Branch Protection for `main`
**Location:** Settings → Branches → Add branch ruleset

Configure:
- Require pull request before merging
- Require 1 approval minimum
- Block force pushes
- Block deletions
- **No CI/status checks** (not configured yet)

### 2. Add Repository Topics
**Location:** Main page → About section → gear icon

Suggested topics:
- `claude`
- `claude-code`
- `anthropic`
- `plugins`
- `cli`
- `developer-tools`

### 3. Enable Discussions
**Location:** Settings → General → Features → Discussions

Enable for community Q&A and announcements.

### 4. Enable Security Features
**Location:** Settings → Code security and analysis

- Enable private vulnerability reporting
- Enable secret scanning alerts

### 5. Add Community Files (via GitHub UI)

| File | Add via | Notes |
|------|---------|-------|
| CODE_OF_CONDUCT.md | Community Standards → Add | Use Contributor Covenant |
| CONTRIBUTING.md | Community Standards → Add | Brief guidelines |
| SECURITY.md | Security → Set up security policy | Vulnerability reporting info |
| Issue templates | Settings → Features → Set up templates | **Minimal:** Bug + Feature only |
| PR template | Community Standards → Add | Simple checklist |

---

## Verification

After implementation, verify:
1. Community Standards page shows 100% green checklist
2. Main branch shows "protected" badge
3. Security tab shows all features enabled
4. Topics appear on main repo page
5. Discussions tab is visible in nav

---

## Notes

- This plan covers **settings only** per user request
- Code/README improvements deferred to later
- All changes done via GitHub web UI (no code commits needed for settings)
