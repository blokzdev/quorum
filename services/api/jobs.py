"""Server-owned, serialized job execution.

Each run is built as an isolated graph (clean config + per-job keys) and streamed to its event log.
Runs are serialized through a single worker thread: the process-global engine config / ``os.environ``
make concurrent in-process runs unsafe, and serializing also caps cost on a single-user desktop. A
second request simply queues behind the first.
"""

from __future__ import annotations

import logging
import queue
import re
import threading
import uuid
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any

from services.api.event_log import EventLog
from tradingagents.default_config import DEFAULT_CONFIG
from tradingagents.reporting import write_report_tree
from tradingagents.runtime import events as ev
from tradingagents.runtime.isolation import JobIsolationContext, build_api_keys_dict
from tradingagents.runtime.runner import ANALYST_ORDER, run_streaming

logger = logging.getLogger(__name__)

# Crude NL-intent ticker fallback for vibe mode (e.g. "what's the vibe on NVDA?"). A proper
# LLM-based intent resolver is a planned follow-up; for now an explicit ``ticker`` always wins.
_TICKER_RE = re.compile(r"\b([A-Z]{1,5}(?:[.\-][A-Z0-9]{1,4})?)\b")
_CANONICAL_SECTIONS = (
    "market_report", "sentiment_report", "news_report", "fundamentals_report",
    "investment_plan", "trader_investment_plan", "final_trade_decision",
)


@dataclass
class Job:
    run_id: str
    request: dict[str, Any]
    event_log: EventLog
    status: str = "queued"          # queued | running | done | error | cancelled
    cancel_flag: bool = False
    created_at: str = field(default_factory=lambda: datetime.now().isoformat(timespec="seconds"))
    final_state: dict[str, Any] | None = None
    report_path: str | None = None
    error: str | None = None


def _detect_asset_type(ticker: str) -> str:
    return "crypto" if "-USD" in ticker.upper() else "stock"


def _extract_ticker(intent: str | None) -> str | None:
    match = _TICKER_RE.search(intent or "")
    return match.group(1) if match else None


def plan_run(req: dict[str, Any]) -> dict[str, Any]:
    """Resolve a run request (vibe or pro) into the concrete inputs for a graph run."""
    ticker = req.get("ticker") or _extract_ticker(req.get("intent"))
    if not ticker:
        raise ValueError("no ticker resolved: provide 'ticker' or an 'intent' that names one")

    asset_type = req.get("asset_type") or _detect_asset_type(ticker)
    trade_date = req.get("trade_date") or datetime.now().strftime("%Y-%m-%d")
    requested = {a.lower() for a in (req.get("analysts") or list(ANALYST_ORDER))}
    selected = [a for a in ANALYST_ORDER if a in requested] or list(ANALYST_ORDER)
    depth = int(req.get("research_depth") or 1)

    config = dict(DEFAULT_CONFIG)
    config["max_debate_rounds"] = depth
    config["max_risk_discuss_rounds"] = depth
    if req.get("provider"):
        config["llm_provider"] = req["provider"].lower()
    if req.get("deep_model"):
        config["deep_think_llm"] = req["deep_model"]
    if req.get("quick_model"):
        config["quick_think_llm"] = req["quick_model"]
    if req.get("output_language"):
        config["output_language"] = req["output_language"]
    if req.get("backend_url"):
        config["backend_url"] = req["backend_url"]

    params = {
        "mode": req.get("mode", "vibe"), "research_depth": depth,
        "provider": config["llm_provider"], "deep_model": config["deep_think_llm"],
        "quick_model": config["quick_think_llm"],
    }
    return {
        "config": config, "selected": selected, "ticker": ticker, "trade_date": trade_date,
        "asset_type": asset_type, "params": params,
        "env_keys": build_api_keys_dict(req.get("api_keys") or {}),
    }


