"""Runs the harness on this Mac with an in-memory SQLite store, for trying the app's
guardrail events, buddy and coach links in the simulator before SingleStore is set up.
Never deployed (scripts/ is in .vercelignore); everything is lost when it stops.

    cd harness && uv run python scripts/local_sqlite.py [--seed]

Then point the simulator at it:
    xcrun simctl spawn booted defaults write com.evergreentraining.app recommend_url http://127.0.0.1:8000

--seed gives each device that registers a sample last week (a 18 → 13 km swap, a kept run,
the week's counts and a pain answer), so a coach link has something to show.
"""
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import os  # noqa: E402

os.environ["SINGLESTORE_URL"] = "sqlite:local"          # the store is on; _conn below is SQLite

import uvicorn  # noqa: E402

from api.index import app  # noqa: E402
from harness import devices, store  # noqa: E402
from tests.sqlite_store import Conn  # noqa: E402

conn = Conn()
store._conn = lambda: conn


def seed(user: str) -> None:
    today = date.today()
    monday = today - timedelta(days=today.weekday() + 7)
    sunday = monday + timedelta(days=6)
    at = datetime.now(timezone.utc).isoformat()
    events = [
        {"id": "seed-flag-1", "type": "flag", "at": at, "kind": "spike", "unit": "km", "planned": 18, "suggested": 13,
         "longest30": 13, "injuryAdjusted": False, "runDay": sunday.isoformat(), "run": "swap-5eed00000001"},
        {"id": "seed-choice-1", "type": "choice", "at": at, "choice": "accept", "kind": "spike",
         "run": "swap-5eed00000001", "runDay": sunday.isoformat()},
        {"id": "seed-flag-2", "type": "flag", "at": at, "kind": "tired", "unit": "minutes", "planned": 45, "suggested": 35,
         "injuryAdjusted": False, "runDay": (monday + timedelta(days=3)).isoformat(), "run": "swap-5eed00000002"},
        {"id": "seed-choice-2", "type": "choice", "at": at, "choice": "accept", "kind": "tired",
         "run": "swap-5eed00000002", "runDay": (monday + timedelta(days=3)).isoformat()},
        {"id": f"range_week-{monday}", "type": "range_week", "at": at, "weekStart": monday.isoformat(),
         "daysCounted": 6, "daysInRange": 5, "swaps": 2, "comebacks": 0},
        {"id": f"pain-{monday}-1", "type": "pain", "at": at, "answer": "aLittle", "weekStart": monday.isoformat()},
    ]
    store.save_events(user, events, {"range_week"})


if "--seed" in sys.argv:
    register = devices.register

    def register_and_seed(user: str) -> str:
        token = register(user)
        seed(user)
        return token

    devices.register = register_and_seed

uvicorn.run(app, host="127.0.0.1", port=8000)
