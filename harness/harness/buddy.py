"""The accountability buddy (range plan item 22, X6 and X8; eng review D6; tasks T4, T5, E11, E12).

A push-side person invites one friend with an 8-character code (40 bits, 48 hours, works
once). When the inviter finishes a workout, the phone logs `workout_completed`, and the
friend gets one note: "Alex did a 15-minute walk." Never misses, never "comeback".
Each note is stored pending or sent; one that fails is retried on the pair's next events
call and dropped after 24 hours. At most 3 notes per pair per day. Everything here needs
the persistent store (SingleStore) and fails closed without it.

Responses never carry another user's anonymous id (T5).
"""
from __future__ import annotations

import hashlib
import json
import secrets
import uuid
from datetime import datetime, timedelta, timezone

from harness import apns, store

CODE_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"  # Crockford base32: no I, L, O, U
CODE_LENGTH = 8                                      # 32^8 = 2^40 (task T4)
INVITE_TTL = timedelta(hours=48)
REDEEM_FAILURES_PER_HOUR = 10
NOTES_PER_DAY = 3
NOTE_RETRY_WINDOW = timedelta(hours=24)
NAME_MAX = 40


class BuddyError(Exception):
    """A friendly refusal; `code` is what the app shows."""

    def __init__(self, code: str, status: int = 409):
        super().__init__(code)
        self.code, self.status = code, status


def _now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _hash(code: str) -> str:
    return hashlib.sha256(code.strip().upper().encode()).hexdigest()


def _need_store():
    if not store.enabled():
        raise store.StoreUnavailable()


def clean_name(name: str) -> str:
    """1–40 characters, trimmed, no control characters (eng re-run Section 1 #5)."""
    name = " ".join((name or "").split())
    if not name or len(name) > NAME_MAX or any(ord(c) < 32 or ord(c) == 127 for c in name):
        raise BuddyError("bad_name", 422)
    return name


def _paired_row(cur, user: str):
    cur.execute("SELECT pair_id, inviter_id, friend_id, inviter_display_name, paired_at FROM buddy_pairs "
                "WHERE status = 'paired' AND (inviter_id = %s OR friend_id = %s)", (user, user))
    return cur.fetchone()


# --- invites and pairing ---

def create_invite(user: str, display_name: str) -> dict:
    _need_store()
    name = clean_name(display_name)
    code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LENGTH))
    now = _now()
    with store._conn().cursor() as cur:
        if _paired_row(cur, user):
            raise BuddyError("already_paired")
        # One open invite at a time: a new one replaces the old.
        cur.execute("UPDATE buddy_pairs SET status = 'ended' WHERE inviter_id = %s AND status = 'invited'", (user,))
        cur.execute("INSERT INTO buddy_pairs (pair_id, inviter_id, friend_id, code_hash, status, inviter_display_name, "
                    "created_at, expires_at, paired_at) VALUES (%s, %s, NULL, %s, 'invited', %s, %s, %s, NULL)",
                    (str(uuid.uuid4()), user, _hash(code), name, now, now + INVITE_TTL))
    return {"code": code, "expiresAt": (now + INVITE_TTL).isoformat() + "Z"}


def redeem(user: str, code: str) -> dict:
    """Pairs the friend. Refuses: too many failed tries this hour, an unknown code, your own
    code, a used or expired code, or anyone already paired. The pairing is one conditional
    UPDATE checked by rowcount, so two redeems of one code can't both win (E11)."""
    _need_store()
    now = _now()
    with store._conn().cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM buddy_redeem_failures WHERE user_id = %s AND at > %s",
                    (user, now - timedelta(hours=1)))
        if int(cur.fetchone()[0]) >= REDEEM_FAILURES_PER_HOUR:
            raise BuddyError("too_many_tries", 429)

        def fail(reason: str, status: int = 409):
            cur.execute("INSERT INTO buddy_redeem_failures (user_id, at) VALUES (%s, %s)", (user, now))
            raise BuddyError(reason, status)

        cur.execute("SELECT pair_id, inviter_id, status, expires_at, inviter_display_name FROM buddy_pairs "
                    "WHERE code_hash = %s", (_hash(code),))
        row = cur.fetchone()
        if not row:
            fail("unknown_code", 404)
        pair_id, inviter, status, expires, name = row
        if inviter == user:
            fail("own_code")
        if status != "invited":
            fail("used")
        if _as_dt(expires) < now:
            fail("expired")
        if _paired_row(cur, user) or _paired_row(cur, inviter):
            fail("already_paired")
        cur.execute("UPDATE buddy_pairs SET friend_id = %s, status = 'paired', paired_at = %s "
                    "WHERE pair_id = %s AND status = 'invited'", (user, now, pair_id))
        if cur.rowcount != 1:
            fail("used")
    return {"status": "paired", "role": "friend", "buddyName": name}


def status(user: str) -> dict:
    """What the app's People section shows. The friend's side gets the last few notes."""
    _need_store()
    with store._conn().cursor() as cur:
        row = _paired_row(cur, user)
        if row:
            pair_id, inviter, _friend, name, paired_at = row
            role = "inviter" if inviter == user else "friend"
            out = {"status": "paired", "role": role, "buddyName": name if role == "friend" else None,
                   "yourName": name if role == "inviter" else None, "pairedAt": _iso(paired_at), "notes": []}
            if role == "friend":
                cur.execute("SELECT doc FROM buddy_notes WHERE pair_id = %s AND status = 'sent' "
                            "ORDER BY created_at DESC LIMIT 5", (pair_id,))
                out["notes"] = [store._json(r[0]) for r in cur.fetchall()]
            return out
        cur.execute("SELECT expires_at, inviter_display_name FROM buddy_pairs WHERE inviter_id = %s "
                    "AND status = 'invited' AND expires_at > %s", (user, _now()))
        invite = cur.fetchone()
        if invite:
            return {"status": "invited", "role": "inviter", "expiresAt": _iso(invite[0]), "yourName": invite[1]}
    return {"status": "none"}


