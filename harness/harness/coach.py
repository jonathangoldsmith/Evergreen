"""The coach view (range plan item 20, X4, X7, X10; design decisions 8, 9, 15 and 17).

A runner shares a private, read-only link with their coach. The link holds a random
128-bit token; only its hash is stored. The page shows the last 4 weeks of swaps with
their reasons and the weekly range counts, from the runner's own uploaded events, never
raw Health data, calendar titles or injury details. How the runner felt (weekly pain
answers, Sore and Tired reasons, and the 30-day longest on injury-adjusted swaps) shows
only if they ticked "Include how I've felt". A share lasts 90 days and can be renewed or
revoked; revoked, expired and unknown links all read the same.
"""
from __future__ import annotations

import base64
import hashlib
import html
import secrets
import uuid
from datetime import date, datetime, timedelta, timezone

from harness import store
from harness.buddy import BuddyError, clean_name

SHARE_TTL = timedelta(days=90)
WINDOW_DAYS = 28
INACTIVE = "This link is no longer active."


def _now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def _as_dt(value) -> datetime:
    return value if isinstance(value, datetime) else datetime.fromisoformat(str(value))


def _need_store():
    if not store.enabled():
        raise store.StoreUnavailable()


# --- shares ---

def create(user: str, display_name: str, include_feelings: bool) -> dict:
    _need_store()
    name = clean_name(display_name)
    token = secrets.token_urlsafe(16)                    # 128 bits
    share_id, now = str(uuid.uuid4()), _now()
    with store._conn().cursor() as cur:
        cur.execute("INSERT INTO coach_shares (share_id, user_id, token_hash, display_name, include_feelings, "
                    "created_at, expires_at, revoked_at) VALUES (%s, %s, %s, %s, %s, %s, %s, NULL)",
                    (share_id, user, _hash(token), name, int(include_feelings), now, now + SHARE_TTL))
    return {**_share(share_id, name, include_feelings, now + SHARE_TTL, None), "token": token}


def list_shares(user: str) -> list[dict]:
    _need_store()
    with store._conn().cursor() as cur:
        cur.execute("SELECT share_id, display_name, include_feelings, expires_at, revoked_at FROM coach_shares "
                    "WHERE user_id = %s ORDER BY created_at DESC", (user,))
        return [_share(r[0], r[1], bool(r[2]), r[3], r[4]) for r in cur.fetchall()]


def update(user: str, share_id: str, include_feelings: bool | None, display_name: str | None, renew: bool) -> dict:
    _need_store()
    sets, args = [], []
    if include_feelings is not None:
        sets.append("include_feelings = %s"); args.append(int(include_feelings))
    if display_name is not None:
        sets.append("display_name = %s"); args.append(clean_name(display_name))
    if renew:
        sets.append("expires_at = %s"); args.append(_now() + SHARE_TTL)
    with store._conn().cursor() as cur:
        if sets:
            cur.execute(f"UPDATE coach_shares SET {', '.join(sets)} WHERE share_id = %s AND user_id = %s "
                        "AND revoked_at IS NULL", (*args, share_id, user))
            if cur.rowcount != 1:
                raise BuddyError("unknown_share", 404)
    return next((s for s in list_shares(user) if s["id"] == share_id), {})


def revoke(user: str, share_id: str) -> None:
    _need_store()
    with store._conn().cursor() as cur:
        cur.execute("UPDATE coach_shares SET revoked_at = %s WHERE share_id = %s AND user_id = %s",
                    (_now(), share_id, user))


def _share(share_id, name, feelings, expires, revoked) -> dict:
    expires = _as_dt(expires)
    state = "revoked" if revoked else "expired" if expires < _now() else "active"
    return {"id": share_id, "displayName": name, "includeFeelings": feelings,
            "expiresAt": expires.isoformat() + "Z", "state": state}


# --- the page ---

