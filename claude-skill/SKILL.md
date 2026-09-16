---
name: badger
description: Manage the local daily checklist reminder app "Badger" (add/remove/list/check status/history of reminder items, and start/stop/restart/check-health of its background launchd service). Use when the user asks to be reminded of something recurring, to check on/adjust an existing reminder, to see reminder history/adherence, or to check whether the reminder service is running.
---

Always invoke the CLI by its absolute path, since this skill may run from any
directory and the user's PATH shim may not be sourced in a non-interactive
shell: `~/badger/bin/badger`.

## Item management

- Add: `~/badger/bin/badger add "<Name>" [--interval N] [--start HH:MM] [--end HH:MM]`
  - Map natural language to flags, e.g. "remind me to drink water every 30 minutes" -> `--interval 30`.
  - Omit flags the user didn't specify — they inherit the app's defaults (15 min, 08:00-22:00).
- Remove: `~/badger/bin/badger remove "<Name>"`
- List configured items: `~/badger/bin/badger list`
- Today's status per item: `~/badger/bin/badger status`
- History / adherence: `~/badger/bin/badger history [--item "<Name>"] [--days N]`
- Pause/resume all nagging (checklist + meetings): `~/badger/bin/badger pause` / `~/badger/bin/badger resume`

Item names must match exactly (case-sensitive) what's shown by `list`/`status` — look it up first if unsure rather than guessing.

## Meeting reminders

If the user asks about Google Calendar / meeting join reminders:

- Preview upcoming events + detected join links: `~/badger/bin/badger calendar list [--hours N]`
- Force-test the overlay on the soonest event with a join link: `~/badger/bin/badger calendar test`
- This feature is off by default (`calendar.enabled: false`) and hand-edited in `config.yaml`, not via a CLI verb - point the user at the "Meeting reminders" section of README.md to enable it.

## Background service management

The reminder checker runs as a launchd agent labeled `com.badger.checker`, ticking every 60s.

- Check if running / last exit status: `launchctl list | grep com.badger.checker`
  (a PID column with a number means it's currently mid-tick; "-" is normal between ticks — a nonzero "last exit code" column indicates the last tick errored)
- Force an immediate tick (e.g. to test a change right away): `launchctl kickstart -k gui/$(id -u)/com.badger.checker`
- Stop it: `launchctl bootout gui/$(id -u)/com.badger.checker`
- Start it again: `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.badger.checker.plist`
- Recent activity / errors: `tail -n 50 ~/badger/data/checker.log` and `~/badger/data/checker.err.log`

The menu bar icon runs as a separate launchd agent labeled `com.badger.statusbar` (persistent, not a periodic tick). Same commands as above, substituting that label and `~/badger/data/statusbar.log`/`.err.log`.

Never edit `~/badger/config.yaml` or `data/state.json`/`data/history.jsonl` directly — always go through the CLI so validation and locking are respected.
