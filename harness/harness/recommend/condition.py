"""Runner profile and shoe wear, from real distances in the fake Health data. Deterministic."""
from __future__ import annotations

from datetime import datetime, timedelta

from harness.models import Condition, Profile, ShoeState

KM_PER_MILE = 1.609344
DEFAULT_LIFE_KM = 650   # ~400 mi, a daily road trainer
WORN_AT = 0.60
REPLACE_AT = 0.85


def runs(workouts: list[dict]) -> list[dict]:
    return [w for w in workouts if w["activityType"] == "Running" and w.get("durationMin", 0) >= 10]


def profile(workouts: list[dict], now: datetime) -> Profile:
    recent = [w for w in runs(workouts) if w["start"] >= now - timedelta(days=28)]
    km = [w.get("distanceKm") or 0 for w in recent]
    paces = [w["paceMinPerKm"] for w in recent if w.get("paceMinPerKm")]
    return Profile(
        weeklyKm=round(sum(km) / 4, 1),
        runsPerWeek=round(len(recent) / 4, 2),
        longestRunKm=round(max(km, default=0), 1),
        avgPaceMinPerKm=round(sum(paces) / len(paces), 2) if paces else None,
        indoorShare=round(sum(1 for w in recent if w.get("indoor")) / len(recent), 2) if recent else 0.0,
    )


def condition(workouts: list[dict], shoes: ShoeState, now: datetime, life_km: int = DEFAULT_LIFE_KM) -> Condition:
    counted = [w for w in runs(workouts) if w["start"].date() >= shoes.boughtOn and w["end"] <= now]
    run_km = sum(w.get("distanceKm") or 0 for w in counted)
    km = shoes.startMiles * KM_PER_MILE + run_km
    share = km / life_km
    status = "replace" if share >= REPLACE_AT else "worn" if share >= WORN_AT else "fresh"
    return Condition(
        km=round(km, 1),
        miles=round(km / KM_PER_MILE),
        lifeKm=life_km,
        percentLife=round(share * 100),
        status=status,
        runsCounted=len(counted),
        why=(f"{round(shoes.startMiles)} mi on the pair before tracking plus {round(run_km, 1)} km from "
             f"{len(counted)} logged runs since {shoes.boughtOn.isoformat()}: {round(share * 100)}% of a "
             f"{life_km} km life."),
    )
