# Quorum — Phase 2 Plan

> **Status:** Phase 2 in progress. This is the locked reference for Phase 2. Each subphase (P2.x)
> gets its own focused planning session against this document; update the checkboxes and the
> decisions log as work lands.

## Why Phase 2

Phase 1 shipped a proven vertical slice: a frameless 3-pane Flutter desktop terminal that spawns the
Python FastAPI sidecar, streams a real 11-agent run over SSE, and renders the pipeline rail /
bull-vs-bear tug-of-war / verdict rail (de-forked from TradingAgents on 2026-06-26).

Phase 2 turns that slice into a usable product across four tracks:

1. **Hub** — a home surface with multi-run history.
2. **Settings / Model Studio** — provider + model picker backed by `model_catalog.py`, with
   bring-your-own (BYO) provider keys.
3. **Applied brand polish** — formalized design system + deferred motion/skeleton/timer work.
4. **Signed Windows installer** — a standalone, distributable, signed build.

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
  → Model Studio is mostly UI + wiring, not new backend work.
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
| 1 | Sequencing | De-risk-first. Gating spike (P2.0) before feature work; P2.5 builds the **debug-signed** installer; **P2.6** closes out Phase 2. Production signing + security sweep + key rotation + GA are **Phase 3 (V1 Release & Hardening)**. |
| 2 | Hub scope | **Home**: Launch + Run history (with cached review) + Watchlist. **Run Comparison** (diff two runs of one ticker across model configs/dates) is the flagship "separate multi-agent view", scoped as a **stretch** (P2.4d). |
| 3 | BYO key storage | `flutter_secure_storage`, one entry per provider, `.env` first-launch import, per-run injection via `RunRequest.api_keys` (sidecar stays stateless). See [ADR 0001](decisions/0001-byo-api-key-storage.md). |
| 4 | Navigation | Lightweight in-app shell (enum / `IndexedStack` + `Navigator`) now; revisit GoRouter only if the post-V1 mobile remote needs deep-linking. |
| 5 | Subphase naming | `P2.x`, one topic per commit — extends the Phase-1 `S0–S4` convention. |
| 6 | Sidecar bundling | **Open** — decided by the P2.0 spike, then recorded as ADR 0002. |

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
  merge surfaced at P2.6).

## Roadmap

### P2.0 — Sidecar-bundling spike *(gating; mostly throwaway)*

- [ ] **P2.0 Sidecar-bundling spike** — PyInstaller-freeze `services.api` into a standalone sidecar
  exe; prove the stdout `{port, token}` handshake + `/healthz` + a cost-free `demo` stream all work
  when launched as a frozen exe *outside* the repo `.venv`. Decide one-file vs one-dir vs embedded
  relocatable venv.

**Exit:** a frozen sidecar runs a demo end-to-end with no repo/.venv present; the bundling strategy
is chosen → ADR 0002.

> Secret hygiene + the shared Gemini test-key rotation moved to **Phase 3** (V1 Release & Hardening),
> per the phase cadence below — they happen once, at GA, with the security sweep.

### P2.1 — Shared foundation (plumbing) *(blocks Hub + Studio)*

- [ ] **P2.1a Navigation shell** — replace `home: TerminalScreen` with a shell hosting Hub /
  Terminal / Settings surfaces.
- [ ] **P2.1b `catalogProvider`** — wire the unused `ApiClient.catalog()` to fetch + cache
  `/catalog/providers` in a Riverpod provider.
- [ ] **P2.1c `RunConfig` value-object** — refactor `RunController.start()` to thread the full
  `createRun` body (`mode / ticker / provider / deep_model / quick_model / analysts / research_depth
  / api_keys / output_language`), replacing the hardcoded demo params.

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

### P2.3 — Settings & Model Studio *(depends on P2.1b/c + P2.2)*

- [ ] **P2.3a Settings shell + secure key vault** — `flutter_secure_storage` per-provider entries,
  `.env` first-launch import, a "Forget all keys" action; keys flow into `RunConfig.api_keys`.
- [ ] **P2.3b Model Studio** — provider selector; quick/deep model dropdowns from `catalogProvider`;
  conditional effort knobs (`google_thinking_level` | `openai_reasoning_effort` | `anthropic_effort`,
  shown only for the matching provider); custom-model escape hatch; `backend_url` for multi-endpoint
  providers; saved presets ("Benches").

**Exit:** a user can enter + store keys, pick provider + quick/deep models + effort, save a preset,
and launch a real `pro`/`vibe` run from the desktop (validated against local Ollama
`llama3.2:latest` or a real key); keys persist across restart; Settings/Studio goldens land.

### P2.4 — Hub / run history *(depends on P2.1a + net-new persistence)*

- [ ] **P2.4a Backend persistence** — write a `run.json` manifest (run_id, ticker, trade_date,
  created_at, rating, thesis, confidence, cost, model/provider, report_path, status) in
  `jobs._write_reports` alongside the report tree; add a `GET /runs` list endpoint in `app.py`; scan
  the manifest dir on `JobRegistry` startup so history survives restart.
- [ ] **P2.4b Domain** — `RunSummary` type + `ApiClient.listRuns()` in `quorum_core`; the reducer
  carries run params / `assetType` so a run can be re-opened / re-run.
- [ ] **P2.4c Hub UI (Home)** — Launch surface + Run history list (filter/sort, BUY/HOLD/SELL pills)
  with click-through to a **cached run review** (re-render verdict rail + reports from `run.json` /
  `/runs/{id}/reports`, no re-run) + Watchlist (tracked tickers → latest verdict + re-run).
