---
name: phase6-test
description: Verification workflow — auth test, API test, format test, install test
---

# Phase 6: Testing & Verification

Comprehensive verification workflow to ensure the CLI works end-to-end. Run all tests before considering the project complete.

## 1. Auth Test

Verify authentication layer extracts cookies and tokens correctly:

```bash
node -e "import('./src/auth.js').then(m => m.getServiceAuth()).then(a => console.log('token:', !!a.token, 'cookies:', a.cookieString.length, 'chars'))"
```

Expected output:
```
token: true cookies: 450 chars
```

If you see `token: false` or `cookies: 0 chars`, auth is broken. Check:
- Chrome profile path in auth.js
- Cookie domain filter
- Token extraction regex/selector

## 2. API Test

Run each command and verify it returns actual data, not errors:

```bash
# List commands - should return multiple items
node src/cli.js orders
node src/cli.js favorites
node src/cli.js restaurants --lat 60.17 --lon 24.94
node src/cli.js search "pizza"

# Detail commands - use actual IDs from above
node src/cli.js order <actual-order-id>
```

For each command:
- Verify markdown output appears on stdout
- Check stderr for any error messages
- Confirm data looks correct (real restaurant names, prices, dates)
- If you see "Authentication failed" or "No data found", investigate API endpoint

## 3. Format Test

Verify JSON mode produces valid, parseable JSON:

```bash
# Pipe each command through JSON parser
node src/cli.js orders --json | node -e "JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log('✓ valid JSON')"

node src/cli.js favorites --json | node -e "JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log('✓ valid JSON')"

node src/cli.js search "burger" --json | node -e "JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log('✓ valid JSON')"
```

Expected: Each prints `✓ valid JSON`

If you see `SyntaxError`, check format.js for:
- Missing commas
- Unescaped quotes in strings
- Invalid JSON.stringify usage

## 4. Error Handling Test

Verify clean error messages for invalid input:

```bash
# Missing required args
node src/cli.js order
# Expected: "mdbrowser: order command requires an order ID"

# Invalid command
node src/cli.js invalid-command
# Expected: help text or "Unknown command: invalid-command"

# Missing required flags
node src/cli.js restaurants
# Expected: error about missing --lat and --lon
```

For each error:
- Message should go to stderr, not stdout
- Should use `mdbrowser:` prefix (or your service name)
- Should be actionable (tell user what to fix)
- Should NOT show stack traces to end users

## 5. Fallback Test

Verify Puppeteer scraping fallback works when API fails:

```bash
# Temporarily break API in src/api.js
# Change API base URL to something invalid:
# const API_BASE = 'https://broken.invalid.com';

node src/cli.js orders
# Expected: stderr shows "servicename: API failed (...), trying scrape fallback..."
# Then stdout shows scraped data

# Restore API_BASE before proceeding
```

If fallback doesn't trigger:
- Check withFallback() wrapper exists in api.js
- Verify scrape.js exports the right functions
- Check puppeteer is in optionalDependencies

## 6. Install Test

Test global installation and command availability:

```bash
# Link package globally
npm link

# Run global command
myservice --help
myservice list --limit 3

# Test from different directory
cd /tmp
myservice favorites

# Return to project
cd -

# Verify binary works
which myservice
# Expected: /usr/local/bin/myservice or similar
```

Expected:
- Command works from any directory
- `--help` shows all commands
- Output same as `node src/cli.js`

## 7. Uninstall Test

Clean up after testing:

```bash
npm unlink
which myservice
# Expected: "myservice not found" or empty output
```

## Error Handling Checklist

For each command, verify it handles:
- Missing authentication (no Chrome cookies found)
- Network errors (timeout, DNS failure)
- API errors (4xx, 5xx responses)
- Empty results (no orders, no favorites)
- Malformed API responses (missing fields, wrong types)
- Invalid user input (bad coordinates, missing IDs)

Every error should:
- Write to stderr, not stdout
- Include helpful context (which field is missing, what to do next)
- Exit with non-zero code
- NOT leak stack traces or internal URLs

## Reporting Test Results

After running all tests, report:

```
✓ Auth test: cookies extracted, token found
✓ API test: all commands return data
✓ Format test: JSON output valid
✓ Error handling: clean messages, no stack traces
✓ Fallback test: scraping works when API fails
✓ Install test: global command works
✓ Uninstall: cleanup successful

All tests passed!
```

If any test fails:
- Report which test failed
- Include actual vs expected output
- Suggest specific fixes
- Don't mark phase complete until all pass

## Troubleshooting Common Failures

**"No cookies found"**
- User not logged into service in Chrome
- Wrong Chrome profile path
- Cookie domain filter too strict

**"API returned 401/403"**
- Token extraction failed
- Token expired (have user re-login)
- Wrong API endpoint or headers

**"API returned empty array"**
- Account has no data (no orders, no favorites)
- API pagination issue (missing limit/offset params)
- Wrong query parameters

**"Fallback never triggers"**
- API error not throwing (check try-catch in api.js)
- withFallback() not wrapping the function
- Scrape module import path wrong

**"JSON parse error"**
- Formatters returning markdown when json=true
- Missing `return JSON.stringify(data, null, 2)` guard
- Data contains unescaped quotes
