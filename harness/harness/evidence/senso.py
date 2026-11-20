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


def search_many(kind: str, queries: list[tuple[str, int]], timeout_s: float = 2.5) -> tuple[list[Evidence], bool]:
    """Several targeted queries in parallel, keeping the top n of each (deduplicated).
    Live only if every query answered; otherwise the cached passages for the kind."""
    if config.SENSO_API_KEY:
        import concurrent.futures as cf
        try:
            with cf.ThreadPoolExecutor(max_workers=len(queries)) as pool:
                found = list(pool.map(lambda q: _senso(q[0], timeout_s)[: q[1]], queries))
            out, seen = [], set()
            for group in found:
                for e in group:
                    if e.passage not in seen:
                        seen.add(e.passage)
                        out.append(e)
            if all(found):
                return out, True
        except Exception:
            pass
    return [Evidence(**p) for p in data.passages(kind)], False


def _tidy(text: str) -> str:
    """Senso chunks can start mid-word; start at the next whole word."""
    text = text.strip()
    if text and text[0].islower() and " " in text:
        text = text.split(" ", 1)[1]
        text = text[0].upper() + text[1:]
    return text


def _senso(query: str, timeout_s: float) -> list[Evidence]:
    base = (config.SENSO_BASE_URL or DEFAULT_BASE).rstrip("/")
    r = httpx.post(f"{base}/org/search/context", json={"query": query},
                   headers={"X-API-Key": config.SENSO_API_KEY}, timeout=timeout_s)
    r.raise_for_status()
    out = []
    for item in r.json().get("results", [])[:MAX_PASSAGES]:
        text = _tidy(item.get("chunk_text") or "")
        if text:
            out.append(Evidence(source=item.get("title") or "Senso", passage=text[:400]))
    return out
