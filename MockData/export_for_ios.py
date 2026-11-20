"""Trim MockData/output/*/health.json into the small persona files the iOS app bundles.

Keeps the persona, the history range and the workouts, and drops raw samples and
time-zone offsets: the app re-anchors each workout's local wall-clock time so the
history always ends the day before the story day (eng review D6).

Run from the repo root after regenerating the mock data:
    /usr/bin/python3 MockData/export_for_ios.py
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT.parent / "app" / "TrackerPlusPlus" / "Resources" / "Personas"
PERSONAS = {"sedentary": "sam", "moderate": "alex", "half_marathon": "jordan"}


def local(ts: str) -> str:
    # "2026-10-24T10:13:50.216112-08:00" -> "2026-10-24T10:13:50"
    return ts[:19]


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for folder, key in PERSONAS.items():
        data = json.loads((ROOT / "output" / folder / "health.json").read_text())
        days = [d["date"] for d in data["dailySummaries"]]
        workouts = [
            {
                "id": f"{key}-{local(w['start'])}",
                "activityType": w["activityType"],
                "start": local(w["start"]),
                "end": local(w["end"]),
                "avgHeartRate": w["heartRate"]["avg"],
                # Effort (1-10) arrives with Tony's generator change (plan item 1).
                "effort": w.get("effort"),
            }
            for w in data["workouts"]
        ]
        persona = {
            "key": key,
            "name": data["persona"]["name"],
            "description": data["persona"]["description"],
            "historyStart": min(days),
            "historyEnd": max(days),
            "workouts": workouts,
        }
        path = OUT / f"{key}.json"
        path.write_text(json.dumps(persona, indent=1) + "\n")
        print(f"{path.relative_to(ROOT.parent)}: {len(workouts)} workouts, {min(days)} to {max(days)}")


if __name__ == "__main__":
    main()
