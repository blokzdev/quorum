"""Integration tests for the Quorum API sidecar's job plumbing (P0.7).

Drives a real JobRegistry + EventLog + run_streaming against a FAKE graph (no LLM calls), proving:
request planning, the serialized worker, the full event stream, structured-JSON capture through the
real contextvar, report writing, and cooperative cancellation. The thin FastAPI/SSE layer over this
is covered separately (test_api_http.py).
"""

import json
import time

import pytest
from fastapi.testclient import TestClient

import services.api.app as app_module
import services.api.jobs as jobs_mod
import tradingagents.agents.utils.structured as structmod
import tradingagents.graph.trading_graph as trading_graph_mod
from services.api.jobs import JobRegistry, plan_run
from tradingagents.runtime.events import EventType

pytestmark = pytest.mark.unit


# --- A fake graph standing in for TradingAgentsGraph (same surface _execute uses). ---

class _FakePropagator:
    def create_initial_state(self, ticker, trade_date, asset_type="stock", instrument_context="", **_):
        return {"company_of_interest": ticker, "trade_date": trade_date}

    def get_graph_args(self):
        return {}


class _FakeInner:
    def __init__(self, chunks, sleep=0.0):
        self._chunks = chunks
        self._sleep = sleep

    def stream(self, _init_state, **_):
        for chunk in self._chunks:
            if self._sleep:
                time.sleep(self._sleep)
            if "final_trade_decision" in chunk:  # simulate the PM agent capturing structured output
                sink = structmod._structured_sink.get()
                if sink is not None:
                    sink("Portfolio Manager", {"rating": "Buy", "investment_thesis": "solid moat"})
            yield chunk


def _make_fake_graph(chunks, sleep=0.0):
    class _FakeGraph:
        def __init__(self, _selected, config=None, debug=False):
            self.graph = _FakeInner(chunks, sleep)
            self.propagator = _FakePropagator()

        def resolve_instrument_context(self, ticker, _asset_type):
            return f"ctx:{ticker}"

        def process_signal(self, decision):
            return "Buy" if decision else "Hold"

    return _FakeGraph


FULL_CHUNKS = [
    {"market_report": "MKT"},
    {"market_report": "MKT", "sentiment_report": "SENT"},
    {"market_report": "MKT", "sentiment_report": "SENT", "news_report": "NEWS",
     "fundamentals_report": "FUND"},
    {"market_report": "MKT", "sentiment_report": "SENT", "news_report": "NEWS",
     "fundamentals_report": "FUND",
     "investment_debate_state": {"bull_history": "B", "bear_history": "R", "judge_decision": "PLAN"}},
    {"trader_investment_plan": "TRADE"},
    {"risk_debate_state": {"aggressive_history": "A", "conservative_history": "C",
                           "neutral_history": "N", "judge_decision": "DEC"},
     "final_trade_decision": "DEC"},
]


