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
from typing import Literal

from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from sse_starlette.sse import EventSourceResponse

from services.api.jobs import JobRegistry
from tradingagents.llm_clients.model_catalog import MODEL_OPTIONS
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
    providers = {
        provider: {
            mode: [{"label": label, "value": value} for label, value in options]
            for mode, options in modes.items()
        }
        for provider, modes in MODEL_OPTIONS.items()
    }
    return {
        "contract_version": CONTRACT_VERSION,
        "providers": providers,
        "analysts": ["market", "social", "news", "fundamentals"],
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
