from __future__ import annotations

import json
from datetime import date as date_cls
from datetime import datetime, timedelta

from . import paths


def append(item: str, event: str, when: datetime) -> None:
    path = paths.history_path()
    record = {
        "timestamp": when.isoformat(),
        "date": when.date().isoformat(),
        "item": item,
        "event": event,
    }
    with open(path, "a") as f:
        f.write(json.dumps(record) + "\n")
        f.flush()


def read_all() -> list[dict]:
    path = paths.history_path()
    if not path.exists():
        return []
    records = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                records.append(json.loads(line))
    return records


def query(item: str | None = None, days: int | None = None) -> list[dict]:
    records = read_all()
    if item is not None:
        records = [r for r in records if r["item"] == item]
    if days is not None:
        cutoff = (date_cls.today() - timedelta(days=days - 1)).isoformat()
        records = [r for r in records if r["date"] >= cutoff]
    records.sort(key=lambda r: r["timestamp"])
    return records
