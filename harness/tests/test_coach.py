"""The coach view (range plan item 20; X7, X10; E13), on SQLite."""
import pytest
from fastapi.testclient import TestClient

from api.index import app
from harness import coach, store
from tests.sqlite_store import Conn

RUNNER = "usr_aaaaaaaaaaaaaaaa"
client = TestClient(app)


@pytest.fixture
def db(monkeypatch):
    conn = Conn()
    monkeypatch.setenv("SINGLESTORE_URL", "user:pw@fake:3306/db")
    monkeypatch.setattr(store, "_conn", lambda: conn)
    return conn


def events(*items):
    assert client.post(f"/users/{RUNNER}/events", json={"events": list(items)}).status_code == 200


def flag(run="swap-aaaaaaaaaaaa", kind="spike", injury=False, day="2026-11-22"):
    return {"id": f"flag-{run}-{kind}", "type": "flag", "at": "2026-11-21T19:00:00-08:00", "kind": kind, "unit": "km",
            "planned": 18, "suggested": 13, "longest30": 13, "injuryAdjusted": injury, "runDay": day, "run": run}


def choice(run="swap-aaaaaaaaaaaa", what="accept", kind="spike", n=1):
    return {"id": f"choice-{run}-{n}", "type": "choice", "at": f"2026-11-21T19:0{n}:00-08:00", "choice": what,
            "kind": kind, "run": run, "runDay": "2026-11-22"}


PAIN = {"id": "pain-2026-11-16-1", "type": "pain", "at": "2026-11-22T18:05:00-08:00", "answer": "aLittle",
        "ostrc": [1, 1, 0, 1], "weekStart": "2026-11-16"}
WEEK = {"id": "range_week-2026-11-16", "type": "range_week", "at": "2026-11-22T19:00:00-08:00",
        "weekStart": "2026-11-16", "daysCounted": 6, "daysInRange": 5, "swaps": 1, "comebacks": 0}


def share(feelings=False, name="Sam"):
    r = client.post(f"/users/{RUNNER}/coach-shares", json={"displayName": name, "includeFeelings": feelings})
    assert r.status_code == 200
    return r.json()


def page(token):
    return client.get(f"/coach/{token}")


def test_a_share_is_a_128_bit_token_stored_only_as_a_hash(db):
    made = share()
    assert len(made["token"]) >= 22 and made["state"] == "active"
    rows = db.rows("coach_shares")
    assert made["token"] not in str(rows)
    assert "token" not in str(client.get(f"/users/{RUNNER}/coach-shares").json())


def test_without_the_tick_swaps_say_only_why_in_general(db):
    events(flag(), choice(), flag("swap-bbbbbbbbbbbb", "sore"), choice("swap-bbbbbbbbbbbb", kind="sore"), PAIN, WEEK)
    html = page(share()["token"]).text
    assert "18 km → 13 km" in html
    assert "Shortened: big jump" in html and "Shortened: how you felt" in html
    assert "sore" not in html.lower() and "pain" not in html.lower().replace("for pain or injury", "")
    assert "In range 5 of 6 days · 1 swap" in html


def test_with_the_tick_the_coach_sees_how_the_runner_felt(db):
    events(flag(kind="sore"), choice(kind="sore"), PAIN, WEEK)
    html = page(share(feelings=True)["token"]).text
    assert "Felt sore" in html and "A little pain" in html
    assert "[1, 1, 0, 1]" not in html and "ostrc" not in html.lower()      # OSTRC is never shown


def test_an_injury_adjusted_longest_needs_the_tick(db):
    events(flag(injury=True), choice())
    assert "30-day longest" not in page(share()["token"]).text
    assert "30-day longest 13 km" in page(share(feelings=True)["token"]).text


def test_an_undone_or_kept_swap_isnt_shown(db):
    events(flag(), choice(), choice(what="undo", n=2), flag("swap-bbbbbbbbbbbb"), choice("swap-bbbbbbbbbbbb", "keep"))
    assert "No changes in the last 4 weeks. Every run stayed in range." in page(share()["token"]).text


def test_fields_are_escaped(db):
    html = page(share(name="<script>alert(1)</script>")["token"]).text
    assert "<script>alert" not in html and "&lt;script&gt;" in html


def test_revoked_expired_and_unknown_links_read_the_same(db):
    a, b = share(), share()
    client.delete(f"/users/{RUNNER}/coach-shares/{a['id']}")
    db.db.execute("UPDATE coach_shares SET expires_at = '2000-01-01 00:00:00' WHERE share_id = ?", (b["id"],))
    pages = {page(a["token"]).text, page(b["token"]).text, page("not-a-real-token").text}
    assert len(pages) == 1 and coach.INACTIVE in pages.pop()


def test_the_page_is_never_indexed_or_cached(db):
    r = page(share()["token"])
    assert r.status_code == 200 and r.headers["content-type"].startswith("text/html")
    assert "noindex" in r.headers["x-robots-tag"] and r.headers["cache-control"] == "no-store"
    assert '<meta name="robots" content="noindex, nofollow">' in r.text


def test_the_tick_can_change_and_a_share_can_be_renewed(db):
    events(flag(kind="tired"), choice(kind="tired"))
    made = share()
    assert "Shortened: how you felt" in page(made["token"]).text
    r = client.patch(f"/users/{RUNNER}/coach-shares/{made['id']}", json={"includeFeelings": True, "renew": True})
    assert r.json()["includeFeelings"] is True
    assert "Felt tired" in page(made["token"]).text


def test_deleting_the_runner_ends_every_link(db):
    made = share()
    client.delete(f"/users/{RUNNER}")
    assert coach.INACTIVE in page(made["token"]).text
    assert db.rows("coach_shares") == []


def test_without_a_store_sharing_fails_closed_and_links_read_inactive(monkeypatch):
    monkeypatch.delenv("SINGLESTORE_URL", raising=False)
    assert client.post(f"/users/{RUNNER}/coach-shares", json={"displayName": "Sam"}).status_code == 503
    assert coach.INACTIVE in page("anything").text
