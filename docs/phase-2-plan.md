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

### P2.1 — Shared foundation (plumbing) *(blocks Hub + Studio)* — ✅ DONE

- [x] **P2.1a Navigation shell** — replace `home: TerminalScreen` with a shell hosting Hub /
  Terminal / Settings surfaces.
- [x] **P2.1b `catalogProvider`** — wire the unused `ApiClient.catalog()` to fetch + cache
  `/catalog/providers` in a Riverpod provider.
- [x] **P2.1c `RunConfig` value-object** — refactor `RunController.start()` to thread the full
  `createRun` body (`mode / ticker / provider / deep_model / quick_model / analysts / research_depth
  / api_keys / output_language`), replacing the hardcoded demo params. Design it to extend cleanly to
  a per-agent model map (P2.5).

**Exit:** the app boots into a switchable shell; the catalog is fetched + cached; a run launches from
a `RunConfig` (not hardcoded); demo still streams end-to-end; goldens updated.

### P2.2 — Design system + deferred terminal polish — ✅ DONE

- [x] **P2.2a** Lift `quorum_colors.dart` `QC.*` tokens into a Material 3 `ThemeExtension`
  (`brand.dart`); add `flutter_launcher_icons` + a proper multi-DPI Quorum icon (replace the single
  `.ico`).
- [x] **P2.2b** Deferred backlog polish: card-entrance motion, verdict-rail reveals, elapsed run timer.

**Result:** `QuorumBrand` ThemeExtension reads FROM the `QC` consts (single source) for new surfaces;
the terminal keeps `QC.*` (its painters have no `BuildContext`) so the existing goldens stay
byte-identical. New ascending-bars app icon via `flutter_launcher_icons`. Adopted the adversarial
critiques' two scope cuts: a **single unified finite `_Reveal`** (no per-index stagger) and the
existing fixed-height verdict skeleton (no per-field incremental reveal). The elapsed timer is
golden-deterministic via an injected `elapsedOverride` (the live `Timer` lives in `TerminalSurface`,
never `TerminalBody`). Motion settles to identical pixels, so only `terminal_midrun.png` re-baselined
(shows `02:14`, visually reviewed). 4 commits (C1 ThemeExtension, C2 icon, C3 motion, C4 timer).

### P2.3 — Settings & Model Studio (quick/deep) *(depends on P2.1b/c + P2.2)*

Ships the supported shared `quick_think_llm` + `deep_think_llm` split — the foundation the Dream Team
(P2.5) extends into per-agent assignment.

- [x] **P2.3a Settings shell + secure key vault** — `flutter_secure_storage` per-provider entries,
  `.env` first-launch import, a "Forget all keys" action; keys flow into `RunConfig.api_keys`.
- [x] **P2.3b Model Studio** — provider selector; quick/deep model dropdowns from `catalogProvider`;
  conditional effort knobs (`google_thinking_level` | `openai_reasoning_effort` | `anthropic_effort`,
  shown only for the matching provider); custom-model escape hatch; `backend_url` for multi-endpoint
  providers; saved presets ("Benches").

**Exit:** a user can enter + store keys, pick provider + quick/deep models + effort, save a preset,
and launch a real `pro`/`vibe` run from the desktop (validated against local Ollama
`llama3.2:latest` or the Gemini test key); keys persist across restart; Settings/Studio goldens land.

✅ **Done** (commits C1–C8 on `feat/p2.3-model-studio`). Engine effort wire-path + `RunConfig`
effort fields; `KeyVault` over the OS credential store (write-only key field; `.env`→vault seed;
Forget-all); Model Studio surface (provider/quick/deep/custom, conditional effort + `backend_url`,
Benches) launching via `SettingsController.buildLaunchConfig`; `catalogProvider` recovers on run
error. **Verification:** 40 `flutter test` green incl. a no-API-key-leak widget guard + the Model
Studio golden (read-verified: the key value is never painted); an adversarial multi-agent review
(security dim found no leak) whose confirmed fixes landed; and **headless sidecar real runs on both
providers** — Ollama `llama3.2:latest` completed a real market-analyst report (incl. a tool call);
Google Gemini reached the provider with the key injected via `api_keys`, and the key value was
confirmed **absent from the sidecar log**. (GUI launch + the native build canary remain gated on the
local VS C++/CMake install; the headless runs exercise the same sidecar contract.) Two LOW review
nits — keyboard-operability of custom controls and filled-button WCAG contrast — are tracked as
follow-ups.

