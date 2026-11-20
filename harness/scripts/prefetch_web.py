"""Research shoes on the web with Nimble and save the snapshot (and to SingleStore if configured).
PYTHONPATH=. uv run python scripts/prefetch_web.py [persona]"""
import sys, time
from harness.web import research
from harness import store

persona = sys.argv[1] if len(sys.argv) > 1 else "jordan"
t = time.monotonic()
snap = research.research(persona)
path = research.save_snapshot(snap)
print(f"{len(snap['pages'])} pages → {len(snap['candidates'])} candidates in {time.monotonic()-t:.1f}s → {path}")
for c in snap["candidates"]:
    print(f"- {c['name']} ${c['amountCents']/100:.0f} wide={c['wideToeBox']} plate={c['carbonPlate']} {c['surface']} {c['cushion']} ({c['sourceHost']})")
print("singlestore:", store.save_candidates(snap))
