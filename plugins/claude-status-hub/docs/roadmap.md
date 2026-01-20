# Status Hub Roadmap

## Vision

Transform Status Hub from a **monitoring tool** into an **action hub**.

**The `/hub-ack` Paradigm:**
```
[1] Alert appears in statusline (single line, non-blocking)
[2] User continues working
[3] User types /hub-ack when ready
[4] System evaluates: What alert? What time? What's possible?
[5] Smart wizard offers best actions for THIS moment
[6] User selects action or dismisses
```

---

## v1.1.0 - Contextual Actions Foundation (Current PR)

**Focus**: GitHub PR actions via `/hub-ack`

### Features

- **GitHub PR Contextual Actions**
  - CI failure wizard with flaky detection (checks if test also fails on main)
  - Ready-to-merge wizard with per-org/repo merge strategy
  - Changes requested / review required wizards
  - New comments wizard
  - Merge conflict detection

- **CI Fix Assistance**
  - "Ask Claude to investigate" option
  - Fix loop mode (stay in session until CI passes)
  - Buildkite MCP integration for richer CI interactions

- **Merge Strategy Config**
  ```json
  {
    "github": {
      "mergeStrategy": {
        "default": "squash",
        "orgs": { "acme-corp": "aviator" },
        "repos": { "acme-corp/legacy": "merge-commit" },
        "customCommands": { "acme-corp/special": "gh pr comment {number} --body \"✨\"" }
      }
    }
  }
  ```

### Files
```
skills/hub-ack.md                 # Main dispatcher
skills/hub-ack-github-pr.md       # PR contextual actions
skills/hub-focus.md               # Focus mode (basic)
skills/hub-refresh-calendar.md    # Browser-based calendar refresh
commands/hub-ack.md               # Command entry point
commands/hub-focus.md             # Focus command
docs/config-schema.md             # Config reference
```

---

## v1.2.0 - Calendar Integration

**Focus**: Meeting alerts with time-aware wizards

### Features

- **Browser-Based Calendar** (Chrome MCP)
  - Read calendar via DOM from open Google Calendar tab
  - Works with corporate SSO/Okta

- **Meeting Alert Wizards** (time-aware responses)

  | Timing | Options |
  |--------|---------|
  | > 5min before | Join early, Set reminder, DM "running late" |
  | -5 to +5min | Join now, DM "5 min late", DM "10 min late" |
  | +5 to +30min | Join late, DM "joining shortly", Skip async |
  | > 30min after | Dismiss, DM "sorry I missed it" |

- **Context Handoff**
  ```
  📋 Session Context Handoff
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Project: fiale-claude-plugins
  Working on: auth/handler.ts (line 142)

  Recent activity:
  • Refactoring OAuth token refresh logic
  • Added retry mechanism for failed refreshes

  Unsaved changes:
  • auth/handler.ts (modified)
  • auth/types.ts (modified)
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ```

- **Standup Auto-Detection**
  - Pattern match: "standup" or "daily" in meeting title
  - Handles shifting meeting times

### Config
```json
{
  "calendar": {
    "connection": "chrome",
    "chrome": { "tabId": null },
    "alertMinutesBefore": 5,
    "alertWithDocsBefore": 10,
    "lateMessageTo": "organizer"
  }
}
```

### Files
```
skills/hub-ack-calendar.md        # Meeting contextual actions
skills/hub-refresh-calendar.md    # Calendar data refresh (exists)
```

---

## v1.3.0 - Smart Focus Mode

**Focus**: Calendar-aware focus with meeting conflict handling

### Features

- **Smart `/hub-focus`**
  ```
  🎯 Starting Focus Mode

     📅 Calendar check:
        • 10:30 AM - Quick sync with @bob (in 45 min)
        • 11:00 AM - Sprint Planning (in 1h 15m) ⚠️ recurring

     How long do you want to focus?
     [1] 30 minutes (no conflicts)
     [2] 1 hour (conflicts with Quick sync)
     [3] Until next meeting (45 min)
  ```

- **Meeting Conflict Handling**
  - Decline + DM organizer with custom message
  - Keep meeting (will interrupt focus)
  - Auto-decline non-recurring, ask for recurring

- **Notification Suppression**
  - Configure critical channels that still alert during focus
  - VIP DMs option

- **Slack Status Integration**
  - Auto-set "🎯 Deep focus until {end_time}"
  - Auto-expire when focus ends

### Config
```json
{
  "focus": {
    "enabled": true,
    "defaultDurationHours": 2,
    "meetingConflictHandling": "ask",
    "defaultDeclineMessage": "In deep focus mode, can we handle this async?",
    "criticalChannels": ["#incidents", "#outages"],
    "defaultStatus": "🎯 Deep focus until {end_time}",
    "setSlackStatus": true,
    "autoExpireStatus": true
  }
}
```

### Files
```
skills/hub-focus.md               # Enhanced focus mode
skills/hub-ack-focus.md           # Focus/break contextual actions
```

---

## v1.4.0 - Slack Integration

**Focus**: VIP message monitoring and smart replies

### Features

- **Browser-Based Slack** (Chrome MCP)
  - Read unreads/messages via DOM from open Slack tab
  - Works with corporate SSO

