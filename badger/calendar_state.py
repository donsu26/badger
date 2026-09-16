from __future__ import annotations

import json
import sys
from datetime import datetime, timedelta

from . import paths

_META_KEY = "__meta__"
_PRUNE_AFTER = timedelta(hours=24)
_WARN_INTERVAL = timedelta(hours=1)


def load() -> dict:
    path = paths.calendar_state_path()
    if not path.exists():
        return {}
    with open(path) as f:
        return json.load(f)


def save(state: dict) -> None:
    path = paths.calendar_state_path()
    tmp = path.with_suffix(".json.tmp")
    with open(tmp, "w") as f:
        json.dump(state, f, indent=2, sort_keys=True)
    tmp.replace(path)


def prune(state: dict, now: datetime) -> None:
    cutoff = now.timestamp() - _PRUNE_AFTER.total_seconds()
    for key in [k for k in state if k != _META_KEY]:
        entry = state[key]
        if entry.get("start_epoch", 0) < cutoff:
            del state[key]


def maybe_warn_unauthorized(state: dict, now: datetime, status: str) -> None:
    meta = state.setdefault(_META_KEY, {})
    last_warned = meta.get("last_auth_warning_at")
    if last_warned is not None:
        elapsed = now - datetime.fromisoformat(last_warned)
        if elapsed < _WARN_INTERVAL:
            return
    print(f"calendar: not authorized (status={status}); run "
          f"'bin/calendar-events request-access' to grant Calendar access",
          file=sys.stderr)
    meta["last_auth_warning_at"] = now.isoformat()
