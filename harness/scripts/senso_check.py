"""Check Senso search with the configured key (prints results, never the key)."""
import sys, time
import httpx
from harness import config
from harness.evidence.senso import DEFAULT_BASE

base = (config.SENSO_BASE_URL or DEFAULT_BASE).rstrip("/")
print("key configured:", bool(config.SENSO_API_KEY), "| base:", base)
q = sys.argv[1] if len(sys.argv) > 1 else "when to replace running shoes"
t = time.monotonic()
r = httpx.post(f"{base}/org/search/context", json={"query": q}, headers={"X-API-Key": config.SENSO_API_KEY}, timeout=15)
print(r.status_code, f"{(time.monotonic()-t)*1000:.0f} ms")
try:
    d = r.json()
    print("total_results:", d.get("total_results"))
    for it in d.get("results", [])[:5]:
        print("-", it.get("title"), "|", (it.get("chunk_text") or "")[:120].replace("\n", " "))
    if r.status_code >= 400:
        print(str(d)[:300])
except Exception:
    print(r.text[:300])
