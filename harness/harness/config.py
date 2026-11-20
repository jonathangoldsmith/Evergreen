"""Settings from the environment, or harness/.env (git-ignored). Values are never logged."""
from __future__ import annotations

import os
from pathlib import Path

from dotenv import load_dotenv

REPO_ROOT = Path(__file__).resolve().parents[2]
load_dotenv(REPO_ROOT / ".env")
load_dotenv(Path(__file__).resolve().parents[1] / ".env")


def _get(*names: str) -> str:
    for name in names:
        value = os.environ.get(name, "").strip()
        if value:
            return value
    return ""


SIE_API_KEY = _get("SIE_API_KEY", "SUPERLINKED_API_KEY")
SIE_BASE_URL = _get("SIE_BASE_URL") or "https://api.superlinked.com"
SENSO_API_KEY = _get("SENSO_API_KEY")
SENSO_BASE_URL = _get("SENSO_BASE_URL")  # set from Senso's docs once we have access
HARNESS_SECRET = _get("HARNESS_SECRET")

RERANK_MODEL = "Qwen/Qwen3-Reranker-4B"
DECIDE_MODEL = "Qwen/Qwen3.8-27B-FP8"
