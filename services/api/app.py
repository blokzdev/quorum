"""Quorum local API sidecar — FastAPI app exposing the streaming contract over 127.0.0.1.

Endpoints: ``/healthz``, ``/catalog/providers``, ``POST /runs``, ``GET /runs/{id}``,
``GET /runs/{id}/events`` (SSE with Last-Event-ID), ``POST /runs/{id}/cancel``,
``GET /runs/{id}/reports``, ``POST /shutdown``. All routes except ``/healthz`` require the
per-launch bearer token in ``Authorization`` when ``QUORUM_API_TOKEN`` is set.
"""

from __future__ import annotations

import asyncio
import json
import os
import threading
from typing import Any, Literal

from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from sse_starlette.sse import EventSourceResponse

from services.api.jobs import JobRegistry
from tradingagents.llm_clients.model_catalog import MODEL_OPTIONS
from tradingagents.llm_clients.tool_capability import model_supports_tools
from tradingagents.runtime.events import CONTRACT_VERSION, EventType

app = FastAPI(title="Quorum API", version=str(CONTRACT_VERSION))
registry = JobRegistry()

_PUBLIC_PATHS = {"/healthz"}
_SSE_IDLE_TIMEOUT = 15  # seconds between heartbeats when no events are flowing


class RunRequest(BaseModel):
    mode: Literal["vibe", "pro", "demo"] = "vibe"
    intent: str | None = None
    ticker: str | None = None
    trade_date: str | None = None
    asset_type: str | None = None
    analysts: list[str] | None = None
    research_depth: int = 1
    provider: str | None = None
    deep_model: str | None = None
    quick_model: str | None = None
    backend_url: str | None = None
    # Per-provider effort/thinking knob — the UI sends only the one for the chosen provider; the
    # engine reads these from config (_get_provider_kwargs) and clients ignore unsupported efforts.
    google_thinking_level: str | None = None
    openai_reasoning_effort: str | None = None
    anthropic_effort: str | None = None
    output_language: str = "English"
    # "Dream Team" (P2.5): per-agent-role model overrides ({role_key: {provider, model, backend_url?,
    # effort?}}). Inner type stays permissive so a forward-compat field never 422s the request; the
    # engine reads keys defensively. Unset -> the shared quick/deep split runs every role.
    agent_models: dict[str, dict[str, Any]] | None = None
    # P3.1: per-category data-vendor selection ({category: vendor}), partial — unspecified categories
    # keep the engine default. Permissive (like agent_models) so a forward-compat category never 422s.
    data_vendors: dict[str, str] | None = None
    # BYO provider/vendor keys for this run ({provider: key}); never persisted server-side.
    api_keys: dict[str, str] | None = None
    # demo mode only: per-step delay in seconds (0 = instant, for tests).
    step_delay: float | None = None


@app.middleware("http")
async def _bearer_auth(request: Request, call_next):
    expected = os.environ.get("QUORUM_API_TOKEN")
    if (
        expected
        and request.url.path not in _PUBLIC_PATHS
        and request.headers.get("authorization", "") != f"Bearer {expected}"
    ):
        return JSONResponse({"error": "unauthorized"}, status_code=401)
    return await call_next(request)


@app.get("/healthz")
async def healthz():
    return {"status": "ok", "contract_version": CONTRACT_VERSION}


@app.get("/catalog/providers")
async def catalog():
    # `tool_capable` (additive) feeds the Dream Team gate: market/news/fundamentals analysts loop on
    # tool calls, so the desktop blocks a non-tool model there. null = unknown (e.g. a custom/local
    # model) → the UI warns rather than blocks. Existing label/value are unchanged.
    providers = {
        provider: {
            mode: [
                {"label": label, "value": value, "tool_capable": model_supports_tools(provider, value)}
                for label, value in options
            ]
            for mode, options in modes.items()
        }
        for provider, modes in MODEL_OPTIONS.items()
    }
    return {
        "contract_version": CONTRACT_VERSION,
        "providers": providers,
        "analysts": ["market", "social", "news", "fundamentals"],
    }


