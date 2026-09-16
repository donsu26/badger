from __future__ import annotations

import subprocess
from pathlib import Path

DONE = "done"
SKIP = "skip"
JOIN = "join"
DISMISS = "dismiss"
TIMEOUT = "timeout"

_OVERLAY_BIN = Path(__file__).resolve().parent.parent / "bin" / "overlay"


def show_dialog(name: str, giving_up_after: int = 50) -> str:
    """Show a full-screen, blurred, blocking overlay reminding the user of `name`.

    Implemented as a compiled Swift binary (built by setup.sh from
    overlay-src/overlay.swift), not a script run via osascript/JXA — a
    manually-driven NSApplication invoked through osascript could display
    windows but never actually became the key/active app, so real mouse
    clicks on the buttons were silently swallowed. A compiled process running
    a real NSApp.run() event loop becomes key/main/active correctly.

    Returns "done", "skip", or "timeout" (also used for any error / crash,
    since a failed overlay must never crash the checker tick).
    """
    result = subprocess.run(
        [str(_OVERLAY_BIN), name, str(giving_up_after)],
        capture_output=True,
        text=True,
        check=False,
    )
    value = result.stdout.strip()
    if result.returncode != 0 or value not in (DONE, SKIP, TIMEOUT):
        return TIMEOUT
    return value


def show_meeting_dialog(title: str, join_url: str, giving_up_after: int = 90) -> str:
    """Show the full-screen overlay in meeting mode, with a "Join Meeting"
    button (opens `join_url` directly via NSWorkspace) when a join_url is
    given, or just "Dismiss" when it's empty.

    Returns "join", "dismiss", or "timeout" (also used for any error/crash,
    same fail-safe contract as show_dialog).
    """
    result = subprocess.run(
        [str(_OVERLAY_BIN), "--meeting", title, join_url, str(giving_up_after)],
        capture_output=True,
        text=True,
        check=False,
    )
    value = result.stdout.strip()
    if result.returncode != 0 or value not in (JOIN, DISMISS, TIMEOUT):
        return TIMEOUT
    return value
