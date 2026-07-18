"""P5.2a — the concurrent pull lane, against a FAKE Ollama line stream (the monkeypatchable
``_ollama_pull_lines`` seam). Covers: the sidecar-side scope wall (non-catalog tag refused), the
NDJSON normalization (early events omit ``completed``), the drift tripwire (early + at-success),
the honest error taxonomy, cancel semantics, idempotent join, re-pull-after-terminal, terminal
snapshot retention, the SSE snapshot sweep, and the bearer gate.

Uses ``with TestClient(app)`` (lifespan portal) so tasks created on the loop progress between
requests; assertions poll ``GET /pulls`` with a deadline instead of sleeping blind.
"""

import asyncio
import time

import pytest
from fastapi.testclient import TestClient

import services.api.app as app_module
import services.api.pulls as pulls_mod

pytestmark = pytest.mark.unit

# A REAL curated tag + its exact seed bytes (POST /pulls validates against the curated catalog).
TAG = "qwen3.5:0.8b"
TAG_BYTES = 1_036_034_688


@pytest.fixture(autouse=True)
def _fresh_registry(monkeypatch):
    monkeypatch.delenv("QUORUM_API_TOKEN", raising=False)
    monkeypatch.setattr(app_module, "pull_registry", pulls_mod.PullRegistry())


def _client():
    return TestClient(app_module.app)


