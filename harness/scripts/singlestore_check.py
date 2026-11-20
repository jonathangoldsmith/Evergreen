"""Set up and check SingleStore (never prints the URL):
  creates the tables, loads the web snapshot for a persona, reads it back, runs one recommendation
  through the logger and reads the audit record back.
PYTHONPATH=. uv run python scripts/singlestore_check.py [persona]"""
import sys
from harness import store
from harness.web import research

persona = sys.argv[1] if len(sys.argv) > 1 else "jordan"
if not store.enabled():
    sys.exit("SINGLESTORE_URL is not set in harness/.env")
snap = research.load_snapshot(persona)
if not snap:
    sys.exit(f"no snapshot for {persona}; run scripts/prefetch_web.py {persona} first")
print("save:", store.save_candidates(snap))
rows = store.load_candidates(persona)
print("read back:", len(rows or []), "candidates")
rid = store.log_recommendation(persona, "check", "test", 0, {"check": True})
print("audit write:", rid)
print("audit read:", bool(rid and store.get_recommendation(rid)))
print("recent:", [(r["item"], r["source"]) for r in store.recent_recommendations(persona, 3)])
