"""Load the demo knowledge base into Senso (one raw doc per passage set). Fake demo content only.
Run once: PYTHONPATH=. uv run python scripts/senso_ingest.py   (409 = already uploaded, fine)"""
import time
import httpx
from harness import config, data
from harness.evidence.senso import DEFAULT_BASE

base = (config.SENSO_BASE_URL or DEFAULT_BASE).rstrip("/")
H = {"X-API-Key": config.SENSO_API_KEY}

docs = [
    ("Running shoe care guide",
     "Replace road running shoes every 300 to 500 miles (about 480 to 800 km), sooner if the midsole feels flat "
     "or the outsole is worn through. Runners with high weekly mileage reach that range in a few months.\n\n"
     "Break in a new pair with two or three short, easy runs before racing in it. Never race in shoes you haven't run in. "
     "In the last week before a race, keep long runs in a pair you know.\n\n"
     "Worn-out shoes lose cushioning first: shorten long runs or move them to a bike or elliptical until the new pair arrives."),
    ("Jordan's fit notes", "Jordan needs a wide toe box and does not want a carbon plate. Runs on road. Training for a half marathon."),
    ("Demo Gym day-pass policy", "Demo Gym day pass: $15. Free cancellation until 60 minutes before your visit. 0.4 mi from work."),
]
for s in data.catalog():
    docs.append((f"{s['name']} listing",
                 f"{s['name']}: {s['blurb']} Price ${s['amountCents']/100:.0f}. Ships in {s['arrivesInDays']} days. "
                 f"{'Wide toe box.' if s['wideToeBox'] else 'Standard (narrow) fit.'} {'Carbon plate.' if s['carbonPlate'] else 'No plate.'} "
                 f"Surface: {s['surface']}. Cushion: {s['cushion']}. Drop {s['dropMm']} mm. Expected life about {s['lifeKm']} km. "
                 "Demo store, no charge. Free returns for 30 days."))

nodes = []
for title, text in docs:
    r = httpx.post(f"{base}/org/kb/raw", json={"title": title, "text": text}, headers=H, timeout=30)
    print(r.status_code, title)
    if r.status_code == 202:
        nodes.append(r.json()["kb_node_id"])
for n in nodes:
    for _ in range(36):
        st = httpx.get(f"{base}/org/kb/nodes/{n}", headers=H, timeout=15).json()
        status = (st.get("content") or {}).get("processing_status") or st.get("processing_status")
        if status in ("complete", "failed"):
            print(n, status)
            break
        time.sleep(5)
