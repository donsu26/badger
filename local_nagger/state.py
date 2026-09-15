from __future__ import annotations

import json
from datetime import datetime

from . import paths

PENDING = "pending"
DONE = "done"
SKIPPED = "skipped"
MISSED = "missed"


def now() -> datetime:
    return datetime.now().astimezone()


def default_entry() -> dict:
    return {
        "last_reset_date": None,
        "status": PENDING,
        "status_time": None,
        "last_nagged_at": None,
    }


def load() -> dict:
    path = paths.state_path()
    if not path.exists():
        return {}
    with open(path) as f:
        return json.load(f)


def save(state: dict) -> None:
    path = paths.state_path()
    tmp = path.with_suffix(".json.tmp")
    with open(tmp, "w") as f:
        json.dump(state, f, indent=2, sort_keys=True)
    tmp.replace(path)
