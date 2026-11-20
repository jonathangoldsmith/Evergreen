import pytest


@pytest.fixture(autouse=True)
def _no_secret(monkeypatch):
    """Tests run without the shared secret unless a test sets it."""
    from harness import config
    monkeypatch.setattr(config, "HARNESS_SECRET", "")
