"""Per-device auth (eng review D7, task E9): one token per install, bound to its user."""
import pytest
from fastapi.testclient import TestClient

from api.index import app
from harness import config, store
from tests.sqlite_store import Conn

ALICE = "usr_aaaaaaaaaaaaaaaa"
BOB = "usr_bbbbbbbbbbbbbbbb"
client = TestClient(app)


@pytest.fixture(params=["memory", "singlestore"])
def backend(request, monkeypatch):
    if request.param == "singlestore":
        conn = Conn()
        monkeypatch.setenv("SINGLESTORE_URL", "user:pw@fake:3306/db")
        monkeypatch.setattr(store, "_conn", lambda: conn)
        return conn
    return None


def register(user, secret=""):
    return client.post("/devices", json={"user": user}, headers={"X-Harness-Secret": secret})


def auth(token):
    return {"Authorization": f"Bearer {token}"}


def test_a_device_reads_only_its_own_user(backend):
    alice = register(ALICE).json()["token"]
    bob = register(BOB).json()["token"]
    assert client.get(f"/users/{ALICE}", headers=auth(alice)).status_code == 200
    assert client.get(f"/users/{ALICE}", headers=auth(bob)).status_code == 401       # another user's data
    assert client.get(f"/users/{ALICE}").status_code == 401                          # no token
    assert client.get(f"/users/{ALICE}", headers=auth("made-up")).status_code == 401


def test_the_shared_secret_alone_reads_nothing(monkeypatch, backend):
    monkeypatch.setattr(config, "HARNESS_SECRET", "shared")
    register(ALICE, secret="shared")
    assert client.get(f"/users/{ALICE}", headers={"X-Harness-Secret": "shared"}).status_code == 401
    assert register(BOB).status_code == 401                                          # registering needs the secret


def test_a_user_registers_once(backend):
    assert register(ALICE).status_code == 200
    r = register(ALICE)
    assert r.status_code == 409 and r.json()["detail"] == "already_registered"


def test_delete_removes_the_device(backend):
    token = register(ALICE).json()["token"]
    assert client.delete(f"/users/{ALICE}", headers=auth(token)).status_code == 200
    assert client.get(f"/users/{ALICE}", headers=auth(token)).status_code == 401
    assert register(ALICE).status_code == 200                                        # a fresh start can register again
    if backend:
        assert len(backend.rows("devices")) == 1


def test_only_a_hash_is_kept(backend):
    token = register(ALICE).json()["token"]
    if backend:
        assert token not in str(backend.rows("devices"))
    else:
        from harness import devices
        assert token not in str(devices._memory)


def test_a_malformed_user_id_is_still_refused():
    assert register("jordan").status_code == 422
    assert client.get("/users/jordan").status_code == 422
