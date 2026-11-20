# TrackerPlusPlus harness

The stateless backend that recommends running shoes from the fake persona data. The app stays the agent's hands: it applies what comes back and writes the calendar. Design: [docs/designs/trackerplusplus-recommendation-harness.md](../docs/designs/trackerplusplus-recommendation-harness.md).

## Run

Needs [uv](https://docs.astral.sh/uv/). Keys go in the repo-root `.env` (git-ignored): `SUPERLINKED_API_KEY` (or `SIE_API_KEY`), and optionally `SENSO_API_KEY` and `HARNESS_SECRET`.

```sh
cd harness
uv sync
PYTHONPATH=. uv run python scripts/warm.py      # loads both SIE models; also the smoke test
PYTHONPATH=. uv run python scripts/sample.py    # Jordan's demo preset, live (add --offline for the fallback)
uv run pytest -q                                # 11 tests; the live SIE test skips without a key
PYTHONPATH=. uv run uvicorn api.index:app --reload --port 8000
```

## Routes

| Route | What it does |
|---|---|
| `GET /health` | Which keys are configured (never their values) |
| `POST /warm` | Loads the two SIE models before the demo, since cold starts can take minutes |
| `POST /evidence` | `{purchaseKind, query}` → `{evidence, live}`, the shape `EvidenceClient.swift` expects. Cached passages until Senso is wired. Open even when a secret is set, because the app sends no header. |
| `POST /shoes/recommend` | `{persona, now, shoes:{boughtOn,startMiles}, raceDate, mandate}` → `{condition, profile, purchase?, live, source}`. `purchase` uses the Swift `Purchase` shape. |

```sh
curl -s localhost:8000/shoes/recommend -H 'content-type: application/json' -d '{
  "persona":"jordan","now":"2026-11-20T09:00:00-08:00",
  "shoes":{"boughtOn":"2026-10-22","startMiles":267},"raceDate":"2026-11-29",
  "mandate":[{"id":"ask-first","text":"Ask me before buying anything else.","category":"any","maxAutoCents":0}]}'
```

## How it decides

1. Load the persona's workouts, shifted so the history ends the day before `now` (as the app does).
2. Compute wear from the real `distanceKm` of runs since `boughtOn`, plus `startMiles`: ≥85% of a 650 km life means replace. No purchase if the pair is fresh or the race is more than 14 days away.
3. Hard filters in code: fit notes (toe box, no carbon plate, surface) and arrival at least 3 days before the race.
4. **Superlinked SIE:** `Qwen/Qwen3-Reranker-4B` scores the shortlist against the runner's profile. `Qwen/Qwen3.8-27B-FP8` picks one and writes why each other shoe lost, constrained to a JSON schema.
5. Guardrails: the pick must be on the shortlist, and every other shoe needs a short reason. Otherwise, or on any SIE error or timeout, a deterministic pick: high cushion for long runs ≥15 km, then cheapest. `source` says which path answered.
6. Mandate: over the `any` line's `maxAutoCents` means `awaitingApproval`. Approval, cancellation, action ids and break-in runs stay in Swift.

The whole route has a 5 s budget. Measured on Jordan: about 2.7–3.5 s live and about 0.3 s on the fallback.

## Deploy (Vercel)

`vercel.json` routes everything to `api/index.py`, and `requirements.txt` holds the dependencies. Set the same environment variables in the Vercel project, deploy from `harness/`, then `curl <url>/health` and `POST <url>/warm`.
