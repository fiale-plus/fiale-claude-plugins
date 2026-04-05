---
name: xurl
description: Cost-optimized X/Twitter workflows via xurl CLI with local sandbox testing. Posts, replies, search, timeline, engagement — all wrapped with spending guardrails, sandbox-first defaults, and pay-per-use cost awareness. Triggers on "/xurl", "post to X", "tweet", "post on twitter", "search X", "check mentions", "xurl post", "send a tweet", "check my timeline", "search twitter", "search and engage", "monitor engagement", "like from search", "review timeline", "batch like", "post and watch".
---

# xurl — Cost-Optimized X/Twitter Operations

Run the X API through xurl with aggressive cost optimization. Every penny counts — default to sandbox, confirm before spending, track costs in real time.

**Announce at start:** "Using xurl for cost-optimized X/Twitter operations."

## Security Rules (mandatory, from xurl SKILL.md)

These are non-negotiable. Violating any of them leaks credentials.

- **Never read, print, parse, or send `~/.xurl`** to the conversation. This file contains secrets.
- **Never use `--verbose` / `-v`** — it exposes auth headers/tokens in output.
- **Never use inline secret flags** in agent commands: `--bearer-token`, `--consumer-key`, `--consumer-secret`, `--access-token`, `--token-secret`, `--client-id`, `--client-secret`.
- **Credential registration is manual.** The user must run `xurl auth apps add ...` and `xurl auth oauth2` themselves, outside this session. Do not execute auth commands with secrets.
- To check auth state safely: `xurl auth status` (shows apps and token status without exposing secrets).

## Step 1: Environment Detection

Run silently — only surface issues, not successes:

```bash
which xurl 2>/dev/null && echo "xurl: installed" || echo "xurl: NOT FOUND"
which playground 2>/dev/null && echo "playground: installed" || echo "playground: NOT FOUND"
playground status 2>&1 || true
echo "API_BASE_URL=${API_BASE_URL:-'(not set)'}"
xurl auth status 2>&1 || true
cat /tmp/xurl-session-config.json 2>/dev/null || echo "no session config"
```

**Determine mode and act:**

- **Everything configured, session config exists**: skip setup entirely. Show one-line header and proceed with the user's request: `[SANDBOX MODE]` or `[LIVE MODE — limit: $X.XX]`
- **Playground running, no session config**: "Ready. Sandbox mode active. What would you like to do?"
- **Only xurl auth, no playground**: "No sandbox running. Live mode — real credits will be used."
- **`API_BASE_URL` set to localhost**: announce "Sandbox mode active via API_BASE_URL."
- **xurl not installed**: show install options and stop
- **Auth not configured**: show manual setup instructions and stop

**If xurl is not installed:**
```bash
brew install --cask xdevplatform/tap/xurl   # macOS
npm install -g @xdevplatform/xurl            # npm
go install github.com/xdevplatform/xurl@latest  # Go
```

**If playground is not installed** and user wants sandbox:
```bash
go install github.com/xdevplatform/playground/cmd/playground@latest
playground start    # serves at http://localhost:8080
playground refresh  # update OpenAPI spec cache (optional)
```

**If xurl auth is not configured**, tell the user to run these themselves (outside this session):
```
xurl auth apps add my-app --client-id <YOUR_ID> --client-secret <YOUR_SECRET>
xurl auth oauth2
```
They must set the redirect URI to `http://localhost:8080/callback` in the X Developer Console.

## Step 2: Sandbox Mode (playground)

When playground is running, **default to sandbox** for all operations. This costs $0.

Set the `API_BASE_URL` env var to redirect all xurl commands to the local playground:

```bash
export API_BASE_URL=http://localhost:8080
```

Now **all shortcut commands work against sandbox** — same syntax as live mode:

```bash
xurl post "Hello from sandbox!"
xurl search "query" -n 5
xurl user @handle
xurl timeline -n 20
xurl mentions -n 10
xurl read POST_ID
xurl reply POST_ID "Nice!"
xurl like POST_ID
```

Raw path access also works (playground accepts any auth token):

```bash
xurl /2/users/me
xurl -X POST /2/tweets -d '{"text":"sandbox post"}'
```

Prefix all sandbox output with `[SANDBOX]`.

### Cost preview

After testing a workflow in sandbox, show what it would cost on the real API:

```bash
# Simulated cost breakdown
curl -s http://localhost:8080/api/accounts/0/cost | jq '.'

# Current pricing rates (may reflect real X API rates)
curl -s http://localhost:8080/api/credits/pricing | jq '.'

# Usage breakdown by event type and request type
curl -s "http://localhost:8080/api/accounts/0/usage?interval=30days&groupBy=eventType" | jq '.'
curl -s "http://localhost:8080/api/accounts/0/usage?interval=30days&groupBy=requestType" | jq '.'
```

Present the cost preview to the user before they switch to live mode.

### State management and error simulation