- [ ] **P2.4d Run Comparison** *(stretch)* — diff two runs of the same ticker across model
  configs/dates.

**Exit:** finishing a run writes a manifest; `GET /runs` lists prior runs; the Hub home lists
history + watchlist, opens a cached review without re-running, and survives a sidecar restart; Hub
goldens land.

### P2.5 — Installer packaging & Flutter CI *(depends on P2.0; build the distributable)*

- [ ] **P2.5a** Bundle the frozen sidecar exe into the desktop package; rewrite
  `desktop_sidecar_endpoint.dart`'s spawn path to launch it (keep the `.venv` fallback for local dev).
- [ ] **P2.5b** Installer packaging (MSIX vs Inno/WiX per P2.0); include the C++ ATL build deps
  required by `flutter_secure_storage_windows`. Validate the full install/launch flow with a
  **debug / self-signed cert** — production keystore signing is deferred to **Phase 3**.
- [ ] **P2.5c** CI — add a Flutter build + `flutter test` (incl. goldens) job and a packaging job to
  [`.github/workflows/ci.yml`](../.github/workflows/ci.yml).

**Exit:** a packaged Quorum installs + launches on a clean machine, spawns the bundled sidecar
(no repo/.venv), and runs demo + a real run; CI gates Flutter + Python.

### P2.6 — Phase 2 close-out *(closing milestone)*

- [ ] **P2.6a Completeness-critic pass** — what's missing / regressed / deferred across P2.0–P2.5
  (modality not covered, claim unverified, golden stale, exit criterion quietly skipped).
- [ ] **P2.6b Close-out** — update `phase-2-plan.md` (tick boxes, record outcomes + new ADRs), then
  open the `phase-2 → main` PR + the Phase 2 close-out docs PR for final review.

**Exit:** Phase 2 is feature-complete (Hub, Model Studio, brand, **debug-signed** installer), verified
against every subphase's exit criteria, and merged to `main`; the close-out docs summarize what
shipped vs deferred. Production signing + hardening + GA continue in **Phase 3**.

## After Phase 2 — the longer roadmap

Phase 2 ships the feature set + a debug-signed, internally-installable build. The product line
continues; each phase below gets its own start-of-phase plan + docs when it begins.

### Phase 3 — V1 Release & Hardening
The release-engineering phase that turns the feature-complete app into a trusted public V1:

- **Security sweep** — secret hygiene (rotate the shared **Gemini test key**; sweep fixtures/CI for
  hardcoded/shared keys; `.env` gitignored + clean of history); re-verify the `JobIsolationContext`
  env snapshot/restore now that BYO-key runs are common; add a `/healthz` contract-version check.
- **Technical-debt pass** — TODO / dead-code cleanup; candidate: **P0.3b** (converge `cli/main.py`
  onto `runtime.run_streaming`); contract / forward-compat audit.
- **Production code-signing** — swap the P2.5 debug/self-signed cert for the production keystore/cert
  (provisioning + timestamp + signing hook) → a **signed** installer; release/distribution CI. May
  coordinate with the macOS port so both platforms sign together.
- **GA** — the first signed public release.

### Post-V1
- Mobile-as-remote (LAN/WAN over the same API, with TLS + auth)
- Paper-trading sandbox (P10/P11)
- macOS port (may pull forward into Phase 3 for a multi-platform signed launch)

### Deferred niceties
- Run Comparison (if it slips from P2.4d)
- Cost / usage-insights dashboard
- Optional master-passphrase vault toggle (defense-in-depth on top of the OS keystore — see ADR 0001)

## Risk register

1. **Sidecar bundling** *(top risk)* — gates the installer; mitigated by the P2.0a spike *before*
   committing dates. If PyInstaller can't cleanly freeze the engine's transitive deps
   (LangChain/LangGraph + native libs), the installer milestone slips.
2. **Run-history is net-new** — easy to under-scope; manifest + list endpoint + restart-scan are all
   new code with no Phase-1 foundation.
3. **Catalog staleness / dual source of truth** — Model Studio must call `/catalog/providers` live,
   not cache a snapshot; custom-model IDs validate late (at graph build), so surface failures clearly.
4. **Event-contract drift** — `CONTRACT_VERSION = 1`; unknown events are silently dropped on the Dart
   side. Any addition must be additive + version-guarded; add a `/healthz` contract-version check.
5. **BYO-key threat model** — same-user processes can decrypt OS-stored keys; re-verify
   `JobIsolationContext` env restore once real BYO runs are the common path; require TLS once the API
   leaves loopback (mobile remote). See [ADR 0001](decisions/0001-byo-api-key-storage.md).
6. **CI blind spot for UI** — no Flutter job today; P2.5c closes it but is itself at risk of slipping,
   so UI regressions go uncaught until then.

## Conventions

- **Engine** is the source of truth; extend, don't rewrite. The package name `tradingagents` is
  frozen for upstream merge-ability.
- **Subphases** are `P2.x`, one topic per commit, with explicit exit criteria (above).
- **UI is verified via golden render-to-PNG** (`flutter test --update-goldens`), plus sidecar +
  headless real runs. Live Flutter-GPU windows can't be screen-captured in this environment.
- **Decisions** with lasting consequence get an ADR under [`docs/decisions/`](decisions/).
