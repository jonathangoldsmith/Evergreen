"""SingleStore layer against an in-memory fake connection (no database needed)."""
import json
from datetime import datetime

import pytest
from fastapi.testclient import TestClient

from harness import store


class FakeCursor:
    def __init__(self, db):
        self.db, self.rows = db, []

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def execute(self, sql, args=()):
        s = " ".join(sql.split())
        if s.startswith(("CREATE", "SELECT 1")):
            return
        if s.startswith("DELETE FROM shoe_candidates"):
            self.db["c"] = [r for r in self.db["c"] if r[0] != args[0]]
        elif s.startswith("INSERT INTO shoe_candidates"):
            self.db["c"].append(args)
        elif s.startswith("SELECT doc FROM shoe_candidates"):
            self.rows = [(r[3],) for r in sorted(self.db["c"], key=lambda r: r[1]) if r[0] == args[0]]
        elif s.startswith("INSERT INTO recommendations"):
            self.db["r"].append(args)
        elif s.startswith("SELECT id, created_at") and "WHERE id" in s:
            self.rows = [r for r in self.db["r"] if r[0] == args[0]]
        elif s.startswith("SELECT id, created_at"):
            rows = [r for r in self.db["r"] if not args or r[2] == args[0]]
            self.rows = sorted(rows, key=lambda r: r[1], reverse=True)
        else:
            raise AssertionError(s)

    def executemany(self, sql, seq):
        for args in seq:
            self.execute(sql, args)

    def fetchall(self):
        return self.rows

    def fetchone(self):
        return self.rows[0] if self.rows else None


class FakeConn:
    def __init__(self):
        self.db = {"c": [], "r": []}

    def cursor(self):
        return FakeCursor(self.db)


@pytest.fixture
def fake_db(monkeypatch):
    conn = FakeConn()
    monkeypatch.setenv("SINGLESTORE_URL", "user:pw@fake:3306/db")
    monkeypatch.setattr(store, "_conn", lambda: conn)
    store._cache.clear()
    return conn


SNAP = {"persona": "jordan", "fetchedAt": "2026-11-20T18:00:00+00:00",
        "candidates": [{"id": "b-shoe", "name": "B"}, {"id": "a-shoe", "name": "A"}]}


def test_off_without_url(monkeypatch):
    monkeypatch.delenv("SINGLESTORE_URL", raising=False)
    monkeypatch.delenv("SINGLESTORE_DB_URL", raising=False)
    assert not store.enabled()
    assert store.load_candidates("jordan") is None and store.log_recommendation("jordan", "sie", "x", 1, {}) is None
    assert store.save_candidates(SNAP).startswith("off")


def test_candidates_round_trip_and_replace(fake_db):
    assert store.save_candidates(SNAP) == "saved 2 candidates"
    assert [c["id"] for c in store.load_candidates("jordan")] == ["a-shoe", "b-shoe"]
    store.save_candidates({**SNAP, "candidates": [{"id": "c-shoe", "name": "C"}]})
    assert [c["id"] for c in store.load_candidates("jordan")] == ["c-shoe"]
    assert store.load_candidates("alex") is None


def test_audit_write_and_read(fake_db):
    rid = store.log_recommendation("jordan", "sie", "New Balance 1080", 3800, {"shortlist": ["a"]})
    assert rid
    rec = store.get_recommendation(rid)
    assert rec["item"] == "New Balance 1080" and rec["record"] == {"shortlist": ["a"]} and rec["latencyMs"] == 3800
    assert [r["id"] for r in store.recent_recommendations("jordan")] == [rid]


def test_audit_failure_never_raises(monkeypatch):
    monkeypatch.setenv("SINGLESTORE_URL", "user:pw@fake:3306/db")
    def boom():
        raise ConnectionError("down")
    monkeypatch.setattr(store, "_conn", boom)
    store._cache.clear()
    assert store.log_recommendation("jordan", "sie", "x", 1, {}) is None
    assert store.load_candidates("jordan") is None
    assert store.save_candidates(SNAP).startswith("failed")


def test_recommend_logs_and_returns_audit_id(fake_db, monkeypatch):
    from api.index import app
    from harness import config
    from harness.clients import sie
    monkeypatch.setattr(config, "SENSO_API_KEY", "")
    monkeypatch.setattr(sie, "rerank", lambda *a, **k: (_ for _ in ()).throw(sie.SIEUnavailable("off")))
    body = {"persona": "jordan", "now": "2026-11-20T09:00:00-08:00", "shoes": {"boughtOn": "2026-10-22", "startMiles": 267},
            "raceDate": "2026-11-29", "mandate": []}
    c = TestClient(app)
    r = c.post("/shoes/recommend", json=body).json()
    assert r["auditId"]
    rec = c.get(f"/audit/{r['auditId']}").json()
    assert rec["item"] == r["purchase"]["item"] and rec["record"]["candidatesFrom"] == "catalog"
    assert rec["record"]["purchase"]["id"] == "shoes-2026-10-22"
    assert c.get("/audit/recent?persona=jordan").json()["recommendations"][0]["id"] == r["auditId"]
    assert c.get("/audit/nope").status_code == 404


def test_audit_routes_off_without_url(monkeypatch):
    from api.index import app
    monkeypatch.delenv("SINGLESTORE_URL", raising=False)
    monkeypatch.delenv("SINGLESTORE_DB_URL", raising=False)
    assert TestClient(app).get("/audit/recent").status_code == 503


def test_connect_args_handles_special_password_characters():
    a = store.connect_args("singlestoredb://admin:p@ss:w,rd/#1?x@svc-abc.aws.singlestore.com:3306/trackerplusplus?ssl=true")
    assert a == {"host": "svc-abc.aws.singlestore.com", "port": 3306, "user": "admin", "password": "p@ss:w,rd/#1?x",
                 "database": "trackerplusplus"}
    assert store.connect_args("u:p@h")["port"] == 3306


def test_connect_args_from_portal_mysql_command():
    a = store.connect_args("mysql -u admin -h svc-1-dml.aws-oregon-3.svc.singlestore.com -P 3306 "
                           "--default-auth=mysql_native_password --password='a|{:_b,?c$d@e@f'")
    assert a == {"user": "admin", "host": "svc-1-dml.aws-oregon-3.svc.singlestore.com", "port": 3306,
                 "password": "a|{:_b,?c$d@e@f"}
    assert store.connect_args("mysql -u u -h h -P 3333 --password=x trackerplusplus")["database"] == "trackerplusplus"
