"""The concurrent model-pull lane (P5.2a) — asyncio tasks on the event loop, NEVER the run worker.

Why a separate lane (plan A1): ``jobs.py``'s serialized worker exists for process-global config/env
isolation and LLM cost capping — neither applies to a pull, and queueing a 6–24GB download behind (or
ahead of) an analysis run would block one on the other for the download's duration. Runs live on the
``quorum-job-worker`` *thread*; pulls are pure network I/O as tasks on uvicorn's loop — by
construction neither can block the other (the A1 exit criterion is structural, not scheduled).

The pull-stream contract is a SEPARATE lightweight snapshot stream — it never enters the run event
union and does not bump ``CONTRACT_VERSION``. Snapshots are state-carrying and idempotent (latest
wins), so reconnects need no ``Last-Event-ID``/replay: the SSE endpoint emits every known pull's
current snapshot on connect, then live updates.

Ollama ``/api/pull`` behavior (live-verified on 0.32.0): NDJSON lines — ``pulling manifest`` →
per-layer ``{status: 'pulling <digest12>', digest, total, completed?}`` (early events omit
``completed`` → 0) → ``verifying sha256 digest`` → ``writing manifest`` → ``success``; error lines
carry ``{"error": ...}``; a cancelled pull resumes server-side on re-pull (documented + demonstrated).

Drift tripwire (P5.2c): the curated catalog carries each entry's EXACT registry model-layer bytes;
Ollama tags are repointable post-ship, so a repointed tag surfaces as a visible byte mismatch —
early (a layer larger than the catalog's model layer) or at success (no layer matched it) — never a
silent lie. State is in-memory by design: a sidecar restart forgets pull *history*, not progress
(Ollama owns the blobs; re-pull resumes).
"""

from __future__ import annotations

import asyncio
import json
import time
from collections.abc import AsyncIterator
from dataclasses import dataclass, field
from typing import Any

# Terminal states — a tag in one of these may be re-pulled fresh (the cancel→resume path).
_TERMINAL = {"success", "error", "cancelled"}


async def _ollama_pull_lines(base_url: str, tag: str) -> AsyncIterator[dict[str, Any]]:
    """Stream parsed NDJSON lines from Ollama's ``POST /api/pull``. Module-level so tests
    monkeypatch this seam with a fake line stream (the ``_fetch_ollama_tags`` precedent)."""
    import httpx  # lazy — keep it off the demo boot path (ADR 0002)

    async with (
        httpx.AsyncClient(timeout=httpx.Timeout(30.0, connect=5.0)) as client,
        client.stream(
            "POST", f"{base_url}/api/pull", json={"model": tag, "stream": True}
        ) as resp,
    ):
        resp.raise_for_status()
        async for line in resp.aiter_lines():
            if not line.strip():
                continue
            try:
                yield json.loads(line)
            except ValueError:
                continue  # a malformed line is skipped, not fatal — the stream may recover


@dataclass
class PullState:
    """One tag's pull, normalized from Ollama's per-layer NDJSON into idempotent snapshots."""

    tag: str
    catalog_bytes: int
    status: str = "pulling"  # pulling | verifying | success | error | cancelled
    error: str | None = None
    error_kind: str | None = None  # ollama_unreachable | ollama_error
    drift: bool = False
    drift_reason: str | None = None
    started_at: float = field(default_factory=time.time)
    finished_at: float | None = None
    layers: dict[str, dict[str, int]] = field(default_factory=dict)  # digest -> {total, completed}
    task: asyncio.Task | None = None

    @property
    def total(self) -> int:
        return sum(layer["total"] for layer in self.layers.values())

    @property
    def completed(self) -> int:
        return sum(layer["completed"] for layer in self.layers.values())

    def snapshot(self) -> dict[str, Any]:
        return {
            "tag": self.tag,
            "status": self.status,
            "total": self.total,
            "completed": self.completed,
            "catalog_bytes": self.catalog_bytes,
            "drift": self.drift,
            "drift_reason": self.drift_reason,
            "error": self.error,
            "error_kind": self.error_kind,
            "started_at": self.started_at,
            "finished_at": self.finished_at,
        }


