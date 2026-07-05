# Phase 3 — Depth & Refinement

> Status: **planned** (plan-lock 2026-07-05; Phase 2 shipped to `main` 2026-07-05). Phase 2 delivered the
> *shell* — Hub, Model Studio, Dream Team, installer, CI. Phase 3 surfaces the **untapped power of the
> TradingAgents engine** and deepens the product toward a shippable V1, **before** the V1 Release &
> Hardening phase (now **Phase 4**). Recon-grounded (a 4-theme engine-surface fan-out); each subphase is
> tightly boxed with **falsifiable exit criteria** — a "refinements" phase is the classic scope-creep
> sink, so the scope wall ([CLAUDE.md](../CLAUDE.md) → Operating doctrine) applies at full strength.

## Framing & the open-core line

Phase 2 shipped a shell over a rich engine the app barely exposes: `RunConfig` already carries `assetType`
and `tradeDate` with **no UI**; the engine has data vendors (yfinance / Alpha Vantage / FRED / Polymarket /
StockTwits / Reddit) selectable per category but the app runs **yfinance defaults**; the capability gate
ships **dormant** (`_NON_TOOL_MODELS` is empty); the debate renders as two accumulated blobs rather than a
turn-by-turn debate. Phase 3 closes those gaps.

**Open-core boundary ([ADR 0006](decisions/0006-open-core-signal-boundary.md), locked with the founder):**
raw data vendors computed **locally with the user's own key** are **free** (same model as the existing LLM
BYO keys); the **hosted / curated / synced signal intelligence** (the paid signal-layer moat) is **not
designed in Phase 3** — it stays Phase-4+/server-side. So P3.1 may surface FRED/Polymarket as BYO-key raw
sources without cannibalizing revenue.

## Phase cadence (set once)

- **Merge model:** subphase PRs self-merged into a `phase-3` integration branch; `main` untouched until the
  phase-end `phase-3 → main` merge (**founder-approved**, never self-approved).
- **Cost boundary:** unchanged from Phase 2 — **Ollama + demo + the shared Gemini test key** — **plus
  free-tier data-vendor keys** (FRED free key, Alpha Vantage free key, Polymarket keyless). **No paid spend
  without asking.** Real spend (production signing, release infra) stays **Phase 4**.
- **Sensitive ops:** surface per the doctrine (merges to `main`, key rotation, paid spend, contract/scope
  changes). The engine package name `tradingagents` stays frozen for upstream merge-ability — all engine
  changes additive.

## Subphases

Recommended order de-risks and minimises golden re-baseline churn: **P3.1 + P3.5** are the run-config pair
(do them adjacent) → **P3.2** (settings-area) → **P3.3** (terminal-area) → **P3.4** last (its
contrast/focus changes re-baseline terminal/hub goldens P3.3 also touches).

### P3.1 — Data sources (BYO-key vendors + asset type)

Surface the engine's existing per-category **data-vendor selection** + an explicit **asset-type toggle**,
with **zero new engine capability** (`dataflows/interface.py:route_to_vendor` already routes a vendor chain;
`isolation.py:_VENDOR_API_KEY_ENV` already injects FRED/Alpha-Vantage keys per job).

- [x] **P3.1a Contract seam** — add a `data_vendors` field (per-category `dict[str,str]`) to `RunRequest`
  + thread it through `plan_run` into `config["data_vendors"]` (partial-merge via `dataflows/config.py`);
  mirror `dataVendors` on Dart `RunConfig` (toJson/fromJson/copyWith). A new **`GET /catalog/vendors`**
  serves the category→vendors map + per-vendor key requirement (derived from the engine, so the UI can't
  drift). Additive; does not touch the frozen `model_catalog` tuple.
