---
name: local-nagger
description: Manage the local daily checklist reminder app "Local Nagger" (add/remove/list/check status/history of reminder items, and start/stop/restart/check-health of its background launchd service). Use when the user asks to be reminded of something recurring, to check on/adjust an existing reminder, to see reminder history/adherence, or to check whether the reminder service is running.
---

Always invoke the CLI by its absolute path, since this skill may run from any
directory and the user's PATH shim may not be sourced in a non-interactive
shell: `~/local-nagger/bin/nagger`.

## Item management

- Add: `~/local-nagger/bin/nagger add "<Name>" [--interval N] [--start HH:MM] [--end HH:MM]`
  - Map natural language to flags, e.g. "remind me to drink water every 30 minutes" -> `--interval 30`.
  - Omit flags the user didn't specify — they inherit the app's defaults (15 min, 08:00-22:00).
- Remove: `~/local-nagger/bin/nagger remove "<Name>"`
- List configured items: `~/local-nagger/bin/nagger list`
- Today's status per item: `~/local-nagger/bin/nagger status`
- History / adherence: `~/local-nagger/bin/nagger history [--item "<Name>"] [--days N]`

Item names must match exactly (case-sensitive) what's shown by `list`/`status` — look it up first if unsure rather than guessing.

## Background service management

The reminder checker runs as a launchd agent labeled `com.donsu.local-nagger`, ticking every 60s.

- Check if running / last exit status: `launchctl list | grep com.donsu.local-nagger`
  (a PID column with a number means it's currently mid-tick; "-" is normal between ticks — a nonzero "last exit code" column indicates the last tick errored)
- Force an immediate tick (e.g. to test a change right away): `launchctl kickstart -k gui/$(id -u)/com.donsu.local-nagger`
- Stop it: `launchctl bootout gui/$(id -u)/com.donsu.local-nagger`
- Start it again: `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.donsu.local-nagger.plist`
- Recent activity / errors: `tail -n 50 ~/local-nagger/data/checker.log` and `~/local-nagger/data/checker.err.log`

Never edit `~/local-nagger/config.yaml` or `data/state.json`/`data/history.jsonl` directly — always go through the CLI so validation and locking are respected.
