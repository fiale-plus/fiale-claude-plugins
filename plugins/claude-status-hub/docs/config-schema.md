# Status Hub Config Schema

Reference for `~/.claude/status-config.json` structure.

## Full Schema

```json
{
  "contextDisplay": "bar",
  "contextAlertThreshold": 80,

  "workSchedule": {
    "startHour": 9,
    "endHour": 17,
    "workDays": ["mon", "tue", "wed", "thu", "fri"],
    "timezone": "America/New_York"
  },

  "team": {
    "channel": "#engineering-team",
    "standupChannel": "#daily-standup",
    "standupDetection": "auto"
  },

  "github": {
    "trackAllPRs": true,
    "repos": [],
    "checkMainForFlaky": true,
    "offerClaudeInvestigation": true,
    "mergeStrategy": {
      "default": "squash",
      "orgs": {
        "acme-corp": "aviator"
      },
      "repos": {
        "acme-corp/legacy": "merge-commit"
      },
      "customCommands": {
        "acme-corp/special": "gh pr comment {number} --body \"✨\""
      }
    },
    "alerts": {
      "ciFailures": true,
      "reviewDecisions": true,
      "comments": true,
      "conflicts": true,
      "mergeReady": true
    }
  },

  "calendar": {
    "connection": "auto",
    "chrome": { "tabId": null },
    "playwright": { "profile": "default", "headless": false },
    "alertMinutesBefore": 5,
    "alertWithDocsBefore": 10,
    "lateMessageTo": "organizer",
    "lastSeen": {
      "nextMeeting": null
    }
  },

  "slack": {
    "connection": "auto",
    "workspace": "mycompany.slack.com",
    "chrome": { "tabId": null },
    "playwright": { "profile": "default", "headless": false },
    "vipPeople": ["@boss", "@tech-lead"],
    "channels": ["#incidents", "#deployments"],
    "keywords": ["@here", "your-name"],
    "knowledgeSources": ["confluence:wiki", "notion:docs"],
    "digestWallsOfText": true,
    "digestMultipleMessages": true
  },

  "jira": {
    "url": "https://yourcompany.atlassian.net",
    "connection": "browser",
    "offerPlanningSession": true
  },

  "focus": {
    "enabled": true,
    "defaultDurationHours": 2,
    "meetingConflictHandling": "ask",
    "defaultDeclineMessage": "In deep focus mode, can we handle this async?",
    "criticalChannels": ["#incidents", "#outages"],
    "defaultStatus": "🎯 Deep focus until {end_time}",
    "breakAfterMinutes": 75,
    "minBreakWindow": 15,
    "setSlackStatus": true,
    "autoExpireStatus": true
  },

  "foreground": [],
  "background": {
    "service": null,
    "tabId": null
  }
}
```

## Section Details

### workSchedule

Working hours configuration for time-aware features.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `startHour` | number | 9 | Work day start hour (0-23) |
| `endHour` | number | 17 | Work day end hour (0-23) |
| `workDays` | string[] | ["mon"..."fri"] | Working days |
| `timezone` | string | auto-detected | IANA timezone |

### github.mergeStrategy

Per-org/repo merge strategy configuration.

**Resolution order**: `repos[owner/repo]` > `orgs[owner]` > `default`

| Strategy | gh Command |
|----------|------------|
| `squash` | `gh pr merge --squash` |
| `rebase` | `gh pr merge --rebase` |
| `merge-commit` | `gh pr merge --merge` |
| `aviator` | `gh pr comment --body "/aviator merge"` |
| custom | Defined in `customCommands` |

### Continuous Check Handling

Merge services like Aviator and Mergify run checks that stay pending until triggered (e.g., `/aviator merge`). These "continuous" or "eternal" checks are detected by name pattern and excluded from the blocking check count.

**Built-in patterns**: `aviator`, `mergify`, `merge-when-ready` (case-insensitive)

**Behavior**:
- When all blocking checks pass but continuous checks are running: shows `🚀:ready ⏳1`
- Alerts trigger when blocking checks finish (transition from `~` to `🚀`)
- Continuous checks don't prevent "ready to merge" status

### Auto-Merge

PRs can be configured for automatic merging when they become ready. Set `autoMerge: true` on a foreground PR item.

