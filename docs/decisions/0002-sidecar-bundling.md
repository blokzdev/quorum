# ADR 0002 — Sidecar bundling strategy

- **Status:** Accepted (2026-06-26)
- **Context:** Phase 2 P2.0 spike ([phase-2-plan.md](../phase-2-plan.md#p20--sidecar-bundling-spike-gating-mostly-throwaway))
- **Deciders:** Quorum desktop/ops track
- **Spike:** [`packaging/spike/`](../../packaging/spike/)

## Context

The Phase 2 installer (P2.6) must ship the Python FastAPI sidecar inside the desktop app. Today
`apps/desktop/lib/engine/desktop_sidecar_endpoint.dart` spawns the sidecar by searching upward for
`.venv\Scripts\python.exe` — a shipped exe has no repo `.venv`, so the sidecar would never start. The
P2.0 spike resolves *how* to freeze the sidecar into a standalone executable that preserves the exact
desktop contract (stdout `{port, token}` handshake, `/healthz`, bearer auth, SSE stream, `/shutdown`,
`QUORUM_PARENT_PID` self-exit, taskkill teardown) when run with no Python, no `.venv`, and no repo
present.

## Decision

**Freeze the sidecar with PyInstaller in `onedir` mode**, and **decouple the demo path from the
engine via a lazy import** so a demo-capable bundle excludes the heavy ML stack.

Empirically verified on this Windows host (Python 3.12.5, PyInstaller 6.21.0):

- **Lazy import** (`services/api/jobs.py`): deferring the `TradingAgentsGraph` import out of module
  top-level dropped `import services.api.app` from **~1898 → 500 modules**, with **zero**
  `langgraph / yfinance / pandas / numpy / stockstats` on the demo path. `langchain_core` remains
  (loaded unconditionally by `tradingagents/__init__.py`; it cannot be excluded without editing that
  package).
- **Demo onedir bundle:** `quorum_sidecar.exe` 14 MB, **61 MB** total — vs ~300–400 MB unexcluded.
  No heavy modules leaked into `_internal`; `pydantic_core` present.
- **Frozen contract, run from outside the repo/.venv with a sanitized env: 11/11 PASS** — handshake
  (`contract_version: 1`) in **428 ms** (Dart budget 12 s), `/healthz` 200, catalog 401-without /
  200-with token, demo `POST /runs` 202, SSE to `run_done` (rating Buy, confidence 0.72, seq
  monotonic from 0), `/shutdown` exit.
- **Parent-PID self-exit:** the frozen exe self-exits **2.20 s** after its `QUORUM_PARENT_PID` dies,
  and is torn down by `taskkill /T /F` in 0.20 s.

### Required code fixes (landed for real, not throwaway)

1. **Lazy engine import** — `services/api/jobs.py`: `TradingAgentsGraph` imported inside
   `_execute()`'s pro/vibe branch (the demo early-return runs first).
2. **Windows parent-PID watchdog** — `services/api/__main__.py`: `OpenProcess` returns a live handle
   even for an **already-exited** PID, so the watchdog never fired on parent death (an orphaned-
   process bug in Phase 1). Fixed by confirming liveness via `GetExitCodeProcess` (`STILL_ACTIVE` ==
   259), with the handle `restype` set to avoid 64-bit truncation.

Pinned versions at spike time: PyInstaller 6.21.0, pydantic 2.13.4 / pydantic_core 2.46.4,
fastapi 0.138.1, uvicorn 0.49.0, sse-starlette 3.4.5, anyio 4.14.1, langchain-core 1.4.8.

## Alternatives considered

- **PyInstaller `onefile`** — rejected: each launch re-extracts to a `_MEIxxxx` temp dir, risking the
  12 s handshake budget under cold-start + antivirus scans, and gives no on-disk inspectability.
  `onedir` starts faster and is signable as a folder.
- **Embedded / relocatable venv** (ship `python.exe` + `site-packages`) — rejected: still ships a
  Python runtime and does not force the frozen-import discipline the installer needs; larger and more
  fragile to path assumptions.
- **Nuitka** — rejected: heavier toolchain for no benefit on a loopback sidecar.

## Consequences

- **Cold-start (428 ms) is well under the 12 s Dart budget** — no need to raise
  `desktop_sidecar_endpoint.dart`'s handshake timeout. (Re-measure on a locked-down / AV-heavy target;
  bump to 15–20 s only if a real machine exceeds ~6 s.)
- **The full-engine freeze already works — a strong de-risk for P2.6.** The spike's
  `quorum_sidecar_full.spec` (125 MB, `collect_submodules` of langchain_core + langgraph) **PASSED**
  the import smoke: `/healthz` 200, and a pro run **executed into the analyst stage**
  (`run_started → stage_started → agent_started → token`) with **no `ModuleNotFoundError`** — the
  downstream failure was only the deliberately-unreachable Ollama endpoint. So the LangChain/LangGraph
  stack both freezes and runs. P2.6 should ship **one combined onedir** that runs demo cheaply (the
  lazy import keeps demo light at runtime even with the engine bundled) and pro/vibe when keys are
  present; remaining P2.6 work is trimming size and pinning the `collect_*` hooks against production
  deps, not proving feasibility.
- **Re-verify the watchdog fix against a real Flutter parent** in P2.6 integration (here the parent
  was a Python subprocess).
- **`langchain_core` is unavoidably bundled** (≈ baseline size cost) — accepted.
- **`console=True` is required** so the stdout handshake reaches the desktop's piped stdout; a future
  no-console variant needs a different handshake channel (file/named-pipe) — flagged for P2.6.
- The spike is throwaway: only the two source fixes land for real; everything under
  `packaging/spike/` (specs, entry shim, harness) is scaffolding, with `build/` + `dist*/` git-ignored.

## Sources

- [PyInstaller documentation — onedir vs onefile, spec files, hooks](https://pyinstaller.org/en/stable/)
- Spike artifacts: [`packaging/spike/`](../../packaging/spike/) (`quorum_sidecar_demo.spec`,
  `quorum_sidecar_full.spec`, `spike_check.py`, `sidecar_entry.py`).
