# CLAUDE.md — Quorum

This repo is a de-forked descendant of **TradingAgents**, evolved into **Quorum**: a premium
**desktop** research terminal (Windows → macOS) that wraps the existing Python multi-agent
trading-analysis engine, with a mobile remote planned post-V1. This file orients any agent working
here. Keep it current; it is loaded into context each session.

> Status: **Phase 4 (V1 Release & Hardening) in progress — P4.1 ✅ P4.2 ✅ P4.3 ✅; P4.4/P4.5 remain.**
> Plan-locked + merged (**[docs/phase-4-plan.md](docs/phase-4-plan.md)**, PR #32). Heading to an **unsigned
> 1.0.0 Windows GA** (**zero paid spend** — production code-signing **deferred to V2**,
> [ADR 0007](docs/decisions/0007-defer-code-signing-to-v2.md)). Done: **P4.1** security + CI-hardening
> (gitleaks secret-scan gate, SECURITY.md + threat model, required-flutter merge gate); **P4.2** UX-integrity
> (the 4 recon-audit blockers: WCAG-AA chip contrast, a golden-harness H1 fix, shell-chrome golden coverage,
> vendor-attributed key labels); **P4.3** release CI (packaging build **proven e2e** + clean-install smoke +
> a frozen-bundle per-provider freeze check). Remaining: **P4.4** unsigned-release readiness (Run-anyway docs
> + Defender pre-submission; the **hub-03** in-app disclaimer is a founder decision — [HUMAN.md](HUMAN.md) §2)
> and **P4.5** GA close-out (version/docs reconciliation, then the founder-gated 1.0.0 publish). Merge model:
> subphases self-merged as-you-go (founder-delegated) gated on full CI green + fresh-context review; the GA
> publish stays founder-surfaced. Phases 1–3 shipped to `main` (Phase 3 = PR #29 `0a7ad57`). Phase 3 (Depth & Refinement)
> surfaced the untapped engine — **BYO-key data vendors** (P3.1),
> **local-model discovery + a live capability gate** (P3.2), **debate-terminal depth** (P3.3), **UI/UX +
> a11y** (P3.4), and **historical as-of + a look-ahead correctness fix** (P3.5) — all locked in
> **[docs/phase-3-plan.md](docs/phase-3-plan.md)** with the open-core raw-vs-curated line in
> [0006](docs/decisions/0006-open-core-signal-boundary.md); every subphase went recon → adversarial-validate
> → real-path verify → fresh-context review → self-merge, full CI suite green (ruff + pytest + flutter analyze/test/goldens/build + clean-install smoke).
> (Phase 2 complete, merged to `main` 2026-07-05; Phase 1 vertical slice + de-fork 2026-06-26 — Phase 2
> shipped the Hub + nav, Settings/**Model Studio**, the **Dream Team** roster + gates, brand, and a
> validated Windows installer + Flutter CI gate, per [docs/phase-2-plan.md](docs/phase-2-plan.md) + ADRs
> [0001](docs/decisions/0001-byo-api-key-storage.md)/[0002](docs/decisions/0002-sidecar-bundling.md)/[0004](docs/decisions/0004-per-agent-model-routing.md)/[0005](docs/decisions/0005-installer-format.md).)
> Phase 4 (V1 Release & Hardening, current) is security sweep + a secret-scan gate, release CI, UX-integrity,
> and an unsigned GA; **production code-signing is a V2 fast-follow** ([ADR 0007](docs/decisions/0007-defer-code-signing-to-v2.md));
> mobile remote + paper-trading + a real crypto pipeline + macOS are post-V1/future phases. Product vision +
> the 3 signature bets (Track Record, Dream Team, debate terminal + FRED/Polymarket signals) live in
> **[docs/roadmap.md](docs/roadmap.md)**.
> The engine package stays named `tradingagents` to preserve merge-ability with upstream
> `TauricResearch/TradingAgents`.

## Operating doctrine (Ultracode MO — read first)

The autonomous loop: workflows fan out the heavy research/design/review; **I (Opus 4.8) own the final
adversarial pass, the executive refinement (keep the real findings, reject the false ones), and the
decision to ship.** Every safeguard below is self-administered, and self-administered checks decay into
no-ops — so **prefer artifacts over assertions, and a fresh context over my own for any final
judgment.** When a guardrail feels like ceremony, that feeling is the drift, not a reason to skip it.

**Orchestrate, don't rubber-stamp.**
1. **Match machinery to the change.** Workflows are for genuine research, design, or multi-file risk —
   NOT trivial/single-file/mechanical edits (do those directly). If you can't name what a fan-out would
   find that you couldn't, don't spawn it.
2. **Workflows fan out execution, never the decision.** Before accepting a workflow's converged output,
   restate the one assumption that, if false, makes it worthless, and check it yourself against code —
   not the prose. Confidence ≠ evidence; length ≠ rigor; N agents sharing a prompt = one opinion.
3. **The adversarial pass produces an artifact, not a feeling.** Triage every fan-out finding: KEEP
   (with the file:line/test that proves it real) / REJECT (why it's a false positive) / DEFER→backlog.
   A pass that keeps all or rejects all is presumed not to have happened. Put the triage in the PR.
4. **The pre-merge review runs in FRESH context** — a subagent/workflow given only the diff + exit
   criteria, never the implementation rationale. The implementer's context is the worst judge of its
   own work. (Keystone — this is what breaks the self-grading loop.)

**Verify against falsification.**
5. Map each exit criterion to the evidence that would FALSIFY it, and run that. "Tests pass" ≠ "feature
   correct" — name the test that fails if the feature is broken; write it if it's missing.
6. **A re-baselined golden needs a written visual-diff justification** (what pixels changed + why each
   is intended; Read the PNG). An unexplained `--update-goldens` is a *failed* verification.
7. **Distrust the synthetic path.** Demo is cost-free synthetic; it can't prove key injection, provider
   wiring, frozen-exe spawn, or SSE resume. Verify those on the real (Ollama/Gemini) path and state
   which path each claim was checked on.

**Scope wall — deepen, don't widen.**
8. "Maximize / world-class" = **depth + rigor on in-scope work, not new surface.** Work is in-scope iff
   it's necessary to make a *currently-listed* exit criterion verifiably pass. Four checks before adding
   anything mid-subphase: **exit-criterion** (maps to a checkbox in the plan doc?), **counterfactual**
   (skip it → a criterion fails / a test goes red?), **new-surface** (adds a new capability / endpoint /
   config key / contract field? → out), **reversibility** (required now AND no cheaper later?). Go deep
   inside the box; the wall is the exit-criteria list.
9. **Done is falsifiable.** The adversarial pass runs once; it fixes real defects but does NOT reopen
   scope or re-plan unless a criterion is *actually failing*. "Could be stronger" is a backlog line, not
   a reopen. A subphase is done when every listed criterion verifiably passes.
10. **Harvest the upside the deep work surfaces** (the constructive flip side of the wall). A thorough
    fan-out generates vision-aligned adjacencies beyond the current scope; the maximize-within-scope rule
    discards them *to a tracked destination, never to /dev/null*. Discipline so this strengthens the wall
    instead of dissolving it: **capture ≠ commit** (logging an idea schedules nothing — acting on it still
    pays the full four checks, drained at phase-end); **vision-aligned bar** (it must advance a stated bet
    — Track Record / Dream Team / debate-terminal + FRED·Polymarket signals — or a named future phase,
    else drop it for real; this is what stops backlog-rot); **route by home** — a coherent future-phase
    *feature/capability* → [`docs/roadmap.md`](docs/roadmap.md) or the phase plan, tagged to its phase; a
    smaller homeless *enhancement* → `docs/backlog.md`; both carry a provenance tag (which subphase's
    fan-out surfaced it). Capture is an explicit output of the adversarial-validation step, not a reflex.
11. **Backlog** ([`docs/backlog.md`](docs/backlog.md), append-only, one line): the instant work fails the
    four checks, append a line and move on (capture must be cheaper than doing the work). Drain at
    phase-end, never mid-phase. **Exception:** a `security` / `correctness` / `data-loss` item is
    surfaced to `HUMAN.md` the same session — it does not wait in the backlog.

**Keep the human in the loop (decision surfacing, not approval gating).**
12. Maintain **[`HUMAN.md`](HUMAN.md)** — the co-founder log (Blocked-on-you / Want-your-input /
    Decided-FYI / What-shipped / Archive + a header tracking spend vs the agreed cost boundary). It's a
    **router + queue, never canonical**: a pointer + the human-action delta; ADR-worthy → write the ADR
    and link it. Blockers (§1) and forks (§2) are **pushed in the chat turn** the moment they arise,
    never buried; FYI/shipped are pull-only. Don't start work that depends on an open blocker. When
    unsure FYI-vs-fork, it's a fork. "Reversible" is judged at *phase-end* cost (rip out one commit, or
    ten?) — a contract/schema/token-name decision is a fork even if cheap to change now.
13. **Still surface (never self-approve through):** key rotation, cert/signing, paid spend beyond the
    agreed boundary, **publishing / GA release (tag + distribute)**, genuine product forks,
    contract/security/scope changes. **Merges to `main` are founder-delegated (2026-07-06)** — self-merge
    verified subphase work gated on **full CI green** (a required-status-check on `main` enforces the flutter
    analyze/test/goldens/build job) **+ a fresh-context pre-merge review**; the outward-facing **GA
    publish/tag** stays surfaced.

**Persistence.** This doctrine is the contract; **memory is a backstop — on any conflict, CLAUDE.md
wins and memory is corrected.** Open each substantive subphase by restating the loop in one line + the
tripwires that apply (fan-out? goldens touched? real-path needed? sensitive op ahead? open HUMAN.md
blockers?) — if you can't state them, you haven't reloaded the MO.

## What this project is

A user picks a ticker; a team of LLM agents (analysts → bull/bear researcher debate → trader →
risk team → portfolio manager) debate and produce a **BUY / HOLD / SELL** verdict with drill-down
into each agent's report. Models are **user-selectable across many frontier providers**. The Flutter
desktop app is the premium front-end; the Python engine is the brain, bundled and run as a local
sidecar (provider keys stay on the user's machine; mobile-as-remote reuses the same API post-V1).

It is a **research / educational** tool, **not financial advice**. Keep that posture in the product
(disclaimers, no real-money execution in early versions; paper-trading sandbox is a post-V1 phase).

The repo is **public and Apache-2.0**, built on the open TradingAgents engine (attribution in
[`NOTICE`](NOTICE); the README is Quorum's, not upstream's). The planned business model is
**open-core** — the local client stays open and free; paid value (Track Record sync, hosted runs, the
signal layer) lives server-side behind entitlement. See [`docs/monetization.md`](docs/monetization.md)
and [ADR 0003](docs/decisions/0003-open-source-and-open-core-monetization.md). Price the *tooling*,
never *advice* (regulatory posture).

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
- `apps/desktop/` — Flutter (org dev.quorum), Riverpod 3 (`runControllerProvider`,
  `settingsControllerProvider`, `appSurfaceProvider` nav). A frameless shell (`quorum_shell.dart`)
  switches between the surfaces Phase 2 shipped:
  - **Hub** (`hub_surface.dart`) — launch card, watchlist, run history + filters, click-through to a
    cached review (re-renders a finished run through `TerminalBody`), and the post-run Dream Team
    **cast list**.
  - **Settings / Model Studio** (`settings_surface.dart`) — provider/quick+deep pickers off
    `catalogProvider`, write-only OS-vault API keys, saved **Benches**, and the **Dream Team roster**
    (`dream_team_roster.dart`): a stage-grouped 12-role provider+model picker with the capability gate
    (block non-tool models on the tool-analyst roles) + the pre-launch multi-provider key gate.
  - **Terminal** (`terminal_screen.dart`) — the frameless 3-pane run view (pipeline rail / reasoning
    feed with the bull-vs-bear tug-of-war / verdict rail).
  `SidecarLauncher.resolve()` (`engine/`) spawns the **bundled frozen sidecar** (`<appDir>/sidecar/
  quorum_sidecar.exe`) when packaged, else `.venv\Scripts\python.exe -m services.api` in dev; teardown
  is `/shutdown` → `taskkill /T`, backstopped by the `QUORUM_PARENT_PID` watchdog. `quorum_colors.dart`
  = design tokens; bundled brand fonts Inter + JetBrains Mono under `fonts/`; window chrome via
  `window_manager` (`onWindowClose` owns teardown → `destroy()`). Packaged by `packaging/` (PyInstaller
  freeze + Inno Setup, [ADR 0005](docs/decisions/0005-installer-format.md)); CI gates it on
  windows-latest (`.github/workflows/ci.yml` `flutter` job).
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
- **Secret hygiene**: the **product** BYOK keys live write-only in the OS keychain (injected per-run, never
  on disk); the only `.env` key is a **dev/CI-only** shared Gemini key (gitignored, never committed —
  verified clean of history — and never shipped: not in the PyInstaller spec). Its rotation is **deferred to
  post-V1** (dev-hygiene, not a GA gate); a secret-scan CI gate lands in Phase 4 (P4.1a).

## Working loop (phase cadence)

The autonomous **phase-execution loop** — the *mechanics*; the behavioral contract (orchestration,
verification-as-artifact, the scope wall, fresh-context review, what to surface, HUMAN.md) is the
**Operating doctrine** near the top of this file.

1. **Start of phase** — lock the plan in a small docs PR (roadmap, subphases, **falsifiable** exit
   criteria, decisions/ADRs). Current: [`docs/phase-2-plan.md`](docs/phase-2-plan.md).
2. **Per subphase** — research/design via Workflow → **personally adversarially validate** the plan
   (restate + check its load-bearing assumption against code) → self-approve (no human gate) →
   implement in small reviewable commits → **verify against falsification** (golden render-to-PNG +
   sidecar + headless demo/**real** runs + `ruff`/`pytest` + `flutter test`) → **fresh-context
   pre-merge review** → refine until exit criteria pass → subphase PR self-merged into the integration
   branch. Tick the plan checkboxes; ADR for any consequential decision; log out-of-scope work to
   [`docs/backlog.md`](docs/backlog.md).
3. **End of phase** — completeness-critic pass (incl. a **scope audit**: any shipped capability with no
   exit criterion is unsanctioned creep) → review the `→ main` PR **in slices**, not one mega-diff →
   close-out docs PR.

**Verification is the gate** — never mark a subphase done unverified; report failures faithfully. The
per-phase cadence (merge model, cost boundary, sensitive-op handling) is set once at phase start — see
the plan doc's "Phase cadence" — and the live HITL queue is [`HUMAN.md`](HUMAN.md).

## Git

`origin` = `blokzdev/quorum` (**public, Apache-2.0**), `upstream` = `TauricResearch/TradingAgents`
(pull engine fixes manually). `main` is the product line. Branch for changes; commit/push only when
asked. Note: GitHub treats `origin` as a standalone repo (not a fork), so `gh pr create` needs
`--repo blokzdev/quorum` or it defaults the base to the upstream parent.
