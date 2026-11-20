"""Citations for a purchase: Senso context search (passages, no generated answer), else cached.

Senso: POST {base}/org/search/context, header X-API-Key, body {"query": ...};
results[] carry title and chunk_text. Any failure, timeout or empty result -> cached passages, live=False."""
from __future__ import annotations

import httpx

from harness import config, data
from harness.models import Evidence

DEFAULT_BASE = "https://apiv2.senso.ai/api/v1"
MAX_PASSAGES = 4


def search(kind: str, query: str, timeout_s: float = 2.5) -> tuple[list[Evidence], bool]:
    if config.SENSO_API_KEY:
        try:
            found = _senso(query, timeout_s)
            if found:
                return found, True
        except Exception:
            pass
    return [Evidence(**p) for p in data.passages(kind)], False


def _senso(query: str, timeout_s: float) -> list[Evidence]:
    base = (config.SENSO_BASE_URL or DEFAULT_BASE).rstrip("/")
    r = httpx.post(f"{base}/org/search/context", json={"query": query},
                   headers={"X-API-Key": config.SENSO_API_KEY}, timeout=timeout_s)
    r.raise_for_status()
    out = []
    for item in r.json().get("results", [])[:MAX_PASSAGES]:
        text = (item.get("chunk_text") or "").strip()
        if text:
            out.append(Evidence(source=item.get("title") or "Senso", passage=text[:400]))
    return out
