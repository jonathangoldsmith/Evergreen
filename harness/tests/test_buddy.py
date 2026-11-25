"""The accountability buddy (range plan item 22; tasks T4, T5, E11, E12), on SQLite."""
import re

import pytest
from fastapi.testclient import TestClient

from api.index import app
from harness import buddy, store
from tests.sqlite_store import Conn

INVITER = "usr_1111111111111111"
FRIEND = "usr_2222222222222222"
OTHER = "usr_3333333333333333"
TOKEN = "ab" * 32
client = TestClient(app)


@pytest.fixture
def db(monkeypatch):
    conn = Conn()
    monkeypatch.setenv("SINGLESTORE_URL", "user:pw@fake:3306/db")
    monkeypatch.setattr(store, "_conn", lambda: conn)
    return conn


@pytest.fixture
def pushes(monkeypatch):
    """Every APNs send, answered by `pushes.answer`."""
    class Pushes(list):
        answer = "sent"
    sent = Pushes()

    def fake(token, env, title, body):
        sent.append((token, env, title, body))
        return sent.answer
    monkeypatch.setattr(buddy.apns, "send", fake)
    return sent


def invite(user=INVITER, name="Alex"):
    return client.post(f"/users/{user}/buddy", json={"displayName": name})


def redeem(code, user=FRIEND):
    return client.post(f"/users/{user}/buddy/redeem", json={"code": code})


def pair(db):
    code = invite().json()["code"]
    assert redeem(code).status_code == 200
    client.put(f"/users/{FRIEND}/push-token", json={"token": TOKEN, "environment": "sandbox"})
    return code


def workout(id="w-0000000001", minutes=15, kind="Walking", user=INVITER):
    return client.post(f"/users/{user}/events", json={"events": [{
        "id": id, "type": "workout_completed", "at": "2026-11-25T18:45:00-08:00",
        "activityType": kind, "minutes": minutes}]})


def test_an_invite_is_8_characters_of_40_bits(db):
    r = invite()
    assert r.status_code == 200
    assert re.fullmatch(r"[0-9A-HJKMNP-TV-Z]{8}", r.json()["code"])
    assert len(buddy.CODE_ALPHABET) == 32
    assert client.get(f"/users/{INVITER}/buddy").json()["status"] == "invited"


def test_redeeming_pairs_both_sides_without_sharing_ids(db):
    pair(db)
    friend = client.get(f"/users/{FRIEND}/buddy").json()
    inviter = client.get(f"/users/{INVITER}/buddy").json()
    assert friend["status"] == "paired" and friend["role"] == "friend" and friend["buddyName"] == "Alex"
    assert inviter["status"] == "paired" and inviter["role"] == "inviter"
    for body in (friend, inviter):
        assert "usr_" not in str(body)             # T5: no one else's anonymous id


@pytest.mark.parametrize("case", ["own", "used", "expired", "already", "unknown"])
def test_codes_that_cant_be_used_are_refused_kindly(db, case):
    code = invite().json()["code"]
    if case == "own":
        r = redeem(code, user=INVITER)
        assert r.json()["detail"] == "own_code"
    elif case == "used":
        redeem(code)
        r = redeem(code, user=OTHER)
        assert r.json()["detail"] == "used"
    elif case == "expired":
        db.db.execute("UPDATE buddy_pairs SET expires_at = '2000-01-01 00:00:00'")
        r = redeem(code)
        assert r.json()["detail"] == "expired"
    elif case == "already":
        other = invite(user=OTHER, name="Sam").json()["code"]
        redeem(other)
        r = redeem(code)
        assert r.json()["detail"] == "already_paired"
    else:
        r = redeem("ZZZZZZZZ")
        assert r.status_code == 404
    assert r.status_code in (404, 409)


def test_the_11th_failed_redeem_in_an_hour_is_refused(db):
    for _ in range(10):
        assert redeem("ZZZZZZZZ").status_code == 404
    code = invite().json()["code"]
    assert redeem(code).status_code == 429              # T4: even a good code


def test_one_code_pairs_once(db):
    code = invite().json()["code"]
    assert redeem(code).status_code == 200
    assert redeem(code, user=OTHER).status_code == 409
    assert len([r for r in db.rows("buddy_pairs") if r[4] == "paired"]) == 1


