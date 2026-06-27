# Quorum — Phase 2 Plan

> **Status:** Phase 2 in progress. This is the locked reference for Phase 2. Each subphase (P2.x)
> gets its own focused planning session against this document; update the checkboxes and the
> decisions log as work lands. For the product vision + the full banded roadmap, see
> [roadmap.md](roadmap.md).

## Why Phase 2

Phase 1 shipped a proven vertical slice: a frameless 3-pane Flutter desktop terminal that spawns the
Python FastAPI sidecar, streams a real 11-agent run over SSE, and renders the pipeline rail /
bull-vs-bear tug-of-war / verdict rail (de-forked from TradingAgents on 2026-06-26).

Phase 2 turns that slice into a usable product. Its tracks:

1. **Hub** — a home surface with multi-run history (+ Track Record seed hooks).
2. **Settings / Model Studio** — provider + quick/deep model picker backed by `model_catalog.py`,
   with bring-your-own (BYO) provider keys.
3. **Dream Team** — per-agent model assignment (a signature bet; see [roadmap.md](roadmap.md)).
4. **Applied brand polish** — formalized design system + deferred motion/skeleton/timer work.
5. **Installer** — a standalone, distributable, **debug-signed** build (production signing → Phase 3).

Because Phase 2 spans desktop UI, the sidecar/engine, and ops/packaging, the roadmap, subphases,
exit criteria, and load-bearing decisions are locked here *before* feature code, so each subphase can
be planned independently against a stable reference.

## What recon established

These facts (verified by code reading) shape the sequencing:

- **Model Studio's backbone already exists.** `GET /catalog/providers` serves the full
  `{provider: {quick|deep: [{label, value}]}}` catalog ([services/api/app.py](../services/api/app.py)).
  `POST /runs` (`RunRequest`) already accepts `provider / deep_model / quick_model / backend_url /
  api_keys / analysts / research_depth / output_language`. `quorum_core`'s `ApiClient.catalog()`
  exists but is **unused** by the desktop. BYO `api_keys` are request-scoped, "never persisted
  server-side", and injected per job into `os.environ` via `JobIsolationContext`.
  → core Model Studio (quick/deep) is mostly UI + wiring, not new backend work.
- **Per-agent model routing needs engine work.** The engine instantiates exactly two LLM clients
  (`quick_think_llm` + `deep_think_llm`) shared across all agents — so the **Dream Team** (a distinct
  model per agent role) is a vertical feature requiring per-role routing in the engine, not just UI.
- **The desktop is single-screen, no router.** `main.dart` wires `home: TerminalScreen`;
  `RunController.start()` hardcodes `{mode: 'demo', ticker: 'NVDA', step_delay: 0.2}`.
- **The Hub is the backend-heavy gap.** Jobs live in-memory in `JobRegistry`; there is **no
  `GET /runs` list endpoint**, no run manifest, and the structured verdict is dropped to disk (only
  the markdown tree is written, under `~/.tradingagents/logs/quorum_runs/{ticker}_{run_id}_{ts}/`).
  Run history is net-new.
- **The installer is greenfield and the top program risk.** `desktop_sidecar_endpoint.dart`
  hardcodes an upward `.venv\Scripts\python.exe` search — a shipped exe has no `.venv`, so the
  sidecar never spawns. There is no PyInstaller / MSIX / signing setup, and CI gates Python
  (ruff + pytest) only — no Flutter job.
- **Brand tokens are mature but inlined** in `quorum_colors.dart` (`QC.*`), not yet a
  `ThemeExtension`; the app ships a single static `.ico` and version `1.0.0+1`.

## Locked decisions

| # | Decision | Choice |
|---|----------|--------|
| 1 | Sequencing | De-risk-first. Gating spike (P2.0) before feature work; P2.6 builds the **debug-signed** installer; **P2.7** closes out Phase 2. Production signing + security sweep + key rotation + GA are **Phase 3 (V1 Release & Hardening)**. |
| 2 | Hub scope | **Home**: Launch + Run history (with cached review) + Watchlist. **Run Comparison** (diff two runs of one ticker across model configs/dates) is the flagship "separate multi-agent view", scoped as a **stretch** (P2.4d). |
| 3 | BYO key storage | `flutter_secure_storage`, one entry per provider, `.env` first-launch import, per-run injection via `RunRequest.api_keys` (sidecar stays stateless). See [ADR 0001](decisions/0001-byo-api-key-storage.md). |
| 4 | Navigation | Lightweight in-app shell (enum / `IndexedStack` + `Navigator`) now; revisit GoRouter only if the post-V1 mobile remote needs deep-linking. |
| 5 | Subphase naming | `P2.x`, one topic per commit — extends the Phase-1 `S0–S4` convention. |
| 6 | Sidecar bundling | **PyInstaller `onedir`**, demo decoupled from the engine via lazy import; verified 11/11 frozen outside repo/.venv. See [ADR 0002](decisions/0002-sidecar-bundling.md). |
| 7 | Model Studio scope | **Quick/deep in P2.3** (the supported shared split); the **Dream Team** per-agent assignment is its own V1 phase **P2.5** (needs engine per-role routing), built to integrate maximally with the UI. |

