# CLAUDE.md — Quorum

This repo is a de-forked descendant of **TradingAgents**, evolved into **Quorum**: a premium
**desktop** research terminal (Windows → macOS) that wraps the existing Python multi-agent
trading-analysis engine, with a mobile remote planned post-V1. This file orients any agent working
here. Keep it current; it is loaded into context each session.

> Status: **Phase 1 complete** (de-forked 2026-06-26). The Python engine is mature; the Flutter
> desktop app + FastAPI sidecar are a proven vertical slice. Next is Phase 2 (Hub, Settings/Model
> Studio, applied brand, signed installer). The engine package stays named `tradingagents` to
> preserve merge-ability with upstream `TauricResearch/TradingAgents`.

## What this project is

A user picks a ticker; a team of LLM agents (analysts → bull/bear researcher debate → trader →
risk team → portfolio manager) debate and produce a **BUY / HOLD / SELL** verdict with drill-down
into each agent's report. Models are **user-selectable across many frontier providers**. The Flutter
desktop app is the premium front-end; the Python engine is the brain, bundled and run as a local
sidecar (provider keys stay on the user's machine; mobile-as-remote reuses the same API post-V1).

It is a **research / educational** tool, **not financial advice**. Keep that posture in the product
(disclaimers, no real-money execution in early versions; paper-trading sandbox is a post-V1 phase).

## The engine (Python, `tradingagents/`)

Built on **LangGraph**. Entry point: `tradingagents.graph.trading_graph.TradingAgentsGraph`.

- `graph/` — orchestration. `propagate(ticker, date, asset_type)` runs the whole graph.
  `_run_graph` drives `self.graph.stream(..., stream_mode="values")`, yielding the full accumulated
  state per node — the live-progress hook the sidecar subscribes to. Checkpoint resume is opt-in.
- `agents/` — analysts (market, social, news, fundamentals), researchers (bull/bear), managers
  (research, portfolio), risk_mgmt (aggressive/conservative/neutral), trader. Some emit structured
  output (`agents/schemas.py`, `agents/utils/structured.py`).
- `llm_clients/` — provider layer. `factory.create_llm_client` dispatches native clients
  (anthropic, google, azure, bedrock) and routes the rest through an OpenAI-compatible registry.
  `model_catalog.py` holds current frontier model IDs per provider; effort knobs are per-provider.
- `dataflows/` — data vendors (yfinance free default, Alpha Vantage, FRED, Polymarket, StockTwits,
  Reddit, news) behind a verified data-access contract. Config: `data_vendors` per category.
- `default_config.py` — single `_ENV_OVERRIDES` map (`TRADINGAGENTS_*` → config key); env-driven.
- `reporting` — `write_report_tree(final_state, ticker, path)` writes the markdown report tree.
- `runtime/` (Quorum addition) — TUI-free streaming seam: `events.py` (typed `Event` contract,
  `CONTRACT_VERSION`), `runner.py` (`run_streaming` maps `graph.stream` chunks → incremental events;
  decomposes investment_debate_state/risk_debate_state into discrete bull/bear/aggressive/… sections),
  `isolation.py` (`JobIsolationContext` per-job config + key injection).
- `cli/` — interactive Typer/Rich CLI (the original UX reference).

**The completed-run `final_state` shape is the UI's data model**: `market_report`, `sentiment_report`,
`news_report`, `fundamentals_report`, `investment_debate_state` (bull/bear/judge),
`trader_investment_plan`, `risk_debate_state`, `investment_plan`, `final_trade_decision`.

## The backend sidecar (`services/api/`)

FastAPI on `127.0.0.1:0` (ephemeral port) + per-launch bearer token; **SSE** event stream; runs are
server-owned durable jobs (serialized, one at a time). `__main__.py` prints a `{port, token}` stdout
handshake and self-exits if `QUORUM_PARENT_PID` dies. Endpoints: `/healthz` (public), `/catalog/...`,
`POST /runs`, `GET /runs/{id}`, `GET /runs/{id}/events` (SSE, Last-Event-ID resume), `/cancel`,
`/reports`, `/shutdown`. `mode: "demo"` streams a cost-free synthetic run; `"pro"`/`"vibe"` run the
real engine. `demo.py` is the synthetic streamer.

## The desktop app (`apps/desktop/` Flutter + `packages/quorum_core/` pure Dart)

- `packages/quorum_core/` — portable domain layer: sealed `QuorumEvent` union (mirrors
  `runtime/events.py`), immutable `RunViewState`, pure `reduce(state,event)`, `ApiClient`,
  hand-rolled `SseTransport` (bearer + Last-Event-ID), `EngineEndpoint` abstraction.
- `apps/desktop/` — Flutter (org dev.quorum), Riverpod 3 (one `runControllerProvider`),
  `DesktopSidecarEndpoint` spawns `.venv\Scripts\python.exe -m services.api` (taskkill teardown).
  `lib/ui/terminal_screen.dart` = the frameless 3-pane terminal (pipeline rail / reasoning feed with
  the bull-vs-bear tug-of-war / verdict rail); `quorum_colors.dart` = design tokens; bundled brand
  fonts Inter + JetBrains Mono under `fonts/`. Window chrome via `window_manager` (frameless,
  `onWindowClose` owns sidecar teardown → `destroy()`).
- **Verify UI via golden render-to-PNG** (`flutter test --update-goldens` → Read the PNG): the test
  harness loads the bundled fonts so committed goldens are deterministic. Live Flutter-GPU windows
  can't be screen-captured here (PrintWindow/CopyFromScreen blank/occluded; dev-exe gets no
  computer-use grant) — golden is primary; prove window/teardown behaviour via WM_CLOSE + `tasklist`.