```bash
# Save current state
curl -s http://localhost:8080/state/export > /tmp/xurl-playground-state.json

# Restore a saved state
curl -s -X POST -H "Content-Type: application/json" \
  -d @/tmp/xurl-playground-state.json http://localhost:8080/state/import

# Reset to fresh defaults
curl -s -X POST http://localhost:8080/state/reset

# Force-save state to disk
curl -s -X POST http://localhost:8080/state/save

# Simulate rate limiting to test error handling
curl -X PUT http://localhost:8080/config/update \
  -H "Content-Type: application/json" \
  -d '{"errors": {"enabled": true, "error_rate": 0.3, "error_type": "rate_limit"}}'

# Disable error simulation
curl -X PUT http://localhost:8080/config/update \
  -H "Content-Type: application/json" \
  -d '{"errors": {"enabled": false}}'
```

Web UI for browsing sandbox data: `http://localhost:8080/playground`

### Switching to live

When the user says "go live", "publish", "send it for real", or similar:

```bash
unset API_BASE_URL
echo "Now targeting: ${API_BASE_URL:-https://api.x.com}"
```

Show the mode banner: "[LIVE MODE] Switched. Session limit: $X.XX. Every write will show its cost inline."

**For any ambiguous write command** when mode is not explicit: default to sandbox if playground is running. If playground is not running, ask before going live — never silently default to live.

## Step 3: Live Mode

Prefix all live output with `[LIVE $X.XX]` showing the cost of each operation.

Use xurl shortcut commands against the real API:

```bash
xurl post "text"                    # $0.01
xurl reply POST_ID "text"          # $0.01
xurl quote POST_ID "text"          # $0.01
xurl read POST_ID                  # $0.005
xurl search "query" -n 10          # ~$0.005 × results (see note)
xurl user @handle                  # $0.01
xurl timeline -n 20                # ~$0.005 × results
xurl mentions -n 10                # ~$0.005 × results
xurl like POST_ID                  # $0.015
xurl repost POST_ID                # $0.015
xurl follow @handle                # $0.015
xurl bookmark POST_ID              # $0.015
xurl dm @handle "message"          # $0.015
xurl dms -n 10                     # ~$0.01 × results
xurl media upload file.jpg         # $0.01
```

Note: search/timeline/mentions billing per-post vs per-request is not publicly confirmed by X. The ~$0.005/result is community consensus. Use the lowest `-n` value that satisfies your need — it directly controls cost.

### Batch reads (major cost saver)

When reading 3+ posts, prefer the batch endpoint over individual reads:

```bash
# Individual: 10 reads × $0.005 = $0.05
xurl read ID1 && xurl read ID2 && ... # expensive

# Batch: up to 100 IDs in one request — significantly cheaper
xurl /2/tweets?ids=ID1,ID2,ID3,...,ID10
```

Community data suggests batch reads cost ~75% less than equivalent individual reads. Always prefer batch when reading multiple known post IDs.

### Write operations — compose + confirm

**Single writes**: inline confirmation — "[LIVE] Post: «{text}» ($0.01) — confirm?"

**Batch of same type** (user described the plan): one confirmation showing all items, total cost, and count — no per-item prompts. Example: "Like 5 posts ($0.075 total) — confirm?"

**First write of session**: always individual confirmation, even in batch context.

**Trust mode**: after the first confirmed write of a given type, offer "Skip confirmations for [likes/reposts/etc.] this session?" Store in `/tmp/xurl-session-config.json` under `trusted_actions`. The spending limit guardrail remains active regardless.

**Before batch reads** (search, timeline, mentions with -n > 10), show estimated cost inline — no separate confirmation.

Post IDs and full URLs both work: `xurl read https://x.com/user/status/123` extracts the ID automatically.

## Step 4: Spending Guardrails

Check for existing session config (already done in Step 1). If config exists with a spending limit, use it silently.

If no config exists AND user is in live mode, ask once inline:
> "No session limit set. Suggestions: $0.25 (casual), $2.00 (dev testing), $10.00 (automation). Default $0.25 — proceed? (or say an amount)"

Do not block sandbox operations for missing config — sandbox is always free.

Store in `/tmp/xurl-session-config.json`:
```json
{"spending_limit": 0.25, "spent": 0.0, "operations": 0, "trusted_actions": []}
```

This file persists across sessions until reboot (`/tmp`). Delete manually to reset.

Track spending locally using approximate costs:

| Operation | Approximate Cost |
|-----------|-----------------|
| Post read | $0.005 |
| Batch read (N posts) | ~$0.005 × N × 0.25 |
| User lookup | $0.010 |
| Post write | $0.010 |
| DM read | $0.010 |
| DM send | $0.015 |
| Engagement (like/follow/repost) | $0.015 |

These are community-sourced estimates. X does not publish per-endpoint rates publicly — the Developer Console is the only authoritative source, and prices can change without notice.

Update the tracker after every live API call. Guardrails:
- **80% of limit** → yellow warning: "Approaching spending limit ($X.XX / $Y.YY)"
- **100% of limit** → hard stop with options:
  1. Raise limit: "set limit $X.XX"
  2. Continue in sandbox (no further live writes)
  3. End session — show summary

