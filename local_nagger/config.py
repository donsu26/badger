from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import time

import yaml

from . import paths

TIME_RE = re.compile(r"^([01]\d|2[0-3]):([0-5]\d)$")

DEFAULT_DEFAULTS = {
    "interval_minutes": 15,
    "window_start": "08:00",
    "window_end": "22:00",
}


class ConfigError(ValueError):
    pass


@dataclass(frozen=True)
class Item:
    name: str
    interval_minutes: int
    window_start: time
    window_end: time


def _parse_time(value: str, field: str) -> time:
    if not TIME_RE.match(value):
        raise ConfigError(f"{field} must be HH:MM (24h), got {value!r}")
    h, m = value.split(":")
    return time(int(h), int(m))


def load_raw() -> dict:
    path = paths.config_path()
    if not path.exists():
        return {"defaults": dict(DEFAULT_DEFAULTS), "items": []}
    with open(path) as f:
        data = yaml.safe_load(f) or {}
    data.setdefault("defaults", {})
    data.setdefault("items", [])
    return data


def save_raw(raw: dict) -> None:
    path = paths.config_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        yaml.safe_dump(raw, f, sort_keys=False)


def _build_items(raw: dict) -> dict[str, Item]:
    defaults = raw.get("defaults") or {}
    default_interval = int(defaults.get("interval_minutes", DEFAULT_DEFAULTS["interval_minutes"]))
    default_start = defaults.get("window_start", DEFAULT_DEFAULTS["window_start"])
    default_end = defaults.get("window_end", DEFAULT_DEFAULTS["window_end"])

    items: dict[str, Item] = {}
    for entry in raw.get("items") or []:
        name = entry.get("name")
        if not name:
            raise ConfigError("every item must have a name")
        if name in items:
            raise ConfigError(f"duplicate item name: {name!r}")

        interval = int(entry.get("interval_minutes", default_interval))
        if interval <= 0:
            raise ConfigError(f"{name}: interval_minutes must be > 0")

        start = _parse_time(entry.get("window_start", default_start), f"{name}.window_start")
        end = _parse_time(entry.get("window_end", default_end), f"{name}.window_end")
        if not start < end:
            raise ConfigError(f"{name}: window_start must be before window_end (same-day windows only)")

        items[name] = Item(name=name, interval_minutes=interval, window_start=start, window_end=end)

    return items


def load_items() -> dict[str, Item]:
    return _build_items(load_raw())


def add_item(
    name: str,
    interval_minutes: int | None = None,
    window_start: str | None = None,
    window_end: str | None = None,
) -> None:
    raw = load_raw()
    items = raw.setdefault("items", [])
    if any(i.get("name") == name for i in items):
        raise ConfigError(f"item already exists: {name!r}")

    entry: dict = {"name": name}
    if interval_minutes is not None:
        entry["interval_minutes"] = interval_minutes
    if window_start is not None:
        entry["window_start"] = window_start
    if window_end is not None:
        entry["window_end"] = window_end
    items.append(entry)

    _build_items(raw)  # validate before persisting
    save_raw(raw)


def remove_item(name: str) -> bool:
    raw = load_raw()
    items = raw.get("items") or []
    new_items = [i for i in items if i.get("name") != name]
    if len(new_items) == len(items):
        return False
    raw["items"] = new_items
    save_raw(raw)
    return True