### Run / test

```bash
pip install ".[dev]"                                  # engine deps (use the repo .venv)
pytest                                                # CI gate = ruff + pytest (unit/integration/smoke)
ruff check .
cd apps/desktop && flutter test test/                 # Dart unit + golden suite
flutter build windows --debug                         # build the desktop app
```
CI (`.github/workflows/ci.yml`) gates on **ruff + pytest** — keep new packages passing it.

## Architecture direction

- **Engine**: source of truth; extend, don't rewrite. Package name `tradingagents` is frozen.
- **Sidecar**: thin FastAPI wrapper; the streaming/job/event seam already generalizes from
  "analysis run" to a future "execution job" (paper-trading sandbox = post-V1 P10/P11).
- **Desktop**: Flutter premium UI; provider/model selection backed by `model_catalog.py` (Phase 2
  Model Studio). **Mobile** = LAN/WAN remote over the *same* API, post-V1.

## Environment & sandbox conventions (Windows host)

- Host: Windows 11, **PowerShell primary** (Bash tool available for POSIX). Python 3.12 in `.venv`.
  **Flutter/Dart installed** (`C:\dev\flutter`). Ollama runs locally on `:11434` for free real runs
  — note the pre-installed Llama-3 8B models lack tool-calling; use `llama3.2:latest` (tool-capable).
- **Docker**: a separate **Knovo** project runs a Supabase stack (ports 54321–54327, 5432). Do not
  disturb it. Avoid Windows-excluded port ranges for the sidecar (let it pick ephemeral).
- Scratch/work files go in the session scratchpad, not the repo.
- **Secret hygiene**: provider keys live only in the gitignored `.env` (never committed — verified
  clean of history). A shared Gemini test key is pending rotation (release-hygiene task).

## Working loop

Research → Plan subphases → execute → test (golden + sidecar + headless real runs) → refine.
Operate in **Ultracode** mode: author Workflows for substantive research/review fan-out and
adversarially verify before committing. Ship small, reviewable commits with clear exit criteria.

## Git

`origin` = `blokzdev/quorum` (private), `upstream` = `TauricResearch/TradingAgents` (pull engine
fixes manually). `main` is the product line. Branch for changes; commit/push only when asked.