The Developer Console spending limit is your absolute safety net — set it to your maximum (e.g., $10/month for casual use). The session limit here is your active-use guardrail. Both should be configured.

## Step 5: Common Workflows

### Post + Monitor Engagement
```
1. xurl post "..." → [LIVE $0.01] → note the post ID
2. Wait (user-specified interval)
3. xurl read {ID} → check public_metrics
4. If engagement exceeds user's threshold, reply or repost
```

### Search + Engage
```
1. xurl search "query" -n 10 → review results (sandbox first if available)
2. Go live: batch-confirm engagement (like/repost) in one prompt
3. Show summary: "Engaged with N posts, spent $X.XX"
```

### Timeline Review
```
1. xurl timeline -n 20 → surface results
2. User flags interesting posts
3. Batch-engage with flagged posts: one confirmation for the whole set
```

## Step 6: Error Recovery

**Playground not running (user expects sandbox):**
```
Sandbox not available — playground is not running.
  1. Start sandbox: `playground start` (~2s)
  2. Switch to live mode (real credits)
  3. Cancel
Which? (default: 1)
```

**Auth token expired mid-session (401):**
```
[LIVE] Auth error — token may have expired.
Run outside this session: xurl auth oauth2
Sandbox available in the meantime.
```

**Rate limited (429) — not billed:**
```
[LIVE] Rate limited (429) — this request was NOT billed.
Next retry: check x-rate-limit-reset header.
  1. Wait and retry automatically
  2. Reduce batch size (e.g., -n 5 instead of -n 20)
  3. Cancel
```

**Spending limit reached:**
```
[LIVE] Spending limit reached ($X.XX / $Y.YY).
  1. Raise limit: "set limit $Z.ZZ"
  2. Continue in sandbox (no further live writes)
  3. End session — show summary
Sandbox operations remain available.
```

## Step 7: Multi-Profile Setup

Show this recommendation **after the user's first successful live write**, not at session start.

If the user has only one app configured, suggest:

- **Playground** — local sandbox, unlimited free testing
- **dev** app — real API with $5 spending limit in Developer Console
- **prod** app — real API with production spending limit

The user registers apps manually (outside this session):
```
xurl auth apps add dev --client-id <ID> --client-secret <SECRET>
xurl auth apps add prod --client-id <ID> --client-secret <SECRET>
```

Switch: `xurl auth default dev` or `xurl --app prod post "..."`

## Step 8: Session Summary

When the user asks for a summary, or at session end:

1. If playground was used, show simulated cost:
   ```bash
   curl -s http://localhost:8080/api/accounts/0/cost | jq '.'
   ```

2. If live API was used, show real usage:
   ```bash
   xurl --auth app /2/usage/tweets?days=1
   ```

3. Show local tracker data from `/tmp/xurl-session-costs.json`

Present as:

```
## X API Session Summary
| Category | Count | Est. Cost |
|----------|-------|-----------|
| Sandbox ops | N | $0.00 (free) |
| Live reads | N | $X.XX |
| Live writes | N | $X.XX |
| Total live spend | — | $X.XX |
| Would-cost (sandbox→live) | — | $X.XX |
```

## Step 9: Quick Pick (no context)

If the user invokes `/xurl` with no argument and no prior context:

```
What would you like to do?
  1. Post / reply / quote
  2. Search X
  3. Check timeline or mentions
  4. Engage with posts (like, repost, bookmark)
  5. Send or read DMs
  6. Check usage and session costs
  7. Set up or review xurl configuration
```

## Billing Reference

**24h UTC deduplication**: Same resource requested multiple times within one UTC day is billed once. Note: reads of the same post on different UTC days each incur a separate charge.

**Only successful responses are billed.** Failed requests (4xx, 5xx) cost nothing. Rate-limited (429) requests are not billed.

**Monthly cap**: 2M post reads. Enterprise ($42K+/mo) required beyond that.

**Spending limits**: Set in the Developer Console to prevent runaway costs. Auto-recharge tops up when balance is low.

**xAI credit rewards**: 10% back at $200+ cumulative spend, 15% at $500+, 20% at $1,000+. Only meaningful at $200+/month — solo/casual users won't hit this threshold.

### Rate Limits (separate from billing)

| Endpoint | Per App / 15min | Per User / 15min |
|----------|----------------|-----------------|
| Post lookup | 450 | 900 |
| Search recent | 450 | 300 |
| Post create | 10K / 24h | 100 / 15min |
| Like | — | 50 / 15min, 1K / 24h |
| User lookup | 300 | 900 |

On 429: back off and retry. Rate-limited requests are not billed.

### Reference Links

For up-to-date information (pricing may change):
- Pricing: https://docs.x.com/x-api/getting-started/pricing
- Usage & billing: https://docs.x.com/x-api/fundamentals/post-cap
- Rate limits: https://docs.x.com/x-api/fundamentals/rate-limits
- Usage API: https://docs.x.com/x-api/usage/introduction
- xurl: https://github.com/xdevplatform/xurl
- Playground: https://github.com/xdevplatform/playground
- Docs source: https://github.com/xdevplatform/docs
