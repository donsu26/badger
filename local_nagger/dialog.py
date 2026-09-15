from __future__ import annotations

import subprocess
from pathlib import Path

DONE = "done"
SKIP = "skip"
TIMEOUT = "timeout"

_OVERLAY_SCRIPT = Path(__file__).resolve().parent / "overlay.js"


def show_dialog(name: str, giving_up_after: int = 50) -> str:
    """Show a full-screen, blurred, blocking overlay reminding the user of `name`.

    Implemented as a JXA (JavaScript for Automation) script run via osascript,
    which reliably owns a WindowServer connection in this environment; a bare
    PyObjC NSApplication run from a plain background Python process was
    observed to hang with no window ever appearing.

    Returns "done", "skip", or "timeout" (also used for any error / crash,
    since a failed overlay must never crash the checker tick).
    """
    result = subprocess.run(
        ["osascript", "-l", "JavaScript", str(_OVERLAY_SCRIPT), name, str(giving_up_after)],
        capture_output=True,
        text=True,
        check=False,
    )
    value = result.stdout.strip()
    if result.returncode != 0 or value not in (DONE, SKIP, TIMEOUT):
        return TIMEOUT
    return value
