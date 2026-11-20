"""Web research for shoe candidates: Nimble search (expert reviews) → SIE Qwen extracts shoes.

Run ahead of time (scripts/prefetch_web.py or POST /shoes/prefetch); the recommendation reads
the saved candidates, never the live web, so it stays inside the phone's time limit."""
from __future__ import annotations

import concurrent.futures as cf
import json
import os
import re
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

import httpx

from harness import config, data
from harness.clients import sie

NIMBLE_URL = "https://sdk.nimbleway.com/v2/search"
SNAPSHOT_DIR = Path(__file__).resolve().parents[1] / "data" / "web_candidates"
DEMO_SHIP_DAYS = 3          # delivery stays simulated: reviews carry no arrival dates
DEFAULT_LIFE_KM = 650

QUERIES = {
    "jordan": [
        "best wide toe box road running shoes 2026",
        "best cushioned daily trainer running shoes for half marathon training 2026",
    ],
}
DEFAULT_QUERIES = ["best daily trainer road running shoes 2026"]

EXTRACT_SCHEMA = {
    "type": "object",
    "properties": {"shoes": {"type": "array", "items": {
        "type": "object",
        "properties": {
            "name": {"type": "string"},
            "brand": {"type": "string"},
            "priceUsd": {"type": ["number", "null"]},
            "wideToeBox": {"type": ["boolean", "null"]},
            "carbonPlate": {"type": ["boolean", "null"]},
            "surface": {"type": "string", "enum": ["road", "trail", "unknown"]},
            "cushion": {"type": "string", "enum": ["low", "medium", "high", "unknown"]},
            "dropMm": {"type": ["number", "null"]},
            "quote": {"type": "string"},
        },
        "required": ["name", "brand", "priceUsd", "wideToeBox", "carbonPlate", "surface", "cushion", "dropMm", "quote"],
        "additionalProperties": False}}},
    "required": ["shoes"], "additionalProperties": False,
}


def nimble_search(query: str, max_results: int = 6, timeout_s: float = 30) -> list[dict]:
    key = os.environ.get("NIMBLE_API_KEY", "")
    if not key:
        raise RuntimeError("NIMBLE_API_KEY not set")
    r = httpx.post(NIMBLE_URL, json={"query": query, "max_results": max_results, "search_depth": "standard", "country": "US"},
                   headers={"Authorization": f"Bearer {key}"}, timeout=timeout_s)
    r.raise_for_status()
    return r.json().get("results", [])


def _extract(page: dict) -> list[dict]:
    text = (page.get("description") or page.get("content") or "")[:4000]
    if len(text) < 200:
        return []
    prompt = (
        "From this running-shoe review page, list each specific running shoe model it recommends. Only use facts "
        "stated on the page; use null or 'unknown' when the page doesn't say. quote: one short sentence copied from "
        "the page about that shoe (under 30 words).\n\n"
        f"Page title: {page.get('title')}\n\n{text}\n\nAnswer in JSON."
    )
    out = sie.chat_json(prompt, EXTRACT_SCHEMA, "shoe_extract", max_tokens=1200, provision_timeout_s=60)
    host = urlparse(page.get("url", "")).netloc.removeprefix("www.")
    return [{**s, "sourceTitle": page.get("title", host), "sourceHost": host, "url": page.get("url", "")} for s in out["shoes"]]


def _slug(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


def to_candidate(s: dict) -> dict | None:
    """Shape an extracted shoe like a catalog entry. Needs a name and a price."""
    if not s.get("name") or not s.get("priceUsd"):
        return None
    name = s["name"] if s["brand"].lower() in s["name"].lower() else f"{s['brand']} {s['name']}"
    cushion = s["cushion"] if s["cushion"] != "unknown" else "medium"
    return {
        "id": _slug(name), "name": name, "amountCents": int(round(float(s["priceUsd"]) * 100)),
        "arrivesInDays": DEMO_SHIP_DAYS, "wideToeBox": s["wideToeBox"], "carbonPlate": s["carbonPlate"],
        "surface": s["surface"] if s["surface"] != "unknown" else "road", "cushion": cushion,
        "dropMm": s["dropMm"] if s["dropMm"] is not None else 8, "lifeKm": DEFAULT_LIFE_KM,
        "blurb": s["quote"], "quote": s["quote"], "url": s["url"], "sourceTitle": s["sourceTitle"],
        "sourceHost": s["sourceHost"], "web": True,
    }


def research(persona: str) -> dict:
    """Nimble → extract → dedupe. Returns the snapshot dict (not saved)."""
    queries = QUERIES.get(persona, DEFAULT_QUERIES)
    with cf.ThreadPoolExecutor(max_workers=8) as pool:
        pages = [p for group in pool.map(nimble_search, queries) for p in group]
        extracted = list(pool.map(lambda p: _safe(_extract, p), pages))
    seen, cands = set(), []
    for group in extracted:
        for s in group:
            c = to_candidate(s)
            if c and c["id"] not in seen:
                seen.add(c["id"])
                cands.append(c)
    return {"persona": persona, "fetchedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "queries": queries, "pages": [{"title": p.get("title"), "url": p.get("url")} for p in pages],
            "candidates": cands}


def _safe(fn, *a):
    try:
        return fn(*a)
    except Exception:
        return []


def save_snapshot(snap: dict) -> Path:
    SNAPSHOT_DIR.mkdir(parents=True, exist_ok=True)
    path = SNAPSHOT_DIR / f"{snap['persona']}.json"
    path.write_text(json.dumps(snap, indent=1))
    return path


def load_snapshot(persona: str) -> dict | None:
    path = SNAPSHOT_DIR / f"{persona}.json"
    try:
        snap = json.loads(path.read_text())
        return snap if snap.get("candidates") else None
    except Exception:
        return None
