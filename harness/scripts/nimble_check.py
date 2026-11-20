"""Probe Nimble search (prints results, never the key). Usage: scripts/nimble_check.py [shopping|general]"""
import json, os, sys, time
import httpx
from harness import config  # loads harness/.env

key = os.environ.get("NIMBLE_API_KEY", "")
print("key configured:", bool(key))
mode = sys.argv[1] if len(sys.argv) > 1 else "shopping"
body = {"query": "wide toe box daily road running shoe no carbon plate high cushion", "max_results": 6, "country": "US"}
body |= {"focus": "shopping", "search_depth": "lite"} if mode == "shopping" else {"search_depth": "standard"}
t = time.monotonic()
r = httpx.post("https://sdk.nimbleway.com/v2/search", json=body, headers={"Authorization": f"Bearer {key}"}, timeout=60)
print(r.status_code, f"{(time.monotonic()-t)*1000:.0f} ms")
d = r.json()
if r.status_code >= 400:
    print(str(d)[:400]); sys.exit()
print("total:", d.get("total_results"))
for it in d.get("results", [])[:6]:
    print("-", it.get("title"), "|", it.get("url"))
    print("   desc:", (it.get("description") or "")[:140].replace("\n", " "))
    if it.get("additional_data"):
        print("   additional_data:", json.dumps(it["additional_data"])[:300])
    if it.get("content"):
        print("   content:", it["content"][:200].replace("\n", " "))
