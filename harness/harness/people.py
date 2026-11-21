"""Whose history a recommendation reads: a real person's Apple Health data, or a demo persona's files.

Order: the history the phone sent with this request (kept for the user when it carries a `user` id),
else the history last kept for that user, else the persona's bundled files. Real histories are already
in real time, so unlike the persona files they're never re-anchored.
"""
from __future__ import annotations

from datetime import date, datetime

from harness import data, store
from harness.models import History


def resolve(persona: str, user: str | None, history: History | None, now: datetime,
            keep_weekdays: bool = False) -> tuple[list[dict], list[dict], str]:
    """(workouts, daily summaries, source) with source "phone", "stored" or "persona".
    Raises KeyError when there's no history and no persona file, which the API turns into 404."""
    if history is not None:
        doc = history.model_dump(mode="json")
        if user:
            store.save_history(user, doc)
        return workouts(doc, now), daily(doc, now), "phone"
    if user:
        doc = store.get_history(user)
        if doc:
            return workouts(doc, now), daily(doc, now), "stored"
    return (data.workouts(persona, now, keep_weekdays=keep_weekdays),
            data.daily(persona, now, keep_weekdays=keep_weekdays), "persona")


def workouts(doc: dict, now: datetime) -> list[dict]:
    """Workouts that ended before `now`, in the shape the recommenders use (parsed times, durationMin)."""
    out = []
    for w in doc.get("workouts", []):
        start, end = _dt(w["start"]), _dt(w["end"])
        if end <= now:
            minutes = (end - start).total_seconds() / 60
            pace = minutes / w["distanceKm"] if w.get("distanceKm") else None
            out.append({**w, "start": start, "end": end, "durationMin": minutes, "paceMinPerKm": pace})
    return sorted(out, key=lambda w: w["start"])


def daily(doc: dict, now: datetime) -> list[dict]:
    """Daily summaries for days before today."""
    out = []
    for d in doc.get("daily", []):
        day = d["date"] if isinstance(d["date"], date) else date.fromisoformat(d["date"])
        if day < now.date():
            out.append({**d, "date": day})
    return sorted(out, key=lambda d: d["date"])


def _dt(value) -> datetime:
    return value if isinstance(value, datetime) else datetime.fromisoformat(str(value).replace("Z", "+00:00"))
