---
name: hub-custom
description: Set up tracking for a custom service not built into the hub
argument-hint: <service-name>
---

# Hub Custom - Setup Tracking for Unknown Services

Set up status tracking for any service by finding or creating an appropriate refresh skill.

## Parse Argument

Extract `<service-name>` from the argument (e.g., "sentry", "linear", "jira").

If no service name provided, ask: "What service do you want to track?"

## Step 1: Check Existing Skills

Before doing anything, check if a skill already exists:

```bash
ls ${CLAUDE_PLUGIN_ROOT}/skills/hub-refresh-<service>*.md 2>/dev/null
```

If found:
- Say "Found existing skill: [filename]. Service is ready to track."
- Ask if they want to add it to monitoring now

## Step 2: Present Choice

Use AskUserQuestion:

```
question: "How would you like to set up tracking for <service>?"
header: "Setup"
options:
  - label: "AI-powered (Recommended)"
    description: "I'll search for integrations and figure out the best approach"
  - label: "Guide me"
    description: "I'll describe what I want to track in my own words"
```

## Path A: AI-Powered Detection

### A1. Check Installed MCPs

Look for relevant MCPs in the system:
- Check `~/.claude/mcp.json` for installed servers
- Check if any MCP name contains the service name
- If found: "You have [mcp-name] installed. I can use this to track <service>."

### A2. Search for Available Integrations

If no MCP found:
```
Web search: "<service> MCP server Claude"
Web search: "<service> Claude Code plugin"
```

If results found:
- Present options to user
- Offer to help install
- After install, create skill that uses the MCP

### A3. Browser Integration

If no MCP available or user declines:

1. Ask: "Do you have <service> open in a browser tab?"
2. If yes:
   - Get tabs via `mcp__claude-in-chrome__tabs_context_mcp`
   - Find the service tab
   - Take screenshot: `mcp__claude-in-chrome__computer` action=screenshot
   - Read page structure: `mcp__claude-in-chrome__read_page`
3. Analyze the page:
   - Look for notification badges, counters, status indicators
   - Identify elements that would be useful to track
4. Present findings:
   - "I found these trackable elements: [list]"
   - "Which would you like to monitor?"
5. Generate skill file with selected elements

### A4. API-Based Solution

If browser integration not possible:
- Ask if service has an API
- If yes: Generate a skill that uses Bash to call the API
- If no: Suggest manual tracking or give up gracefully

## Path B: User-Guided Setup

1. Ask: "What would you like to track? Describe it in your own words."
   - Example: "I want to know when there are new unresolved errors"
   - Example: "Track the count of open issues assigned to me"

2. Ask clarifying questions one at a time:
   - "Where does this information appear?" (browser tab, API, CLI tool)
   - "How should I detect changes?" (count increases, status changes, new items)
   - "When should I alert you?" (any change, threshold, specific values)

3. Based on answers, determine approach:
   - Browser: Ask for tab, analyze page
   - API: Ask for endpoint/auth details
   - CLI: Ask for command to run

4. Generate skill file

## Generate Skill File

Create `${CLAUDE_PLUGIN_ROOT}/skills/hub-refresh-<service>.user.md`:

```markdown
---
name: hub-refresh-<service>
author: user
created: <today's date>
source: <browser|mcp|api|cli>
---

# Refresh <Service>

## Data Source
<How to get the data - tab ID, MCP call, API endpoint, CLI command>

## Extraction
<What to extract and how>

## Alert Detection
<When hasAlert should be true>

## Output Format
Return:
- icon: <appropriate icon>
- title: <what to show>
- detail: <secondary info>
- hasAlert: <true/false based on detection>
```

## Configure Permissions

After generating the skill, automatically detect and add required permissions to `~/.claude/settings.json`.

### Permission Detection

Scan the generated skill content for tool usage:

1. **MCP tools** - Find patterns like `mcp__<server>__<tool>`
   - Extract the full tool name (e.g., `mcp__plugin_sentry_sentry__search_issues`)
   - Add as permission WITHOUT parentheses: `"mcp__plugin_sentry_sentry__search_issues"`

2. **CLI commands** - Find bash/shell commands
   - `gh pr`, `gh issue` → `"Bash(gh pr view:*)"`
   - `curl <url>` → `"Bash(curl <domain>:*)"`
   - Custom CLI → `"Bash(<command>:*)"`

3. **Browser tools** - Find `mcp__claude-in-chrome__*` patterns
   - These require active browser tab
   - Warn: "Browser-based tracking only works during foreground refresh."
   - Still add MCP permission for foreground use

### Add Permissions

Read `~/.claude/settings.json`, merge new permissions into `permissions.allow[]`:

```javascript
// Example: after creating Sentry skill
existingAllow.push("mcp__plugin_sentry_sentry__search_issues");
// Deduplicate
permissions.allow = [...new Set(existingAllow)];
```

**IMPORTANT**: Expand `${HOME}` and `${CLAUDE_PLUGIN_ROOT}` to actual paths when writing.

### Report to User

Say: "Added permissions for background refresh:
- `<permission1>`
- `<permission2>`

These allow the status hub to refresh <service> without prompts."

## After Skill Created

1. Say "Created `hub-refresh-<service>.user.md`"
2. Ask: "Would you like to start tracking <service> now?"
3. If yes:
   - Add to config's foreground array
   - Run initial refresh
   - Update bridge
   - Say "Now tracking <service>. Use `/hub list` to see status."