- **VIP Message Alerts**
  ```
  💬 New message from @sarah (Tech Lead) - 3 minutes ago

     "Quick question about the API - are we still planning
     to deprecate the v1 endpoints this quarter?"

     [1] Search knowledge sources for answer
     [2] "Let me check and get back in 10m"
     [3] "Can we discuss in our 1:1?"
     [r] Reply directly...
     [d] Mark as seen

     @sarah status: 🟢 Online
  ```

- **Knowledge Source Search**
  - Search Confluence, Notion, etc. for relevant info
  - Compose reply with found information

- **Message Digest**
  - Summarize walls of text (> 500 chars)
  - Digest multiple messages (> 3)

### Config
```json
{
  "slack": {
    "connection": "chrome",
    "chrome": { "tabId": null },
    "vipPeople": ["@boss", "@tech-lead"],
    "channels": ["#incidents", "#deployments"],
    "keywords": ["@here", "your-name"],
    "knowledgeSources": ["confluence:wiki", "notion:docs"],
    "digestWallsOfText": true,
    "digestMultipleMessages": true
  }
}
```

### Files
```
skills/hub-ack-slack.md           # Slack contextual actions
skills/hub-refresh-slack.md       # Slack data refresh
```

---

## v1.5.0 - Break Reminders & Wellness

**Focus**: Reactive break suggestions with calendar awareness

### Features

- **Break Reminder Alerts**
  ```
  ☕ Great focus session! 94 minutes of deep work.

     📊 Session stats:
        • Files edited: 4
        • Lines changed: +127 / -43
        • Commits: 2

     ⏰ Next: Sprint Planning at 2:00 PM (25 min)

     [1] Take break, set Slack "☕ Back at 1:55"
     [2] Take break, no status change
     [3] Keep working, remind me in 15m
     [d] Dismiss
  ```

- **Calendar-Aware Logic**
  - Only fire when: focus >= 75 min AND next meeting > 15 min away
  - No alerts if meeting starting in next 10 min

### Config
```json
{
  "focus": {
    "breakAfterMinutes": 75,
    "minBreakWindow": 15,
    "breakSlackStatus": "☕ Taking a break"
  }
}
```

---

## v1.6.0 - Jira Integration

**Focus**: Planning session kickoff from ticket assignments

### Features

- **Ticket Assignment Alerts**
  ```
  📋 PROJ-456 "Implement OAuth flow" - Assigned to you

     Status: To Do
     Sprint: Sprint 23
     Story Points: 5

     [1] Start planning session
         → /compact current context
         → Load ticket as planning context
         → Begin implementation planning

     [2] View ticket in browser
     [d] Dismiss
  ```

- **Browser-Based Jira** (or Atlassian Rovo MCP)

### Config
```json
{
  "jira": {
    "url": "https://yourcompany.atlassian.net",
    "connection": "browser",
    "offerPlanningSession": true
  }
}
```

### Files
```
skills/hub-ack-jira.md            # Jira contextual actions
skills/hub-refresh-jira.md        # Jira data refresh
```

---

## v2.0.0 - Consolidated Setup Wizard

**Focus**: Unified onboarding experience

### Features

- **5-Step Setup Wizard** (`/hub-setup`)
  1. Work Schedule (hours, days, timezone)
  2. Team Communication (channels, standup)
  3. GitHub Setup (PRs, merge strategy, CI assistance)
  4. Calendar & Meetings (connection, alert timing)
  5. Slack & Focus (VIPs, channels, break reminders)

- **Connection Architecture** (pluggable)
  ```json
  {
    "calendar": {
      "connection": "chrome"  // chrome | official | oauth-mcp | disabled
    },
    "slack": {
      "connection": "chrome"  // chrome | official | oauth-mcp | disabled
    }
  }
  ```

- **Official MCP Ready**
  - When Anthropic ships official MCPs, users just change `connection` type
  - No other config changes needed

---

## Future Considerations (Not Planned)

**Explicitly excluded from roadmap:**

- Sentry, Linear integrations
- Cross-session notifications
- Team dashboards
- Historical analytics / ML predictions
- Music contextual AI suggestions

These may be revisited based on user feedback.

---

## Connection Options Summary

| Service | Chrome MCP | Official MCP | OAuth MCP |
|---------|------------|--------------|-----------|
| Google Calendar | DOM read | Coming | nspady (DIY) |
| Slack | DOM read | Coming | korotovsky (DIY) |
| Jira | DOM read | - | Rovo MCP |
| GitHub | - | - | gh CLI (works) |

**Recommended path:**
1. **Now**: Chrome MCP (browser-based) - works with corporate SSO
2. **Alternative**: OAuth MCP (DIY token setup)
3. **Future**: Official MCPs from Anthropic - zero config

---

## Competitive Advantage

| Feature | Status Hub | Competition |
|---------|------------|-------------|
| Action from status | `/hub-ack` wizard | All statuslines are read-only |
| Alert-aware commands | Auto-target alerting items | Manual ID specification |
| Cross-service intelligence | PR + Slack + Calendar | Single-service tools |
| Corporate-friendly auth | Browser-based (no API keys) | Requires tokens/keys |
| Time-aware responses | Different options based on when you ack | Static responses |
