"""Evergreen harness: stateless FastAPI app (Vercel entry point)."""
from __future__ import annotations

import hmac
import re
from typing import Literal

from pydantic import BaseModel, Field
from fastapi import Depends, FastAPI, Header, HTTPException, Response
from fastapi.responses import HTMLResponse

from harness import buddy, coach, config, devices, events, store
from harness.clients import sie
from harness.evidence import senso
from harness.models import USER_ID, EvidenceRequest, EvidenceResponse, ShoesRequest, ShoesResponse
from harness.recommend import shoes, workouts

app = FastAPI(title="Evergreen harness", version="0.1.0")


def require_secret(x_harness_secret: str = Header(default="")) -> None:
    """Only enforced when HARNESS_SECRET is set. /evidence stays open: EvidenceClient sends no header."""
    if config.HARNESS_SECRET and not hmac.compare_digest(x_harness_secret, config.HARNESS_SECRET):
        raise HTTPException(status_code=401, detail="bad secret")


def require_device(user: str, authorization: str = Header(default="")) -> None:
    """Every /users/{user}/... route: the caller's device token must belong to this user (E9)."""
    if not re.fullmatch(USER_ID, user):
        raise HTTPException(status_code=422, detail="not an anonymous user id")
    token = authorization.removeprefix("Bearer ").strip() if authorization.startswith("Bearer ") else ""
    if not devices.verify(user, token):
        raise HTTPException(status_code=401, detail="unknown device")


def require_device_for(user: str | None, authorization: str) -> None:
    """A planner call that names a person (their id, maybe their Health history) needs that
    person's device token too: the shared secret alone can't read or overwrite anyone's
    kept history (T12). Demo personas, with no `user`, need only the secret."""
    if user is not None:
        require_device(user, authorization)


class DeviceRequest(BaseModel):
    user: str = Field(pattern=USER_ID)


@app.post("/devices", dependencies=[Depends(require_secret)])
def device_register(req: DeviceRequest) -> dict:
    """Registers this install and returns its own token, once per user (eng review D7)."""
    try:
        return {"token": devices.register(req.user)}
    except devices.AlreadyRegistered:
        raise HTTPException(status_code=409, detail="already_registered")


@app.get("/health")
def health(response: Response) -> dict:
    """Open. In production a missing store is a failed health check (T1): events, buddies,
    coach links and device tokens all need it."""
    ok = store.enabled() or __import__("os").environ.get("VERCEL_ENV") != "production"
    if not ok:
        response.status_code = 503
    return {"ok": ok, "sie": bool(config.SIE_API_KEY), "senso": bool(config.SENSO_API_KEY),
            "nimble": bool(__import__("os").environ.get("NIMBLE_API_KEY")), "singlestore": store.enabled(),
            "secret": bool(config.HARNESS_SECRET),
            "persona": bool(__import__("os").environ.get("PERSONA_API_KEY")), "version": app.version}


@app.post("/warm", dependencies=[Depends(require_secret)])
def warm() -> dict:
    return {**sie.warm(provision_timeout_s=240), **store.warm()}


def _user(user: str) -> str:
    if not re.fullmatch(USER_ID, user):
        raise HTTPException(status_code=422, detail="not an anonymous user id")
    return user


@app.get("/users/{user}", dependencies=[Depends(require_device)])
def user_get(user: str) -> dict:
    """What the harness keeps for this anonymous id: history size and age, recommendation count, age check."""
    return store.user_summary(_user(user))


@app.delete("/users/{user}", dependencies=[Depends(require_device)])
def user_delete(user: str) -> dict:
    """Erases everything kept for this id: Apple Health history, recommendation records, age check."""
    try:
        return {"deleted": store.delete_user(_user(user))}
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"singlestore: {type(exc).__name__}")


@app.post("/users/{user}/events", dependencies=[Depends(require_device)])
def user_events(user: str, req: events.EventsRequest) -> dict:
    """The phone's guardrail events (plan item 9, eng review D1). Fails closed: 503 without a
    persistent store and 502 on a write failure, so the phone's outbox keeps them; on success,
    returns the ids stored, which the outbox acknowledges. A repeated id is stored once."""
    user = _user(user)
    docs = [e.model_dump(mode="json") for e in req.events]
    try:
        stored = store.save_events(user, docs, events.UPSERT_TYPES)
    except store.StoreUnavailable:
        raise HTTPException(status_code=503, detail="no persistent store")
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"singlestore: {type(exc).__name__}")
    # A paired inviter's finished workouts become buddy notes; earlier notes that failed are retried (D6).
    try:
        notes = buddy.on_workouts(user, [d for d in docs if d["type"] == "workout_completed"])
    except Exception:
        notes = {"queued": 0, "sent": 0}
    return {"stored": stored, "buddyNotes": notes}