**When autoMerge is enabled:**
- The statusline shows `🔁` indicator (e.g., `🚀🔁` or `2🔁 PRs`)
- When PR is ready (approved + checks pass + mergeable), the configured merge strategy executes automatically
- Works for both: PRs that transition to ready, and PRs already ready when autoMerge is enabled
- Each PR is only auto-merged once (tracked via `lastSeen.autoMergeAttempted`)
- Actions are logged to `~/.claude/status-hub.log`

**No auto-merge if:**
- `autoMerge: false` or not set
- Auto-merge was already attempted for this PR

**Strategy resolution:** Uses `github.mergeStrategy` config (repos > orgs > default)

### calendar

Calendar integration with automatic connection detection.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `connection` | string | "auto" | "auto", "chrome", "playwright", "disabled" |
| `chrome.tabId` | number | null | Browser tab ID for Google Calendar (Chrome MCP) |
| `playwright.profile` | string | "default" | Playwright browser profile name |
| `playwright.headless` | boolean | false | Run Playwright in headless mode |
| `alertMinutesBefore` | number | 5 | Alert timing for regular meetings |
| `alertWithDocsBefore` | number | 10 | Alert timing for meetings with attachments |
| `lateMessageTo` | string | "organizer" | Who to DM if running late |

**Connection Priority** (when `auto`): Chrome MCP > Playwright

### slack

Slack integration with automatic connection detection.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `connection` | string | "auto" | "auto", "mcp", "chrome", "playwright", "api", "disabled" |
| `workspace` | string | null | Slack workspace URL (e.g., "mycompany.slack.com") |
| `chrome.tabId` | number | null | Browser tab ID for Slack (Chrome MCP) |
| `playwright.profile` | string | "default" | Playwright browser profile name |
| `playwright.headless` | boolean | false | Run Playwright in headless mode |
| `vipPeople` | string[] | [] | DMs from these people trigger alerts |
| `channels` | string[] | [] | New messages in these channels trigger alerts |
| `keywords` | string[] | [] | Messages containing these trigger alerts |
| `knowledgeSources` | string[] | [] | Sources for reply assistance |

**Connection Priority** (when `auto`): Slack MCP > Chrome MCP > Playwright > API (xoxc+d)

**Connection Methods:**
- `mcp`: Official Slack MCP plugin (best for non-corporate setups)
- `chrome`: Claude-in-Chrome extension with open Slack tab
- `playwright`: Headless browser automation via Playwright MCP
- `api`: Legacy xoxc+d cookie method (unreliable, last resort)

### focus

Focus time and break reminder settings.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | true | Enable focus mode features |
| `defaultDurationHours` | number | 2 | Default focus session length |
| `meetingConflictHandling` | string | "ask" | "ask", "auto-decline", "never" |
| `criticalChannels` | string[] | [] | Channels that still alert during focus |
| `breakAfterMinutes` | number | 75 | Trigger break reminder after N minutes |
| `minBreakWindow` | number | 15 | Minimum gap before next meeting for break |

### foreground[]

Array of monitored items. Each item type has specific fields:

#### GitHub PR Item

```json
{
  "owner": "acme-corp",
  "repo": "my-project",
  "number": 123,
  "autoMerge": true,
  "lastSeen": {
    "commentsCount": 5,
    "state": "OPEN",
    "reviewDecision": "APPROVED",
    "checksFailed": 0,
    "checksPending": 0,
    "mergeable": "MERGEABLE"
  },
  "hasAlert": false
}
```

#### Calendar Item

```json
{
  "service": "calendar",
  "lastSeen": {
    "nextMeeting": {
      "title": "Daily Standup",
      "startTime": 1234567890000,
      "meetingLink": "https://meet.google.com/...",
      "organizer": "alice@company.com"
    }
  },
  "hasAlert": false
}
```

#### Slack Item

```json
{
  "service": "slack",
  "workspace": "acme-corp",
  "tabId": 12345,
  "lastSeen": {
    "unreadCount": 0
  },
  "hasAlert": false
}
```

#### Finance Item

```json
{
  "service": "finance",
  "symbols": ["NASDAQ:AAPL"],
  "alertThreshold": {
    "changePercent": 5
  },
  "lastSeen": {
    "NASDAQ:AAPL": { "price": 248.51, "change": -2.75 }
  },
  "hasAlert": false
}
```

## Migration

When upgrading from older config versions, the skills handle missing fields gracefully with defaults.