### Phase cadence & autonomy envelope

Phase 2 runs as an autonomous **Ultracode phase-execution loop** (see the root `CLAUDE.md` "Working
loop"): per subphase — plan → adversarially validate → **self-approve** (no human gate) → implement
in small commits → test/emulate → refine until exit criteria pass. The settings below bound that
autonomy for this phase:

- **Merge model:** each subphase is a small PR into a long-running **`phase-2` integration branch**,
  self-merged after green checks + self-review. **`main` stays untouched** until phase end, when a
  single `phase-2 → main` PR + the close-out docs go up for final review.
- **Validation cost boundary:** validate with **local Ollama `llama3.2:latest`** (free, tool-capable)
  + cost-free **demo** mode wherever possible; use the **shared Gemini test key** (test-only; never
  logged/committed) for the **cloud path** and hybrid local+cloud runs (e.g. quick=Ollama /
  deep=Gemini). No other paid spend without asking.
- **Sensitive ops — prep then pause:** do all automatable prep, then **stop and surface** before any
  irreversible / account-dependent action — merging to `main`, **key rotation**, **cert/keystore
  signing**, external publishing. These are concentrated in **Phase 3** (with the `phase-2 → main`
  merge surfaced at P2.7).

## Roadmap

### P2.0 — Sidecar-bundling spike *(gating; mostly throwaway)* — ✅ DONE

- [x] **P2.0 Sidecar-bundling spike** — PyInstaller-freeze `services.api` into a standalone sidecar
  exe; prove the stdout `{port, token}` handshake + `/healthz` + a cost-free `demo` stream all work
  when launched as a frozen exe *outside* the repo `.venv`.

**Result:** PyInstaller **`onedir`**; the demo path is decoupled from the engine via a lazy import.
The 61 MB demo bundle passed the contract harness **11/11** outside the repo/.venv (428 ms handshake);
the Windows parent-PID watchdog (an orphaned-process bug found in Phase 1) was fixed and verified
(self-exit 2.20 s), and taskkill teardown works. Two real fixes landed (lazy engine import +
watchdog). Spike scaffolding in [`packaging/spike/`](../packaging/spike/). See
[ADR 0002](decisions/0002-sidecar-bundling.md).

> Secret hygiene + the shared Gemini test-key rotation moved to **Phase 3** (V1 Release & Hardening),
> per the phase cadence below — they happen once, at GA, with the security sweep.

### P2.1 — Shared foundation (plumbing) *(blocks Hub + Studio)*

- [ ] **P2.1a Navigation shell** — replace `home: TerminalScreen` with a shell hosting Hub /
  Terminal / Settings surfaces.
- [ ] **P2.1b `catalogProvider`** — wire the unused `ApiClient.catalog()` to fetch + cache
  `/catalog/providers` in a Riverpod provider.
- [ ] **P2.1c `RunConfig` value-object** — refactor `RunController.start()` to thread the full
  `createRun` body (`mode / ticker / provider / deep_model / quick_model / analysts / research_depth
  / api_keys / output_language`), replacing the hardcoded demo params. Design it to extend cleanly to
  a per-agent model map (P2.5).

**Exit:** the app boots into a switchable shell; the catalog is fetched + cached; a run launches from
a `RunConfig` (not hardcoded); demo still streams end-to-end; goldens updated.

### P2.2 — Design system + deferred terminal polish

- [ ] **P2.2a** Lift `quorum_colors.dart` `QC.*` tokens into a Material 3 `ThemeExtension`
  (`brand.dart`); add `flutter_launcher_icons` + a proper multi-DPI Quorum icon (replace the single
  `.ico`).
- [ ] **P2.2b** Deferred backlog polish: staggered card-entrance motion, full verdict-rail skeletons
  (incremental field reveal), elapsed run timer (header).

**Exit:** new code consumes tokens via the `ThemeExtension` (no inline `QC` in new screens); the new
icon shows in window + taskbar; the three polish items land with goldens; reduce-motion is respected;
goldens stay deterministic.

### P2.3 — Settings & Model Studio (quick/deep) *(depends on P2.1b/c + P2.2)*

Ships the supported shared `quick_think_llm` + `deep_think_llm` split — the foundation the Dream Team
(P2.5) extends into per-agent assignment.

- [ ] **P2.3a Settings shell + secure key vault** — `flutter_secure_storage` per-provider entries,
  `.env` first-launch import, a "Forget all keys" action; keys flow into `RunConfig.api_keys`.
- [ ] **P2.3b Model Studio** — provider selector; quick/deep model dropdowns from `catalogProvider`;
  conditional effort knobs (`google_thinking_level` | `openai_reasoning_effort` | `anthropic_effort`,
  shown only for the matching provider); custom-model escape hatch; `backend_url` for multi-endpoint
  providers; saved presets ("Benches").

**Exit:** a user can enter + store keys, pick provider + quick/deep models + effort, save a preset,
and launch a real `pro`/`vibe` run from the desktop (validated against local Ollama
`llama3.2:latest` or the Gemini test key); keys persist across restart; Settings/Studio goldens land.

### P2.4 — Hub / run history *(depends on P2.1a + net-new persistence)*

- [ ] **P2.4a Backend persistence (+ Track Record seed hooks)** — write a `run.json` manifest
  alongside the report tree in `jobs._write_reports` (run_id, ticker, trade_date, created_at, rating,
  thesis, confidence, cost, **model/provider**, report_path, status); add a `GET /runs` list endpoint
  in `app.py`; scan the manifest dir on `JobRegistry` startup so history survives restart.
  **Track Record seed hooks (signature bet, built post-V1):** also persist the fields a future realized
  hit-rate / alpha scorecard needs — the verdict/rating, the trade_date, and the **price/entry context
  at call time** — so Track Record can be computed later with **no backfill**.
- [ ] **P2.4b Domain** — `RunSummary` type + `ApiClient.listRuns()` in `quorum_core`; the reducer
  carries run params / `assetType` so a run can be re-opened / re-run.
- [ ] **P2.4c Hub UI (Home)** — Launch surface + Run history list (filter/sort, BUY/HOLD/SELL pills)
  with click-through to a **cached run review** (re-render verdict rail + reports from `run.json` /
  `/runs/{id}/reports`, no re-run) + Watchlist (tracked tickers → latest verdict + re-run).
- [ ] **P2.4d Run Comparison** *(stretch)* — diff two runs of the same ticker across model
  configs/dates.

**Exit:** finishing a run writes a manifest (incl. the Track Record seed fields); `GET /runs` lists
prior runs; the Hub home lists history + watchlist, opens a cached review without re-running, and
survives a sidecar restart; Hub goldens land.

### P2.5 — Dream Team: per-agent model assignment *(signature bet; needs engine work)*

The differentiated "AI dream team": assign a different frontier model to each agent role — e.g. Opus
on the portfolio manager, a fast cheap model on the analysts, Grok on the bull. The engine today only
supports a shared quick/deep split, so this is a vertical feature, built to integrate maximally into
the UI/UX.

- [ ] **P2.5a Engine — per-role routing** — extend the engine to accept a per-agent-role model map
  (config + `trading_graph` wiring), defaulting to today's quick/deep behavior when unset. **Extend,
  don't rewrite**; keep the `tradingagents` package mergeable with upstream.
- [ ] **P2.5b Contract + domain** — thread the per-role map through the sidecar `RunRequest`,
  `quorum_core` `RunConfig`, and the run metadata (so the Hub/Track Record can record which model
  played which role).
- [ ] **P2.5c Model Studio UI — Dream Team** — extend P2.3's Studio into a per-agent assignment
  surface (the 11-agent roster → a model picker per role), with presets and clear provenance, falling
  back cleanly to the quick/deep preset.

**Exit:** a user can assign distinct models per agent role and launch a run that honors them
(validated with a hybrid Ollama-quick / Gemini-deep mix across roles); unset roles fall back to
quick/deep; Dream Team goldens land; the engine change is additive (quick/deep runs unchanged).

### P2.6 — Installer packaging & Flutter CI *(depends on P2.0; build the distributable)*

- [ ] **P2.6a** Bundle the frozen sidecar exe into the desktop package; rewrite
  `desktop_sidecar_endpoint.dart`'s spawn path to launch it (keep the `.venv` fallback for local dev).
  Lead tasks from the P2.0 spike: productionize the **full-engine** freeze (the spike proved demo;
  the engine freeze is the punch-list) and **re-verify the parent-PID watchdog fix against a real
  Flutter parent**.
- [ ] **P2.6b** Installer packaging (MSIX vs Inno/WiX per P2.0); include the C++ ATL build deps
  required by `flutter_secure_storage_windows`. Validate the full install/launch flow with a
  **debug / self-signed cert** — production keystore signing is deferred to **Phase 3**.
- [ ] **P2.6c** CI — add a Flutter build + `flutter test` (incl. goldens) job and a packaging job to
  [`.github/workflows/ci.yml`](../.github/workflows/ci.yml).

**Exit:** a packaged Quorum installs + launches on a clean machine, spawns the bundled sidecar
(no repo/.venv), and runs demo + a real run; CI gates Flutter + Python.

### P2.7 — Phase 2 close-out *(closing milestone)*

- [ ] **P2.7a Completeness-critic pass** — what's missing / regressed / deferred across P2.0–P2.6
  (modality not covered, claim unverified, golden stale, exit criterion quietly skipped).
- [ ] **P2.7b Close-out** — update `phase-2-plan.md` (tick boxes, record outcomes + new ADRs), then
  open the `phase-2 → main` PR + the Phase 2 close-out docs PR for final review.

**Exit:** Phase 2 is feature-complete (Hub, Model Studio, Dream Team, brand, **debug-signed**
installer), verified against every subphase's exit criteria, and merged to `main`; the close-out docs
summarize what shipped vs deferred. Production signing + hardening + GA continue in **Phase 3**.

## After Phase 2 — the longer roadmap

Phase 2 ships the feature set + a debug-signed, internally-installable build. The product line
continues; the full vision + bands live in [roadmap.md](roadmap.md). In brief:

### Phase 3 — V1 Release & Hardening
The release-engineering phase that turns the feature-complete app into a trusted public V1:

- **Security sweep** — secret hygiene (rotate the shared **Gemini test key**; sweep fixtures/CI for
  hardcoded/shared keys; `.env` gitignored + clean of history); re-verify the `JobIsolationContext`
  env snapshot/restore now that BYO-key runs are common; add a `/healthz` contract-version check.
- **Technical-debt pass** — TODO / dead-code cleanup; candidate: **P0.3b** (converge `cli/main.py`
  onto `runtime.run_streaming`); contract / forward-compat audit.
- **Production code-signing** — swap the P2.6 debug/self-signed cert for the production keystore/cert
  (provisioning + timestamp + signing hook) → a **signed** installer; release/distribution CI. May
  coordinate with the macOS port so both platforms sign together.
- **GA** — the first signed public release.

### Post-V1 (signature bets + platform)
- **Track Record** — the realized hit-rate + alpha scorecard (trust flagship; P2.4 seeds its data).
- **FRED macro + Polymarket signals** — surface the engine's macro + prediction-market data as
  structured signals (needs the engine to emit them as structured events first).
- Backtesting / historical replay · Automation & alerts · Paper-trading sandbox (P10/P11) ·
  Real brokerage execution (compliance-gated, far future) · Advanced AI & extensibility
  (custom agents/prompts, MCP tools) · Mobile-as-remote (LAN/WAN, TLS + auth) · macOS port ·
  Auto-update & distribution maturity.

### Deferred niceties
- Run Comparison (if it slips from P2.4d)
- Cost / usage-insights dashboard
- ⌘K command palette; per-run spend caps
- Optional master-passphrase vault toggle (defense-in-depth on top of the OS keystore — see ADR 0001)

## Risk register

1. **Sidecar bundling** *(top risk)* — gates the installer; mitigated by the P2.0 spike *before*
   committing dates. If PyInstaller can't cleanly freeze the engine's transitive deps
   (LangChain/LangGraph + native libs), the installer milestone slips.
2. **Run-history is net-new** — easy to under-scope; manifest + list endpoint + restart-scan are all
   new code with no Phase-1 foundation.
3. **Dream Team touches the frozen engine** — per-role routing must be **additive** (default to
   quick/deep), or it risks upstream merge-ability and regressions to existing runs.
4. **Catalog staleness / dual source of truth** — Model Studio must call `/catalog/providers` live,
   not cache a snapshot; custom-model IDs validate late (at graph build), so surface failures clearly.
5. **Event-contract drift** — `CONTRACT_VERSION = 1`; unknown events are silently dropped on the Dart
   side. Any addition must be additive + version-guarded; add a `/healthz` contract-version check.
6. **BYO-key threat model** — same-user processes can decrypt OS-stored keys; re-verify
   `JobIsolationContext` env restore once real BYO runs are the common path; require TLS once the API
   leaves loopback (mobile remote). See [ADR 0001](decisions/0001-byo-api-key-storage.md).
7. **CI blind spot for UI** — no Flutter job today; P2.6c closes it but is itself at risk of slipping,
   so UI regressions go uncaught until then.

## Conventions

- **Engine** is the source of truth; extend, don't rewrite. The package name `tradingagents` is
  frozen for upstream merge-ability.
- **Subphases** are `P2.x`, one topic per commit, with explicit exit criteria (above).
- **UI is verified via golden render-to-PNG** (`flutter test --update-goldens`), plus sidecar +
  headless real runs. Live Flutter-GPU windows can't be screen-captured in this environment.
- **Decisions** with lasting consequence get an ADR under [`docs/decisions/`](decisions/).
