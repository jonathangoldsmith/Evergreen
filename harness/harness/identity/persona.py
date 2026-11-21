"""Persona Relay age check: a yes/no claim ("over 18?") with no identity data.

Flow (all on the server; the API key never leaves the harness):
  1. create_relay(claim)       → relay token + secret (kept here) + session token (for the app's Persona flow)
  2. the person completes Persona's flow with the session token (in sandbox, claims pass without it)
  3. check(relay)              → challenge → blind a token → Persona signs it (Privacy Pass, API key)
                                 → unblind → redeem on the relay → {"claim_result": "passed" | "failed"}

Blind RSA follows RFC 9474 (RSABSSA-SHA384-PSS, salt 48, no message prefix, as Persona's production
protocol). token_input follows Persona's variant: 0x0002 || SHA256(nonce) || SHA256(mac) || SHA256(key-id),
each hashed as its text (checked against Persona's published test vector in tests)."""
from __future__ import annotations

import base64
import hashlib
import json
import os
import secrets
import uuid

import httpx
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding

from harness import config  # noqa: F401  (loads harness/.env)

BASE = "https://api.withpersona.com"
VERSION = "2026-09-29"
CLAIM = "age_over18_verified"
SALT_LEN = 48
TIMEOUT = 10


class PersonaError(RuntimeError):
    pass


def key() -> str:
    return os.environ.get("PERSONA_API_KEY", "").strip()


def enabled() -> bool:
    return bool(key())


def sandbox() -> bool:
    return os.environ.get("PERSONA_SANDBOX", "").lower() in ("1", "true", "yes") or key().startswith("persona_sandbox")


def _b64d(s: str) -> bytes:
    return base64.urlsafe_b64decode(s.replace("+", "-").replace("/", "_") + "=" * (-len(s) % 4))


def _b64u(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


# --- RFC 9474 blind RSA (PSS, SHA-384) ---

def _mgf1(seed: bytes, length: int) -> bytes:
    out, counter = b"", 0
    while len(out) < length:
        out += hashlib.sha384(seed + counter.to_bytes(4, "big")).digest()
        counter += 1
    return out[:length]


def _emsa_pss_encode(msg: bytes, em_bits: int, salt: bytes) -> bytes:
    m_hash = hashlib.sha384(msg).digest()
    em_len = (em_bits + 7) // 8
    h = hashlib.sha384(b"\x00" * 8 + m_hash + salt).digest()
    db = b"\x00" * (em_len - len(salt) - len(h) - 2) + b"\x01" + salt
    masked = bytes(a ^ b for a, b in zip(db, _mgf1(h, em_len - len(h) - 1)))
    masked = bytes([masked[0] & (0xFF >> (8 * em_len - em_bits))]) + masked[1:]
    return masked + h + b"\xbc"


def blind(public_key, msg: bytes) -> tuple[bytes, int]:
    n, e = public_key.public_numbers().n, public_key.public_numbers().e
    k = (n.bit_length() + 7) // 8
    m = int.from_bytes(_emsa_pss_encode(msg, n.bit_length() - 1, secrets.token_bytes(SALT_LEN)), "big")
    while True:
        r = secrets.randbelow(n - 2) + 2
        try:
            inv = pow(r, -1, n)
            break
        except ValueError:
            continue
    return (m * pow(r, e, n) % n).to_bytes(k, "big"), inv


def finalize(public_key, msg: bytes, blind_sig: bytes, inv: int) -> bytes:
    n = public_key.public_numbers().n
    k = (n.bit_length() + 7) // 8
    sig = (int.from_bytes(blind_sig, "big") * inv % n).to_bytes(k, "big")
    public_key.verify(sig, msg, padding.PSS(mgf=padding.MGF1(hashes.SHA384()), salt_length=SALT_LEN), hashes.SHA384())
    return sig


def token_input(nonce: str, mac: str, key_id: str) -> bytes:
    h = lambda s: hashlib.sha256(s.encode()).digest()
    return b"\x00\x02" + h(nonce) + h(mac) + h(key_id)


# --- Persona calls ---

def _headers(extra: dict | None = None) -> dict:
    return {"Content-Type": "application/json", "Persona-Version": VERSION, **(extra or {})}


def create_relay(claim: str = CLAIM) -> dict:
    """Returns relay-token, relay-secret (keep server-side), relay-session-access-token (give to the app)."""
    r = httpx.post(f"{BASE}/api/privacy/v1/relays", timeout=TIMEOUT,
                   headers=_headers({"Authorization": f"Bearer {key()}"}),
                   json={"claim-type": claim, "encryption-key-jwk": None, "sandbox": sandbox()})
    if r.status_code >= 300:
        raise PersonaError(f"create relay {r.status_code}: {r.text[:200]}")
    return r.json()


def _privacy_pass(claim: str) -> tuple[str, dict]:
    ch = httpx.post(f"{BASE}/api/privacy/v1/relays/challenge", timeout=TIMEOUT, headers=_headers(),
                    json={"claim-type": claim, "sandbox": sandbox()})
    if ch.status_code >= 300:
        raise PersonaError(f"challenge {ch.status_code}: {ch.text[:200]}")
    c = ch.json()
    challenge = json.loads(_b64d(c["challenge"]))
    pub = serialization.load_der_public_key(_b64d(c["token-key"]))
    nonce = secrets.token_hex(32)
    msg = token_input(nonce, challenge["mac"], c["token-key-id"])
    blinded, inv = blind(pub, msg)
    r = httpx.post(f"{BASE}/api/v1/privacy-passes", timeout=TIMEOUT,
                   headers=_headers({"Authorization": f"Bearer {key()}"}),
                   json={"blinded-token": _b64u(blinded), "key-id": c["token-key-id"]})
    if r.status_code >= 300:
        raise PersonaError(f"privacy pass {r.status_code}: {r.text[:200]}")
    body = r.json()
    blind_sig = body.get("blind-sig") or (body.get("data") or {}).get("attributes", {}).get("blind-sig")
    sig = finalize(pub, msg, _b64d(blind_sig), inv)
    token = {"token_nonce": nonce, "signature": _b64u(sig), "key_id": c["token-key-id"], "challenge": challenge}
    return _b64u(json.dumps(token, separators=(",", ":")).encode()), c


def check(relay_token: str, relay_secret: str, claim: str = CLAIM) -> dict:
    """Redeem a Privacy Pass on the relay. Returns {claim_result, claim_type, methodology?, token_consumed}."""
    token, _ = _privacy_pass(claim)
    r = httpx.post(f"{BASE}/api/privacy/v1/relays/{relay_token}/generate-claim", timeout=TIMEOUT,
                   headers=_headers({"Authorization": f"PrivateToken token={token}", "Persona-Relay-Secret": relay_secret,
                                     "Idempotency-Key": str(uuid.uuid4())}))
    if r.status_code >= 300:
        raise PersonaError(f"generate claim {r.status_code}: {r.text[:300]}")
    d = r.json()
    payload = d.get("claim-payload")
    claim_doc = json.loads(payload) if isinstance(payload, str) else (payload or {})
    return {**claim_doc, "token_consumed": d.get("token-consumed"), "encryption": d.get("claim-payload-encryption")}
