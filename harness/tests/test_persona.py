import hashlib

import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient

from api.index import app
from harness.identity import persona as P

BODY = {"persona": "jordan", "now": "2026-11-20T09:00:00-08:00", "shoes": {"boughtOn": "2026-10-22", "startMiles": 267},
        "raceDate": "2026-11-29", "mandate": [{"id": "ask-first", "text": "Ask me.", "category": "any", "maxAutoCents": 50000}]}


def test_token_input_matches_persona_test_vector():
    out = P.token_input("a3f8c2d1e5b4a7f0c9d2e1b6a5f4c3d2e1b0a9f8c7d6e5f4a3b2c1d0e9f8a7b6",
                        "b1e9d4c7a2f5e8d3b6a1f0e9d8c7b6a5f4e3d2c1b0a9f8e7d6c5b4a3f2e1d0",
                        "c7a2f1e4d3b6a5f8e7d2c1b4a3f6e5d4c3b2a1f0e9d8c7b6a5f4e3d2c1b0a9").hex()
    assert out == ("000205a11543a705818ed8325787a8d62e3671e7da0d86e7f03be85c3550efa2d3c56bf1d5b977f76c6f352c19125d"
                   "517666d7e13683c5e6bfd20fda34f9a712367633677cf4111a585c9be12746e1d120b1eef6e2cd8d9faeccb6127510168ac689")


def test_blind_sign_finalize_round_trip():
    priv = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    pub, n, d = priv.public_key(), priv.private_numbers().public_numbers.n, priv.private_numbers().d
    msg = b"\x00\x02" + hashlib.sha256(b"x").digest() * 3
    blinded, inv = P.blind(pub, msg)
    blind_sig = pow(int.from_bytes(blinded, "big"), d, n).to_bytes(256, "big")     # what the issuer does
    assert len(P.finalize(pub, msg, blind_sig, inv)) == 256                      # raises if the signature is invalid


@pytest.fixture
def fake_persona(monkeypatch):
    monkeypatch.setenv("PERSONA_API_KEY", "persona_sandbox_test")
    monkeypatch.setattr(P, "create_relay", lambda claim=P.CLAIM: {"relay-token": "rt", "relay-secret": "rs", "relay-session-access-token": "sess"})
    calls = []
    def check(token, secret, claim=P.CLAIM):
        calls.append((token, secret))
        return {"claim_type": claim, "claim_result": "passed", "methodology": [{"method": "document_selfie", "result": "passed"}]}
    monkeypatch.setattr(P, "check", check)
    return calls


def test_purchases_locked_until_verified(fake_persona):
    from harness.clients import sie
    c = TestClient(app)
    r = c.post("/shoes/recommend", json=BODY).json()                 # mandate would auto-buy ($500 limit)...
    assert r["identity"]["required"] and not r["identity"]["verified"]
    assert r["purchase"]["status"] == "awaitingApproval" and "Persona" in r["purchase"]["noticed"]
    start = c.post("/verify/start", json={"persona": "jordan"}).json()
    assert start["sessionToken"] == "sess" and "relay-secret" not in str(start)
    st = c.post("/verify/check", json={"persona": "jordan"}).json()
    assert st["verified"] and st["method"] == "document_selfie" and fake_persona == [("rt", "rs")]
    r = c.post("/shoes/recommend", json=BODY).json()
    assert r["identity"]["verified"] and r["purchase"]["status"] == "bought"   # ...and now it can
    assert c.post("/verify/check", json={"persona": "jordan"}).json()["verified"] and len(fake_persona) == 1  # no second redeem


def test_check_before_start_is_409(fake_persona):
    assert TestClient(app).post("/verify/check", json={"persona": "sam"}).status_code == 409


def test_gate_off_without_key():
    r = TestClient(app).post("/shoes/recommend", json=BODY).json()
    assert not r["identity"]["required"] and r["purchase"]["status"] == "bought"
    assert TestClient(app).post("/verify/start", json={"persona": "jordan"}).status_code == 503
