"""Apple push for buddy notes (range plan item 22, X8).

Token-based: a .p8 key from the developer account, kept only in server environment
variables (never in the repo): APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY (the key
file's contents) and APNS_TOPIC (the app's bundle id). One HTTP/2 client and one JWT
per warm instance, as Apple asks. Each device token carries its environment
(production for TestFlight, sandbox for Xcode builds) and picks the matching host.
"""
from __future__ import annotations

import os
import threading
import time
from typing import Literal

HOSTS = {"production": "https://api.push.apple.com", "sandbox": "https://api.sandbox.push.apple.com"}
JWT_TTL_S = 50 * 60          # Apple rejects tokens older than an hour
TIMEOUT_S = 5.0

Outcome = Literal["sent", "invalid", "failed"]

_lock = threading.Lock()
_client = None
_jwt: tuple[float, str] | None = None


def configured() -> bool:
    return all(os.environ.get(k) for k in ("APNS_KEY_ID", "APNS_TEAM_ID", "APNS_PRIVATE_KEY", "APNS_TOPIC"))


def _token() -> str:
    global _jwt
    import jwt
    with _lock:
        if _jwt and time.time() - _jwt[0] < JWT_TTL_S:
            return _jwt[1]
        now = int(time.time())
        key = os.environ["APNS_PRIVATE_KEY"].replace("\\n", "\n")
        signed = jwt.encode({"iss": os.environ["APNS_TEAM_ID"], "iat": now}, key, algorithm="ES256",
                            headers={"kid": os.environ["APNS_KEY_ID"]})
        _jwt = (now, signed)
        return signed


def _http():
    global _client
    import httpx
    with _lock:
        if _client is None:
            _client = httpx.Client(http2=True, timeout=TIMEOUT_S)
        return _client


def send(device_token: str, environment: str, title: str, body: str) -> Outcome:
    """One alert. "invalid" means drop the token (410, or 400 BadDeviceToken); "failed" means
    try again later (timeout, server error, or no key configured)."""
    if not configured():
        return "failed"
    host = HOSTS.get(environment, HOSTS["production"])
    try:
        response = _http().post(
            f"{host}/3/device/{device_token}",
            headers={"authorization": f"bearer {_token()}", "apns-topic": os.environ["APNS_TOPIC"],
                     "apns-push-type": "alert", "apns-priority": "10"},
            json={"aps": {"alert": {"title": title, "body": body}, "sound": "default"}},
        )
    except Exception:
        return "failed"
    if response.status_code == 200:
        return "sent"
    reason = ""
    try:
        reason = response.json().get("reason", "")
    except Exception:
        pass
    if response.status_code == 410 or (response.status_code == 400 and reason == "BadDeviceToken"):
        return "invalid"
    return "failed"
