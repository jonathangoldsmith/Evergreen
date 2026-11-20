import pytest


@pytest.fixture(autouse=True)
def _no_secret(monkeypatch):
    """Tests run without the shared secret unless a test sets it."""
    from harness import config
    monkeypatch.setattr(config, "HARNESS_SECRET", "")


@pytest.fixture(autouse=True)
def _catalog_only(monkeypatch, request):
    """Tests use the fake catalog unless marked @pytest.mark.web."""
    if request.node.get_closest_marker("web") or request.node.fspath.basename == "test_store.py":
        if request.node.fspath.basename == "test_store.py":
            from harness.web import research
            monkeypatch.setattr(research, "load_snapshot", lambda persona: None)
        return
    from harness import store
    from harness.web import research
    monkeypatch.setattr(research, "load_snapshot", lambda persona: None)
    monkeypatch.setattr(store, "load_candidates", lambda persona: None)


@pytest.fixture(autouse=True)
def _no_real_singlestore(monkeypatch, request):
    """Never touch a real database in tests (test_store.py sets a fake one)."""
    if request.node.fspath.basename != "test_store.py":
        monkeypatch.delenv("SINGLESTORE_URL", raising=False)