def page_for(token: str) -> str:
    """The coach page's HTML, or the same inactive page for revoked, expired and unknown links."""
    if not store.enabled():
        return render_inactive()
    with store._conn().cursor() as cur:
        cur.execute("SELECT user_id, display_name, include_feelings, expires_at, revoked_at FROM coach_shares "
                    "WHERE token_hash = %s", (_hash(token),))
        row = cur.fetchone()
        if not row or row[4] is not None or _as_dt(row[3]) < _now():
            return render_inactive()
        user, name, feelings = row[0], row[1], bool(row[2])
        since = _now() - timedelta(days=WINDOW_DAYS)
        cur.execute("SELECT doc FROM guardrail_events WHERE user_id = %s AND created_at > %s "
                    "AND type IN ('flag', 'choice', 'range_week', 'pain') ORDER BY created_at", (user, since))
        events = [store._json(r[0]) for r in cur.fetchall()]
    return render(name, feelings, events)


def summarize(events: list[dict], feelings: bool) -> dict:
    """Swaps taken (newest first), weekly counts and, with the tick, pain answers."""
    flags = {e.get("run"): e for e in events if e.get("type") == "flag" and e.get("run")}
    latest: dict[str, dict] = {}
    for e in events:
        if e.get("type") == "choice":
            latest[e["run"]] = e                         # the newest choice for a run wins
    swaps = []
    for run, choice in latest.items():
        flag = flags.get(run)
        if choice["choice"] != "accept" or not flag:
            continue
        swaps.append(_swap_line(flag, feelings))
    swaps.sort(key=lambda s: s["day"], reverse=True)
    weeks = {}
    for e in events:
        if e.get("type") == "range_week":
            weeks[e["weekStart"]] = e                    # last write wins (eng re-run outside voice #2)
    pain = {}
    if feelings:
        for e in events:
            if e.get("type") == "pain":
                pain[e["weekStart"]] = e["answer"]       # the one-tap answer; OSTRC is never shown
    return {"swaps": swaps, "weeks": sorted(weeks.values(), key=lambda w: w["weekStart"], reverse=True),
            "pain": pain}


def _size(value: float, unit: str) -> str:
    return f"{round(value)} km" if unit == "km" else f"{round(value)} min"


def _swap_line(flag: dict, feelings: bool) -> dict:
    kind, unit = flag["kind"], flag["unit"]
    change = f"{_size(flag['planned'], unit)} → {_size(flag['suggested'], unit)}"
    big_jump = kind in ("spike", "returnSpike")
    if feelings:
        reason = {"spike": "Big jump", "returnSpike": "Back from an injury",
                  "sore": "Felt sore", "tired": "Felt tired",
                  "body": "Body readings off usual", "load": "Big week"}[kind]
    else:
        reason = "Shortened: big jump" if big_jump else "Shortened: big week" if kind == "load" else "Shortened: how you felt"
    # The 30-day longest on an injury-adjusted swap hints at an injury, so it needs the tick (X10).
    show_longest = flag.get("longest30") and (feelings or not flag.get("injuryAdjusted")) and big_jump
    detail = f"30-day longest {_size(flag['longest30'], unit)}" if show_longest else None
    return {"day": flag["runDay"], "change": change, "reason": reason, "detail": detail}


PAIN_WORDS = {"no": "No pain", "aLittle": "A little pain", "yes": "Pain", "noAnswer": "No answer"}
DISCLAIMER = "Evergreen suggests training changes. It isn't medical advice; see a physio or doctor for pain or injury."


def render(name: str, feelings: bool, events: list[dict]) -> str:
    s = summarize(events, feelings)
    e = html.escape
    items = []
    for swap in s["swaps"]:
        day = date.fromisoformat(swap["day"])
        extra = f" · {e(swap['detail'])}" if swap["detail"] else ""
        items.append(f'<li><time datetime="{e(swap["day"])}">{e(day.strftime("%a, %b %-d"))}</time> '
                     f'<span class="change">{e(swap["change"])}</span><br>'
                     f'<span class="muted">{e(swap["reason"])}{extra}</span></li>')
    weeks = []
    for week in s["weeks"]:
        start = date.fromisoformat(week["weekStart"])
        line = (f"In range {int(week['daysInRange'])} of {int(week['daysCounted'])} days"
                if week["daysCounted"] else "Not enough data")
        if week.get("swaps"):
            line += f" · {int(week['swaps'])} swap{'s' if week['swaps'] != 1 else ''}"
        if feelings and week["weekStart"] in s["pain"]:
            line += f" · {PAIN_WORDS.get(s['pain'][week['weekStart']], '')}"
        weeks.append(f'<li><time datetime="{e(week["weekStart"])}">Week of {e(start.strftime("%b %-d"))}</time>'
                     f'<br><span class="muted">{e(line)}</span></li>')
    body = (f"<h2>Changes</h2><ul>{''.join(items)}</ul>" if items
            else "<p>No changes in the last 4 weeks. Every run stayed in range.</p>")
    if weeks:
        body += f"<h2>Weeks</h2><ul>{''.join(weeks)}</ul>"
    return _page(f"{e(name)}'s training", f"<h1>{e(name)}</h1><p class='muted'>The last 4 weeks, from Evergreen. "
                 f"Read-only.</p>{body}")