@app.get("/catalog/vendors")
async def catalog_vendors():
    # P3.1: the per-category data-vendor catalog for Model Studio's "Data sources" picker. Derived
    # ENTIRELY from engine constants + the single-source vendor->key map, so `needs_key`/`key_env` can
    # never drift from what build_api_keys_dict actually injects. Lazy-imported: the vendor taxonomy lives
    # in the heavy dataflows package — keep it off the app-boot/demo path (ADR 0002).
    from tradingagents.dataflows.interface import (
        OPTIONAL_CATEGORIES,
        TOOLS_CATEGORIES,
        VENDOR_METHODS,
    )
    from tradingagents.default_config import DEFAULT_CONFIG
    from tradingagents.runtime.isolation import VENDOR_API_KEY_ENV

    defaults = DEFAULT_CONFIG.get("data_vendors", {})
    categories = []
    for cat, info in TOOLS_CATEGORIES.items():
        vendors = sorted({v for tool in info["tools"] for v in VENDOR_METHODS.get(tool, {})})
        categories.append({
            "key": cat,
            "label": info.get("description", cat),
            "optional": cat in OPTIONAL_CATEGORIES,
            "default": defaults.get(cat),
            "vendors": [
                {"value": v, "needs_key": v in VENDOR_API_KEY_ENV, "key_env": VENDOR_API_KEY_ENV.get(v)}
                for v in vendors
            ],
        })
    return {"contract_version": CONTRACT_VERSION, "categories": categories}


def _resolve_ollama_native_base() -> str:
    """The Ollama HOST root for the native REST API (/api/tags). The engine's Ollama base is the
    OpenAI-compat endpoint (``…/v1``, overridable via ``OLLAMA_BASE_URL``); the native API lives at the
    host root, so strip a trailing ``/v1``."""
    base = (os.environ.get("OLLAMA_BASE_URL") or "http://localhost:11434/v1").rstrip("/")
    if base.endswith("/v1"):
        base = base[: -len("/v1")]
    return base


def _parse_ollama_models(data: dict[str, Any]) -> list[dict[str, Any]]:
    """Map Ollama ``/api/tags`` JSON → the picker's ``{name, tool_capable, size, family}`` rows.

    ``tool_capable`` is ``"tools" in capabilities`` — but a MISSING ``capabilities`` field (older Ollama)
    yields ``None`` (UNKNOWN), which the desktop gate WARNS on and never blocks, so a stale-Ollama user is
    never falsely locked out. Sorted (tool-capable first, then name) so the useful models surface on top.
    """
    out: list[dict[str, Any]] = []
    for m in data.get("models", []) or []:
        name = m.get("name") or m.get("model")
        if not name:
            continue
        caps = m.get("capabilities")
        tool_capable = ("tools" in caps) if isinstance(caps, list) else None
        details = m.get("details") or {}
        out.append({
            "name": name,
            "tool_capable": tool_capable,
            "size": m.get("size"),
            "family": details.get("family"),
        })
    # tool-capable (True) first, unknown (None) last, then alphabetical — a stable, useful ordering.
    out.sort(key=lambda r: (r["tool_capable"] is not True, r["tool_capable"] is None, r["name"]))
    return out


async def _fetch_ollama_tags(base_url: str) -> dict[str, Any]:
    # httpx is already an [api] dep + bundled (PyInstaller hiddenimports); import lazily to keep it off
    # the demo path (ADR 0002). Short timeout so a slow/absent Ollama never hangs the picker.
    import httpx

    async with httpx.AsyncClient(timeout=2.5) as client:
        resp = await client.get(f"{base_url}/api/tags")
        resp.raise_for_status()
        return resp.json()


@app.get("/catalog/local-models")
async def catalog_local_models():
    """P3.2a: the DEVICE's installed Ollama models + per-model tool-capability, so the picker surfaces
    real local models (Gemma/Qwen/GLM/…) instead of a hand-typed id. Bearer-gated. Degrades to an empty
    list when Ollama is unreachable/slow — the desktop then keeps its static Ollama option."""
    try:
        data = await _fetch_ollama_tags(_resolve_ollama_native_base())
        models = _parse_ollama_models(data)
    except Exception:
        models = []  # Ollama down / slow / malformed → empty; the desktop falls back cleanly.
    return {"contract_version": CONTRACT_VERSION, "local_models": models}


async def _fetch_ollama_version(base_url: str) -> str | None:
    """The device's Ollama version (``GET /api/version``) — or ``None`` when Ollama is absent/slow.
    Module-level (like ``_fetch_ollama_tags``) so endpoint tests can monkeypatch it. ``None`` is the
    discriminator the desktop uses for BOTH the per-entry version gate (a too-old Ollama visibly gates
    entries whose ``min_ollama_version`` exceeds it) and the Ollama-absent onboarding state (P5.3c/A4)."""
    import httpx

    try:
        async with httpx.AsyncClient(timeout=2.5) as client:
            resp = await client.get(f"{base_url}/api/version")
            resp.raise_for_status()
            version = resp.json().get("version")
            return version if isinstance(version, str) and version else None
    except Exception:
        return None  # Ollama down / slow / malformed -> absent; the catalog is still served.