- [x] **P3.1b Vendor + asset-type UI + keystore** — a per-category vendor picker in Model Studio (driven by
  `/catalog/vendors`); **FRED + Alpha Vantage BYO-key** entry reusing the P2.5c keystore/import flow (keys
  sent in `RunConfig.apiKeys`, injected per-run, **never persisted server-side**); a stock/crypto toggle
  binding `RunConfig.assetType`.
  *Exit:* a run with a **non-default vendor** demonstrably routes to it (sidecar test on the threaded
  `data_vendors`; a FRED-backed macro run works with a user key that never lands in a log or on disk); the
  vendor keystore round-trips like the LLM keys; the asset-type toggle sets `assetType` and the run's
  prompts reflect it. **Honest scope:** `assetType` today only *relabels agent prompts* — it does **not**
  route crypto-specific data or tools (a crypto run still hits yfinance). The toggle is labelled honestly;
  a **real crypto pipeline is a dedicated future phase** (see roadmap), explicitly **out of P3**.

  > ✅ **P3.1 complete** (2026-07-05, self-merged to `phase-3`). All 5 exit criteria verified by a
  > fresh-context pre-merge review (mergeable, no HIGH/MED). Routing + partial-merge (no `DEFAULT_CONFIG`
  > mutation), key-never-on-disk (full-run byte scan), write-only keystore (golden), asset-type honesty
  > (crypto doesn't reroute; prompt framing does change), and the engine-derived `/catalog/vendors` all
  > have falsification tests. **Real-path** (doctrine #7): the *spawned* sidecar serves the live 6-category
  > catalog (bearer-enforced), and a live yfinance BTC-USD pull returned real OHLCV through the default
  > vendor. 3 LOW review findings triaged (1 fixed, 2 → `docs/backlog.md` catalog-driven-gate).

### P3.2 — Local & edge model UX

Make the Ollama picker list the **device's real installed models** with per-model tool-capability, and
**wake the dormant capability gate** — the direct answer to "does the app support recent local/edge models"
(Gemma / Qwen / GLM / …): yes, any Ollama-served model, now surfaced rather than hand-typed.

- [x] **P3.2a Discovery endpoint** — a sidecar **`GET /catalog/local-models`** proxying the resolved
  `OLLAMA_BASE_URL`'s `/api/tags`, returning `[{name, tool_capable: 'tools' in capabilities, size, family}]`
  (keeps discovery server-side behind the bearer boundary; adds `httpx` to the sidecar). Degrades cleanly
  when Ollama is unreachable.
- [x] **P3.2b Discovered-model picker + live gate** — fold discovered models (with real `toolCapable`) into
  the Ollama option list so a discovered **non-tool** model renders as a **disabled "no tools"** item on the
  market/news/fundamentals roles and a tool-capable one is directly pickable; add the **launch-time backstop**
  (the run-create path gates the *effective* tool-role model — incl. the global quick model on unassigned
  tool roles — not only the picker).
  *Exit (falsifiable):* the picker lists this device's actual installed models (sidecar test + widget test,
  not the static 3 ids); a discovered non-tool model is un-pickable on tool-analyst roles while a tool-capable
  one is pickable; the launch backstop refuses a config whose effective market model is known-non-tool; a
  **real hybrid/local run** on the engine returns **non-empty** market/news/fundamentals reports (tool calls
  actually fired — real-path, per doctrine tripwire 7); Ollama-down falls back to the static list without
  hanging. *De-risk first:* confirm a `tools`-capable Ollama model (`llama3.2:latest`) actually fires
  `tool_calls` end-to-end before committing block-vs-warn (largely proven this session).

  > ✅ **P3.2 complete** (2026-07-05, self-merged to `phase-3`). Fresh-context review: **mergeable**, all
  > 5 exit criteria MET. A recon win: Ollama `/api/tags` carries `capabilities` inline (verified on the
  > real device, 0.30.11) → single round-trip, and `httpx` was already a dep → zero bundle cost. Discovery
  > + gate + backstop verified on the **real device**: the spawned sidecar discovered all 3 installed
  > models with correct tool-capability, and a **live `llama3.2:latest` market-analyst run fired
  > `tool_calls`** (a 2460-char report with real snapshot OHLCV) — de-risking block-vs-warn. The picker
  > gate + launch backstop share one `toolCapabilityOf` (quorum_core) so they can't drift; a missing
  > `capabilities` field (older Ollama) → null → WARN, never false-block. Golden `hub_capability_gate`
  > (Run disabled + roles named) Read + verified. 3 LOW findings triaged (1 already fixed, 1 documented,
  > 1 → backlog).

### P3.3 — Debate-terminal depth *(signature bet #2)*

Make the debate **read as a debate**. No new vendor/endpoint/hosted signal — pure runtime-event + UI depth.

- [x] **P3.3a Turn-structured debate events** — decompose `investment_debate_state` (`history`/`count`) into
  **per-turn** bull/bear events so the tug-of-war renders an alternating turn thread that grows with
  `research_depth`, and drive the balance **lean from the structured `ResearchPlan.recommendation`** (a real
  5-tier rating) instead of prose keyword-matching. Resolve the dead `agent_done.confidence` seam (emit a
  real value **or** remove the field — no dead seam ships).
- [x] **P3.3b Risk-debate parity + structured chips** — surface the 3-way aggressive/conservative/neutral
  **risk debate** with its own synthesis visual + a **risk-judge ribbon** (its own section, not silently
  folded into `final_trade_decision`); show already-on-the-wire structured signals (sentiment band/score/
  confidence chip, trader action/entry/stop chips) on their section cards.
  *Exit (golden-tested):* a depth-2 fixture (4 bull/bear turns) renders **≥4 distinct turn blocks** in
  speaking order (a depth-1 vs depth-2 fixture pair proves the decomposition is real, not a re-blob); the
  risk debate renders a 3-way synthesis + a risk-judge ribbon whose text == the risk judge (not the PM
  decision); two fixtures differing **only** in structured `recommendation` (Buy vs Sell) **flip** the
  balance bar; a runner unit test asserts per-turn event count scales with `max_debate_rounds`. Re-baselined
  terminal goldens carry a written visual-diff justification. *De-risk first:* verify per-turn boundaries are
  cleanly recoverable from `history` on a real depth-2 run (else snapshot-diff `bull_history`/`bear_history`
  per chunk) — the one thing that could make P3.3a a rabbit hole.

  > ✅ **P3.3 complete** (2026-07-05, self-merged to `phase-3`). Fresh-context review: all 5 exit criteria
  > MET, no HIGH/MED-blocking. The rabbit-hole de-risk resolved cleanly — turns recover from `history` via
  > the `"Bull/Bear Analyst:"` line-anchored delimiter, confirmed on a **real Gemini depth-2 debate** (exactly
  > 4 ordered turns, no stray delimiter in any body). The balance bar is driven by the structured 5-tier
  > `recommendation` (already on the wire in the `investment_plan` section) — no runtime change; ditto the
  > P3.3b chips (sentiment/trader structured, already on the wire). Golden pair (depth-1 vs depth-2) proves
  > the decomposition is real; the dead `agent_done.confidence` seam is gone. Honest scope: the risk judge IS
  > the PM decision in this engine, so the RISK VERDICT ribbon presents that as the risk-debate conclusion
  > (no separate risk-manager node — a future engine change). 2 review findings → backlog (demo showcase,
  > cached-review structured fidelity).

### P3.4 — UI/UX + a11y *(tight, client-only)*

Zero new surface — all golden / widget / Semantics-testable.

- [ ] **P3.4a Keyboard operability** — wrap the custom `GestureDetector` controls (nav tabs, caption
  buttons, depth toggles, analyst chips, Set-stage, Dream Team / role-row disclosures) in
  `FocusableActionDetector` so each is Tab-focusable with a visible focus ring and activates on Enter/Space
  (keep the existing `Semantics` labels). The focus ring must paint **only on focus** so the 8 existing
  goldens stay byte-stable.
- [ ] **P3.4b Contrast + error surface** — add an **`onAccent`** brand token so the "Run analysis" FilledButton
  label reaches **≥4.5:1** (fixes the 3.77:1 AA-normal failure); **read `RunViewState.error`** in the
  terminal (today it's dropped) → render the failure reason + a Retry CTA on `RunPhase.error`, distinct from
  the empty state.
  *Exit:* widget tests prove every custom control is Tab-reachable and fires on Enter+Space; a pure-Dart
  contrast-math test asserts the Run-button label ≥4.5:1 (fails today at 3.77:1); a new `terminal_error.png`
  golden shows the failure reason + Retry; the Run-button goldens are re-baselined with a written visual-diff
  note (only the fill/label pixels changed).

### P3.5 — Historical as-of analysis

The date picker **and** its correctness fix — split from P3.1 because it carries a real look-ahead concern
and seeds the future backtesting phase.

- [x] **P3.5a As-of date picker** — a `tradeDate` picker in the launch surface (binds the existing
  `RunConfig.tradeDate`; no contract change) + a clear **"as-of DATE"** indicator in the terminal/verdict
  so a historical run is never mistaken for a live one.
- [x] **P3.5b Look-ahead clamp** *(correctness)* — the deterministic data path already clamps to the as-of
  date, but the raw OHLCV **tool** (`get_YFin_data_online` / `get_stock_data`) does **not** clamp `end_date`
  to `trade_date`, so a past-date run can leak future rows into the model's tool calls. Clamp it.
  *Exit:* a past-date run's raw OHLCV tool cannot return rows after `trade_date` (a test feeds a past
  `trade_date` and asserts no future rows in the tool result); the terminal shows the as-of indicator; the
  **Polymarket** live-source caveat (it always reflects `now`) is surfaced as a note when a past date is set.
  *(Full backtest/replay — scrubbing a timeline, performance attribution — remains a future phase.)*

  > ✅ **P3.5 complete** (2026-07-05, self-merged to `phase-3`). Fresh-context review: **ship**, all 5 exit
  > criteria MET (it even falsified the clamp test — neutering the helper turned it red). Clamp is
  > engine-side via the config `as_of_date` channel (LLM-independent), vendor-agnostic (yfinance + Alpha
  > Vantage), verified end-to-end through the real `plan_run → JobIsolationContext → get_stock_data` path
  > (a live yfinance BTC-USD/AAPL pull returned zero rows after the as-of). The review surfaced a **sibling
  > look-ahead leak in `get_news`** (same `(start_date, end_date)` class) — closed in-session via a shared
  > `as_of_guard` (the only sibling; all other date-bounded tools take `curr_date` and are as-of-aware).
  > The terminal "as-of" indicator is deterministic (no `DateTime.now()` at render); `tradeDate` is a
  > deliberately-unpersisted per-run input.

**Exit (phase):** a user can (1) select data vendors + asset type and run against them with BYO vendor keys
that never persist; (2) pick a **discovered** local Ollama model with the capability gate **live** (non-tool
models blocked on analyst roles); (3) read a **turn-structured** debate + a distinct **risk** synthesis with
structured confidence chips; (4) operate the app **by keyboard** at **AA contrast** and see live-run errors;
(5) run an **as-of historical** analysis with the look-ahead leak closed — all golden/unit/real-path
verified; the free client surfaces **BYO-key raw** vendors while the **hosted signal layer stays reserved**
([ADR 0006](decisions/0006-open-core-signal-boundary.md)); CI stays green (Python + Flutter).

## Not in Phase 3 (deferred — captured, not dropped)

- **Real crypto pipeline** (crypto-specific data vendors/tools/routing — not just a prompt relabel) → a
  **dedicated future phase** in [roadmap.md](roadmap.md). P3.1's toggle is the honest thin version only.
- **Full backtesting / replay** (timeline scrub, performance attribution) → future phase; P3.5 ships only
  as-of-date analysis + the correctness clamp.
- First-run onboarding + the Hub key-gate "Set in Settings" deep-link (new surface); debate replay/scrub +
  interactive transcript drill-down; in-app `ollama pull`; LM Studio/vLLM discovery; per-role effort/base-URL
  UI; a light/high-contrast theme; a keyboard-shortcut layer; a live-AT (NVDA) audit. All → `backlog.md` /
  roadmap, tagged to their P3 fan-out.
