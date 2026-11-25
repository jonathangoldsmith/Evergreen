"""Optional SingleStore layer: web shoe candidates and a permanent recommendation log (the audit trail).

Off unless SINGLESTORE_URL is set (e.g. "user:password@host:3306/database" from the workspace's
Connect → Python screen). Everything is best-effort: a failure never blocks or breaks a recommendation.

Tables (created on first use):
  shoe_candidates(persona, id, fetched_at, doc JSON)          web research, one row per shoe
  recommendations(id, created_at, persona, source, item, latency_ms, doc JSON)   one row per pick
  user_history(user_id, updated_at, doc JSON)                  a real person's Apple Health history, latest copy
  guardrail_events(user_id, event_id, type, created_at, doc)  the brake's events from the phone (plan item 9)
  buddy_pairs, buddy_notes, buddy_redeem_failures, push_tokens  the accountability buddy (item 22)
For a real person, `persona` in recommendations and verifications holds their anonymous `usr_` id.
Without SINGLESTORE_URL, user history and verifications live in memory (lost on a cold start).
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
    """CREATE TABLE IF NOT EXISTS user_history (
        user_id VARCHAR(80) NOT NULL, updated_at DATETIME(6) NOT NULL, doc JSON NOT NULL,
        PRIMARY KEY (user_id))""",
    """CREATE TABLE IF NOT EXISTS guardrail_events (
        user_id VARCHAR(80) NOT NULL, event_id VARCHAR(64) NOT NULL, type VARCHAR(32) NOT NULL,
        created_at DATETIME(6) NOT NULL, received_at DATETIME(6) NOT NULL, doc JSON NOT NULL,
        PRIMARY KEY (user_id, event_id), SHARD KEY (user_id))""",
    """CREATE TABLE IF NOT EXISTS buddy_pairs (
        pair_id VARCHAR(36) NOT NULL, inviter_id VARCHAR(80) NOT NULL, friend_id VARCHAR(80),
        code_hash VARCHAR(64) NOT NULL, status VARCHAR(16) NOT NULL, inviter_display_name VARCHAR(40) NOT NULL,
        created_at DATETIME(6) NOT NULL, expires_at DATETIME(6) NOT NULL, paired_at DATETIME(6),
        PRIMARY KEY (pair_id), SHARD KEY (pair_id))""",
    """CREATE TABLE IF NOT EXISTS buddy_notes (
        pair_id VARCHAR(36) NOT NULL, note_id VARCHAR(64) NOT NULL, inviter_id VARCHAR(80) NOT NULL,
        friend_id VARCHAR(80) NOT NULL, status VARCHAR(16) NOT NULL, attempts INT NOT NULL,
        created_at DATETIME(6) NOT NULL, doc JSON NOT NULL,
        PRIMARY KEY (pair_id, note_id), SHARD KEY (pair_id))""",
    """CREATE TABLE IF NOT EXISTS buddy_redeem_failures (
        user_id VARCHAR(80) NOT NULL, at DATETIME(6) NOT NULL, SHARD KEY (user_id))""",
    """CREATE TABLE IF NOT EXISTS coach_shares (
        share_id VARCHAR(36) NOT NULL, user_id VARCHAR(80) NOT NULL, token_hash VARCHAR(64) NOT NULL,
        display_name VARCHAR(40) NOT NULL, include_feelings TINYINT NOT NULL, created_at DATETIME(6) NOT NULL,
        expires_at DATETIME(6) NOT NULL, revoked_at DATETIME(6), PRIMARY KEY (share_id), SHARD KEY (share_id))""",
    """CREATE TABLE IF NOT EXISTS push_tokens (
        user_id VARCHAR(80) NOT NULL, token VARCHAR(200) NOT NULL, environment VARCHAR(16) NOT NULL,
        updated_at DATETIME(6) NOT NULL, PRIMARY KEY (user_id), SHARD KEY (user_id))""",
]
# Columns that hold a user's anonymous id. delete_user erases every table that has one,
# so a new table is covered the moment its DDL names one (eng review E8).
USER_COLUMNS = ("user_id", "persona", "inviter_id", "friend_id")


def user_tables() -> list[tuple[str, str]]:
    """(table, column) for every user column of every table in DDL, read from the DDL itself.
    A buddy pair has two (inviter and friend), so deleting either person removes it."""
    import re
    out = []
    for stmt in DDL:
        table = re.search(r"CREATE TABLE IF NOT EXISTS (\w+)", stmt).group(1)
        for column in USER_COLUMNS:
            if re.search(rf"\b{column}\b\s+VARCHAR", stmt):
                out.append((table, column))
    return out
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


# --- a real person's history (Apple Health, sent by the phone); memory fallback when SingleStore is off ---

_histories: dict[str, dict] = {}


def save_history(user: str, doc: dict) -> None:
    """Keeps the latest history for an anonymous user id. Best-effort: a failed write never blocks a pick."""
    _histories[user] = {**doc, "updatedAt": datetime.now(timezone.utc).isoformat()}
    if not enabled():
        return
    try:
        with _conn().cursor() as cur:
            cur.execute("REPLACE INTO user_history (user_id, updated_at, doc) VALUES (%s, %s, %s)",
                        (user, datetime.now(timezone.utc).replace(tzinfo=None), json.dumps(doc, default=str)))
    except Exception:
        pass


def get_history(user: str) -> dict | None:
    """The latest stored history for a user, with `updatedAt`; None if there is none."""
    if enabled():
        try:
            with _conn().cursor() as cur:
                cur.execute("SELECT doc, updated_at FROM user_history WHERE user_id = %s", (user,))
                r = cur.fetchone()
            if r:
                doc = {**_json(r[0]), "updatedAt": r[1].isoformat() + "Z" if hasattr(r[1], "isoformat") else str(r[1])}
                _histories[user] = doc
                return doc
        except Exception:
            pass
    return _histories.get(user)


def user_summary(user: str) -> dict:
    """What the harness holds for a user, for the app's privacy screen."""
    h = get_history(user)
    recs = 0
    if enabled():
        try:
            with _conn().cursor() as cur:
                cur.execute("SELECT COUNT(*) FROM recommendations WHERE persona = %s", (user,))
                recs = int(cur.fetchone()[0])
        except Exception:
            pass
    return {"user": user, "historyStored": h is not None, "updatedAt": (h or {}).get("updatedAt"),
            "workouts": len((h or {}).get("workouts", [])), "days": len((h or {}).get("daily", [])),
            "recommendations": recs, "ageCheck": get_verification(user) is not None,
            "guardrailEvents": count_events(user)}


