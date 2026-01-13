---
name: hub-refresh-sentry
author: user
created: 2026-01-12
source: mcp
---

# Refresh Sentry

Track unresolved issues from Sentry for the configured project.

## Config Structure

Each Sentry item in `foreground[]` should have:
```json
{
  "service": "sentry",
  "organizationSlug": "fiale",
  "projectSlug": "my-awesome-project",
  "regionUrl": "https://de.sentry.io",
  "lastSeen": {"issueCount": 0},
  "hasAlert": false
}
```

## Data Source

Use Sentry MCP tools:
```
mcp__plugin_sentry_sentry__search_issues(
  organizationSlug: item.organizationSlug,
  projectSlugOrId: item.projectSlug,
  regionUrl: item.regionUrl,
  naturalLanguageQuery: "unresolved issues from last 24 hours",
  limit: 10
)
```

## Extraction

From the search results:
- Count total unresolved issues
- Get the most recent issue title

## Alert Detection

Set `hasAlert: true` if:
- `issueCount > lastSeen.issueCount` (new issues appeared)

## Output Format

Return for bridge:
```json
{
  "site": "sentry",
  "icon": "🔥",
  "title": "<count> issues",
  "detail": "<latest issue title truncated>",
  "hasAlert": <true if new issues>
}
```

Icon options:
- `🔥` = has unresolved issues
- `✓` = no issues