# --- the accountability buddy (range plan item 22) ---

class BuddyName(BaseModel):
    displayName: str


class BuddyCode(BaseModel):
    code: str


class PushToken(BaseModel):
    token: str = Field(min_length=16, max_length=200, pattern=r"^[0-9a-fA-F]+$")
    environment: Literal["production", "sandbox"]


def _buddy(call):
    try:
        return call()
    except store.StoreUnavailable:
        raise HTTPException(status_code=503, detail="no persistent store")
    except buddy.BuddyError as err:
        raise HTTPException(status_code=err.status, detail=err.code)


@app.post("/users/{user}/buddy", dependencies=[Depends(require_device)])
def buddy_invite(user: str, req: BuddyName) -> dict:
    """A new 8-character invite code, good for 48 hours and one friend."""
    return _buddy(lambda: buddy.create_invite(_user(user), req.displayName))


@app.post("/users/{user}/buddy/redeem", dependencies=[Depends(require_device)])
def buddy_redeem(user: str, req: BuddyCode) -> dict:
    return _buddy(lambda: buddy.redeem(_user(user), req.code))


@app.get("/users/{user}/buddy", dependencies=[Depends(require_device)])
def buddy_status(user: str) -> dict:
    return _buddy(lambda: buddy.status(_user(user)))


@app.patch("/users/{user}/buddy", dependencies=[Depends(require_device)])
def buddy_rename(user: str, req: BuddyName) -> dict:
    return _buddy(lambda: buddy.rename(_user(user), req.displayName))


@app.delete("/users/{user}/buddy", dependencies=[Depends(require_device)])
def buddy_unpair(user: str) -> dict:
    return _buddy(lambda: buddy.unpair(_user(user)))


@app.put("/users/{user}/push-token", dependencies=[Depends(require_device)])
def push_token(user: str, req: PushToken) -> dict:
    """This device's APNs token and its environment, for buddy notes only."""
    _buddy(lambda: buddy.save_token(_user(user), req.token, req.environment))
    return {"saved": True}


@app.post("/workouts/recommend", dependencies=[Depends(require_secret)])
def workouts_recommend(req: workouts.WorkoutsRequest, authorization: str = Header(default="")) -> dict:
    """The next 7 days: health data (load, sleep, resting HR) + shoe condition + memory → calendar-ready actions."""
    require_device_for(req.user, authorization)
    try:
        return workouts.recommend(req)
    except KeyError:
        raise HTTPException(status_code=404, detail=f"unknown persona {req.persona}")


@app.post("/shoes/prefetch", dependencies=[Depends(require_secret)])
def shoes_prefetch(persona: str = "jordan") -> dict:
    """Research shoes on the web now (Nimble + SIE, ~30 s) and store them in SingleStore.
    Vercel can't write files, so without SINGLESTORE_URL this only reports what it found;
    the deployed snapshot (scripts/prefetch_web.py, committed) stays the source."""
    from harness.web import research
    snap = research.research(persona)
    return {"persona": persona, "pages": len(snap["pages"]), "candidates": len(snap["candidates"]),
            "fetchedAt": snap["fetchedAt"], "singlestore": store.save_candidates(snap)}


@app.get("/audit/recent", dependencies=[Depends(require_secret)])
def audit_recent(persona: str | None = None, limit: int = 20) -> dict:
    """The latest recommendations from SingleStore: what the agent decided, from what, and why."""
    if not store.enabled():
        raise HTTPException(status_code=503, detail="audit log off (no SINGLESTORE_URL)")
    try:
        return {"recommendations": store.recent_recommendations(persona, limit)}
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"singlestore: {type(exc).__name__}")


@app.get("/audit/{rid}", dependencies=[Depends(require_secret)])
def audit_get(rid: str) -> dict:
    """One full audit record by the auditId a recommendation returned."""
    if not store.enabled():
        raise HTTPException(status_code=503, detail="audit log off (no SINGLESTORE_URL)")
    try:
        rec = store.get_recommendation(rid)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"singlestore: {type(exc).__name__}")
    if not rec:
        raise HTTPException(status_code=404, detail="no such recommendation")
    return rec


class VerifyRequest(BaseModel):
    persona: str


@app.post("/verify/start", dependencies=[Depends(require_secret)])
def verify_start(req: VerifyRequest) -> dict:
    """Start a Persona age check (18+). Returns the session token the app opens Persona's flow with."""
    from harness.identity import gate, persona
    if not persona.enabled():
        raise HTTPException(status_code=503, detail="age check off (no PERSONA_API_KEY)")
    try:
        return gate.start(req.persona)
    except persona.PersonaError as exc:
        raise HTTPException(status_code=502, detail=str(exc)[:200])