def _poll(client, tag, until, timeout=5.0):
    """Poll GET /pulls until ``until(snapshot)`` is true (the task runs on the lifespan loop)."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        snaps = {s["tag"]: s for s in client.get("/pulls").json()["pulls"]}
        snap = snaps.get(tag)
        if snap and until(snap):
            return snap
        time.sleep(0.02)
    raise AssertionError(f"pull {tag} never reached the expected state in {timeout}s")


def _fake_lines(lines, delay=0.0):
    async def fake(_base, _tag):
        for line in lines:
            if delay:
                await asyncio.sleep(delay)
            yield line

    return fake


HAPPY = [
    {"status": "pulling manifest"},
    {"status": "pulling aaaa", "digest": "sha256:aaaa", "total": TAG_BYTES},  # completed omitted -> 0
    {"status": "pulling aaaa", "digest": "sha256:aaaa", "total": TAG_BYTES, "completed": TAG_BYTES // 2},
    {"status": "pulling aaaa", "digest": "sha256:aaaa", "total": TAG_BYTES, "completed": TAG_BYTES},
    {"status": "pulling bbbb", "digest": "sha256:bbbb", "total": 1_000, "completed": 1_000},
    {"status": "verifying sha256 digest"},
    {"status": "writing manifest"},
    {"status": "success"},
]


def test_pull_rejects_non_catalog_tag(monkeypatch):
    # The sidecar-side scope wall: the pull lane refuses anything outside the curated Draft Board,
    # so no client bug (or crafted request) turns it into a generic model downloader.
    with _client() as client:
        resp = client.post("/pulls", json={"tag": "hf.co/evil/backdoor:latest"})
        assert resp.status_code == 422
        assert "curated" in resp.json()["error"]


def test_happy_path_aggregates_layers_and_finishes_clean(monkeypatch):
    monkeypatch.setattr(pulls_mod, "_ollama_pull_lines", _fake_lines(HAPPY))
    with _client() as client:
        resp = client.post("/pulls", json={"tag": TAG})
        assert resp.status_code == 202
        snap = _poll(client, TAG, lambda s: s["status"] == "success")
        assert snap["total"] == TAG_BYTES + 1_000  # per-digest totals summed
        assert snap["completed"] == TAG_BYTES + 1_000
        assert snap["catalog_bytes"] == TAG_BYTES
        assert snap["drift"] is False  # the model layer matched the curated bytes exactly
        assert snap["error"] is None and snap["finished_at"] is not None


def test_drift_when_no_layer_matches_catalog_bytes(monkeypatch):
    repointed = [
        {"status": "pulling aaaa", "digest": "sha256:aaaa", "total": TAG_BYTES - 5_000,
         "completed": TAG_BYTES - 5_000},
        {"status": "success"},
    ]
    monkeypatch.setattr(pulls_mod, "_ollama_pull_lines", _fake_lines(repointed))
    with _client() as client:
        client.post("/pulls", json={"tag": TAG})
        snap = _poll(client, TAG, lambda s: s["status"] == "success")
        assert snap["drift"] is True
        assert snap["drift_reason"] == "no layer matched catalog bytes"


def test_early_drift_when_a_layer_exceeds_catalog_bytes(monkeypatch):
    bigger = [
        {"status": "pulling aaaa", "digest": "sha256:aaaa", "total": TAG_BYTES * 3},
        {"status": "success"},
    ]
    monkeypatch.setattr(pulls_mod, "_ollama_pull_lines", _fake_lines(bigger))
    with _client() as client:
        client.post("/pulls", json={"tag": TAG})
        snap = _poll(client, TAG, lambda s: s["drift"])
        assert snap["drift_reason"] == "layer exceeds catalog bytes"


def test_ollama_error_line_passes_through_honestly(monkeypatch):
    monkeypatch.setattr(pulls_mod, "_ollama_pull_lines", _fake_lines([
        {"status": "pulling manifest"},
        {"error": "write /models/blobs: no space left on device"},
    ]))
    with _client() as client:
        client.post("/pulls", json={"tag": TAG})
        snap = _poll(client, TAG, lambda s: s["status"] == "error")
        assert snap["error_kind"] == "ollama_error"
        assert "no space left" in snap["error"]


def test_connect_failure_is_ollama_unreachable(monkeypatch):
    async def refuse(_base, _tag):
        raise ConnectionError("connection refused")
        yield  # pragma: no cover — makes this an async generator

    monkeypatch.setattr(pulls_mod, "_ollama_pull_lines", refuse)
    with _client() as client:
        client.post("/pulls", json={"tag": TAG})
        snap = _poll(client, TAG, lambda s: s["status"] == "error")
        assert snap["error_kind"] == "ollama_unreachable"


def test_stream_ending_without_success_is_an_error_not_a_zombie(monkeypatch):
    monkeypatch.setattr(pulls_mod, "_ollama_pull_lines", _fake_lines([
        {"status": "pulling aaaa", "digest": "sha256:aaaa", "total": 10},
    ]))
    with _client() as client:
        client.post("/pulls", json={"tag": TAG})
        snap = _poll(client, TAG, lambda s: s["status"] == "error")
        assert "ended without success" in snap["error"]


def test_cancel_aborts_an_active_pull(monkeypatch):
    endless = [{"status": "pulling aaaa", "digest": "sha256:aaaa", "total": TAG_BYTES,
                "completed": i} for i in range(0, TAG_BYTES, TAG_BYTES // 1000)]
    monkeypatch.setattr(pulls_mod, "_ollama_pull_lines", _fake_lines(endless, delay=0.01))
    with _client() as client:
        client.post("/pulls", json={"tag": TAG})
        _poll(client, TAG, lambda s: s["completed"] > 0)  # genuinely in flight
        assert client.post("/pulls/cancel", json={"tag": TAG}).status_code == 200
        snap = _poll(client, TAG, lambda s: s["status"] == "cancelled")
        assert snap["finished_at"] is not None
        # Cancelling again: no active pull -> 404.
        assert client.post("/pulls/cancel", json={"tag": TAG}).status_code == 404


def test_double_post_joins_the_active_pull(monkeypatch):
    calls = 0

    async def counting(base, tag):
        nonlocal calls
        calls += 1
        for line in HAPPY:
            await asyncio.sleep(0.02)
            yield line

    monkeypatch.setattr(pulls_mod, "_ollama_pull_lines", counting)
    with _client() as client:
        assert client.post("/pulls", json={"tag": TAG}).status_code == 202
        assert client.post("/pulls", json={"tag": TAG}).status_code == 200  # join, not restart
        _poll(client, TAG, lambda s: s["status"] == "success")
        assert calls == 1


def test_repull_after_terminal_starts_fresh(monkeypatch):
    calls = 0

    async def counting(base, tag):
        nonlocal calls
        calls += 1
        yield {"status": "pulling aaaa", "digest": "sha256:aaaa", "total": TAG_BYTES,
               "completed": TAG_BYTES}
        yield {"status": "success"}

    monkeypatch.setattr(pulls_mod, "_ollama_pull_lines", counting)
    with _client() as client:
        assert client.post("/pulls", json={"tag": TAG}).status_code == 202
        _poll(client, TAG, lambda s: s["status"] == "success")
        assert client.post("/pulls", json={"tag": TAG}).status_code == 202  # fresh, not a join
        _poll(client, TAG, lambda s: s["status"] == "success")
        assert calls == 2


def test_success_with_no_layer_lines_does_not_claim_drift(monkeypatch):
    # Defensive (#52 review): `all()` over an empty layers dict is vacuously True, so a stream that
    # reaches success without any layer lines (a hypothetical future Ollama skipping cached layers
    # on resume) must read as UNVERIFIABLE, not as drift — the tripwire only fires on observed
    # mismatching bytes. (Ollama 0.32.x re-emits every layer on resume — live-verified.)
    monkeypatch.setattr(pulls_mod, "_ollama_pull_lines", _fake_lines([
        {"status": "success"},
    ]))
    with _client() as client:
        client.post("/pulls", json={"tag": TAG})
        snap = _poll(client, TAG, lambda s: s["status"] == "success")
        assert snap["drift"] is False
        assert snap["drift_reason"] is None


def test_terminal_snapshots_are_retained(monkeypatch):
    monkeypatch.setattr(pulls_mod, "_ollama_pull_lines", _fake_lines([
        {"error": "boom"},
    ]))
    with _client() as client:
        client.post("/pulls", json={"tag": TAG})
        _poll(client, TAG, lambda s: s["status"] == "error")
        # A later bootstrap (fresh page/app attach) still sees WHY it died.
        snaps = client.get("/pulls").json()["pulls"]
        assert any(s["tag"] == TAG and s["error"] == "boom" for s in snaps)


@pytest.fixture
def anyio_backend():
    return "asyncio"


@pytest.mark.anyio
async def test_subscribers_receive_live_snapshots_through_terminal(monkeypatch):
    """The fan-out half of the SSE contract, at the registry level.

    Why not a wire test: the pulls stream is deliberately BOARD-LIFETIME (never self-terminates),
    and BOTH in-process harnesses are structurally unable to exercise that — starlette's threaded
    TestClient deadlocks on close (the portal never delivers the disconnect to the parked
    generator), and httpx's ASGITransport buffers the entire ASGI response so an infinite SSE never
    yields headers (verified empirically; each hung for minutes). The endpoint's wire mechanics are
    byte-identical to the proven /runs SSE pattern, the on-connect snapshot sweep serves exactly
    ``snapshots()`` (covered by test_terminal_snapshots_are_retained), and the wire stream is
    proven END-TO-END on the real spawned sidecar as a P5.2 exit artifact — do not re-add an
    in-process wire test for this endpoint without checking those two harness limitations first.
    """
    import anyio

    monkeypatch.setattr(pulls_mod, "_ollama_pull_lines", _fake_lines(HAPPY))
    registry = pulls_mod.PullRegistry()
    q = registry.subscribe()  # subscribe BEFORE starting — nothing may be missed
    state, created = registry.start(TAG, TAG_BYTES, "http://unused")
    assert created
    with anyio.fail_after(10):
        await state.task  # the pull worker runs on this same loop
    # The subscriber saw live snapshots and the LAST one is the terminal success.
    seen = []
    while not q.empty():
        seen.append(q.get_nowait())
    assert seen, "subscriber received no snapshots"
    assert seen[-1]["status"] == "success"
    assert seen[-1]["completed"] == TAG_BYTES + 1_000
    assert any(s["status"] == "pulling" for s in seen)  # progress flowed, not just the terminal
    registry.unsubscribe(q)
    # And the reconnect bootstrap (what the SSE sweep serves) carries the same terminal snapshot.
    assert registry.snapshots()[0]["status"] == "success"


def test_pull_routes_are_bearer_gated(monkeypatch):
    monkeypatch.setenv("QUORUM_API_TOKEN", "s3cret")
    with _client() as client:
        assert client.post("/pulls", json={"tag": TAG}).status_code == 401
        assert client.get("/pulls").status_code == 401
        assert client.post("/pulls/cancel", json={"tag": TAG}).status_code == 401
    for path in ("/pulls", "/pulls/events"):
        assert path not in app_module._PUBLIC_PATHS
