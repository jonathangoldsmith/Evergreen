"""The harness's brake rule against the shared fixtures the phone also runs (task T3)."""
import json
from datetime import date, datetime, timedelta
from pathlib import Path

import pytest

from harness import guardrail

FIXTURES = json.loads((Path(__file__).resolve().parents[2] / "contract" / "fixtures" / "guardrail.json").read_text())


def build(case):
    r = case["run"]
    start = datetime.fromisoformat(r["start"])
    unit = "km" if "km" in r else "minutes"
    run = guardrail.PlannedRun(start=start, size=r.get("km", r["minutes"]), unit=unit, minutes=r["minutes"],
                               hard=r.get("hard", False))
    history = []
    for h in case["history"]:
        s = start - timedelta(days=h["daysBack"])
        minutes = h.get("minutes", (h.get("km") or 0) * 6)
        history.append({"activityType": h.get("type", "Running"), "start": s, "durationMin": minutes,
                        "distanceKm": h.get("km")})
    injury = date.fromisoformat(case["injuryMonth"]) if case.get("injuryMonth") else None
    return run, history, injury


@pytest.mark.parametrize("case", FIXTURES["cases"], ids=[c["name"] for c in FIXTURES["cases"]])
def test_the_shared_cases(case):
    run, history, injury = build(case)
    got = guardrail.flag(run, history, injury, case.get("check"), body_off=case.get("bodyOff", False))
    want = case["expect"]
    if want is None:
        assert got is None
        return
    assert got is not None
    assert (got.kind, got.suggested, got.longest30, got.keep_easy, got.injury_adjusted) == \
        (want["kind"], want["suggested"], want["longest30"], want["keepEasy"], want["injuryAdjusted"])


def test_the_planner_keeps_a_run_in_range():
    """The 7-day planner's check (range plan milestone 3): a run past the 30-day longest is shortened."""
    from harness.recommend.workouts import keep_in_range
    now = datetime.fromisoformat("2026-11-20T09:00:00-08:00")
    history = [{"activityType": "Running", "start": now - timedelta(days=d), "durationMin": 40, "distanceKm": None}
               for d in (3, 7, 12)]
    session = {"date": (now + timedelta(days=2)).date(), "hour": 8, "activityType": "Running", "minutes": 75, "tags": []}
    keep_in_range(session, history, now)
    assert session["minutes"] == 40
    assert session["tags"] == ["kept in range: your longest run this month was 40 min"]

    usual = {"date": (now + timedelta(days=2)).date(), "hour": 8, "activityType": "Running", "minutes": 42, "tags": []}
    keep_in_range(usual, history, now)
    assert usual["minutes"] == 42 and usual["tags"] == []
