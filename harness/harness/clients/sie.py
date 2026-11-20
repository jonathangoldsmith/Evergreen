"""Thin wrapper over the SIE SDK: one client, plain-JSON replies, any failure -> SIEUnavailable."""
from __future__ import annotations

import json
import time
from typing import Any

from sie_sdk import SIEClient
from sie_sdk.types import Item

from harness import config


class SIEUnavailable(RuntimeError):
    pass


def _jsonable(value: Any) -> Any:
    if hasattr(value, "tolist"):
        return value.tolist()
    if isinstance(value, dict):
        return {str(k): _jsonable(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_jsonable(v) for v in value]
    return value


_client: SIEClient | None = None


def client(timeout_s: float = 30) -> SIEClient:
    global _client
    if not (config.SIE_API_KEY or config.SIE_BASE_URL):
        raise SIEUnavailable("no SIE key configured")
    if _client is None:
        _client = SIEClient(api_key=config.SIE_API_KEY or None, base_url=config.SIE_BASE_URL, timeout_s=timeout_s)
    return _client


def rerank(query: str, docs: dict[str, str], instruction: str, provision_timeout_s: float = 5) -> dict[str, float]:
    """Score each doc id against the query. Returns {id: score}."""
    try:
        reply = _jsonable(
            client().score(
                config.RERANK_MODEL,
                Item(id="query", text=query),
                [Item(id=k, text=v) for k, v in docs.items()],
                instruction=instruction,
                provision_timeout_s=provision_timeout_s,
            )
        )
        scores = {str(e["item_id"]): float(e["score"]) for e in reply["scores"]}
    except Exception as exc:  # SDK, network, shape
        raise SIEUnavailable(f"rerank failed: {type(exc).__name__}: {str(exc)[:200]}") from exc
    if set(scores) != set(docs):
        raise SIEUnavailable("rerank reply is missing items")
    return scores


def chat_json(prompt: str, schema: dict, name: str, max_tokens: int = 900, provision_timeout_s: float = 5) -> dict:
    """One chat_completions call constrained to a JSON schema. Returns the parsed object."""
    try:
        reply = _jsonable(
            client().chat_completions(
                config.DECIDE_MODEL,
                [{"role": "user", "content": prompt}],
                max_completion_tokens=max_tokens,
                temperature=0.0,
                response_format={"type": "json_schema", "json_schema": {"name": name, "schema": schema, "strict": True}},
                provision_timeout_s=provision_timeout_s,
            )
        )
        choice = reply["choices"][0]
        if choice.get("finish_reason") not in (None, "stop"):
            raise ValueError(f"cut off: {choice.get('finish_reason')}")
        return json.loads(choice["message"]["content"])
    except Exception as exc:
        raise SIEUnavailable(f"chat failed: {type(exc).__name__}: {str(exc)[:200]}") from exc


def warm(provision_timeout_s: float = 300) -> dict[str, Any]:
    """Load both models; returns timings in ms or the error per model."""
    out: dict[str, Any] = {}
    t = time.monotonic()
    try:
        rerank("road running shoe", {"a": "cushioned road trainer"}, "Rank shoes.", provision_timeout_s)
        out["rerank_ms"] = int((time.monotonic() - t) * 1000)
    except SIEUnavailable as e:
        out["rerank_error"] = str(e)
    t = time.monotonic()
    try:
        chat_json('Answer {"ok": true}.', {"type": "object", "properties": {"ok": {"type": "boolean"}},
                  "required": ["ok"], "additionalProperties": False}, "ping", 20, provision_timeout_s)
        out["chat_ms"] = int((time.monotonic() - t) * 1000)
    except SIEUnavailable as e:
        out["chat_error"] = str(e)
    return out
