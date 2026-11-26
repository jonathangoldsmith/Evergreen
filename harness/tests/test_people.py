"""A real person's Apple Health history: used over the persona files, kept per anonymous user, erasable."""
from datetime import datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from api.index import app
from harness import config, store
from harness.clients import sie
from harness.recommend import workouts as W

NOW = datetime.fromisoformat("2026-11-20T09:00:00-08:00")
USER = "usr_0123456789abcdef"
client = TestClient(app)


@pytest.fixture(autouse=True)
def _clean(monkeypatch):
    store._histories.clear()
    monkeypatch.setattr(sie, "chat_json", lambda *a, **k: (_ for _ in ()).throw(sie.SIEUnavailable("off")))
    monkeypatch.setattr(sie, "rerank", lambda *a, **k: (_ for _ in ()).throw(sie.SIEUnavailable("off")))
    yield
    store._histories.clear()


def history(weeks: int = 4, km: float = 8.0) -> dict:
    """Tuesday and Thursday 7 PM runs and a Saturday 9 AM long run, for `weeks` weeks before NOW."""
    out = []
    for back in range(1, weeks * 7 + 1):
        day = NOW - timedelta(days=back)
        wd = day.weekday()
        if wd in (1, 3, 5):
            hour, minutes = (9, 75) if wd == 5 else (19, 40)
            start = day.replace(hour=hour, minute=0)
            out.append({"activityType": "Running", "start": start.isoformat(),
                        "end": (start + timedelta(minutes=minutes)).isoformat(),
                        "avgHeartRate": 150, "distanceKm": km * (1.8 if wd == 5 else 1)})
    daily = [{"date": (NOW - timedelta(days=d)).date().isoformat(), "sleepMin": 450, "restingHeartRate": 55}
             for d in range(1, 29)]
    return {"workouts": out, "daily": daily}


def body(**over):
    b = {"persona": "me", "now": NOW.isoformat(), "user": USER, "history": history()}
    b.update(over)
    return b


def test_the_week_follows_the_persons_own_history():
    plan = W.build(W.WorkoutsRequest(**body()))
    assert plan["historySource"] == "phone"
    days = {s["date"].weekday(): s for s in plan["sessions"]}
    assert days[1]["activityType"] == "Running" and days[1]["hour"] == 19
    assert days[5]["activityType"] == "Running" and days[5]["hour"] == 9
    assert plan["signals"]["sleep7Min"] == 450 and plan["signals"]["rhr7"] == 55


def test_history_is_kept_for_the_user_and_reused():
    W.build(W.WorkoutsRequest(**body()))
    later = W.build(W.WorkoutsRequest(**body(history=None)))
    assert later["historySource"] == "stored"
    assert {s["date"].weekday() for s in later["sessions"]} >= {1, 3, 5}


def test_demo_personas_still_read_their_files():
    plan = W.build(W.WorkoutsRequest(persona="jordan", now=NOW.isoformat()))
    assert plan["historySource"] == "persona"


def test_an_unknown_person_without_history_is_a_404():
    r = client.post("/workouts/recommend", json={"persona": "me", "now": NOW.isoformat(), "user": USER})
    assert r.status_code == 404


def test_shoe_wear_comes_from_the_phones_distances():
    # 12 weeks of runs at 8 km (14.4 km on Saturdays) on a pair bought 12 weeks ago with 150 mi already on it.
    b = body(history=history(weeks=12), shoes={"boughtOn": (NOW - timedelta(days=84)).date().isoformat(), "startMiles": 150},
             raceDate=(NOW + timedelta(days=9)).date().isoformat(), mandate=[])
    r = client.post("/shoes/recommend", json=b)
    assert r.status_code == 200, r.text
    out = r.json()
    assert out["historySource"] == "phone"
    assert out["condition"]["runsCounted"] == 36 and out["condition"]["status"] == "replace"
    assert out["purchase"]["status"] == "awaitingApproval"


def test_a_bad_user_id_is_refused():
    r = client.post("/workouts/recommend", json=body(user="jonathan@example.com"))
    assert r.status_code == 422
    assert client.get("/users/not-an-id").status_code == 422


def test_users_route_shows_and_erases_what_is_kept(monkeypatch):
    monkeypatch.setattr(config, "HARNESS_SECRET", "s")
    client.post("/workouts/recommend", json=body(), headers={"X-Harness-Secret": "s"})
    # Who may read /users/{user} is the device token's job now (tests/test_devices.py).

    kept = client.get(f"/users/{USER}", headers={"X-Harness-Secret": "s"}).json()
    assert kept["historyStored"] and kept["workouts"] == 12 and kept["days"] == 28

    gone = client.delete(f"/users/{USER}", headers={"X-Harness-Secret": "s"})
    assert gone.status_code == 200 and gone.json()["deleted"]["history"] == 1
    assert client.get(f"/users/{USER}", headers={"X-Harness-Secret": "s"}).json()["historyStored"] is False
    assert client.post("/workouts/recommend", json=body(history=None), headers={"X-Harness-Secret": "s"}).status_code == 404


