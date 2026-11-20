"""Run /shoes/recommend for Jordan's demo preset in-process and print the JSON.
uv run python scripts/sample.py [--offline]"""
import json, sys, time
from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient

if "--offline" in sys.argv:
    from harness import config
    config.SIE_API_KEY = ""
    from harness.clients import sie
    sie._client = None
from api.index import app

tz = timezone(timedelta(hours=-8))
now = datetime(2026, 11, 20, 9, 0, tzinfo=tz)
body = {
    "persona": "jordan", "now": now.isoformat(),
    "shoes": {"boughtOn": "2026-10-22", "startMiles": 267},
    "raceDate": (now.date() + timedelta(days=9)).isoformat(),
    "mandate": [{"id": "ask-first", "text": "Ask me before buying anything else.", "category": "any", "maxAutoCents": 0},
                {"id": "day-pass", "text": "Day passes up to $20: book it, tell me after.", "category": "dayPass", "maxAutoCents": 2000}],
}
t = time.monotonic()
from harness import config as _c
r = TestClient(app).post("/shoes/recommend", json=body, headers={"X-Harness-Secret": _c.HARNESS_SECRET})
print(r.status_code, f"{(time.monotonic() - t) * 1000:.0f} ms")
print(json.dumps(r.json(), indent=2))
