---
name: cli-create
description: Scaffold a new service CLI from templates
args: <name> <base-url> "<description>"
---

# /cli-create

Create a new standalone CLI for a web service.

## Arguments

- `<name>` — Service name (lowercase, e.g. `avanza`, `spotify`, `notion`)
- `<base-url>` — Service base URL (e.g. `https://www.avanza.se`)
- `<description>` — Short description in quotes

## Steps

1. **Create directory structure:**
   ```
   clis/<name>/
   ├── src/
   │   ├── cli.js
   │   ├── auth.js
   │   ├── api.js
   │   ├── format.js
   │   └── scrape.js
   ├── scripts/
   │   └── discover.js
   ├── docs/
   ├── package.json
   └── README.md
   ```

2. **Read and adapt templates** from `${CLAUDE_PLUGIN_ROOT}/templates/`:
   - `cli.js.tmpl` → `src/cli.js` — Replace `{{SERVICE}}`, `{{DESCRIPTION}}`, `{{COMMANDS}}`
   - `auth.js.tmpl` → `src/auth.js` — Replace `{{DOMAIN}}`, `{{DOMAINS_ARRAY}}`, `{{TOKEN_COOKIE_NAMES}}`
   - `api.js.tmpl` → `src/api.js` — Replace `{{BASE_URL}}`, `{{AUTH_IMPORT}}`
   - `format.js.tmpl` → `src/format.js` — Minimal skeleton, filled after API discovery
   - `package.json.tmpl` → `package.json` — Replace `{{NAME}}`, `{{DESCRIPTION}}`
   - `readme.md.tmpl` → `README.md` — Replace `{{NAME}}`, `{{DESCRIPTION}}`, `{{BASE_URL}}`

3. **Run `npm install`** in `clis/<name>/`

4. **Verify** `node src/cli.js --help` prints usage

5. **Next step:** Tell the user to run `/cli-discover <name> <url>` to map the service's API

## Example

```
/cli-create avanza https://www.avanza.se "Portfolio overview, holdings, and transaction history"
```

Creates `clis/avanza/` with all scaffolding, ready for API discovery.
