"""Warm SIE models locally (also the smoke test): uv run python scripts/warm.py"""
import json

from harness.clients import sie

print(json.dumps(sie.warm(), indent=2))