# --- delete_user's original three tables (eng review D3, task E3): characterization ---

OTHER = "usr_fedcba9876543210"


def _rows(conn, table, column, user):
    cur = conn.db.execute(f"SELECT COUNT(*) FROM {table} WHERE {column} = ?", (user,))
    return cur.fetchone()[0]


def test_delete_still_erases_the_original_three_tables(monkeypatch):
    """History, recommendation records and the age check: gone for this person, kept for
    everyone else, and counted under the keys Your data already shows."""
    from tests.sqlite_store import Conn
    conn = Conn()
    monkeypatch.setenv("SINGLESTORE_URL", "user:pw@fake:3306/db")
    monkeypatch.setattr(store, "_conn", lambda: conn)
    for who in (USER, OTHER):
        store.save_history(who, {"workouts": [], "days": []})
        store.save_verification(who, {"relay_token": "t", "relay_secret": "s", "status": "passed"})
        for n in range(2):
            conn.db.execute("INSERT INTO recommendations (id, created_at, persona, source, item, latency_ms, doc) "
                            "VALUES (?, '2026-11-20 10:00:00', ?, 'rules', 'Pacer 9', 10, '{}')", (f"{who}-{n}", who))

    removed = store.delete_user(USER)

    assert removed["history"] == 1 and removed["recommendations"] == 2 and removed["verifications"] == 1
    for table, column in (("user_history", "user_id"), ("recommendations", "persona"), ("verifications", "persona")):
        assert _rows(conn, table, column, USER) == 0, table
        assert _rows(conn, table, column, OTHER) >= 1, table
    assert store.get_history(OTHER) is not None and USER not in store._histories


def test_without_a_store_delete_still_clears_the_memory_copies(monkeypatch):
    monkeypatch.delenv("SINGLESTORE_URL", raising=False)
    store.save_history(USER, {"workouts": []})
    store.save_verification(USER, {"relay_token": "t", "relay_secret": "s", "status": "passed"})
    assert store.delete_user(USER) == {"history": 1, "recommendations": 0, "verifications": 1}
    assert USER not in store._histories and USER not in store._verifications


# --- a DELETE test per table (range plan task T6) ---

THIRD = "usr_1111222233334444"


def _fill(conn, table: str, values: dict) -> None:
    """One row in `table`: the given columns, and a placeholder in every other NOT NULL one."""
    import uuid
    row = {}
    for _, name, kind, notnull, _, _ in conn.db.execute(f"PRAGMA table_info({table})").fetchall():
        if name in values:
            row[name] = values[name]
        elif notnull:
            row[name] = 1 if kind.upper().startswith(("INT", "TINYINT")) else (
                "{}" if name == "doc" else "2026-11-20 10:00:00" if name.endswith("_at") or name == "at"
                else str(uuid.uuid4()))
    cols = ", ".join(row)
    conn.db.execute(f"INSERT INTO {table} ({cols}) VALUES ({', '.join('?' * len(row))})", tuple(row.values()))


def _person_tables():
    return [(t, c) for t, c in store.user_tables() if t != "shoe_candidates"]


@pytest.mark.parametrize("table,column", _person_tables(), ids=lambda v: v)
def test_delete_erases_this_persons_rows_in_every_table_and_keeps_others(monkeypatch, table, column):
    """Each user table on real SQL: this person's row goes, another person's stays, and the
    answer counts it. Covers each user column, so a pair goes whichever side is deleted."""
    from tests.sqlite_store import Conn
    conn = Conn()
    monkeypatch.setenv("SINGLESTORE_URL", "user:pw@fake:3306/db")
    monkeypatch.setattr(store, "_conn", lambda: conn)
    others = {c: THIRD for t, c in store.user_tables() if t == table and c != column}
    _fill(conn, table, {**others, column: USER})
    _fill(conn, table, {**others, column: OTHER})

    removed = store.delete_user(USER)

    assert _rows(conn, table, column, USER) == 0
    assert _rows(conn, table, column, OTHER) == 1
    assert removed[store._DELETE_KEYS.get(table, table)] == 1


def test_deleting_one_side_of_a_pair_leaves_the_other_persons_own_rows(monkeypatch):
    """The paired-person case: deleting the friend ends the pair and its notes, while the
    inviter's own history, events, device and push token stay."""
    from tests.sqlite_store import Conn
    conn = Conn()
    monkeypatch.setenv("SINGLESTORE_URL", "user:pw@fake:3306/db")
    monkeypatch.setattr(store, "_conn", lambda: conn)
    _fill(conn, "buddy_pairs", {"inviter_id": OTHER, "friend_id": USER, "status": "paired"})
    _fill(conn, "buddy_notes", {"inviter_id": OTHER, "friend_id": USER})
    for table in ("user_history", "guardrail_events", "devices", "push_tokens"):
        _fill(conn, table, {"user_id": OTHER})

    store.delete_user(USER)

    assert conn.rows("buddy_pairs") == [] and conn.rows("buddy_notes") == []
    for table in ("user_history", "guardrail_events", "devices", "push_tokens"):
        assert _rows(conn, table, "user_id", OTHER) == 1, table
