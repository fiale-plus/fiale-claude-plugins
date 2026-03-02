---
description: Install or remove brain scheduling (synthesize, reflect) via cron or launchd
---

Manage automated scheduling for `/synthesize` and `/brain-reflect`. Safe to re-run — checks before adding duplicates.

## Usage

Run with one of:
- `/brain-schedule` — interactive: shows current state, asks what to install/remove
- `/brain-schedule install synthesize` — install synthesize job only
- `/brain-schedule install reflect` — install reflect job only
- `/brain-schedule install all` — install both
- `/brain-schedule remove synthesize` — remove synthesize job
- `/brain-schedule remove reflect` — remove reflect job
- `/brain-schedule remove all` — remove all brain jobs
- `/brain-schedule status` — show current installed jobs

---

## Steps

### 1. Detect OS and existing jobs

```bash
uname -s
which claude
```

Check current crontab:
```bash
crontab -l 2>/dev/null | grep -n "brain:\|/synthesize\|/brain-reflect" || echo "none"
```

On macOS, also check launchd:
```bash
ls ~/Library/LaunchAgents/com.brain.*.plist 2>/dev/null || echo "none"
```

### 2. If interactive (no arguments), show status and ask

```
Current brain schedule:
  synthesize:  <installed at 09:00 daily via cron | not installed>
  reflect:     <installed at 09:00 Mondays via cron | not installed>

What would you like to do?
1. Install synthesize (daily)
2. Install reflect (weekly, Mondays)
3. Install both
4. Remove synthesize
5. Remove reflect
6. Remove all
7. Change schedule time
8. Exit
```

### 3. Ask scheduler preference (if installing, macOS only)

On macOS, ask:
> "Use launchd (recommended — runs even without a terminal) or cron?"
> 1. launchd
> 2. cron

On Linux, use cron only.

### 4. Ask for schedule time (if installing)

> "What time should synthesis run? Default is 09:00. Enter as HH:MM or press Enter."

Parse into hour and minute. For reflect, ask day of week (default: Monday).

### 5. Install jobs

**CLAUDE_PATH** = output of `which claude`
**HOME_DIR** = output of `echo $HOME`
**LOG** = `~/.claude/brain/cron.log`

#### cron — install synthesize

Check if already present:
```bash
crontab -l 2>/dev/null | grep "/synthesize"
```

If not present:
```bash
(crontab -l 2>/dev/null; echo "<MINUTE> <HOUR> * * * <CLAUDE_PATH> -p \"/synthesize\" >> <LOG> 2>&1  # brain:synthesize") | crontab -
```

#### cron — install reflect

```bash
(crontab -l 2>/dev/null; echo "0 9 * * 1 <CLAUDE_PATH> -p \"/brain-reflect\" >> <LOG> 2>&1  # brain:reflect") | crontab -
```

#### launchd — install synthesize (macOS)

Write `~/Library/LaunchAgents/com.brain.synthesize.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.brain.synthesize</string>
  <key>ProgramArguments</key>
  <array>
    <string><CLAUDE_PATH></string>
    <string>-p</string>
    <string>/synthesize</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key><integer><HOUR></integer>
    <key>Minute</key><integer><MINUTE></integer>
  </dict>
  <key>StandardOutPath</key><string><HOME_DIR>/.claude/brain/cron.log</string>
  <key>StandardErrorPath</key><string><HOME_DIR>/.claude/brain/cron.log</string>
  <key>RunAtLoad</key><false/>
</dict></plist>
```

Then:
```bash
launchctl load ~/Library/LaunchAgents/com.brain.synthesize.plist
```

#### launchd — install reflect (macOS)

Write `~/Library/LaunchAgents/com.brain.reflect.plist` with:
```xml
<key>StartCalendarInterval</key>
<dict>
  <key>Weekday</key><integer>1</integer>
  <key>Hour</key><integer>9</integer>
  <key>Minute</key><integer>0</integer>
</dict>
```

Load it similarly.

### 6. Remove jobs

#### cron — remove
```bash
crontab -l 2>/dev/null | grep -v "brain:synthesize" | crontab -
crontab -l 2>/dev/null | grep -v "brain:reflect" | crontab -
```

For `remove all`:
```bash
crontab -l 2>/dev/null | grep -v "brain:" | crontab -
```

#### launchd — remove
```bash
launchctl unload ~/Library/LaunchAgents/com.brain.synthesize.plist 2>/dev/null
rm -f ~/Library/LaunchAgents/com.brain.synthesize.plist

launchctl unload ~/Library/LaunchAgents/com.brain.reflect.plist 2>/dev/null
rm -f ~/Library/LaunchAgents/com.brain.reflect.plist
```

### 7. Confirm and show result

After any change, re-read and display current state:

```
✓ Schedule updated:
  synthesize:  daily at 09:00 via <cron|launchd>
  reflect:     Mondays at 09:00 via <cron|launchd>
  log:         ~/.claude/brain/cron.log
```

Or after removal:
```
✓ Removed: synthesize, reflect
  No brain jobs scheduled on this machine.
```