### P2.4 — Hub / run history *(depends on P2.1a + net-new persistence)*

- [x] **P2.4a Backend persistence (+ Track Record seed hooks)** — `JobRegistry._persist` writes a
  `run.json` manifest beside the report tree (run_id, status, mode, ticker, trade_date, asset_type,
  timestamps, **model/provider**, verdict {rating/thesis/confidence/structured entry-price ctx}, cost,
  report_path) — written BEFORE the terminal status is exposed; `GET /runs` lists them from disk;
  startup `_load_prior_runs` registers prior runs so they resolve after a restart. The manifest is a
  summary built from explicit fields — **never the raw request, so api_keys are never persisted.**
  **Track Record seed hooks:** verdict/rating + trade_date + the entry/price context + model/provider
  are persisted, **no backfill** needed.
- [x] **P2.4b Domain** — `RunSummary` + `ApiClient.listRuns()` in `quorum_core`, with `Verdict.fromJson`
  / `CostSnapshot.fromJson`. (Re-open/re-run is driven off the `RunSummary` fields, not a reducer
  change — the summary already carries provider/models/ticker.)
- [x] **P2.4c Hub UI (Home)** — Launch surface + Run history list (ticker filter, BUY/HOLD/SELL filter
  chips + pills, demo badge, cost, watch star) with click-through to a **cached run review** that
  reconstructs a done `RunViewState` and re-renders through the existing `TerminalBody` (verdict rail
  + tug-of-war + reports, no re-run) from `/runs/{id}/reports`; + Watchlist (tracked tickers → latest
  verdict + one-tap re-run). Shell active surface moved to `appSurfaceProvider` so the Hub can jump to
  the Terminal. `reports.json` persisted so restored runs are reviewable post-restart.
- [ ] **P2.4d Run Comparison** *(stretch — deferred)* — diff two runs of the same ticker across model
  configs/dates.

**Exit:** finishing a run writes a manifest (incl. the Track Record seed fields); `GET /runs` lists
prior runs; the Hub home lists history + watchlist, opens a cached review without re-running, and
survives a sidecar restart; Hub goldens land.

✅ **Done** (P2.4a–c; D deferred as stretch) on `feat/p2.4-hub`. **Verification:** 53 `flutter test`
(8 Hub widget tests + a read-verified Hub golden) + `pytest 539 passed` + `ruff` clean. An adversarial
multi-agent review (security dim found **no key leak** — the manifest is built from explicit fields,
never the request) caught a HIGH bug — the cached review dropped the bull/bear + risk-debate sections
because `report_sections` whitelisted only top-level keys while the debate lives nested in
`investment_debate_state`/`risk_debate_state`; fixed by decomposing them (+ a restart round-trip test)
so the signature debate re-renders. Other review fixes landed (add-only watchlist, cached-review
re-run CTA + no stale review on launch, launch-disabled-without-provider). The Hub golden shows
launch/watchlist/history with color-coded verdict pills and the demo badge.

### P2.5 — Dream Team: per-agent model assignment *(signature bet; needs engine work)*

The differentiated "AI dream team": assign a different frontier model — from a different provider — to
each of the **12 agent roles** (e.g. Opus on the Portfolio Manager, a fast cheap model on the analysts,
Grok on the Bull). The engine today supports only a shared quick/deep split. Full design + the
adversarially-validated decisions are in **[ADR 0004](decisions/0004-per-agent-model-routing.md)**;
the headline: an **additive per-role client resolver** (unset roles fall back to today's quick/deep,
byte-for-byte), a structured `agent_models` wire map, and a **capability gate** (the load-bearing
correctness piece — a non-tool model on market/news/fundamentals silently produces an empty report).
Framing: **static per-role routing** (cheap workers + strong judge — the canonical, cost-positive
pattern that maps onto the existing quick/deep topology), *not* a latency-adding cascade. P2.5c is
split (roster UI vs capability/key gate) per the scope critic.

