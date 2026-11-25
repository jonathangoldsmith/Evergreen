"""POST /users/{u}/events (plan item 9, eng review D1) and delete_user's DDL walk (E8)."""
import json
import re

import pytest
from fastapi.testclient import TestClient

from api.index import app
from harness import store

USER = "usr_0123456789abcdef"
OTHER = "usr_fedcba9876543210"
client = TestClient(app)


class FakeCursor:
    """Just enough SQL for guardrail_events and the deletes."""

    def __init__(self, db):
        self.db, self.rows, self.rowcount = db, [], 0

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def execute(self, sql, args=()):
        s = " ".join(sql.split())
        if self.db.get("fail"):
            raise RuntimeError("write failed")
        if s.startswith(("INSERT IGNORE INTO guardrail_events", "REPLACE INTO guardrail_events")):
            key = (args[0], args[1])
            if s.startswith("INSERT IGNORE") and key in self.db["events"]:
                return
            self.db["events"][key] = args
        elif s.startswith("SELECT COUNT(*) FROM guardrail_events"):
            self.rows = [(sum(1 for k in self.db["events"] if k[0] == args[0]),)]
        elif s.startswith("DELETE FROM"):
            table, column = re.match(r"DELETE FROM (\w+) WHERE (\w+)", s).groups()
            self.db["deleted"].append(table)
            if table == "guardrail_events":
                before = len(self.db["events"])
                self.db["events"] = {k: v for k, v in self.db["events"].items() if k[0] != args[0]}
                self.rowcount = before - len(self.db["events"])
            else:
                self.rowcount = 0
        else:
            raise AssertionError(s)

    def executemany(self, sql, seq):
        for args in seq:
            self.execute(sql, args)

    def fetchone(self):
        return self.rows[0] if self.rows else None


class FakeConn:
    def __init__(self):
        self.db = {"events": {}, "deleted": []}

    def cursor(self):
        return FakeCursor(self.db)


@pytest.fixture
def db(monkeypatch):
    conn = FakeConn()
    monkeypatch.setenv("SINGLESTORE_URL", "user:pw@fake:3306/db")
    monkeypatch.setattr(store, "_conn", lambda: conn)
    return conn.db


def pain(id="pain-2026-11-16", answer="aLittle", **over):
    e = {"id": id, "type": "pain", "at": "2026-11-22T18:05:00-08:00", "answer": answer,
         "ostrc": [1, 1, 0, 1], "weekStart": "2026-11-16"}
    e.update(over)
    return e


def flag(id="flag-0001"):
    return {"id": id, "type": "flag", "at": "2026-11-21T19:00:00-08:00", "kind": "spike", "unit": "km",
            "planned": 18, "suggested": 13, "longest30": 13, "runDay": "2026-11-22"}


def post(events, user=USER):
    return client.post(f"/users/{user}/events", json={"events": events})


def test_events_are_stored_and_their_ids_returned(db):
    r = post([pain(), flag()])
    assert r.status_code == 200
    assert r.json() == {"stored": ["pain-2026-11-16", "flag-0001"]}
    assert len(db["events"]) == 2
    doc = json.loads(db["events"][(USER, "flag-0001")][5])
    assert doc["suggested"] == 13 and doc["type"] == "flag"


def test_a_retry_never_doubles_an_event(db):
    post([pain()])
    r = post([pain(answer="yes")])              # same id again, e.g. after a lost response
    assert r.json()["stored"] == ["pain-2026-11-16"]
    assert len(db["events"]) == 1
    assert json.loads(db["events"][(USER, "pain-2026-11-16")][5])["answer"] == "aLittle"


def test_a_range_week_updates_in_place(db):
    week = {"id": "range_week-2026-11-16", "type": "range_week", "at": "2026-11-22T19:00:00-08:00",
            "weekStart": "2026-11-16", "daysCounted": 6, "daysInRange": 5, "swaps": 1, "comebacks": 0}
    post([week])
    post([{**week, "daysInRange": 6, "at": "2026-11-24T09:00:00-08:00"}])
    assert len(db["events"]) == 1
    assert json.loads(db["events"][(USER, "range_week-2026-11-16")][5])["daysInRange"] == 6


def test_without_a_store_it_fails_closed(monkeypatch):
    monkeypatch.delenv("SINGLESTORE_URL", raising=False)
    assert post([pain()]).status_code == 503


def test_a_write_failure_is_an_error_not_a_quiet_success(db):
    db["fail"] = True
    assert post([pain()]).status_code == 502


@pytest.mark.parametrize("bad", [
    pain(bodyPart="knee"),                       # the "where" never leaves the phone
    {**flag(), "title": "Long run 18 km"},       # no calendar titles
    pain(ostrc=[1, 1, 0]),                       # OSTRC is four answers
    pain(answer="maybe"),
    {"id": "x-00000001", "type": "mystery", "at": "2026-11-22T18:05:00-08:00"},
    {"id": "consent-0001", "type": "consent", "at": "2026-11-22T18:05:00-08:00", "uploads": False,
     "research": False, "version": 1},           # a "no" never leaves the phone
])
def test_unknown_types_and_fields_are_refused(db, bad):
    assert post([bad]).status_code == 422
    assert db["events"] == {}


def test_backtest_answers_carry_no_date_or_distance(db):
    ok = {"id": "bt-00000001", "type": "backtest_answer", "at": "2026-11-20T10:00:00-08:00", "answer": "yes",
          "flagged": True, "jumpPercent": 35, "monthsAgo": 3}
    assert post([ok]).status_code == 200
    assert post([{**ok, "id": "bt-00000002", "day": "2026-08-17"}]).status_code == 422
    assert post([{**ok, "id": "bt-00000003", "distanceKm": 24}]).status_code == 422
    assert post([{**ok, "id": "bt-00000004", "jumpPercent": 37}]).status_code == 422   # rounded to 5


def test_a_bad_user_id_is_refused(db):
    assert post([pain()], user="jordan").status_code == 422


def test_delete_erases_every_user_table_including_events(db):
    post([pain(), flag()])
    post([pain()], user=OTHER)
    r = client.delete(f"/users/{USER}")
    assert r.status_code == 200
    assert r.json()["deleted"]["guardrail_events"] == 2
    assert set(db["deleted"]) == {"verifications", "recommendations", "user_history", "guardrail_events"}
    assert list(db["events"]) == [(OTHER, "pain-2026-11-16")]


def test_every_table_with_a_user_column_is_in_the_delete():
    """A new table whose DDL has a user column is erased without touching delete_user (E8)."""
    tables = {t for t, _ in store.user_tables()}
    created = {re.search(r"CREATE TABLE IF NOT EXISTS (\w+)", s).group(1) for s in store.DDL}
    with_user = {t for t in created
                 if re.search(r"\b(user_id|persona)\b\s+VARCHAR", next(s for s in store.DDL if f"EXISTS {t} " in s))}
    assert tables == with_user
    assert "guardrail_events" in tables


def test_misses_and_comebacks_are_stored(db):
    """The push's logging (range plan item 16)."""
    miss = {"id": "miss-0123456789abcdef", "type": "miss", "at": "2026-11-19T13:30:00-08:00",
            "activityType": "Walking", "minutes": 30}
    offered = {"id": "comeback-offered-0123456789ab", "type": "comeback", "at": "2026-11-19T13:30:00-08:00",
               "action": "offered", "activityType": "Walking", "minutes": 15, "points": 40}
    assert post([miss, offered]).status_code == 200
    assert post([{**offered, "id": "comeback-x-00000001", "action": "accepted"}]).status_code == 422
    assert len(db["events"]) == 2
