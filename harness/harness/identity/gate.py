"""Purchase gate: purchases unlock once the person passes a Persona age check (18+).

On when PERSONA_API_KEY is set (PURCHASE_REQUIRES_AGE_CHECK=0 turns it off). Verification state lives in
SingleStore (memory fallback), keyed by persona. Only the claim result is kept: no name, birthdate or ID."""
from __future__ import annotations

import os
from datetime import datetime, timezone

from harness import store
from harness.identity import persona


def required() -> bool:
    return persona.enabled() and os.environ.get("PURCHASE_REQUIRES_AGE_CHECK", "1") != "0"


def status(who: str) -> dict:
    rec = store.get_verification(who) or {}
    doc = rec.get("doc") or {}
    return {"required": required(), "verified": rec.get("status") == "passed", "state": rec.get("status") or "none",
            "claimType": rec.get("claim_type") or persona.CLAIM, "method": doc.get("method"),
            "verifiedAt": doc.get("verifiedAt"), "sandbox": persona.sandbox(), "provider": "Persona Relay"}


def start(who: str) -> dict:
    relay = persona.create_relay()
    store.save_verification(who, {"relay_token": relay["relay-token"], "relay_secret": relay["relay-secret"],
                                  "status": "started", "claim_type": persona.CLAIM, "doc": {}})
    # The relay secret stays here; the app only gets the session token for Persona's flow.
    return {"sessionToken": relay["relay-session-access-token"], "claimType": persona.CLAIM, "sandbox": persona.sandbox()}


def check(who: str) -> dict:
    rec = store.get_verification(who)
    if not rec:
        raise persona.PersonaError("no verification started for this person")
    if rec["status"] in ("passed", "failed"):
        return status(who)
    claim = persona.check(rec["relay_token"], rec["relay_secret"], rec.get("claim_type") or persona.CLAIM)
    method = ", ".join(m.get("method", "") for m in claim.get("methodology") or []) or None
    rec["status"] = "passed" if claim.get("claim_result") == "passed" else "failed"
    rec["doc"] = {"claimResult": claim.get("claim_result"), "method": method,
                  "verifiedAt": datetime.now(timezone.utc).isoformat(timespec="seconds")}
    store.save_verification(who, rec)
    return status(who)