@app.get("/catalog/edge-models")
async def catalog_edge_models():
    """P5.1a: the curated Edge Model Draft Board — versioned frozen seed data (tiers + per-model exact
    bytes / KV params / capability / verification status) + the detected Ollama version. Bearer-gated
    (not in ``_PUBLIC_PATHS``). The CATALOG is static engine data and is ALWAYS served — only
    ``ollama_version`` degrades to null when Ollama is unreachable (the desktop's absent-state signal).
    Lazy-imported like the other catalog routes (ADR 0002)."""
    from tradingagents.llm_clients.edge_catalog import get_edge_catalog

    version = await _fetch_ollama_version(_resolve_ollama_native_base())
    return {
        "contract_version": CONTRACT_VERSION,
        "ollama_version": version,
        **get_edge_catalog(),
    }


@app.get("/env-keys")
async def env_keys():
    """Host-only: surface provider keys from the local gitignored ``.env`` so the desktop can offer a
    one-time import into its OS keystore. Loopback + bearer only (NOT in ``_PUBLIC_PATHS``); values
    are NEVER logged and must never be exposed on a future remote-mobile surface (ADR 0001 — keys
    stay on the sidecar host). Missing ``.env`` returns ``{}`` (never 500)."""
    from dotenv import dotenv_values, find_dotenv

    from tradingagents.llm_clients.api_key_env import PROVIDER_API_KEY_ENV

    vals = dotenv_values(find_dotenv(usecwd=True))
    out: dict[str, str] = {}
    for provider, env_var in PROVIDER_API_KEY_ENV.items():
        if env_var and vals.get(env_var):
            out[provider] = vals[env_var]
    return out


@app.post("/runs", status_code=202)
async def create_run(req: RunRequest):
    body = req.model_dump()
    # Defense-in-depth: a demo run never touches the engine or keys, so drop any api_keys before the
    # request is stored on the job (the engine path already routes demo before plan_run).
    if body.get("mode") == "demo":
        body["api_keys"] = None
    job = registry.create(body)
    return {"run_id": job.run_id, "status": job.status}


@app.get("/runs")
async def list_runs():
    """Run history: the persisted ``run.json`` summaries (newest first), read from disk so the list
    survives a sidecar restart. Each item carries the verdict/cost summary + model/provider — the
    drill-down reports stay in the report tree, fetched per-run via ``GET /runs/{id}/reports``."""
    return {"runs": registry.list_runs()}


@app.get("/runs/{run_id}")
async def get_run(run_id: str):
    job = registry.get(run_id)
    if job is None:
        raise HTTPException(404, "run not found")
    return {
        "run_id": run_id, "status": job.status, "created_at": job.created_at,
        "last_seq": job.event_log.last_seq, "error": job.error, "report_path": job.report_path,
    }


@app.post("/runs/{run_id}/cancel")
async def cancel_run(run_id: str):
    if not registry.cancel(run_id):
        raise HTTPException(404, "run not found or already finished")
    return {"run_id": run_id, "status": "cancelling"}


@app.get("/runs/{run_id}/reports")
async def get_reports(run_id: str):
    job = registry.get(run_id)
    if job is None:
        raise HTTPException(404, "run not found")
    return {
        "run_id": run_id, "status": job.status,
        "sections": JobRegistry.report_sections(job), "report_path": job.report_path,
    }


@app.get("/runs/{run_id}/events")
async def stream_events(run_id: str, request: Request, last_event_id: str | None = Header(default=None)):
    job = registry.get(run_id)
    if job is None:
        raise HTTPException(404, "run not found")
    log = job.event_log
    start_seq = int(last_event_id) + 1 if (last_event_id and last_event_id.isdigit()) else 0

    async def generator():
        q = log.subscribe()          # subscribe BEFORE replay so nothing is missed
        last = start_seq - 1
        try:
            terminal_replayed = False
            for event in log.replay_from(start_seq):
                yield _sse(event)
                last = event.seq
                terminal_replayed = event.type in (EventType.RUN_DONE, EventType.ERROR)
            if terminal_replayed:
                return  # the run already finished; everything has been replayed
            while True:
                if await request.is_disconnected():
                    return
                try:
                    event = await asyncio.wait_for(q.get(), timeout=_SSE_IDLE_TIMEOUT)
                except asyncio.TimeoutError:
                    yield {"event": "heartbeat", "data": "{}"}
                    continue
                if event.seq <= last:
                    continue  # already delivered via replay
                yield _sse(event)
                last = event.seq
                if event.type in (EventType.RUN_DONE, EventType.ERROR):
                    return
        finally:
            log.unsubscribe(q)

    return EventSourceResponse(generator())


def _sse(event) -> dict:
    return {"id": str(event.seq), "event": event.type.value, "data": json.dumps(event.to_dict())}


@app.post("/shutdown")
async def shutdown():
    # Give the response a moment to flush, then exit the process.
    threading.Timer(0.25, lambda: os._exit(0)).start()
    return {"status": "shutting down"}
