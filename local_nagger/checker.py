from __future__ import annotations

import fcntl
import sys
from datetime import datetime, timedelta

from . import config, dialog, history, paths
from . import state as state_mod


def _combine(d, t):
    return datetime.combine(d, t, tzinfo=state_mod.now().tzinfo)


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
    now = state_mod.now()
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
