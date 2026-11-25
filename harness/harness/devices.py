"""Per-device auth (eng review D7, task E9): each install registers once and gets its own
token; every `/users/{user}/...` route checks the token belongs to that user. The shared
secret only guards registration, which can create a new user but read none: a user who
already has a device can't register another. Only the token's hash is stored, in `devices`
(SingleStore), or in memory when the store is off (lost on a cold start, when the phone
registers again). DELETE removes the device with the rest of the user's data.
"""
from __future__ import annotations

import hashlib
import hmac
import secrets
import uuid
from datetime import datetime, timezone

from harness import store

_memory: dict[str, str] = {}          # user -> token hash, without SingleStore


class AlreadyRegistered(Exception):
    pass


def _hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def register(user: str) -> str:
    token = secrets.token_urlsafe(32)
    if not store.enabled():
        if user in _memory:
            raise AlreadyRegistered()
        _memory[user] = _hash(token)
        return token
    with store._conn().cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM devices WHERE user_id = %s", (user,))
        if int(cur.fetchone()[0]) > 0:
            raise AlreadyRegistered()
        cur.execute("INSERT INTO devices (device_id, user_id, token_hash, created_at) VALUES (%s, %s, %s, %s)",
                    (str(uuid.uuid4()), user, _hash(token), datetime.now(timezone.utc).replace(tzinfo=None)))
    return token


def verify(user: str, token: str) -> bool:
    if not token:
        return False
    wanted = _hash(token)
    if not store.enabled():
        saved = _memory.get(user)
        return bool(saved) and hmac.compare_digest(saved, wanted)
    with store._conn().cursor() as cur:
        cur.execute("SELECT token_hash FROM devices WHERE user_id = %s", (user,))
        return any(hmac.compare_digest(row[0], wanted) for row in cur.fetchall())


def forget(user: str) -> None:
    """The memory copy; SingleStore's row goes with delete_user's DDL walk."""
    _memory.pop(user, None)