- [x] **P2.5a Engine — per-role routing + capability data** *(done — `build_role_llms` + `GraphSetup`
  `role_llms` + `agent_roles.ROLE_TO_NODE` + `supports_tool_calling` + `/catalog` `tool_capable`; 9 unit
  tests incl. additivity + roster-integrity; 548 pytest green; adversarial review of the frozen-package
  change found zero issues)* — `agent_roles.py` (frozen `ROLE_TO_NODE`,
  12 roles); a `_resolve_role_llm` cache in `trading_graph` (key `provider/model/base_url/effort`;
  per-role effort off the role's own provider; shared `callbacks` threaded; **`base_url` falls back to
  the global only when the role shares the global provider**); `GraphSetup` optional `role_llms=None`
  kwarg (keyword-defaulted, byte-compatible with upstream's positional ctor); `supports_tool_calling`
  on `ModelCapabilities` + a **Quorum-side** catalog tool-capable flag (NOT mutating `MODEL_OPTIONS`'s
  tuple / `/catalog` contract) surfaced for the UI gate. **Extend, don't rewrite**; keep `tradingagents`
  upstream-mergeable.
  *Exit:* an empty `agent_models` builds the identical graph (additivity test — quick/deep golden
  byte-identical); a 3-provider map resolves 3 clients honoring per-role provider/model; a
  roster-integrity test asserts every `ROLE_TO_NODE` node is a real `add_node` string (guards the
  `social`/"Sentiment Analyst" rename trap); per-role clients share the run's `callbacks` object.
- [x] **P2.5b Contract + domain + provenance** *(done — `AgentModel` type + `agent_models` on
  RunRequest/RunConfig/RunSummary/SettingsState/Bench; `resolve_agent_models` → `_manifest_dict`
  provenance; `buildLaunchConfig` multi-provider key merge; 3 round-trips + provenance + demo-inert
  tests; 59 flutter + 553 pytest green; adversarial review found zero issues)* — `agent_models` on
  `RunRequest`
  (`dict[str, dict[str, Any]]`), `RunConfig.agentModels` (an `AgentModel` value type) +
  toJson/fromJson/copyWith, `plan_run` → `config["agent_models"]` + the **resolved** map into `params`,
  **`_manifest_dict`** (the real builder, not `_persist`) emits `agent_models`, `RunSummary.agentModels`,
  and `SettingsState`/`Bench` (+ `toBench`/`applyBench`; `withProvider` must **not** clear it).
  `buildLaunchConfig` merges OS-vault keys for **every referenced provider** (∪ the global).
  *Exit:* round-trip tests for **all three** serializations (RunConfig, Bench, SettingsState); a
  multi-provider run injects every referenced key; the manifest records the resolved per-role map; a
  demo run ignores `agent_models` and writes no provenance.
- [x] **P2.5c1 Model Studio — Dream Team roster** *(done — shared `dream_team_roster.dart` mirror +
  collapsible stage-grouped roster + `_ModelAssignmentPicker` (transient half-set edit → never a
  blank-model wire leak) + apply-to-all/per-stage/`setAllAgentModels` + Hub cast list with
  differs-from-default override inference; per-role provider list excludes only `openai_compatible`
  (Ollama kept — baked-in localhost default verified); 2 roster goldens + mirror/controller/widget
  tests; 73 flutter green; fresh-context review returned MERGE, zero blocker/high)* — a stage-grouped
  12-role roster (Analyst desks / Research debate / Trader / Risk team / Portfolio), each with a
  provider+model picker reusing the Model Studio dropdowns; **muted "quick/deep fallback" chips** on
  unassigned roles (vs solid chips on assigned); "apply to all" / per-stage set; Dream Team lineups
  saved as **Benches**; a post-run "cast list" (role → model that ran) on the Hub/verdict.
  *Exit:* the roster renders all 12 with correct fallback chips (golden: all-default + partially-
  assigned); a saved Bench round-trips its roster; "apply to all" sets every role.
- [x] **P2.5c2 Capability + multi-provider key gate** *(done — `ModelOption.toolCapable` contract
  parse + `RoleGate`/`roleGateClass` + `_gateOutcome` (BLOCK iff `toolCapable==false`, never `!=true`,
  so custom/unknown WARNS); `_Dropdown` disabled-item block + `· no tools` tag + `_CapabilityNotice` +
  red/amber `_RoleChip`; `missingKeysProvider` sharing `referencedProviders` with `buildLaunchConfig`,
  `_LaunchCard` gates Run (incl. the async-loading window) + `provider_meta.providerRequiresKeyForLaunch`
  treats openai_compatible key as optional; 2 goldens (hub_needs_keys, dream_team_capability) + block/
  warn/stale + key-gate tests; 86 flutter green; fresh-context review = MERGE, all 8 invariants held)* —
  **block** non-tool-capable models on market/news/fundamentals (reads the catalog tool-capable flag);
  **warn** (don't block) on the four structured roles (PM warning notes degraded rating extraction); a
  consolidated **pre-launch "needs keys for: X, Y"** diff of referenced providers vs the vault.
  *Exit:* assigning a non-tool model to a tool-analyst role is blocked in the UI (tested against the
  catalog flag); a run referencing an uncredentialed provider is gated before `POST /runs` (golden:
  the warning state).

**Exit (phase):** a user assigns distinct models per role and launches a run that honors them
(validated with a hybrid local-Ollama + cloud-judge mix); unset roles fall back to quick/deep; the
engine change is **additive** (quick/deep runs byte-identical); the capability gate blocks a non-tool
model on the 3 tool-analyst roles; multi-provider keys are validated pre-launch; Dream Team goldens land.

**Not in V1 (deferred):** a per-role *effort* UI control (plumbing ships dormant via `spec.effort`;
V1 drives effort from the existing per-provider knobs); exposing `reflector`/`signal_processor`
(internal); auto-escalation / model cascades (static assignment only); per-agent-within-a-role-group
(role granularity is the 12-role roster).

### P2.6 — Installer packaging & Flutter CI *(depends on P2.0; build the distributable)*

- [x] **P2.6a** *(done — `SidecarLauncher.resolve()` spawn path: bundled exe → `.venv` dev fallback,
  6 hermetic tests; full-engine freeze productionized in `packaging/` and proven with a real Ollama
  pro run through the frozen exe; watchdog re-verified against the **real Flutter parent** (built app,
  orphaned sidecar self-exited in 3s). PR #17.)* Bundle the frozen sidecar exe into the desktop package;
  rewrite `desktop_sidecar_endpoint.dart`'s spawn path to launch it (keep the `.venv` fallback for local
  dev). Lead tasks from the P2.0 spike: productionize the **full-engine** freeze and **re-verify the
  parent-PID watchdog fix against a real Flutter parent**.
- [x] **P2.6b** *(done — **Inno Setup** (not MSIX/WiX: our child-process + taskkill/tasklist model would
  fight MSIX's container); per-user install, self-signed cert pipeline. App-local VC++ CRT (dumpbin:
  MSVCP140/VCRUNTIME140/_1; ATL statically linked) so it runs redist-free. Fresh-context review caught a
  HIGH — the freeze bundled no provider LLM packages (lazy imports) so real runs would crash; fixed via
  `collect_all` of the provider stack and re-verified on the real path: installed sidecar ran real
  Ollama + Gemini analyses. Full install→launch→bundled-spawn→watchdog→uninstall validated. `packaging/`.)*
  Installer packaging (MSIX vs Inno/WiX per P2.0); include the C++ ATL build deps required by
  `flutter_secure_storage_windows`. Validate the full install/launch flow with a **debug / self-signed
  cert** — production keystore signing is deferred to **Phase 3**.
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
