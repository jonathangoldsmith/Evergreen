"""Optional SingleStore layer: web shoe candidates and a permanent recommendation log (the audit trail).

Off unless SINGLESTORE_URL is set (e.g. "user:password@host:3306/database" from the workspace's
Connect → Python screen). Everything is best-effort: a failure never blocks or breaks a recommendation.

Tables (created on first use):
  shoe_candidates(persona, id, fetched_at, doc JSON)          web research, one row per shoe
  recommendations(id, created_at, persona, source, item, latency_ms, doc JSON)   one row per pick
"""
from __future__ import annotations

import json
import os
import threading
import time
import uuid
from datetime import datetime, timezone

from harness import config  # noqa: F401  (loads harness/.env)

DDL = [
    """CREATE TABLE IF NOT EXISTS verifications (
        persona VARCHAR(32) NOT NULL, relay_token VARCHAR(256) NOT NULL, relay_secret VARCHAR(256) NOT NULL,
        status VARCHAR(16) NOT NULL, claim_type VARCHAR(64), doc JSON, updated_at DATETIME(6) NOT NULL,
        PRIMARY KEY (persona))""",
    """CREATE TABLE IF NOT EXISTS shoe_candidates (
        persona VARCHAR(32) NOT NULL, id VARCHAR(128) NOT NULL, fetched_at DATETIME NOT NULL,
        doc JSON NOT NULL, PRIMARY KEY (persona, id))""",
    """CREATE TABLE IF NOT EXISTS recommendations (
        id VARCHAR(36) NOT NULL, created_at DATETIME(6) NOT NULL, persona VARCHAR(32) NOT NULL,
        source VARCHAR(16) NOT NULL, item VARCHAR(256), latency_ms INT, doc JSON NOT NULL,
        PRIMARY KEY (id), SORT KEY (created_at))""",
]
CANDIDATE_TTL_S = 300
LOG_WAIT_S = 0.4          # how long a request waits for its audit write before answering anyway

_lock = threading.Lock()
_conn_obj = None
_ready = False
_cache: dict[str, tuple[float, list[dict]]] = {}


def url() -> str:
    """SINGLESTORE_URL or SINGLESTORE_DB_URL; a singlestoredb:// or mysql:// prefix is fine."""
    return (os.environ.get("SINGLESTORE_URL") or os.environ.get("SINGLESTORE_DB_URL") or "").strip()


def connect_args(raw: str) -> dict:
    """Accepts either the portal's mysql command line (mysql -u USER -h HOST -P PORT --password='...' [-D DB | DB])
    or user:password@host:port/database. Parsed by hand: passwords often contain @ : , / # that break URLs."""
    raw = raw.strip()
    if raw.startswith("mysql ") or raw.startswith("-"):
        return _cli_args(raw)
    for prefix in ("singlestoredb://", "mysql://", "singlestore://"):
        if raw.startswith(prefix):
            raw = raw[len(prefix):]
    creds, _, rest = raw.rpartition("@")
    rest = rest.split("?", 1)[0]          # options only after the host; passwords may contain '?'
    user, _, password = creds.partition(":")
    hostport, _, database = rest.partition("/")
    host, _, port = hostport.rpartition(":") if ":" in hostport else (hostport, "", "")
    args = {"host": host, "port": int(port) if port else 3306, "user": user, "password": password}
    if database:
        args["database"] = database
    return args


def _cli_args(raw: str) -> dict:
    import shlex
    tokens = shlex.split(raw)
    if tokens and tokens[0] == "mysql":
        tokens = tokens[1:]
    args: dict = {"port": 3306}
    flags = {"-u": "user", "--user": "user", "-h": "host", "--host": "host", "-P": "port", "--port": "port",
             "-p": "password", "--password": "password", "-D": "database", "--database": "database"}
    i = 0
    while i < len(tokens):
        t = tokens[i]
        if "=" in t and t.startswith("--"):
            name, value = t.split("=", 1)
            if name in flags:
                args[flags[name]] = value
        elif t in flags and i + 1 < len(tokens):
            args[flags[t]] = tokens[i + 1]
            i += 1
        elif t.startswith("-p") and len(t) > 2:
            args["password"] = t[2:]
        elif not t.startswith("-"):
            args["database"] = t
        i += 1
    args["port"] = int(args["port"])
    return args


def enabled() -> bool:
    return bool(url())


def _conn():
    """One connection per warm instance, reopened if it dropped."""
    global _conn_obj, _ready
    import singlestoredb as s2
    with _lock:
        if _conn_obj is not None:
            try:
                with _conn_obj.cursor() as cur:
                    cur.execute("SELECT 1")
                return _conn_obj
            except Exception:
                _conn_obj = None
        _conn_obj = s2.connect(**connect_args(url()), autocommit=True)
        if not _ready:
            with _conn_obj.cursor() as cur:
                for stmt in DDL:
                    cur.execute(stmt)
            _ready = True
        return _conn_obj


def _json(value):
    return json.loads(value) if isinstance(value, (str, bytes)) else value


# --- candidates ---

def save_candidates(snap: dict) -> str:
    if not enabled():
        return "off (no SINGLESTORE_URL)"
    try:
        fetched = datetime.fromisoformat(snap["fetchedAt"]).astimezone(timezone.utc).replace(tzinfo=None)
        with _conn().cursor() as cur:
            cur.execute("DELETE FROM shoe_candidates WHERE persona = %s", (snap["persona"],))
            cur.executemany("INSERT INTO shoe_candidates (persona, id, fetched_at, doc) VALUES (%s, %s, %s, %s)",
                            [(snap["persona"], c["id"], fetched, json.dumps(c)) for c in snap["candidates"]])
        _cache.pop(snap["persona"], None)
        return f"saved {len(snap['candidates'])} candidates"
    except Exception as exc:
        return f"failed: {type(exc).__name__}: {str(exc)[:120]}"


