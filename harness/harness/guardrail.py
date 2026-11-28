"""The brake's rule (range plan items 5 and 6), the same as the phone's GuardrailRule.swift.
contract/fixtures/guardrail.json holds the cases both sides run (task T3).

A planned run is flagged when it's more than 10% past the longest run in the previous 30
days (5% within 12 months of an injury), and the suggestion is that longest (minus 10% after
an injury), never below 3 km or 20 minutes; a floor that reaches the planned size means no
flag. With fewer than 2 comparable runs there's no spike, except after an injury: anything
over 30 minutes or 5 km. Sore cuts a long run by 30%, Tired a long or hard run by 20%, and a
cut under 10% becomes "run it easy". With no morning answer, an off body signal (two of this
morning's readings off the person's usual, worked out on the phone) cuts like Tired. One flag
per run: the smaller suggestion wins.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta

SPIKE_RATIO, INJURED_SPIKE_RATIO, INJURED_CAP_RATIO = 1.10, 1.05, 0.90
LOOKBACK_DAYS, INJURY_MONTHS, MINIMUM_COMPARABLE = 30, 12, 2
RETURN_LIMIT = {"minutes": 30.0, "km": 5.0}
FLOOR = {"minutes": 20.0, "km": 3.0}
LONG = {"minutes": 60.0, "km": 10.0}
SORE_CUT, TIRED_CUT, SMALLEST_CUT = 0.70, 0.80, 0.10


@dataclass
class PlannedRun:
    start: datetime
    size: float | None
    unit: str                       # "km" or "minutes"
    minutes: float
    hard: bool = False
    all_day: bool = False


@dataclass
class Flag:
    kind: str
    planned: float
    suggested: float
    unit: str
    longest30: float | None
    keep_easy: bool
    injury_adjusted: bool
    extra: dict = field(default_factory=dict)

    @property
    def jump_percent(self) -> int | None:
        if not self.longest30:
            return None
        return round((self.planned / self.longest30 - 1) * 100)


def _months_before(d: date, months: int) -> date:
    y, m = divmod(d.month - 1 - months, 12)
    year, month = d.year + y, m + 1
    return date(year, month, min(d.day, 28))


def is_injured(run: PlannedRun, injury_month: date | None) -> bool:
    if not injury_month:
        return False
    return _months_before(run.start.date(), INJURY_MONTHS) <= injury_month <= run.start.date()


def comparable(run: PlannedRun, history: list[dict]) -> list[float]:
    day = run.start.replace(hour=0, minute=0, second=0, microsecond=0)
    since = day - timedelta(days=LOOKBACK_DAYS)
    out = []
    for w in history:
        start = w["start"].astimezone(run.start.tzinfo) if run.start.tzinfo else w["start"]
        if w.get("activityType") != "Running" or not since <= start < day:
            continue
        value = w.get("distanceKm") if run.unit == "km" else w.get("durationMin")
        if value and value > 0:
            out.append(float(value))
    return out


def round_down(value: float, unit: str) -> float:
    return math.floor(value + 1e-9) if unit == "km" else math.floor((value + 1e-9) / 5) * 5


def with_floor(value: float, unit: str) -> float:
    return max(value, FLOOR[unit])


def shown(value: float, unit: str) -> float:
    return round(value, 1) if unit == "km" else float(round(value))


def flag(run: PlannedRun, history: list[dict], injury_month: date | None = None, check: str | None = None,
         upcoming: list[PlannedRun] | None = None, body_off: bool = False) -> Flag | None:
    if run.size is None:
        return None
    injured = is_injured(run, injury_month)
    found = [f for f in (_spike(run, history, injured), _feel(run, check, injured, upcoming or [], body_off)) if f]
    return min(found, key=lambda f: f.suggested) if found else None


def _spike(run: PlannedRun, history: list[dict], injured: bool) -> Flag | None:
    sizes = comparable(run, history)
    if len(sizes) < MINIMUM_COMPARABLE:
        limit = RETURN_LIMIT[run.unit]
        if injured and run.size > limit:
            return Flag("returnSpike", run.size, limit, run.unit, None, False, True)
        return None
    longest = max(sizes)
    if run.size <= longest * (INJURED_SPIKE_RATIO if injured else SPIKE_RATIO):
        return None
    cap = longest * INJURED_CAP_RATIO if injured else longest
    suggested = with_floor(round_down(cap, run.unit), run.unit)
    if suggested >= run.size:
        return None
    return Flag("spike", run.size, suggested, run.unit, shown(longest, run.unit), False, injured)


def _is_long(run: PlannedRun, upcoming: list[PlannedRun]) -> bool:
    if run.size >= LONG[run.unit] or (not run.all_day and run.minutes >= LONG["minutes"]):
        return True
    day = run.start.replace(hour=0, minute=0, second=0, microsecond=0)
    week = [u.size for u in upcoming if u.size is not None and u.unit == run.unit
            and day <= u.start < run.start + timedelta(days=7)]
    return len(week) > 1 and run.size >= max(week)


def _feel(run: PlannedRun, check: str | None, injured: bool, upcoming: list[PlannedRun],
          body_off: bool = False) -> Flag | None:
    if check == "sore" and _is_long(run, upcoming):
        cut = SORE_CUT
    elif check == "tired" and (_is_long(run, upcoming) or run.hard):
        cut = TIRED_CUT
    elif check is None and body_off and (_is_long(run, upcoming) or run.hard):
        cut, check = TIRED_CUT, "body"
    else:
        return None
    suggested = with_floor(round_down(run.size * cut, run.unit), run.unit)
    if suggested > run.size * (1 - SMALLEST_CUT):
        return Flag(check, run.size, run.size, run.unit, None, True, injured)
    return Flag(check, run.size, suggested, run.unit, None, False, injured)
