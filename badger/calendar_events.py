from __future__ import annotations

import json
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

_BIN = Path(__file__).resolve().parent.parent / "bin" / "calendar-events"

_JOIN_URL_RE = re.compile(
    r"https?://[^\s\"'<>]*"
    r"(?:meet\.google\.com|zoom\.us|teams\.microsoft\.com|"
    r"webex\.com|chime\.aws|whereby\.com|gotomeeting\.com)"
    r"[^\s\"'<>]*",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class CalendarEvent:
    id: str
    title: str
    start_epoch: int
    end_epoch: int
    join_url: str | None
    declined: bool
    is_all_day: bool


def _extract_join_url(url: str | None, location: str | None, notes: str | None) -> str | None:
    for candidate in (url, location, notes):
        if not candidate:
            continue
        match = _JOIN_URL_RE.search(candidate)
        if match:
            return match.group(0)
    return None


def check_auth(timeout: float = 5) -> dict:
    try:
        result = subprocess.run(
            [str(_BIN), "check-auth"], capture_output=True, text=True, timeout=timeout, check=False
        )
        return json.loads(result.stdout.strip())
    except (subprocess.SubprocessError, json.JSONDecodeError, OSError):
        return {"authorized": False, "status": "error"}


def request_access(timeout: int = 60) -> dict:
    try:
        result = subprocess.run(
            [str(_BIN), "request-access", "--timeout", str(timeout)],
            capture_output=True,
            text=True,
            timeout=timeout + 5,
            check=False,
        )
        return json.loads(result.stdout.strip())
    except (subprocess.SubprocessError, json.JSONDecodeError, OSError):
        return {"granted": False, "status": "error"}


def query_upcoming(minutes_ahead: int, timeout: float = 10) -> tuple[bool, list[CalendarEvent]]:
    """Never raises; on any failure returns (False, [])."""
    try:
        result = subprocess.run(
            [str(_BIN), "query", "--minutes", str(minutes_ahead)],
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        payload = json.loads(result.stdout.strip())
    except (subprocess.SubprocessError, json.JSONDecodeError, OSError):
        return False, []

    if not payload.get("authorized"):
        return False, []

    events = []
    for raw in payload.get("events", []):
        join_url = _extract_join_url(raw.get("url"), raw.get("location"), raw.get("notes"))
        events.append(
            CalendarEvent(
                id=raw["id"],
                title=raw["title"],
                start_epoch=int(raw["start"]),
                end_epoch=int(raw["end"]),
                join_url=join_url,
                declined=bool(raw.get("declined", False)),
                is_all_day=bool(raw.get("isAllDay", False)),
            )
        )
    return True, events
