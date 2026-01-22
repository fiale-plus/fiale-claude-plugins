---
description: Set up Slack API access using browser session credentials
---

# /hub-setup-slack

Set up Slack API integration using browser session tokens.

## Usage

```
/hub-setup-slack
```

## When to Use

Use this command when:
- You want to read Slack messages from Claude Code
- You want to post messages to Slack channels
- You want to search Slack messages programmatically
- You don't want to create a Slack App (uses browser session instead)

## What It Does

This command walks you through:
1. Extracting credentials from your browser (d cookie + xoxc token)
2. Storing credentials securely in `~/.claude/`
3. Verifying the connection works

## Prerequisites

- A Slack workspace you have access to
- Slack open in your browser (for credential extraction)
- Access to browser DevTools

## Credentials Required

| Credential | Where to Find | Lifespan |
|------------|---------------|----------|
| Workspace URL | Browser address bar | Permanent |
| `d` cookie | DevTools > Application > Cookies | ~1 year |
| `xoxc` token | DevTools > Network > Request Headers | Hours to days |

The setup saves all credentials. When the xoxc token expires, it can be automatically refreshed using the d cookie.

## After Setup

Once configured, you can use the Slack API functions:

```bash
# List channels
slack_list_channels()

# Read messages
slack_get_messages("C123ABC", 20)

# Post a message
slack_post_message("C123ABC", "Hello from Claude!")

# Reply to a thread
slack_post_message("C123ABC", "Thread reply", "1705344000.000100")

# Search messages
slack_search("project update from:@pavel")
```

## Security Notes

- Credentials give full access to your Slack account (as you)
- Stored in `~/.claude/` with 600 permissions (owner-only)
- Never share your credentials or commit them to git
- Run `/hub-setup-slack` again if credentials expire

## Refreshing Credentials

If you get authentication errors:
1. Log into Slack in your browser
2. Run `/hub-setup-slack` to extract fresh credentials

The d cookie rarely expires (~1 year), but the xoxc token may expire more frequently. The tool tries to auto-refresh the xoxc token, but if that fails, you'll need to re-run setup.

## See Also

- `/hub-setup` - Main hub configuration
- `/hub` - View current hub status