def cached_candidates(persona: str) -> list[dict] | None:
    """Candidates already in this instance's memory, or None. Never touches the network."""
    hit = _cache.get(persona)
    return hit[1] if hit and time.monotonic() - hit[0] < CANDIDATE_TTL_S else None


def refresh_candidates_async(persona: str) -> None:
    """Fill the cache in the background so the next request can use SingleStore's candidates."""
    if enabled():
        threading.Thread(target=load_candidates, args=(persona,), daemon=True).start()


def warm(persona: str = "jordan") -> dict:
    """Open the connection and load candidates now (called by /warm before the demo)."""
    if not enabled():
        return {"singlestore": "off"}
    t = time.monotonic()
    rows = load_candidates(persona)
    return {"singlestore_ms": int((time.monotonic() - t) * 1000), "singlestore_candidates": len(rows or [])}


def load_candidates(persona: str) -> list[dict] | None:
    if not enabled():
        return None
    hit = _cache.get(persona)
    if hit and time.monotonic() - hit[0] < CANDIDATE_TTL_S:
        return hit[1]
    try:
        with _conn().cursor() as cur:
            cur.execute("SELECT doc FROM shoe_candidates WHERE persona = %s ORDER BY id", (persona,))
            rows = [_json(r[0]) for r in cur.fetchall()]
    except Exception:
        return None
    if rows:
        _cache[persona] = (time.monotonic(), rows)
    return rows or None


# --- audit log ---

def _insert(rid: str, persona: str, source: str, item: str | None, latency_ms: int, doc: dict) -> None:
    with _conn().cursor() as cur:
        cur.execute("INSERT INTO recommendations (id, created_at, persona, source, item, latency_ms, doc) "
                    "VALUES (%s, %s, %s, %s, %s, %s, %s)",
                    (rid, datetime.now(timezone.utc).replace(tzinfo=None), persona, source, item, latency_ms,
                     json.dumps(doc, default=str)))


def log_recommendation(persona: str, source: str, item: str | None, latency_ms: int, doc: dict) -> str | None:
    """Write one audit record. Waits at most LOG_WAIT_S; returns the id if the write finished, else None."""
    if not enabled():
        return None
    rid = str(uuid.uuid4())
    done = threading.Event()

    def work():
        try:
            _insert(rid, persona, source, item, latency_ms, doc)
            done.set()
        except Exception:
            pass

    t = threading.Thread(target=work, daemon=True)
    t.start()
    t.join(LOG_WAIT_S)
    return rid if done.is_set() else None


def get_recommendation(rid: str) -> dict | None:
    with _conn().cursor() as cur:
        cur.execute("SELECT id, created_at, persona, source, item, latency_ms, doc FROM recommendations WHERE id = %s", (rid,))
        row = cur.fetchone()
    return _row(row) if row else None


def recent_recommendations(persona: str | None = None, limit: int = 20) -> list[dict]:
    limit = max(1, min(int(limit), 100))
    sql = "SELECT id, created_at, persona, source, item, latency_ms, doc FROM recommendations"
    args: tuple = ()
    if persona:
        sql += " WHERE persona = %s"
        args = (persona,)
    sql += f" ORDER BY created_at DESC LIMIT {limit}"
    with _conn().cursor() as cur:
        cur.execute(sql, args)
        return [_row(r) for r in cur.fetchall()]


def _row(r) -> dict:
    return {"id": r[0], "createdAt": r[1].isoformat() + "Z" if hasattr(r[1], "isoformat") else str(r[1]),
            "persona": r[2], "source": r[3], "item": r[4], "latencyMs": r[5], "record": _json(r[6])}


# --- identity verification (Persona Relay); memory fallback when SingleStore is off ---

_verifications: dict[str, dict] = {}


def save_verification(persona: str, rec: dict) -> None:
    """rec: relay_token, relay_secret, status (started|passed|failed), claim_type, doc."""
    _verifications[persona] = rec
    if not enabled():
        return
    try:
        with _conn().cursor() as cur:
            cur.execute("REPLACE INTO verifications (persona, relay_token, relay_secret, status, claim_type, doc, updated_at) "
                        "VALUES (%s, %s, %s, %s, %s, %s, %s)",
                        (persona, rec["relay_token"], rec["relay_secret"], rec["status"], rec.get("claim_type"),
                         json.dumps(rec.get("doc") or {}), datetime.now(timezone.utc).replace(tzinfo=None)))
    except Exception:
        pass


def get_verification(persona: str) -> dict | None:
    if enabled():
        try:
            with _conn().cursor() as cur:
                cur.execute("SELECT relay_token, relay_secret, status, claim_type, doc, updated_at FROM verifications WHERE persona = %s", (persona,))
                r = cur.fetchone()
            if r:
                rec = {"relay_token": r[0], "relay_secret": r[1], "status": r[2], "claim_type": r[3], "doc": _json(r[4]),
                       "updatedAt": r[5].isoformat() + "Z" if hasattr(r[5], "isoformat") else str(r[5])}
                _verifications[persona] = rec
                return rec
        except Exception:
            pass
    return _verifications.get(persona)
