"""The deploy check (range plan task T1): fails unless the deployed harness has its
persistent store and a coach share survives a round trip through it.

    cd harness && uv run python scripts/smoke.py [https://trackerplusplus-harness.vercel.app]

With a throwaway anonymous id it registers a device, creates a coach share, opens it the way
a coach does (`POST /coach/view`, the token never in a URL), lists it, revokes it, sees the
link go inactive, then erases the id with DELETE. Coach shares have no in-memory fallback,
so reading one back means it's in SingleStore and a cold start keeps it. Needs
HARNESS_SECRET (the environment, harness/.env, or else app/Secrets.xcconfig, the one the app is
built with); prints neither it nor any token. Exits 1 on any failure.
"""
from __future__ import annotations

import json
import secrets
import sys
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from harness import config  # noqa: E402  (loads harness/.env)

def _secret() -> str:
    if config.HARNESS_SECRET:
        return config.HARNESS_SECRET
    xcconfig = Path(__file__).resolve().parents[2] / "app" / "Secrets.xcconfig"
    for line in xcconfig.read_text().splitlines() if xcconfig.exists() else []:
        key, _, value = line.partition("=")
        if key.strip() == "HARNESS_SECRET":
            return value.strip()
    return ""


SECRET = _secret()
BASE = (sys.argv[1] if len(sys.argv) > 1 else "https://trackerplusplus-harness.vercel.app").rstrip("/")
NAME = "Smoke check"


def call(method: str, path: str, body: dict | None = None, token: str | None = None) -> tuple[int, str]:
    headers = {"Content-Type": "application/json", "X-Harness-Secret": SECRET}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(BASE + path, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=30) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as err:
        return err.code, err.read().decode()


def check(ok: bool, what: str) -> None:
    print(("ok    " if ok else "FAIL  ") + what)
    if not ok:
        raise SystemExit(1)


def main() -> None:
    status, text = call("GET", "/health")
    health = json.loads(text) if text.startswith("{") else {}
    check(status == 200 and health.get("singlestore") is True, "the store is on (/health)")

    user = "usr_" + secrets.token_hex(8)
    status, text = call("POST", "/devices", {"user": user})
    check(status == 200, "a throwaway device registers" + ("" if status != 401 else " (set HARNESS_SECRET)"))
    device = json.loads(text)["token"]
    try:
        status, text = call("POST", f"/users/{user}/coach-shares", {"displayName": NAME}, device)
        check(status == 200, "a coach share is created")
        share = json.loads(text)
        status, page = call("POST", "/coach/view", {"token": share["token"]})
        check(status == 200 and NAME in page, "the coach link opens (token in the body)")
        status, text = call("GET", f"/users/{user}/coach-shares", token=device)
        check(status == 200 and [s["state"] for s in json.loads(text)["shares"]] == ["active"],
              "the share reads back from the store")
        status, _ = call("DELETE", f"/users/{user}/coach-shares/{share['id']}", token=device)
        check(status == 200, "the share is revoked")
        status, page = call("POST", "/coach/view", {"token": share["token"]})
        check(status == 200 and "no longer active" in page and NAME not in page, "the revoked link reads inactive")
    finally:
        status, _ = call("DELETE", f"/users/{user}", token=device)
        print(("ok    " if status == 200 else "FAIL  ") + "the throwaway id is erased")
    check(status == 200, "cleanup")
    status, _ = call("GET", f"/users/{user}", token=device)
    check(status == 401, "its device is gone too")


if __name__ == "__main__":
    main()
