"""Fake data: persona fixtures (trimmed from MockData), shoe catalog, fit notes, cached passages."""
from __future__ import annotations

import json
from datetime import datetime, timedelta
from functools import lru_cache
from pathlib import Path

DIR = Path(__file__).parent


@lru_cache
def _load(name: str):
    return json.loads((DIR / name).read_text())


def catalog() -> list[dict]:
    return _load("catalog.json")


def fit_notes(persona: str) -> dict:
    return _load("fit_notes.json").get(persona, {"wideToeBox": False, "carbonPlate": None, "surface": "road", "text": "No fit notes."})


def passages(kind: str) -> list[dict]:
    return _load("passages.json").get(kind, [])


def workouts(persona: str, now: datetime) -> list[dict]:
    """The persona's workouts, re-anchored like the app does: the history ends the day before `now`.
    Each workout gets parsed `start`/`end` datetimes in now's offset; workouts after `now` are dropped."""
    path = DIR / "personas" / f"{persona}.json"
    if not path.exists():
        raise KeyError(persona)
    d = _load(f"personas/{persona}.json")
    shift = now.date() - datetime.fromisoformat(d["exportDate"]).date()
    out = []
    for w in d["workouts"]:
        start = datetime.fromisoformat(w["start"]) + timedelta(days=shift.days)
        end = datetime.fromisoformat(w["end"]) + timedelta(days=shift.days)
        if end <= now:
            out.append({**w, "start": start, "end": end})
    return out
