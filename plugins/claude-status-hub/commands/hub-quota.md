---
name: hub-quota
description: Configure quota/rate limit display in statusline
allowedTools:
  - AskUserQuestion
  - Read
  - Write
---

# /hub-quota - Quota Display Setup

Configure estimated usage quota display in your statusline.

Note: This is an ESTIMATION based on token usage, not actual API quota.

## Process

### Step 1: Ask Plan Tier

Use AskUserQuestion:
```
question: "What's your Claude plan?"
header: "Plan"
options:
  - label: "Pro"
    description: "~45K tokens estimated daily"
  - label: "Max (5 hrs)"
    description: "~150K tokens estimated daily"
  - label: "Max (20 hrs)"
    description: "~600K tokens estimated daily"
  - label: "Custom"
    description: "Set your own limit"
```

If Custom, ask: "Enter estimated daily token limit (in thousands, e.g., 100 for 100K):"

### Step 2: Ask Display Format

Use AskUserQuestion:
```
question: "How should quota be displayed?"
header: "Format"
options:
  - label: "Bar ⚡[████░░]"
    description: "Visual progress bar"
  - label: "Number ⚡78%"
    description: "Percentage with icon"
  - label: "Compact ⚡78"
    description: "Minimal, just number"
  - label: "Off"
    description: "Don't show quota"
```

### Step 3: Ask Alert Threshold

Use AskUserQuestion:
```
question: "Alert when quota exceeds?"
header: "Threshold"
options:
  - label: "75%"
  - label: "80% (Recommended)"
  - label: "90%"
```

### Step 4: Save Configuration

Read `~/.claude/status-config.json` and update:

```json
{
  "quota": {
    "plan": "pro",
    "dailyLimit": 45,
    "displayFormat": "bar",
    "alertThreshold": 80
  },
  ...existing config...
}
```

### Step 5: Initialize Quota File

Reset the quota counter:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/hooks/reset-quota.sh
```

### Step 6: Confirm

Say:
```
Quota tracking configured!

Plan: <plan>
Estimated limit: <X>K tokens
Display: <format>
Alert threshold: <X>%

Your statusline will show estimated usage after context.
Example: main* [████░░ 42%] ⚡[██░░░░] › ▶ Song >

Note: This is an ESTIMATE based on tool usage. Actual API quota may differ.

Colors:
- Green: <75% used
- Yellow: 75-90% used
- Red: >90% used (critical)
```