@app.post("/verify/check", dependencies=[Depends(require_secret)])
def verify_check(req: VerifyRequest) -> dict:
    """After the person finishes Persona's flow: redeem a Privacy Pass on the relay and record the yes/no claim."""
    from harness.identity import gate, persona
    try:
        return gate.check(req.persona)
    except persona.PersonaError as exc:
        raise HTTPException(status_code=409 if "no verification" in str(exc) else 502, detail=str(exc)[:200])


@app.get("/verify/status", dependencies=[Depends(require_secret)])
def verify_status(persona: str) -> dict:
    from harness.identity import gate
    return gate.status(persona)


@app.post("/evidence", response_model=EvidenceResponse)
def evidence(req: EvidenceRequest) -> EvidenceResponse:
    items, live = senso.search(req.purchaseKind, req.query)
    return EvidenceResponse(evidence=items, live=live)


@app.post("/shoes/recommend", response_model=ShoesResponse, response_model_exclude_none=True,
          dependencies=[Depends(require_secret)])
def shoes_recommend(req: ShoesRequest, authorization: str = Header(default="")) -> ShoesResponse:
    require_device_for(req.user, authorization)
    try:
        return shoes.recommend(req)
    except KeyError:
        raise HTTPException(status_code=404, detail=f"unknown persona {req.persona}")


# --- the coach view (range plan item 20) ---

class CoachShareRequest(BaseModel):
    displayName: str
    includeFeelings: bool = False


class CoachShareEdit(BaseModel):
    displayName: str | None = None
    includeFeelings: bool | None = None
    renew: bool = False


@app.post("/users/{user}/coach-shares", dependencies=[Depends(require_device)])
def coach_share_create(user: str, req: CoachShareRequest) -> dict:
    """A private read-only link for the runner's coach: the token appears only in this answer."""
    return _buddy(lambda: coach.create(_user(user), req.displayName, req.includeFeelings))


@app.get("/users/{user}/coach-shares", dependencies=[Depends(require_device)])
def coach_share_list(user: str) -> dict:
    return {"shares": _buddy(lambda: coach.list_shares(_user(user)))}


@app.patch("/users/{user}/coach-shares/{share_id}", dependencies=[Depends(require_device)])
def coach_share_edit(user: str, share_id: str, req: CoachShareEdit) -> dict:
    return _buddy(lambda: coach.update(_user(user), share_id, req.includeFeelings, req.displayName, req.renew))


@app.delete("/users/{user}/coach-shares/{share_id}", dependencies=[Depends(require_device)])
def coach_share_revoke(user: str, share_id: str) -> dict:
    _buddy(lambda: coach.revoke(_user(user), share_id))
    return {"revoked": True}


def _coach_html(page: str, csp: str = coach.CSP) -> HTMLResponse:
    return HTMLResponse(page, headers={"X-Robots-Tag": "noindex, nofollow", "Cache-Control": "no-store",
                                       "Referrer-Policy": "no-referrer", "Content-Security-Policy": csp})


def _coach_page_for(token: str) -> str:
    """Revoked, expired and unknown links get the same page, so the token isn't an oracle."""
    try:
        return coach.page_for(token) if 0 < len(token) <= 64 else coach.render_inactive()
    except Exception:
        return coach.render_inactive()


class CoachView(BaseModel):
    token: str = ""


@app.get("/coach", include_in_schema=False)
def coach_shell() -> HTMLResponse:
    """The coach link, `/coach#<token>` (T3): the token after the # never reaches the server or
    its logs. The shell's one script posts it to /coach/view and shows the answer."""
    return _coach_html(coach.render_shell(), coach.SHELL_CSP)


@app.post("/coach/view", include_in_schema=False)
def coach_view(req: CoachView) -> HTMLResponse:
    return _coach_html(_coach_page_for(req.token))


@app.get("/coach/{token}", include_in_schema=False)
def coach_page(token: str) -> HTMLResponse:
    """Public and token-scoped (E13): registered before the catch-all, escaped, never indexed or
    cached. Links made before T3 carry the token in the path, which request logs keep; they
    still open, and this is also the page for a coach without JavaScript."""
    return _coach_html(_coach_page_for(token))


@app.api_route("/{rest:path}", methods=["GET", "POST"], include_in_schema=False)
def not_found(rest: str):
    raise HTTPException(status_code=404, detail=f"no route /{rest}")
