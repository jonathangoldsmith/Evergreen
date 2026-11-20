"""Citations for a purchase. Live Senso search when configured, else the cached passages.

The Senso call is not wired yet: we don't have the key or the knowledge-base id (ask Tony).
Until then `search` always returns the cached passages with live=False, which the phone
shows as "cached"."""
from __future__ import annotations

from harness import config, data
from harness.models import Evidence


def search(kind: str, query: str, timeout_s: float = 2.5) -> tuple[list[Evidence], bool]:
    if config.SENSO_API_KEY:
        try:
            return _senso(kind, query, timeout_s), True
        except Exception:
            pass
    return [Evidence(**p) for p in data.passages(kind)], False


def _senso(kind: str, query: str, timeout_s: float) -> list[Evidence]:
    # TODO(Surya): call Senso's search endpoint with config.SENSO_API_KEY and map results to
    # Evidence(source=title, passage=text). Raise on any failure so the caller falls back.
    raise NotImplementedError("Senso search not wired yet")
