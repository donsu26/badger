from __future__ import annotations

import os
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent


def config_path() -> Path:
    return Path(os.environ.get("NAGGER_CONFIG", PROJECT_DIR / "config.yaml"))


def data_dir() -> Path:
    d = Path(os.environ.get("NAGGER_DATA_DIR", PROJECT_DIR / "data"))
    d.mkdir(parents=True, exist_ok=True)
    return d


def state_path() -> Path:
    return data_dir() / "state.json"


def history_path() -> Path:
    return data_dir() / "history.jsonl"


def lock_path() -> Path:
    return data_dir() / "checker.lock"