class JobRegistry:
    """Holds jobs and runs them one at a time on a background worker thread."""

    def __init__(self, results_dir: Path | None = None):
        self._jobs: dict[str, Job] = {}
        self._queue: queue.Queue[Job] = queue.Queue()
        self._lock = threading.Lock()
        self._results_dir = results_dir or Path(DEFAULT_CONFIG["results_dir"]) / "quorum_runs"
        self._worker = threading.Thread(
            target=self._worker_loop, name="quorum-job-worker", daemon=True
        )
        self._worker.start()

    def create(self, request: dict[str, Any]) -> Job:
        run_id = uuid.uuid4().hex[:16]
        job = Job(run_id=run_id, request=request, event_log=EventLog(run_id))
        with self._lock:
            self._jobs[run_id] = job
        self._queue.put(job)
        return job

    def get(self, run_id: str) -> Job | None:
        with self._lock:
            return self._jobs.get(run_id)

    def cancel(self, run_id: str) -> bool:
        job = self.get(run_id)
        if job is None or job.status in ("done", "error", "cancelled"):
            return False
        job.cancel_flag = True
        return True

    def _worker_loop(self) -> None:
        while True:
            job = self._queue.get()
            try:
                self._execute(job)
            except Exception as exc:  # never let one job take down the worker
                logger.exception("job %s failed", job.run_id)
                job.status = "error"
                job.error = str(exc)
                job.event_log.append(ev.error("job", str(exc)))

    def _execute(self, job: Job) -> None:
        if job.request.get("mode") == "demo":
            self._execute_demo(job)
            return
        # Lazy import: keeps the engine (LangChain/LangGraph + data vendors) off the demo path and out
        # of ``services.api.app``'s import graph, so a demo-capable bundle needn't ship the full ML
        # stack. The engine still loads once per pro/vibe run (cached in sys.modules thereafter).
        from tradingagents.graph.trading_graph import TradingAgentsGraph
        plan = plan_run(job.request)
        job.status = "running"
        self._results_dir.mkdir(parents=True, exist_ok=True)
        with JobIsolationContext(plan["config"], plan["env_keys"]):
            graph = TradingAgentsGraph(tuple(plan["selected"]), config=plan["config"], debug=False)
            instrument = graph.resolve_instrument_context(plan["ticker"], plan["asset_type"])
            init_state = graph.propagator.create_initial_state(
                plan["ticker"], plan["trade_date"],
                asset_type=plan["asset_type"], instrument_context=instrument,
            )
            args = graph.propagator.get_graph_args()
            job.final_state = run_streaming(
                graph, init_state, args, job.event_log.append,
                selected_analysts=plan["selected"], ticker=plan["ticker"],
                trade_date=plan["trade_date"], asset_type=plan["asset_type"],
                params=plan["params"], should_cancel=lambda: job.cancel_flag,
            )
            self._write_reports(job, plan["ticker"])
        job.status = "cancelled" if job.cancel_flag else "done"

    def _execute_demo(self, job: Job) -> None:
        """Cost-free synthetic run (no engine, no keys) for building/demoing the UI."""
        from services.api.demo import run_demo
        job.status = "running"
        ticker = job.request.get("ticker") or _extract_ticker(job.request.get("intent")) or "NVDA"
        delay = job.request.get("step_delay")
        job.final_state = run_demo(
            job.event_log, ticker, lambda: job.cancel_flag,
            step_delay=0.25 if delay is None else float(delay),
        )
        job.status = "cancelled" if job.cancel_flag else "done"

    def _write_reports(self, job: Job, ticker: str) -> None:
        try:
            from tradingagents.dataflows.utils import safe_ticker_component
            stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            path = self._results_dir / f"{safe_ticker_component(ticker)}_{job.run_id}_{stamp}"
            job.report_path = str(write_report_tree(job.final_state, ticker, path))
        except Exception:  # reports are a convenience; a write failure must not fail the run
            logger.debug("report write failed for %s", job.run_id, exc_info=True)

    @staticmethod
    def report_sections(job: Job) -> dict[str, str]:
        fs = job.final_state or {}
        return {k: fs[k] for k in _CANONICAL_SECTIONS if fs.get(k)}
