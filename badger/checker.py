from __future__ import annotations

import fcntl
import sys
from datetime import datetime, timedelta

from . import calendar_events, calendar_state, config, dialog, history, paths
from . import state as state_mod


def _combine(d, t):
    return datetime.combine(d, t, tzinfo=state_mod.now().tzinfo)


def _check_calendar(now: datetime) -> None:
    cal_cfg = config.load_calendar_config()
    if not cal_cfg.enabled:
        return

    cal_st = calendar_state.load()
    calendar_state.prune(cal_st, now)

    authorized, events = calendar_events.query_upcoming(cal_cfg.poll_window_minutes)
    if not authorized:
        status = calendar_events.check_auth().get("status", "unknown")
        calendar_state.maybe_warn_unauthorized(cal_st, now, status)
        calendar_state.save(cal_st)
        return

    due = []
    for ev in events:
        if cal_cfg.ignore_all_day and ev.is_all_day:
            continue
        if cal_cfg.ignore_declined and ev.declined:
            continue
        key = f"{ev.id}|{ev.start_epoch}"
        if key in cal_st:
            continue
        seconds_until_start = ev.start_epoch - now.timestamp()
        if 0 < seconds_until_start <= cal_cfg.lookahead_minutes * 60:
            due.append((key, ev))

    due.sort(key=lambda pair: pair[1].start_epoch)

    for key, ev in due:
        cal_st[key] = {
            "notified_at": now.isoformat(),
            "title": ev.title,
            "start_epoch": ev.start_epoch,
        }
        calendar_state.save(cal_st)  # persist before the blocking dialog (crash-safe)

        result = dialog.show_meeting_dialog(ev.title, ev.join_url or "", cal_cfg.prompt_timeout_seconds)
        resolved = state_mod.now()
        event_name = {"join": "meeting_join", "dismiss": "meeting_dismiss"}.get(result, "meeting_timeout")
        history.append(ev.title, event_name, resolved)

        cal_st[key]["result"] = result
        calendar_state.save(cal_st)


def run_tick() -> None:
    lock_path = paths.lock_path()
    lock_file = open(lock_path, "w")
    try:
        fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        print("previous tick still running, skipping", file=sys.stderr)
        lock_file.close()
        return

    try:
        _tick()
    finally:
        fcntl.flock(lock_file, fcntl.LOCK_UN)
        lock_file.close()


def _tick() -> None:
    if paths.paused_path().exists():
        return

    now = state_mod.now()
    _check_calendar(now)  # before checklist items - meeting timing is more time-sensitive

    today = now.date()
    all_items = config.load_items()
    items = {name: item for name, item in all_items.items() if today.weekday() in item.days}
    st = state_mod.load()

    # 1. daily reset (date-comparison based, self-heals across sleep/crash gaps)
    for name in items:
        entry = st.setdefault(name, state_mod.default_entry())
        if entry["last_reset_date"] != today.isoformat():
            entry["last_reset_date"] = today.isoformat()
            entry["status"] = state_mod.PENDING
            entry["status_time"] = None

    # 2. missed detection: window closed while still pending
    for name, item in items.items():
        entry = st[name]
        window_end_dt = _combine(today, item.window_end)
        if entry["status"] == state_mod.PENDING and now >= window_end_dt:
            entry["status"] = state_mod.MISSED
            entry["status_time"] = now.isoformat()
            history.append(name, state_mod.MISSED, now)

    state_mod.save(st)  # persist resets/misses before any dialog can block/crash

    # 3. determine due items: pending, inside window, interval elapsed
    due = []
    for name, item in items.items():
        entry = st[name]
        if entry["status"] != state_mod.PENDING:
            continue
        window_start_dt = _combine(today, item.window_start)
        window_end_dt = _combine(today, item.window_end)
        if not (window_start_dt <= now < window_end_dt):
            continue
        last_nagged = entry["last_nagged_at"]
        if last_nagged is not None:
            elapsed = now - datetime.fromisoformat(last_nagged)
            if elapsed < timedelta(minutes=item.interval_minutes):
                continue
        due.append(name)

    # 4. sequential blocking dialogs, one item at a time
    for name in due:
        entry = st[name]
        entry["last_nagged_at"] = state_mod.now().isoformat()
        state_mod.save(st)  # persist nag time before showing dialog (crash-safe)

        result = dialog.show_dialog(name)
        resolved = state_mod.now()
        if result == dialog.DONE:
            entry["status"] = state_mod.DONE
            entry["status_time"] = resolved.isoformat()
            history.append(name, state_mod.DONE, resolved)
            state_mod.save(st)
        elif result == dialog.SKIP:
            entry["status"] = state_mod.SKIPPED
            entry["status_time"] = resolved.isoformat()
            history.append(name, state_mod.SKIPPED, resolved)
            state_mod.save(st)
        # "timeout": leave status "pending"; last_nagged_at already bumped so
        # it won't immediately re-fire on the next tick.


if __name__ == "__main__":
    run_tick()