def test_the_inviters_workout_sends_the_friend_one_note(db, pushes):
    pair(db)
    r = workout()
    assert r.json()["buddyNotes"] == {"queued": 1, "sent": 1}
    assert pushes == [(TOKEN, "sandbox", "Your buddy", "Alex did a 15-minute walk.")]
    notes = client.get(f"/users/{FRIEND}/buddy").json()["notes"]
    assert [n["text"] for n in notes] == ["Alex did a 15-minute walk."]
    assert "comeback" not in str(notes).lower()


def test_the_friends_workouts_are_never_shared(db, pushes):
    pair(db)
    client.put(f"/users/{INVITER}/push-token", json={"token": "cd" * 32, "environment": "sandbox"})
    workout(user=FRIEND)
    assert pushes == []


def test_at_most_3_notes_a_day(db, pushes):
    pair(db)
    for i in range(5):
        workout(id=f"w-000000000{i}")
    assert len(pushes) == 3


def test_a_failed_note_is_retried_on_the_next_events_call(db, pushes):
    pair(db)
    pushes.answer = "failed"
    workout(id="w-0000000001")
    assert client.get(f"/users/{FRIEND}/buddy").json()["notes"] == []
    pushes.answer = "sent"
    r = client.post(f"/users/{INVITER}/events", json={"events": [{
        "id": "pain-2026-11-16-1", "type": "pain", "at": "2026-11-22T18:05:00-08:00",
        "answer": "no", "weekStart": "2026-11-16"}]})
    assert r.json()["buddyNotes"] == {"queued": 0, "sent": 1}     # any later events call retries it
    texts = [n["text"] for n in client.get(f"/users/{FRIEND}/buddy").json()["notes"]]
    assert texts == ["Alex did a 15-minute walk."]


def test_a_note_older_than_a_day_is_dropped(db, pushes):
    pair(db)
    pushes.answer = "failed"
    workout(id="w-0000000001")
    db.db.execute("UPDATE buddy_notes SET created_at = '2000-01-01 00:00:00'")
    pushes.answer = "sent"
    workout(id="w-0000000002")
    statuses = sorted(r[4] for r in db.rows("buddy_notes"))
    assert statuses == ["dropped", "sent"]


def test_an_invalid_token_is_removed(db, pushes):
    pair(db)
    pushes.answer = "invalid"
    workout()
    assert db.rows("push_tokens") == []


def test_either_side_can_unpair_and_both_tokens_go(db):
    pair(db)
    client.put(f"/users/{INVITER}/push-token", json={"token": "cd" * 32, "environment": "production"})
    assert client.delete(f"/users/{FRIEND}/buddy").status_code == 200
    assert client.get(f"/users/{INVITER}/buddy").json()["status"] == "none"
    assert db.rows("push_tokens") == []


def test_deleting_a_person_removes_the_pair_but_not_the_other_persons_data(db, pushes):
    pair(db)
    workout()
    store._histories[INVITER] = {"workouts": []}
    r = client.delete(f"/users/{FRIEND}")
    assert r.status_code == 200
    assert db.rows("buddy_pairs") == [] and db.rows("buddy_notes") == [] and db.rows("push_tokens") == []
    assert client.get(f"/users/{INVITER}/buddy").json()["status"] == "none"
    assert INVITER in store._histories
    store._histories.clear()


def test_a_display_name_is_checked(db):
    assert invite(name="").status_code == 422
    assert invite(name="x" * 41).status_code == 422
    assert invite(name="Al\x00ex").status_code == 422
    assert invite(name="  Alex  ").status_code == 200
    assert client.patch(f"/users/{INVITER}/buddy", json={"displayName": "Alexandra"}).json()["yourName"] == "Alexandra"


def test_without_a_store_buddy_routes_fail_closed(monkeypatch):
    monkeypatch.delenv("SINGLESTORE_URL", raising=False)
    assert invite().status_code == 503
    assert client.put(f"/users/{INVITER}/push-token", json={"token": TOKEN, "environment": "sandbox"}).status_code == 503


def test_a_push_token_must_look_like_one(db):
    assert client.put(f"/users/{INVITER}/push-token", json={"token": "not hex!", "environment": "sandbox"}).status_code == 422
    assert client.put(f"/users/{INVITER}/push-token", json={"token": TOKEN, "environment": "staging"}).status_code == 422