class PullRegistry:
    """All pulls, active + terminal (terminal snapshots are retained so a reconnecting UI still sees
    WHY a pull died). Producers and consumers share the event loop → plain ``put_nowait`` fan-out
    (no cross-thread hand-off, unlike EventLog)."""

    def __init__(self) -> None:
        self._pulls: dict[str, PullState] = {}
        self._subscribers: list[asyncio.Queue] = []

    # --- lifecycle -------------------------------------------------------------------------------

    def start(self, tag: str, catalog_bytes: int, base_url: str) -> tuple[PullState, bool]:
        """Start (or join) a pull. Returns ``(state, created)`` — an ACTIVE pull for the tag is
        joined idempotently (double-click safe); a terminal one is replaced by a fresh pull (the
        re-pull-after-cancel path; Ollama resumes server-side)."""
        existing = self._pulls.get(tag)
        if existing is not None and existing.status not in _TERMINAL:
            return existing, False
        state = PullState(tag=tag, catalog_bytes=catalog_bytes)
        self._pulls[tag] = state
        state.task = asyncio.get_running_loop().create_task(self._run_pull(state, base_url))
        return state, True

    def cancel(self, tag: str) -> PullState | None:
        """Cancel an active pull (``None`` = no active pull for the tag). ``task.cancel()`` unwinds
        the httpx stream at the next await, closing the socket — Ollama stops downloading and the
        next pull of the tag resumes from the layers already on disk."""
        state = self._pulls.get(tag)
        if state is None or state.status in _TERMINAL or state.task is None:
            return None
        state.task.cancel()
        return state

    def get(self, tag: str) -> PullState | None:
        return self._pulls.get(tag)

    def snapshots(self) -> list[dict[str, Any]]:
        return [s.snapshot() for s in self._pulls.values()]

    # --- fan-out ---------------------------------------------------------------------------------

    def subscribe(self) -> asyncio.Queue:
        q: asyncio.Queue = asyncio.Queue()
        self._subscribers.append(q)
        return q

    def unsubscribe(self, q: asyncio.Queue) -> None:
        if q in self._subscribers:
            self._subscribers.remove(q)

    def _publish(self, state: PullState) -> None:
        snap = state.snapshot()
        for q in self._subscribers:
            q.put_nowait(snap)

    # --- the pull worker -------------------------------------------------------------------------

    async def _run_pull(self, state: PullState, base_url: str) -> None:
        try:
            async for line in _ollama_pull_lines(base_url, state.tag):
                if "error" in line:
                    state.status = "error"
                    state.error = str(line["error"])  # Ollama's text, passed through honestly
                    state.error_kind = "ollama_error"
                    break
                status = str(line.get("status", ""))
                digest = line.get("digest")
                if digest:
                    total = int(line.get("total") or 0)
                    completed = int(line.get("completed") or 0)  # early events omit it → 0
                    state.layers[digest] = {"total": total, "completed": completed}
                    # Early drift: a single layer LARGER than the curated model layer means the tag
                    # now points at something bigger than what was curated.
                    if total > state.catalog_bytes and not state.drift:
                        state.drift = True
                        state.drift_reason = "layer exceeds catalog bytes"
                elif status.startswith("verifying"):
                    state.status = "verifying"
                elif status == "success":
                    state.status = "success"
                    # At-success drift: the curated model layer's exact bytes must appear among the
                    # pulled layers (both sides come from the same registry manifest data).
                    if not state.drift and all(
                        layer["total"] != state.catalog_bytes for layer in state.layers.values()
                    ):
                        state.drift = True
                        state.drift_reason = "no layer matched catalog bytes"
                self._publish(state)
                if state.status in _TERMINAL:
                    break
            else:
                # Stream ended without a terminal line — treat as an error, never a silent hang.
                if state.status not in _TERMINAL:
                    state.status = "error"
                    state.error = "pull stream ended without success"
                    state.error_kind = "ollama_error"
        except asyncio.CancelledError:
            state.status = "cancelled"
            # Do not re-raise: the task's job is to record the terminal state; Ollama resumes later.
        except Exception as exc:  # connect refused / timeout / HTTP error → Ollama unreachable
            state.status = "error"
            state.error = str(exc)
            state.error_kind = "ollama_unreachable"
        finally:
            state.finished_at = time.time()
            if state.status not in _TERMINAL:  # defensive — never leave a zombie "pulling"
                state.status = "error"
                state.error = state.error or "pull ended unexpectedly"
                state.error_kind = state.error_kind or "ollama_error"
            self._publish(state)
