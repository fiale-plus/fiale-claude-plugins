---
name: hub-context
description: Configure context window display in statusline
allowedTools:
  - AskUserQuestion
  - Read
  - Write
---

# /hub-context - Context Window Display Setup

Configure how context window usage is displayed in your statusline.

## Process

### Step 1: Ask Display Format

Use AskUserQuestion:
```
question: "How should context usage be displayed?"
header: "Format"
options:
  - label: "Bar [████░░ 42%]"
    description: "Visual progress bar with percentage"
  - label: "Percent only"
    description: "Just show 42%"
  - label: "Threshold alert"
    description: "Hidden until above threshold, then show warning"
```

Map answers:
- "Bar" → `contextDisplay: "bar"`
- "Percent only" → `contextDisplay: "percent"`
- "Threshold alert" → `contextDisplay: "threshold"`

### Step 2: Ask Alert Threshold

Use AskUserQuestion:
```
question: "Alert when context usage exceeds?"
header: "Threshold"
options:
  - label: "60%"
  - label: "70%"
  - label: "80% (Recommended)"
  - label: "90%"
```

### Step 3: Save Configuration

Read `~/.claude/status-config.json` and update:

```json
{
  "contextDisplay": "bar",
  "contextAlertThreshold": 80,
  ...existing config...
}
```

### Step 4: Confirm

Say:
```
Context display configured!

Format: <bar/percent/threshold>
Alert threshold: <X>%

Your statusline will now show context usage after the git branch.
Example: main* [████░░░░░░ 42%] › ▶ Song › 2 PRs >

Colors:
- Green: <60% used
- Yellow: 60-80% used
- Red: >80% used (alert state)
```
