"""Optional SingleStore layer: web shoe candidates and a permanent recommendation log (the audit trail).

Off unless SINGLESTORE_URL is set. Every call is best-effort: a failure returns a status string and
never blocks or breaks a recommendation."""
from __future__ import annotations

import json
import os
import uuid
from datetime import datetime, timezone

URL = os.environ.get("SINGLESTORE_URL", "").strip()

DDL = [
    """CREATE TABLE IF NOT EXISTS shoe_candidates (
        persona VARCHAR(32) NOT NULL, id VARCHAR(128) NOT NULL, fetched_at DATETIME NOT NULL,
        doc JSON NOT NULL, PRIMARY KEY (persona, id))""",
    """CREATE TABLE IF NOT EXISTS recommendations (
        id VARCHAR(36) NOT NULL PRIMARY KEY, created_at DATETIME NOT NULL, persona VARCHAR(32) NOT NULL,
        source VARCHAR(16) NOT NULL, item VARCHAR(256), latency_ms INT, doc JSON NOT NULL)""",
]
_ready = False


def enabled() -> bool:
    from harness import config  # noqa: F401  (loads harness/.env)
    return bool(os.environ.get("SINGLESTORE_URL", "").strip())


def _conn():
    global _ready
    import singlestoredb as s2
    conn = s2.connect(os.environ["SINGLESTORE_URL"].strip())
    if not _ready:
        with conn.cursor() as cur:
            for stmt in DDL:
                cur.execute(stmt)
        _ready = True
    return conn


def save_candidates(snap: dict) -> str:
    if not enabled():
        return "off (no SINGLESTORE_URL)"
    try:
        fetched = datetime.fromisoformat(snap["fetchedAt"]).replace(tzinfo=None)
        with _conn() as conn, conn.cursor() as cur:
            cur.execute("DELETE FROM shoe_candidates WHERE persona = %s", (snap["persona"],))
            for c in snap["candidates"]:
                cur.execute("INSERT INTO shoe_candidates (persona, id, fetched_at, doc) VALUES (%s, %s, %s, %s)",
                            (snap["persona"], c["id"], fetched, json.dumps(c)))
        return f"saved {len(snap['candidates'])} candidates"
    except Exception as exc:
        return f"failed: {type(exc).__name__}"


def load_candidates(persona: str) -> list[dict] | None:
    if not enabled():
        return None
    try:
        with _conn() as conn, conn.cursor() as cur:
            cur.execute("SELECT doc FROM shoe_candidates WHERE persona = %s", (persona,))
            rows = [json.loads(r[0]) if isinstance(r[0], str) else r[0] for r in cur.fetchall()]
        return rows or None
    except Exception:
        return None


def log_recommendation(persona: str, source: str, item: str | None, latency_ms: int, doc: dict) -> str | None:
    """Write one audit record; returns its id, or None if logging is off or failed."""
    if not enabled():
        return None
    rid = str(uuid.uuid4())
    try:
        with _conn() as conn, conn.cursor() as cur:
            cur.execute("INSERT INTO recommendations (id, created_at, persona, source, item, latency_ms, doc) "
                        "VALUES (%s, %s, %s, %s, %s, %s, %s)",
                        (rid, datetime.now(timezone.utc).replace(tzinfo=None), persona, source, item, latency_ms,
                         json.dumps(doc, default=str)))
        return rid
    except Exception:
        return None