# Names the app's privacy screen already shows for the original three tables.
_DELETE_KEYS = {"user_history": "history", "recommendations": "recommendations", "verifications": "verifications"}


def delete_user(user: str) -> dict:
    """Erases everything kept for a user: every table with a user column in DDL (history,
    recommendation records, the age check, guardrail events, and any table added later)."""
    removed = {"history": int(_histories.pop(user, None) is not None), "recommendations": 0,
               "verifications": int(_verifications.pop(user, None) is not None)}
    if enabled():
        with _conn().cursor() as cur:
            for table, column in user_tables():
                if table == "shoe_candidates":
                    continue            # keyed by demo persona name, never a user id
                cur.execute(f"DELETE FROM {table} WHERE {column} = %s", (user,))
                key = _DELETE_KEYS.get(table, table)
                removed[key] = max(removed.get(key, 0), cur.rowcount or 0)
    return removed


# --- guardrail events (plan item 9, eng review D1); no memory fallback: fail closed ---

class StoreUnavailable(Exception):
    """No persistent store: the events route answers 503 so the phone keeps them."""


def save_events(user: str, events: list[dict], upsert_types: set[str]) -> list[str]:
    """Stores each event once, keyed by (user, event id). A repeated id is skipped (a retry never
    doubles an event), except upsert types, where the newest copy wins. Returns every id now stored.
    Raises on any failure, so the phone never drops an event it thinks was stored."""
    if not enabled():
        raise StoreUnavailable()
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    insert, replace = [], []
    for e in events:
        at = datetime.fromisoformat(str(e["at"])).astimezone(timezone.utc).replace(tzinfo=None)
        row = (user, e["id"], e["type"], at, now, json.dumps(e, default=str))
        (replace if e["type"] in upsert_types else insert).append(row)
    cols = "(user_id, event_id, type, created_at, received_at, doc) VALUES (%s, %s, %s, %s, %s, %s)"
    with _conn().cursor() as cur:
        if insert:
            cur.executemany(f"INSERT IGNORE INTO guardrail_events {cols}", insert)
        if replace:
            cur.executemany(f"REPLACE INTO guardrail_events {cols}", replace)
    return [e["id"] for e in events]


def count_events(user: str) -> int:
    if not enabled():
        return 0
    try:
        with _conn().cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM guardrail_events WHERE user_id = %s", (user,))
            return int(cur.fetchone()[0])
    except Exception:
        return 0
