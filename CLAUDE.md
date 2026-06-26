# CLAUDE.md — Vibe Trading

This repo is a fork of **TradingAgents** being evolved into **Vibe Trading**: a premium Android app
on top of the existing Python multi-agent trading-analysis engine. This file orients any agent
working here. Keep it current; it is loaded into context each session.

> Status: orientation phase. The Python engine is mature; the mobile app + backend API are
> greenfield. The "Vibe Trading architecture" section below is the agreed direction — update it as
> decisions land.

## What this project is

A user picks a ticker; a team of LLM agents (analysts → bull/bear researcher debate → trader →
risk team → portfolio manager) debate and produce a **BUY / HOLD / SELL** verdict with drill-down
into each agent's report. Models are **user-selectable across many frontier providers**. The Android
app is the new premium front-end; the Python engine is the brain.

It is a **research / educational** tool, **not financial advice**. Keep that posture in the product
(disclaimers, no real-money execution in early versions).

## The existing engine (Python, `tradingagents/`)

Built on **LangGraph**. Entry point: `tradingagents.graph.trading_graph.TradingAgentsGraph`.

- `graph/` — orchestration. `propagate(ticker, date, asset_type)` runs the whole graph.
  `_run_graph` drives `self.graph.stream(..., stream_mode="values")`, yielding the full accumulated
  state per node — **this is the live-progress hook** a backend subscribes to. `__init__` also
  accepts `callbacks=[...]`. Checkpoint resume is opt-in (`checkpoint_enabled` → per-ticker SQLite).
- `agents/` — analysts (market, social, news, fundamentals), researchers (bull/bear), managers
  (research, portfolio), risk_mgmt (aggressive/conservative/neutral), trader. Some emit structured
  output (`agents/schemas.py`, `agents/utils/structured.py`).
- `llm_clients/` — provider layer. `factory.create_llm_client` dispatches native clients
  (anthropic, google, azure, bedrock) and routes the rest through an OpenAI-compatible registry.
  `model_catalog.py` holds the current frontier model IDs per provider. Reasoning/effort knobs are
  per-provider (`google_thinking_level`, `openai_reasoning_effort`, `anthropic_effort`).
- `dataflows/` — data vendors (yfinance, Alpha Vantage, FRED, Polymarket, StockTwits, Reddit, news)
  behind a verified data-access contract + market-data validator. Config: `data_vendors` per category.
- `default_config.py` — single `_ENV_OVERRIDES` map (`TRADINGAGENTS_*` → config key); env-driven.
- `reporting` — `write_report_tree(final_state, ticker, path)` writes the markdown report tree
  (shared by the CLI and programmatic `save_reports`).
- `cli/` — interactive Typer/Rich/questionary CLI; closest thing to a UX spec for the mobile flow.

**The completed-run `final_state` shape is the mobile UI's data model**: `market_report`,
`sentiment_report`, `news_report`, `fundamentals_report`, `investment_debate_state` (bull/bear/judge),
`trader_investment_plan`, `risk_debate_state`, `investment_plan`, `final_trade_decision`.

### Run / test the engine

```bash
pip install ".[dev]"          # core + ruff/pytest
python -m cli.main            # interactive CLI (or: tradingagents)
pytest                        # unit/integration/smoke markers; CI gate = ruff + pytest
ruff check .
```

CI (`.github/workflows/ci.yml`) gates on **ruff + pytest** — keep new packages passing it.

## Vibe Trading architecture (direction — refine as decided)

- **Engine**: keep the Python engine as the source of truth; extend, don't rewrite.
- **Backend**: a thin API service wrapping the engine, running a multi-agent run as a
  **resumable server-side job** that streams node/agent events (provider keys stay server-side or
  BYO; never embed provider secrets in the APK).
- **Mobile**: Android-first premium UI rendering the streaming debate + final verdict, with model/
  provider selection backed by `model_catalog.py`.
- _(Stack, transport, and hosting choices are being finalized in the vision discussion.)_

## Environment & sandbox conventions (Windows host)

- Host: Windows 11, PowerShell primary (Bash tool available for POSIX). Java 22, Node 22, Python 3.12.
  Android SDK / adb / gradle / flutter are **not yet installed**.
- **Docker**: a separate **Knovo** project runs a Supabase stack (ports 54321–54327, 5432). Do not
  disturb it. Prefer isolated containers/networks for Vibe Trading services.
- **Emulators**: other agents use adb/console ports **5554 and 5556**. Any emulator launched here
  must pin a **different** port (e.g. `-port 5560`+) to avoid collisions.
- Self-verify UI changes with the emulator + `adb exec-out screencap` screenshots, not only tests.
- Scratch/work files go in the session scratchpad, not the repo.

## Working loop

Research → Plan subphases/PRs → execute → test (sandbox + emulator + screenshots) → refine.
Ship small, reviewable PRs with clear exit criteria. Use Workflows for substantive research/review
fan-out and adversarially verify before committing to a direction. Discuss the vision before big builds.

## Git

Fork: `origin` = `blokzdev/TradingAgents`, `upstream` = `TauricResearch/TradingAgents`. Branch for
changes; commit/push only when asked.