def _wait_done(job, timeout=5.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if job.status in ("done", "error", "cancelled"):
            return
        time.sleep(0.02)
    raise AssertionError(f"job did not finish in {timeout}s (status={job.status})")


# --- plan_run (request -> concrete run inputs) ---

def test_plan_run_pro_uses_explicit_fields():
    plan = plan_run({"mode": "pro", "ticker": "SPY", "provider": "Anthropic",
                     "deep_model": "claude-opus-4-8", "research_depth": 3})
    assert plan["ticker"] == "SPY"
    assert plan["config"]["llm_provider"] == "anthropic"
    assert plan["config"]["deep_think_llm"] == "claude-opus-4-8"
    assert plan["config"]["max_debate_rounds"] == 3
    assert plan["config"]["max_risk_discuss_rounds"] == 3


def test_plan_run_threads_provider_effort_knobs():
    g = plan_run({"ticker": "SPY", "provider": "google", "google_thinking_level": "high"})
    assert g["config"]["google_thinking_level"] == "high"
    o = plan_run({"ticker": "SPY", "provider": "openai", "openai_reasoning_effort": "medium"})
    assert o["config"]["openai_reasoning_effort"] == "medium"
    a = plan_run({"ticker": "SPY", "provider": "anthropic", "anthropic_effort": "low"})
    assert a["config"]["anthropic_effort"] == "low"
    # Unset -> stays at the engine default (None), never a spurious value.
    assert plan_run({"ticker": "SPY", "provider": "google"})["config"].get("google_thinking_level") is None


def test_plan_run_threads_agent_models_and_resolved_provenance():
    plan = plan_run({
        "ticker": "SPY", "provider": "openai", "deep_model": "gpt-5.5", "quick_model": "gpt-5.4-mini",
        "agent_models": {"bull_researcher": {"provider": "xai", "model": "grok-x"}},
    })
    # the raw overrides reach config (the graph resolves per role)
    assert plan["config"]["agent_models"] == {"bull_researcher": {"provider": "xai", "model": "grok-x"}}
    # the RESOLVED cast list is recorded for provenance: the override + quick/deep fallback for the rest
    am = plan["params"]["agent_models"]
    assert am["bull_researcher"] == {"provider": "xai", "model": "grok-x"}
    assert am["portfolio_manager"] == {"provider": "openai", "model": "gpt-5.5"}  # DEEP fallback


def test_plan_run_without_agent_models_records_no_provenance():
    plan = plan_run({"ticker": "SPY", "provider": "openai"})
    assert "agent_models" not in plan["config"]
    assert plan["params"]["agent_models"] is None


def test_plan_run_vibe_extracts_ticker_from_intent():
    plan = plan_run({"mode": "vibe", "intent": "what's the vibe on NVDA this week?"})
    assert plan["ticker"] == "NVDA"


def test_plan_run_crypto_asset_detection():
    assert plan_run({"ticker": "BTC-USD"})["asset_type"] == "crypto"
    assert plan_run({"ticker": "AAPL"})["asset_type"] == "stock"


def test_plan_run_without_ticker_raises():
    with pytest.raises(ValueError, match="no ticker"):
        plan_run({"mode": "vibe", "intent": "how are markets doing today"})


# --- Full job lifecycle ---

def test_job_runs_and_streams_full_event_sequence(monkeypatch, tmp_path):
    monkeypatch.setattr(trading_graph_mod, "TradingAgentsGraph", _make_fake_graph(FULL_CHUNKS))
    monkeypatch.setattr(jobs_mod, "write_report_tree", lambda fs, t, p: p)
    registry = JobRegistry(results_dir=tmp_path)

    job = registry.create({"mode": "pro", "ticker": "SPY"})
    _wait_done(job)
    assert job.status == "done"

    events = job.event_log.replay_from(0)
    assert events[0].type == EventType.RUN_STARTED
    assert events[-1].type == EventType.RUN_DONE

    sections = {e.data["section"] for e in events if e.type == EventType.REPORT_SECTION_DONE}
    assert {"market_report", "sentiment_report", "news_report", "fundamentals_report",
            "investment_plan", "trader_investment_plan", "final_trade_decision"} <= sections

    done = events[-1]
    assert done.data["rating"] == "Buy"
    assert done.data["structured"] == {"rating": "Buy", "investment_thesis": "solid moat"}
    assert done.data["cancelled"] is False

    # Structured JSON is attached to the verdict section too.
    verdict = next(e for e in events if e.type == EventType.REPORT_SECTION_DONE
                   and e.data["section"] == "final_trade_decision")
    assert verdict.data["structured"]["rating"] == "Buy"

    # Monotonic, gapless sequence numbers.
    assert [e.seq for e in events] == list(range(len(events)))


def test_reports_endpoint_data_after_run(monkeypatch, tmp_path):
    monkeypatch.setattr(trading_graph_mod, "TradingAgentsGraph", _make_fake_graph(FULL_CHUNKS))
    monkeypatch.setattr(jobs_mod, "write_report_tree", lambda fs, t, p: p)
    registry = JobRegistry(results_dir=tmp_path)
    job = registry.create({"mode": "pro", "ticker": "SPY"})
    _wait_done(job)
    sections = JobRegistry.report_sections(job)
    assert sections["market_report"] == "MKT"
    assert sections["final_trade_decision"] == "DEC"


# --- Run manifest + history (P2.4a) ---

def test_manifest_written_with_track_record_fields(monkeypatch, tmp_path):
    monkeypatch.setattr(trading_graph_mod, "TradingAgentsGraph", _make_fake_graph(FULL_CHUNKS))
    monkeypatch.setattr(jobs_mod, "write_report_tree", lambda fs, t, p: p)
    registry = JobRegistry(results_dir=tmp_path)

    job = registry.create({"mode": "pro", "ticker": "SPY",
                           "provider": "anthropic", "deep_model": "claude-opus-4-8"})
    _wait_done(job)

    runs = registry.list_runs()
    assert len(runs) == 1
    m = runs[0]
    assert m["run_id"] == job.run_id
    assert m["ticker"] == "SPY"
    assert m["status"] == "done"
    assert m["mode"] == "pro"
    assert m["provider"] == "anthropic"
    assert m["deep_model"] == "claude-opus-4-8"
    # Track Record seed fields: trade_date, timestamps, and the verdict (rating + entry/price context).
    assert m["trade_date"]
    assert m["created_at"] and m["finished_at"]
    assert m["verdict"]["rating"] == "Buy"
    assert m["verdict"]["structured"] == {"rating": "Buy", "investment_thesis": "solid moat"}
    assert "cost" in m
    assert list(tmp_path.glob("*/run.json"))  # the manifest is on disk, beside the report tree


def test_vendor_and_provider_keys_never_touch_disk(monkeypatch, tmp_path):
    # P3.1c security: BYO keys (LLM + data-vendor) are request-scoped and injected per run — they must
    # NEVER be written to the manifest, the persisted reports, or the report tree. Falsify by driving a
    # full run whose request carries sentinel keys, then scanning EVERY persisted byte for them.
    monkeypatch.setattr(trading_graph_mod, "TradingAgentsGraph", _make_fake_graph(FULL_CHUNKS))
    monkeypatch.setattr(jobs_mod, "write_report_tree", lambda fs, t, p: p)
    registry = JobRegistry(results_dir=tmp_path)

    secret_av = "SECRET-alpha-vantage-3f9a"
    secret_fred = "SECRET-fred-7c1d"
    secret_anth = "SECRET-anthropic-a2b8"
    job = registry.create({
        "mode": "pro", "ticker": "BTC-USD", "asset_type": "crypto",
        "provider": "anthropic", "deep_model": "claude-opus-4-8",
        "data_vendors": {"core_stock_apis": "alpha_vantage"},
        "api_keys": {"alpha_vantage": secret_av, "fred": secret_fred, "anthropic": secret_anth},
    })
    _wait_done(job)
    assert job.status == "done"

    # The manifest records the honest asset_type + vendor-agnostic summary fields.
    m = registry.list_runs()[0]
    assert m["asset_type"] == "crypto"

    # No persisted file anywhere under the results dir may contain any secret substring.
    blob = "\n".join(p.read_text(encoding="utf-8", errors="ignore")
                     for p in tmp_path.rglob("*") if p.is_file())
    for secret in (secret_av, secret_fred, secret_anth):
        assert secret not in blob


def test_history_survives_restart(monkeypatch, tmp_path):
    monkeypatch.setattr(trading_graph_mod, "TradingAgentsGraph", _make_fake_graph(FULL_CHUNKS))
    monkeypatch.setattr(jobs_mod, "write_report_tree", lambda fs, t, p: p)
    reg1 = JobRegistry(results_dir=tmp_path)
    job = reg1.create({"mode": "pro", "ticker": "SPY"})
    _wait_done(job)
    rid = job.run_id

    # A fresh registry over the same dir = a sidecar restart.
    reg2 = JobRegistry(results_dir=tmp_path)
    assert any(r["run_id"] == rid for r in reg2.list_runs())
    restored = reg2.get(rid)  # registered on startup so GET /runs/{id} still resolves post-restart
    assert restored is not None and restored.status == "done"


def test_list_runs_over_http(monkeypatch, tmp_path):
    monkeypatch.delenv("QUORUM_API_TOKEN", raising=False)
    monkeypatch.setattr(app_module.registry, "_results_dir", tmp_path)
    client = TestClient(app_module.app)

    created = client.post("/runs", json={"mode": "demo", "ticker": "NVDA", "step_delay": 0})
    run_id = created.json()["run_id"]
    _poll_status(client, run_id, "done")

    body = client.get("/runs").json()
    assert "runs" in body
    match = [r for r in body["runs"] if r["run_id"] == run_id]
    assert match and match[0]["mode"] == "demo" and match[0]["ticker"] == "NVDA"


def test_restored_run_reports_read_from_disk(monkeypatch, tmp_path):
    monkeypatch.setattr(trading_graph_mod, "TradingAgentsGraph", _make_fake_graph(FULL_CHUNKS))
    monkeypatch.setattr(jobs_mod, "write_report_tree", lambda fs, t, p: p)
    reg1 = JobRegistry(results_dir=tmp_path)
    job = reg1.create({"mode": "pro", "ticker": "SPY"})
    _wait_done(job)
    rid = job.run_id

    # Restart: the restored job has no in-memory final_state, so a cached review must read the
    # persisted reports.json off disk.
    reg2 = JobRegistry(results_dir=tmp_path)
    restored = reg2.get(rid)
    assert restored is not None and restored.final_state is None
    sections = JobRegistry.report_sections(restored)
    assert sections["market_report"] == "MKT"
    assert sections["final_trade_decision"] == "DEC"


def test_restored_run_includes_debate_sections(monkeypatch, tmp_path):
    # The bull/bear tug-of-war + the three risk views live nested in the engine final_state
    # (investment_debate_state / risk_debate_state); a cached review needs them decomposed and
    # persisted, or the signature debate renders empty.
    monkeypatch.setattr(trading_graph_mod, "TradingAgentsGraph", _make_fake_graph(FULL_CHUNKS))
    monkeypatch.setattr(jobs_mod, "write_report_tree", lambda fs, t, p: p)
    reg1 = JobRegistry(results_dir=tmp_path)
    job = reg1.create({"mode": "pro", "ticker": "SPY"})
    _wait_done(job)

    reg2 = JobRegistry(results_dir=tmp_path)  # restart
    sections = JobRegistry.report_sections(reg2.get(job.run_id))
    assert sections["bull"] == "B"
    assert sections["bear"] == "R"
    assert sections["aggressive"] == "A"
    assert sections["conservative"] == "C"
    assert sections["neutral"] == "N"


def test_manifest_records_agent_models_provenance(monkeypatch, tmp_path):
    monkeypatch.setattr(trading_graph_mod, "TradingAgentsGraph", _make_fake_graph(FULL_CHUNKS))
    monkeypatch.setattr(jobs_mod, "write_report_tree", lambda fs, t, p: p)
    registry = JobRegistry(results_dir=tmp_path)
    job = registry.create({
        "mode": "pro", "ticker": "SPY", "provider": "openai",
        "agent_models": {"bull_researcher": {"provider": "xai", "model": "grok-x"}},
    })
    _wait_done(job)
    m = registry.list_runs()[0]
    assert m["agent_models"]["bull_researcher"] == {"provider": "xai", "model": "grok-x"}
    assert m["agent_models"]["portfolio_manager"]["provider"] == "openai"  # resolved fallback


def test_demo_run_ignores_agent_models(monkeypatch, tmp_path):
    monkeypatch.delenv("QUORUM_API_TOKEN", raising=False)
    monkeypatch.setattr(app_module.registry, "_results_dir", tmp_path)
    client = TestClient(app_module.app)
    created = client.post("/runs", json={
        "mode": "demo", "ticker": "NVDA", "step_delay": 0,
        "agent_models": {"bull_researcher": {"provider": "xai", "model": "grok-x"}},
    })
    run_id = created.json()["run_id"]
    _poll_status(client, run_id, "done")
    m = next(r for r in client.get("/runs").json()["runs"] if r["run_id"] == run_id)
    assert m["agent_models"] is None  # demo never reaches plan_run -> no provenance


def test_cooperative_cancel_stops_the_run(monkeypatch, tmp_path):
    slow = [{"market_report": f"m{i}"} for i in range(60)]
    monkeypatch.setattr(trading_graph_mod, "TradingAgentsGraph", _make_fake_graph(slow, sleep=0.02))
    monkeypatch.setattr(jobs_mod, "write_report_tree", lambda fs, t, p: p)
    registry = JobRegistry(results_dir=tmp_path)

    job = registry.create({"mode": "pro", "ticker": "SPY", "analysts": ["market"]})
    time.sleep(0.1)  # let it start streaming
    assert registry.cancel(job.run_id) is True
    _wait_done(job)

    assert job.status == "cancelled"
    done = next(e for e in job.event_log.replay_from(0) if e.type == EventType.RUN_DONE)
    assert done.data["cancelled"] is True


def test_event_log_replay_from_offset():
    from services.api.event_log import EventLog
    from tradingagents.runtime import events as ev

    log = EventLog("test-run")
    for _ in range(5):
        log.append(ev.heartbeat())
    assert [e.seq for e in log.replay_from(0)] == [0, 1, 2, 3, 4]
    assert [e.seq for e in log.replay_from(3)] == [3, 4]
    assert log.last_seq == 4
    assert all(e.run_id == "test-run" for e in log.replay_from(0))


# --- HTTP / SSE wire layer (FastAPI TestClient over the singleton app) ---

def _poll_status(client, run_id, target="done", timeout=3.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        status = client.get(f"/runs/{run_id}").json()["status"]
        if status == target:
            return
        time.sleep(0.02)
    raise AssertionError(f"run {run_id} did not reach {target} (last={status})")


def test_healthz_and_catalog_endpoints():
    client = TestClient(app_module.app)
    health = client.get("/healthz")
    assert health.status_code == 200 and health.json()["status"] == "ok"
    body = client.get("/catalog/providers").json()
    assert "openai" in body["providers"] and "anthropic" in body["providers"]
    assert body["analysts"] == ["market", "social", "news", "fundamentals"]


def test_catalog_exposes_tool_capable_flag(monkeypatch):
    # P2.5a: each option additively carries `tool_capable` for the Dream Team gate, without changing
    # the existing label/value contract.
    monkeypatch.delenv("QUORUM_API_TOKEN", raising=False)
    body = TestClient(app_module.app).get("/catalog/providers").json()
    opt = body["providers"]["anthropic"]["deep"][0]
    assert opt["label"] and opt["value"]  # existing contract preserved
    assert opt["tool_capable"] is True
    custom = next(o for o in body["providers"]["ollama"]["deep"] if o["value"] == "custom")
    assert custom["tool_capable"] is None  # unknown user/local model -> UI warns, not blocks


def test_catalog_vendors_endpoint(monkeypatch):
    # P3.1: /catalog/vendors serves the per-category vendor picker; needs_key/key_env are single-sourced
    # from VENDOR_API_KEY_ENV so the UI can never disagree with what actually gets injected.
    monkeypatch.delenv("QUORUM_API_TOKEN", raising=False)
    from tradingagents.runtime.isolation import VENDOR_API_KEY_ENV

    body = TestClient(app_module.app).get("/catalog/vendors").json()
    cats = {c["key"]: c for c in body["categories"]}
    # The 6 engine categories, with the 2 optional ones flagged.
    assert {"core_stock_apis", "technical_indicators", "fundamental_data", "news_data",
            "macro_data", "prediction_markets"} <= set(cats)
    assert cats["macro_data"]["optional"] and cats["prediction_markets"]["optional"]
    assert not cats["core_stock_apis"]["optional"]
    assert cats["core_stock_apis"]["default"] == "yfinance"
    # core_stock_apis offers alpha_vantage (needs a key) + yfinance (keyless), agreeing with the map.
    core = {v["value"]: v for v in cats["core_stock_apis"]["vendors"]}
    assert core["yfinance"]["needs_key"] is False and core["yfinance"]["key_env"] is None
    for c in body["categories"]:
        for v in c["vendors"]:
            assert v["needs_key"] == (v["value"] in VENDOR_API_KEY_ENV)
            assert v["key_env"] == VENDOR_API_KEY_ENV.get(v["value"])


def test_bearer_auth_enforced(monkeypatch):
    monkeypatch.setenv("QUORUM_API_TOKEN", "s3cret")
    client = TestClient(app_module.app)
    assert client.get("/catalog/providers").status_code == 401
    assert client.get("/catalog/providers",
                      headers={"Authorization": "Bearer s3cret"}).status_code == 200
    assert client.get("/healthz").status_code == 200  # public path bypasses auth


def test_unknown_run_returns_404():
    client = TestClient(app_module.app)
    assert client.get("/runs/doesnotexist").status_code == 404
    assert client.post("/runs/doesnotexist/cancel").status_code == 404


def test_post_run_streams_sse_to_completion(monkeypatch, tmp_path):
    monkeypatch.delenv("QUORUM_API_TOKEN", raising=False)
    monkeypatch.setattr(trading_graph_mod, "TradingAgentsGraph", _make_fake_graph(FULL_CHUNKS))
    monkeypatch.setattr(jobs_mod, "write_report_tree", lambda fs, t, p: p)
    monkeypatch.setattr(app_module.registry, "_results_dir", tmp_path)
    client = TestClient(app_module.app)

    created = client.post("/runs", json={"mode": "pro", "ticker": "SPY"})
    assert created.status_code == 202
    run_id = created.json()["run_id"]

    received: list[str] = []
    with client.stream("GET", f"/runs/{run_id}/events") as resp:
        assert resp.status_code == 200
        for line in resp.iter_lines():
            if line.startswith("data:"):
                payload = json.loads(line[len("data:"):].strip())
                if payload.get("type"):  # skip heartbeats ({} data)
                    received.append(payload["type"])
                    if payload["type"] in ("run_done", "error"):
                        break

    assert received[0] == "run_started"
    assert received[-1] == "run_done"
    assert "report_section_done" in received

    _poll_status(client, run_id, "done")
    reports = client.get(f"/runs/{run_id}/reports").json()
    assert reports["sections"]["final_trade_decision"] == "DEC"


# --- Demo mode (cost-free synthetic run; no engine, no keys) ---

def test_demo_run_streams_full_debate_without_engine():
    from services.api.demo import run_demo
    from services.api.event_log import EventLog

    log = EventLog("demo")
    state = run_demo(log, "NVDA", lambda: False, step_delay=0)
    events = log.replay_from(0)

    assert events[0].type == EventType.RUN_STARTED
    assert events[-1].type == EventType.RUN_DONE
    assert events[-1].data["rating"] == "Buy"
    assert events[-1].data["structured"]["price_target"] == 152.0
    assert events[-1].data["cancelled"] is False

    sections = {e.data["section"] for e in events if e.type == EventType.REPORT_SECTION_DONE}
    assert {"market_report", "sentiment_report", "news_report", "fundamentals_report",
            "investment_plan", "trader_investment_plan", "final_trade_decision"} <= sections
    stages = {e.data["stage"] for e in events if e.type == EventType.STAGE_STARTED}
    assert len(stages) == 5
    assert state["final_trade_decision"].startswith("BUY NVDA")


def test_demo_run_cancels_early():
    from services.api.demo import run_demo
    from services.api.event_log import EventLog

    log = EventLog("demo")
    run_demo(log, "NVDA", lambda: True, step_delay=0)  # cancel immediately
    done = next(e for e in log.replay_from(0) if e.type == EventType.RUN_DONE)
    assert done.data["cancelled"] is True
    assert done.data["rating"] is None


def test_demo_run_over_http_without_keys(monkeypatch, tmp_path):
    monkeypatch.delenv("QUORUM_API_TOKEN", raising=False)
    monkeypatch.setattr(app_module.registry, "_results_dir", tmp_path)
    client = TestClient(app_module.app)

    created = client.post("/runs", json={"mode": "demo", "ticker": "NVDA", "step_delay": 0})
    assert created.status_code == 202
    run_id = created.json()["run_id"]

    received: list[str] = []
    with client.stream("GET", f"/runs/{run_id}/events") as resp:
        for line in resp.iter_lines():
            if line.startswith("data:"):
                payload = json.loads(line[len("data:"):].strip())
                if payload.get("type"):
                    received.append(payload["type"])
                    if payload["type"] in ("run_done", "error"):
                        break

    assert received[0] == "run_started"
    assert received[-1] == "run_done"
    _poll_status(client, run_id, "done")
    assert client.get(f"/runs/{run_id}/reports").json()["sections"]["final_trade_decision"].startswith("BUY")


def test_demo_run_strips_api_keys_from_stored_request(monkeypatch, tmp_path):
    # Defense-in-depth: a demo request must never retain BYO keys on the stored job.
    monkeypatch.delenv("QUORUM_API_TOKEN", raising=False)
    monkeypatch.setattr(app_module.registry, "_results_dir", tmp_path)
    client = TestClient(app_module.app)
    created = client.post("/runs", json={
        "mode": "demo", "ticker": "NVDA", "step_delay": 0,
        "api_keys": {"google": "should-be-stripped"},
    })
    assert created.status_code == 202
    job = app_module.registry.get(created.json()["run_id"])
    assert job is not None
    assert job.request.get("api_keys") is None


def test_env_keys_requires_bearer(monkeypatch):
    monkeypatch.setenv("QUORUM_API_TOKEN", "secret-token")
    client = TestClient(app_module.app)
    assert client.get("/env-keys").status_code == 401
    assert client.get("/env-keys", headers={"Authorization": "Bearer secret-token"}).status_code == 200


def test_env_keys_reads_known_provider_keys_from_dotenv(monkeypatch, tmp_path):
    monkeypatch.delenv("QUORUM_API_TOKEN", raising=False)
    envf = tmp_path / ".env"
    envf.write_text("GOOGLE_API_KEY=g-secret\nUNRELATED=x\n")
    monkeypatch.setattr("dotenv.find_dotenv", lambda *a, **k: str(envf))
    body = TestClient(app_module.app).get("/env-keys").json()
    assert body.get("google") == "g-secret"
    assert "unrelated" not in body  # only known providers are surfaced


def test_env_keys_missing_dotenv_returns_empty(monkeypatch, tmp_path):
    monkeypatch.delenv("QUORUM_API_TOKEN", raising=False)
    monkeypatch.setattr("dotenv.find_dotenv", lambda *a, **k: str(tmp_path / "absent.env"))
    assert TestClient(app_module.app).get("/env-keys").json() == {}
