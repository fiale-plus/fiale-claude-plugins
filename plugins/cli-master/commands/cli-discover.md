---
name: cli-discover
description: Discover a service's API endpoints via Chrome CDP network interception
args: <name> <url>
---

# /cli-discover

Launch a headful browser with Chrome cookies, intercept network traffic, and map JSON API endpoints for a service.

## Arguments

- `<name>` — Service name (must match existing `clis/<name>/` directory)
- `<url>` — Starting URL to navigate to (e.g. `https://www.avanza.se/min-ekonomi/konton.html`)

## Steps

1. **Verify** `clis/<name>/` exists and has `src/auth.js`

2. **Run discovery script:**
   ```bash
   node clis/<name>/scripts/discover.js --url <url>
   ```
   This opens a headful Chrome with injected cookies. The user browses key flows while the script captures API calls.

3. **Review captured endpoints** in `clis/<name>/docs/api-discovery.json`:
   - Identify the API base URL(s)
   - Identify the auth mechanism (Bearer token, cookie, custom header)
   - Map endpoints to CLI commands
   - Note query parameters and response shapes

4. **Update `src/api.js`** with discovered endpoints:
   - Set correct `BASE_URL` and `CONSUMER_API` constants
   - Map each endpoint to an exported function
   - Use correct auth headers

5. **Update `src/auth.js`** if a specific token cookie was identified:
   - Set the token cookie name(s)
   - Handle token extraction

6. **Next step:** Build out `src/format.js` with formatters for each command, then test with `node src/cli.js <command>`

## Tips

- Navigate to pages that trigger the API calls you want to capture (order history, profile, search results)
- The script filters out analytics, fonts, images, and other non-API traffic
- Press Ctrl+C to stop recording early
- Run multiple times if needed — results append to the discovery file

## Example

```
/cli-discover avanza https://www.avanza.se/min-ekonomi/konton.html
```