def render_inactive() -> str:
    return _page("Evergreen", f"<h1>Evergreen</h1><p>{INACTIVE}</p>")


# The link is `/coach#<token>` (range plan task T3): browsers never send what follows the #,
# so the token stays out of request logs. This one script, the page's only JavaScript, reads
# it and posts it to `/coach/view`, then puts the answer's <main> in place of the shell's.
OPENER = (
    '(function(){var s=document.getElementById("status"),t=location.hash.slice(1);'
    'if(!t){s.textContent="' + INACTIVE + '";return}s.textContent="Opening\u2026";'
    'fetch("/coach/view",{method:"POST",headers:{"Content-Type":"application/json"},'
    'body:JSON.stringify({token:t}),cache:"no-store",credentials:"omit"})'
    '.then(function(r){return r.text()}).then(function(h){'
    'var d=new DOMParser().parseFromString(h,"text/html"),m=d.querySelector("main");'
    'if(!m)throw 0;document.title=d.title;document.querySelector("main").replaceWith(m)})'
    '.catch(function(){s.textContent="This page didn\u2019t load. Check the connection and reload."})})();'
)
OPENER_HASH = "sha256-" + base64.b64encode(hashlib.sha256(OPENER.encode()).digest()).decode()
NO_SCRIPT = "Turn on JavaScript and reload to open this page. It keeps the link out of server logs."

# Every coach page loads nothing from anywhere; the shell may also run OPENER and call /coach/view.
CSP = "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
SHELL_CSP = CSP + f"; script-src '{OPENER_HASH}'; connect-src 'self'"


def render_shell() -> str:
    """What `/coach` serves before the token is read: the page's frame, OPENER, and a note
    for a browser without JavaScript."""
    return _page("Evergreen", f'<h1>Evergreen</h1><p id="status" aria-live="polite"></p>'
                 f"<noscript><p>{NO_SCRIPT}</p></noscript>", script=OPENER)


def _page(title: str, content: str, script: str = "") -> str:
    # DESIGN.md's coach page: one reading column, the light and dark tokens, no cards; JavaScript
    # only in the shell's OPENER, and the page it opens is plain HTML.
    tail = f"<script>{script}</script>" if script else ""
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>{title}</title>
<style>
:root {{ --surface:#F7F8F6; --text:#15201B; --muted:#55615B; --accent:#1F6F5C; --rule:#E3E7E4; }}
@media (prefers-color-scheme: dark) {{ :root {{ --surface:#0F1513; --text:#EEF2EF; --muted:#A6B1AC; --accent:#5FC2A6; --rule:#26302C; }} }}
body {{ margin:0; background:var(--surface); color:var(--text); font:17px/1.45 -apple-system, system-ui, sans-serif; }}
main {{ max-width:640px; margin:0 auto; padding:32px 16px; }}
h1 {{ font-family:"General Sans", -apple-system, system-ui, sans-serif; font-weight:600; font-size:30px; margin:0 0 4px; }}
h2 {{ font-size:17px; color:var(--muted); font-weight:600; margin:32px 0 8px; }}
ul {{ list-style:none; padding:0; margin:0; }}
li {{ padding:12px 0; border-bottom:1px solid var(--rule); }}
time {{ font-weight:600; }}
.change {{ font-variant-numeric:tabular-nums; }}
.muted {{ color:var(--muted); }}
footer {{ margin-top:40px; font-size:15px; color:var(--muted); }}
a:focus, :focus-visible {{ outline:2px solid var(--accent); outline-offset:2px; }}
::selection {{ background:var(--accent); color:var(--surface); }}
</style></head>
<body><main>{content}<footer>{DISCLAIMER}</footer></main>{tail}</body></html>"""