def rename(user: str, display_name: str) -> dict:
    _need_store()
    name = clean_name(display_name)
    with store._conn().cursor() as cur:
        cur.execute("UPDATE buddy_pairs SET inviter_display_name = %s WHERE inviter_id = %s "
                    "AND status IN ('invited', 'paired')", (name, user))
    return status(user)


def unpair(user: str) -> dict:
    """Either side ends it; the other side's row disappears with no notification. Both
    push tokens go, since they exist only for buddy notes."""
    _need_store()
    with store._conn().cursor() as cur:
        row = _paired_row(cur, user)
        cur.execute("UPDATE buddy_pairs SET status = 'ended' WHERE (inviter_id = %s OR friend_id = %s) "
                    "AND status IN ('invited', 'paired')", (user, user))
        if row:
            cur.execute("DELETE FROM push_tokens WHERE user_id IN (%s, %s)", (row[1], row[2]))
    return {"status": "none"}


# --- push tokens ---

def save_token(user: str, token: str, environment: str) -> None:
    _need_store()
    with store._conn().cursor() as cur:
        cur.execute("REPLACE INTO push_tokens (user_id, token, environment, updated_at) VALUES (%s, %s, %s, %s)",
                    (user, token, environment, _now()))


# --- notes ---

NOUNS = {"Walking": "walk", "Running": "run", "Cycling": "ride", "Swimming": "swim", "Yoga": "yoga session",
         "Elliptical": "elliptical session", "TraditionalStrengthTraining": "strength session",
         "FunctionalStrengthTraining": "strength session"}


def note_text(name: str, activity: str, minutes: int) -> str:
    """"Alex did a 15-minute walk." A comeback reads like any workout, so a miss never shows."""
    return f"{name} did a {minutes}-minute {NOUNS.get(activity, 'workout')}."


def on_workouts(user: str, completed: list[dict], send=None) -> dict:
    """Called after a user's events are stored: queues a note for each completed workout of a
    paired inviter (at most 3 per pair per day), then delivers every pending note of the pair."""
    if not store.enabled():
        return {"queued": 0, "sent": 0}
    now = _now()
    queued = 0
    with store._conn().cursor() as cur:
        row = _paired_row(cur, user)
        if not row or row[1] != user:
            return {"queued": 0, "sent": 0}       # only the inviter's workouts are shared (one-way, X6)
        pair_id, inviter, friend, name, _ = row
        cur.execute("SELECT COUNT(*) FROM buddy_notes WHERE pair_id = %s AND created_at > %s",
                    (pair_id, now - timedelta(days=1)))
        today = int(cur.fetchone()[0])
        for event in completed:
            if today >= NOTES_PER_DAY:
                break
            doc = {"text": note_text(name, event["activityType"], int(event["minutes"])),
                   "activityType": event["activityType"], "minutes": int(event["minutes"]), "at": str(event["at"])}
            cur.execute("INSERT IGNORE INTO buddy_notes (pair_id, note_id, inviter_id, friend_id, status, attempts, "
                        "created_at, doc) VALUES (%s, %s, %s, %s, 'pending', 0, %s, %s)",
                        (pair_id, event["id"], inviter, friend, now, json.dumps(doc)))
            queued += cur.rowcount or 0
            today += cur.rowcount or 0
    return {"queued": queued, "sent": deliver(pair_id, send=send)}


def deliver(pair_id: str, send=None) -> int:
    """Sends the pair's pending notes. A note older than 24 hours is dropped; an invalid
    token is deleted (410, 400 BadDeviceToken); any other failure stays pending (D6)."""
    send = send or apns.send
    now = _now()
    sent = 0
    with store._conn().cursor() as cur:
        cur.execute("UPDATE buddy_notes SET status = 'dropped' WHERE pair_id = %s AND status = 'pending' "
                    "AND created_at < %s", (pair_id, now - NOTE_RETRY_WINDOW))
        cur.execute("SELECT note_id, friend_id, doc FROM buddy_notes WHERE pair_id = %s AND status = 'pending' "
                    "ORDER BY created_at", (pair_id,))
        pending = cur.fetchall()
        for note_id, friend, doc in pending:
            cur.execute("SELECT token, environment FROM push_tokens WHERE user_id = %s", (friend,))
            token = cur.fetchone()
            if not token:
                continue
            outcome = send(token[0], token[1], "Your buddy", store._json(doc)["text"])
            if outcome == "sent":
                cur.execute("UPDATE buddy_notes SET status = 'sent' WHERE pair_id = %s AND note_id = %s",
                            (pair_id, note_id))
                sent += 1
            else:
                cur.execute("UPDATE buddy_notes SET attempts = attempts + 1 WHERE pair_id = %s AND note_id = %s",
                            (pair_id, note_id))
                if outcome == "invalid":
                    cur.execute("DELETE FROM push_tokens WHERE user_id = %s", (friend,))
    return sent


def _as_dt(value) -> datetime:
    return value if isinstance(value, datetime) else datetime.fromisoformat(str(value))


def _iso(value) -> str | None:
    return None if value is None else _as_dt(value).isoformat() + "Z"
