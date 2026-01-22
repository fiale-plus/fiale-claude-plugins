---
description: Set up Google Calendar API access (for environments without Chrome MCP)
---

# /hub-setup-gcalendar

Set up Google Calendar API integration for Status Hub.

## Usage

```
/hub-setup-gcalendar
```

## When to Use

Use this command when:
- You want calendar alerts without keeping a browser tab open
- You're in a headless or remote environment without Chrome MCP
- You prefer API access over browser DOM scraping

## What It Does

This command walks you through:
1. Creating OAuth2 credentials in Google Cloud Console (if needed)
2. Authorizing access to your Google Calendar
3. Storing credentials securely in `~/.claude/`
4. Verifying the connection works

## Prerequisites

- A Google account
- Access to Google Cloud Console (free)
- Ability to enable APIs and create OAuth credentials

## After Setup

Once configured, your statusline will show upcoming meetings and you can use `/hub-ack` to:
- Join meetings directly
- Send "running late" messages
- Dismiss alerts

## Switching Connection Methods

The hub supports two calendar connection methods:

| Method | Config Value | Pros | Cons |
|--------|--------------|------|------|
| API | `"api"` | Works without browser, headless-friendly | Requires OAuth setup |
| Chrome | `"chrome"` | No API setup needed | Requires browser tab open |

To switch, edit `~/.claude/status-config.json`:
```json
{
  "calendar": {
    "connection": "api"  // or "chrome"
  }
}
```

## See Also

- `/hub-setup` - Main hub configuration
- `/hub-ack` - Acknowledge alerts including calendar
- `/hub` - View current hub status
