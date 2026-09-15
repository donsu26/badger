# Local Nagger

A local macOS app that nags you with a full-screen, blurred overlay until you
mark a recurring daily task done — built because notification banners are too
easy to ignore.

- Each checklist item has its own interval and active time window (default:
  every 15 minutes, 08:00-22:00).
- When an item is due, a full-screen blurred overlay (like DeskMinder) covers
  every display with **Done for today** and **Skip today** buttons — it won't
  go away on its own.
- Runs automatically at login via a `launchd` agent.
- Every done/skipped/missed event is logged for a full daily adherence history.

## Setup

```
./setup.sh
```

This creates a virtualenv, installs dependencies, creates `config.yaml` from
`config.example.yaml` if it doesn't exist yet, installs the Claude Code skill,
and loads the `launchd` agent so the checker starts running immediately (and
again automatically at every login).

Then add the CLI to your `PATH` (setup.sh will print this line if it's not
already in `~/.zshrc`):

```
export PATH="$HOME/local-nagger/bin:$PATH"
```

## Usage

```
nagger add "Take medicine" --interval 15 --start 08:00 --end 22:00
nagger add "Drink water"                     # uses the defaults
nagger list
nagger status
nagger history --item "Take medicine" --days 7
nagger remove "Drink water"
```

`config.yaml` is your personal, hand-editable checklist — it's gitignored
because it may name real medications. Only `config.example.yaml` is committed.

## Claude Code integration

A global Claude Code skill (`~/.claude/skills/local-nagger/`) lets you manage
reminders conversationally from any directory, e.g. "remind me to stretch
every hour" or "is my reminder service running?". The skill source lives in
`claude-skill/SKILL.md` and is installed by `setup.sh`.

## How the overlay works

The reminder popup (`overlay-src/overlay.swift`) is a small compiled Swift
binary (built by `setup.sh` into `bin/overlay`) that shows a borderless,
screen-saver-level `NSWindow` per display with an `NSVisualEffectView` for the
blur, and real "Done for today"/"Skip today" buttons on the screen under your
cursor. It's a compiled binary rather than a script, because a manually
driven `NSApplication` run from an interpreted process (both plain
Python/PyObjC and JXA via `osascript`) could display the windows fine but
never actually became the key/active app, so real mouse clicks on the
buttons were silently swallowed as mere focus-steal attempts. A compiled
process running a real `NSApp.run()` event loop becomes key/main/active
correctly.

## Managing the background service

```
launchctl list | grep com.donsu.local-nagger        # check it's running
launchctl kickstart -k gui/$(id -u)/com.donsu.local-nagger   # force an immediate tick
launchctl bootout gui/$(id -u)/com.donsu.local-nagger        # stop it
tail -f data/checker.log data/checker.err.log                # watch activity/errors
```
