# HUMAN.md — Co-founder log (ganesh ⇄ Opus 4.8)

> The async standup between the human founder (ganesh) and the AI co-founder/PM (Opus 4.8). Opus
> writes; ganesh reads top-down and acts on §1/§2. This file is a **router + queue, never a source of
> truth** — anything durable lives in an ADR, the plan doc, or `CHANGELOG.md`; here we keep a one-line
> pointer + the human-action delta. If an entry needs more than ~3 lines, it belongs in an ADR and this
> links it. **§1 (blockers) and §2 (forks) are also surfaced in the chat turn** the moment they arise;
> §3/§4/§5 are pull-only. Rules: see CLAUDE.md → *Operating doctrine*.

**Last AI update:** 2026-07-05 (**Phase 3 implementation COMPLETE** — P3.1–P3.5 all on `phase-3`; `phase-3 → main` is a fork for you; §1/§4)
**Spend this phase (Phase 3):** boundary = **Ollama + demo + the shared Gemini test key** **+ free-tier
data-vendor keys** (FRED / Alpha Vantage free tiers, Polymarket keyless) — **no paid spend without asking**.
Real spend (production signing, release infra) stays **Phase 4**. (Phase-2 spend was ~cents on the Gemini
test key only.)

---

## 1 · ⛔ Blocked on you — *only-human steps; these gate progress*

- **`phase-3 → main` merge — your call.** The **entire Phase 3 implementation is done** on the `phase-3`
  integration branch: P3.1 (BYO-key vendors + asset toggle), P3.2 (local-model discovery + capability
  gate), P3.3 (debate-terminal depth), P3.4 (UX/a11y), P3.5 (as-of + look-ahead fix). Every subphase:
  parallel recon → my adversarial validation → real-path verification → **fresh-context review** (each
  returned mergeable) → self-merged to `phase-3`. Cost stayed within boundary (Ollama + the shared Gemini
  test key only — a couple of depth-2/real-path runs). **Merges to `main` are founder-gated** (doctrine):
  the `phase-3 → main` PR is yours to review (recommend in slices, not one mega-diff) + approve. Backlog is
  drained (vendor-provenance → roadmap P7). End-of-phase audit passed (completeness verified, zero scope
  creep, CI green: 385 pytest + 146 flutter + ruff). **The `phase-3 → main` PR is open for you:
  [#29](https://github.com/blokzdev/quorum/pull/29)** — review it in slices (the 6 sub-PRs #22–#28,
  linked in the PR body), then approve + merge. I have NOT merged it (founder-gated).

## 2 · 🔱 Want your input — *genuine forks; I have a recommendation*

- _(none open)_

## 3 · ✅ Decisions I made — *FYI; self-approved consequential calls. Newest first; ADR-linked.*

- 2026-07-05 — **Edge Model Draft Board → roadmap (post-V1), on your ask** ("browse/find applicable edge
  models"). A research pass (code recon + a **live Ollama 0.30.11 probe**) killed the literal "HuggingFace
  browser / live catalog" framing — Ollama exposes no machine-readable library or *pre-install*
  tool-capability API, and generic device-filtered browse is LM Studio/Jan/Msty table-stakes — and reshaped
  it into a **curated, tool-capable, device-fit draft board** with the on-brand **roster-fit** differentiator
  ("can this machine run my *whole* Dream Team?") + a Track-Record-ranked defensibility north star. Scoped in
  [roadmap.md](docs/roadmap.md) Band C with a hard "**not** a generic browser" wall; **not Phase 4** (that's
  hardening/GA). Docs-only capture (capture ≠ commit); building it still pays the full four-check wall.
- 2026-07-05 — **Phase 3 (Depth & Refinement) plan-locked** (your themes + calls): 5 boxed subphases —
  P3.1 BYO-key vendors + asset-type, P3.2 local-model discovery + live capability gate, P3.3 debate depth,
  P3.4 UI/UX + a11y, **P3.5 historical as-of** (split out per your call — it carries a correctness fix).
  Open-core line locked → [ADR 0006](docs/decisions/0006-open-core-signal-boundary.md) (BYO-key raw = free,
  hosted-curated = paid). **Real crypto pipeline** → a dedicated future phase (roadmap), NOT P3 — today
  `asset_type` only relabels prompts. **Correctness item (noted, scheduled P3.5b):** the raw OHLCV *tool*
  (`get_YFin_data_online`) doesn't clamp `end_date` to `trade_date`, so a past-date run could leak future
  rows into the model's tool calls (the deterministic snapshot path is already honest). No live impact yet
  (no date picker ships until P3.5); the clamp is a P3.5b exit criterion.
- 2026-07-05 — **Phase 2 SHIPPED (merged to `main`, you approved).** P2.6c added a windows-latest Flutter
  CI gate — verified green on the real runner, and it caught a real bug on its first run (`runner.exe.manifest`
  was untracked via a stray `*.manifest` ignore, which would break any clean clone). P2.7 close-out: the
  completeness-critic returned *ready-after-small-fixes* (no code regression / security / data-loss); the
  must-fixes were doc-refresh + substantiating the P2.5 "hybrid mix" exit, which I did with a **real
  Ollama-analysts + Gemini-judges run** (manifest cast list confirmed the mix; Gemini judge returned an
  Overweight verdict). Full CLAUDE.md/plan/roadmap refresh landed with the merge.
- 2026-07-04 — **P2.6b installer shipped** — **Inno Setup** (your pick; MSIX would fight our child-process
  + taskkill model). Self-contained per-user installer (app-local VC++ CRT, no admin, no redist),
  self-signed cert pipeline (production signing stays Phase 3). **Honest note:** the fresh-context review
  caught a HIGH my *own* verification missed — the freeze bundled no provider LLM packages (they're lazily
  imported), so real runs would have crashed; my earlier "real run PASS" was a false positive (accepted an
  empty run). Fixed (collect_all the provider stack) and re-verified rigorously on report *content*: the
  installed sidecar now runs real Ollama **and** Gemini analyses. This is the fresh-context-review keystone
  working exactly as designed. → [ADR 0005](docs/decisions/0005-installer-format.md).
- 2026-07-04 — **P2.6a spine de-risked on the REAL app** (you installed the toolchain). Proven end-to-end,
  not headless: (1) `flutter build windows --debug` → `quorum.exe`, exit 0; (2) the full-engine
  **PyInstaller freeze** builds (125 MB) and a **real pro run** ran through the *frozen* sidecar against
  Ollama — langgraph + the pandas/numpy/yfinance dataflows imported and produced a verdict (demo never
  touches those, so this is the true transitive-deps proof); (3) rewrote the spawn path to launch the
  bundled exe (`.venv` dev fallback) + **re-verified the `QUORUM_PARENT_PID` watchdog against the real
  Flutter parent** — killed the app without `/T`, the orphaned sidecar self-exited in 3s. The plan's #1
  freeze risk is cleared. Spawn-path change on branch `feat/p2.6a-sidecar-spawn-path` (PR pending review).
  complete**. The design fan-out wanted to exclude *both* openai_compatible and ollama from per-role
  pickers AND its synthesis agent crashed on schema validation — I recovered the 3 analyst outputs from
  the transcripts and synthesized the plan myself (the loop's "I own the synthesis" in action). Key
  call locked in code: the capability BLOCK fires iff `tool_capable == false` (never `!= true`), so a
  custom/local model warns-not-blocks — anything stricter would kill the local-analyst lineup.
- 2026-06-27 — **P2.5c1 Dream Team roster** shipped (PR #13 → `phase-2`). One adversarial-pass catch worth
  knowing: the design fan-out wanted to exclude **Ollama** from per-role pickers; I verified against the
  engine that per-role Ollama works (baked-in localhost default) and **kept it** — excluding it would
  kill the "cheap local analyst + cloud judge" lineup. Only `openai_compatible` is excluded per role
  (genuinely needs a base-URL c1 has no field for → a per-role base-URL field is harvested to backlog).
- 2026-06-27 — Added **upside-harvesting** to the doctrine (your prompt): the design/validation fan-out
  must *capture* vision-aligned over-scope ideas, not discard them — routed by home (future-phase feature
  → `roadmap.md` band; homeless enhancement → `backlog.md`), gated by capture≠commit + a vision-aligned
  bar so it strengthens the scope wall rather than dissolving it. CLAUDE.md rule 10 + backlog header.
- 2026-06-27 — Locked the **Ultracode operating doctrine** into CLAUDE.md + this file (after an
  adversarial self-pressure-test): fresh-context pre-merge review, artifacts-over-assertions triage,
  the four-check scope wall, the spend/HITL queue. Trimmed the panel's optional CI staleness check
  → `docs/backlog.md` (judged net-new automation, out of scope).
- 2026-06-27 — **Dream Team per-role routing** design: structured `agent_models` map, additive engine
  resolver, capability gate as a Quorum-side catalog `tool_capable` flag → [ADR 0004](docs/decisions/0004-per-agent-model-routing.md).
- 2026-06-27 — Went **public + Apache-2.0 + open-core** (your call); README rewritten Quorum-first,
  NOTICE added → [ADR 0003](docs/decisions/0003-open-source-and-open-core-monetization.md). This
  resolved the GitHub-Actions billing block (public repos get free CI).
- 2026-06-27 — Re-baselined the terminal goldens once to load **MaterialIcons** in the test harness
  (icons were rendering as tofu); icon-only change, read-verified. Folded the sidecar `api` deps into
  the `dev` extra so CI actually tests the sidecar.

## 4 · 📦 What shipped — *per-session digest; skim, not a changelog (CHANGELOG.md is canonical)*

### 2026-07-05 — **P3.4 UI/UX + a11y** (merged to `phase-3`) — *Phase 3 implementation COMPLETE*
- **Keyboard operability**: every custom control (nav tabs, depth toggles, analyst chips, disclosures,
  buttons…) is now Tab-focusable + activates on Enter/Space, via a reusable `Focusable` wrapper whose
  focus ring paints only on focus — so **not a single golden changed** from the wrapping.
- **Contrast (WCAG AA)**: the "Run analysis" (and every filled-accent) button label was white-on-blue at
  3.77:1 (an AA-normal fail); a new `onAccent` ink lifts it to 4.97:1 — proved by a pure-Dart contrast test.
- **Error surfacing**: a failed run now shows its reason + a **Retry** button in the terminal (it used to
  silently revert to the idle prompt).
- Fresh-context review: all criteria met; it caught that the hand-rolled filled buttons still failed
  contrast — fixed. 146 flutter tests + contrast math green.

### 2026-07-05 — **P3.3 Debate-terminal depth** (merged to `phase-3`) — *signature bet #2*
- The debate now **reads as a debate**: an alternating **Bull R1 → Bear R1 → Bull R2 → …** turn thread
  that grows with research depth (instead of two static blobs), a balance bar driven by the Research
  Manager's real 5-tier rating (not prose keyword-guessing), and **structured signal chips** on the cards
  (sentiment Bullish/7.4/High-confidence; trader Buy/Entry/Stop). The risk debate gets its own RISK VERDICT
  ribbon.
- **Zero new backend** — the structured signals were already on the wire; P3.3 is a runtime-event +
  reducer + UI job. One genuine runtime addition (per-turn events); the dead `agent_done.confidence` seam
  removed.
- The one rabbit-hole risk (are per-turn boundaries recoverable?) was de-risked cleanly + confirmed on a
  **real Gemini depth-2 debate** (4 clean turns, no false splits). Fresh-context review: all criteria MET.
  139 flutter + 384 pytest + ruff green; depth-1/depth-2 golden pair. **No paid spend beyond the shared
  Gemini test key** (one depth-2 de-risk run).

### 2026-07-05 — **P3.2 Local & edge model UX** (merged to `phase-3`)
- **The direct answer to your question** (Gemma/Qwen/GLM/… local models): the app now **discovers the
  device's actually-installed Ollama models** with real per-model tool-capability and folds them into the
  picker — no more hand-typing an id or guessing from a static list. Verified on *your* machine: it found
  `llama3.2:latest` (tool-capable) + `dolphin-llama3`/`lexi-llama-3` (no tools).
- The **capability gate is now live**: a non-tool local model is a disabled "· no tools" item on the
  analyst roles, and a **launch backstop** refuses a run whose effective analyst model can't call tools
  (even the global quick model) — so a local model that would produce empty reports can't silently run.
- **Real-path proof:** a live `llama3.2:latest` analyst run fired `tool_calls` end-to-end (a real report
  with live OHLCV) — confirming tool-capable local models genuinely work, so blocking non-tool ones is right.
- Recon wins: Ollama's `/api/tags` carries capabilities inline (one round-trip) and `httpx` was already a
  dep (zero bundle cost). Fresh-context review = mergeable; 136 flutter + 381 pytest + ruff green; new
  `hub_capability_gate` golden. **No paid spend** (Ollama-only).

### 2026-07-05 — **P3.5 Historical as-of analysis** (merged to `phase-3`)
- **As-of date picker** on the Hub launch card ("Today" ↔ a warning "As-of DATE" for a historical run;
  future dates unpickable), a deterministic "as-of DATE" terminal indicator, and a **Polymarket
  live-source caveat** (it always reflects *now*; FRED honours the date). `tradeDate` binds the existing
  `RunConfig.tradeDate` — no wire change — and is a per-run input, deliberately **not persisted**.
- **Look-ahead correctness fix (P3.5b):** the raw OHLCV tool trusted the LLM's chosen `end_date`, so a
  past-date run could pull **future** rows into the model. Now clamped engine-side to the run's as-of
  date (LLM-independent), verified through the real `plan_run → isolation → tool` path (zero future rows).
- **Correctness item found + fixed in-session** (doctrine surface): the fresh-context review caught a
  **sibling look-ahead leak in `get_news`** (future *articles* on a historical run) — closed by the same
  shared guard. It was the only sibling; every other date-bounded tool is already as-of-aware.
- Verified: fresh-context review = **ship** (all 5 criteria MET, clamp test falsified-red when neutered).
  119 flutter + 376 pytest + ruff green. New `hub_as_of` golden + 4 re-baselined (Read + justified).

### 2026-07-05 — **P3.1 Data sources** (merged to `phase-3`)
- **BYO-key data vendors + asset-type**, the first Phase-3 subphase: a per-category **Data sources**
  picker in Model Studio (Yahoo Finance default; **Alpha Vantage** as a keyed alternative), a **FRED**
  macro key (optional; enables macro signals, never blocks a launch), a Polymarket keyless default-on
  note, and an honest **stock/crypto** toggle. Driven by a new engine-derived `GET /catalog/vendors`.
- **Your action (optional, non-blocking):** free **FRED** and **Alpha Vantage** keys unlock those
  vendors — yfinance (keyless) is the default and works without any key. Store them in Model Studio →
  Data sources like the LLM keys; they inject per-run and never touch disk.
- **Honest scope (as agreed):** the crypto toggle only *reframes the agents' prompts* — a crypto run
  still pulls yfinance data (verified live: BTC-USD returned real OHLCV through the default vendor). A
  **real crypto pipeline stays a dedicated future phase**.
- Verified: fresh-context pre-merge review (mergeable, no HIGH/MED, all 5 exit criteria falsification-
  tested), keys-never-on-disk byte scan, write-only keystore golden, real spawned-sidecar `/catalog/
  vendors`. 112 flutter + 368 pytest + ruff green. 3 LOW findings → 1 fixed, 2 backlogged.

### 2026-07-05 — **Phase 2 complete → merged to `main`**
- **P2.5c1/c2** Dream Team roster UI + capability/key gate; **P2.6a** bundled-sidecar spawn path + full-
  engine freeze + real-parent watchdog; **P2.6b** validated Inno installer (real install→spawn→run→
  uninstall); **P2.6c** Flutter CI gate (windows-latest, pinned 3.38.6, goldens byte-exact green).
- P2.7 close-out: completeness-critic audit → doc refresh + a real hybrid Ollama/Gemini run to
  substantiate the P2.5 exit. ADRs 0002–0005 in place. `phase-2 → main` merged (founder-approved).
- Verification posture held throughout: golden render-to-PNG, real-path headless runs (the frozen exe +
  hybrid mix), fresh-context pre-merge review on every PR (it caught the provider-freeze HIGH + the
  untracked-manifest bug), scope wall + harvest to backlog/roadmap.

### 2026-06-27 — P2.3 → P2.5b + public/open-core
- **P2.3** Settings & Model Studio (merged), **P2.4** Hub / run history + cached review (merged),
  **P2.5a** engine per-role routing (merged), **P2.5b** agent_models contract + provenance (merged).
- Repo went **public**, Apache-2.0, open-core docs (README/NOTICE/ADR 0003/monetization.md); **CI
  restored + fixed** (sidecar deps).
- Each subphase: workflow research/design + adversarial review (per-finding verified) + headless real
  runs where the synthetic path couldn't prove it. Verified: 59 flutter + 553 pytest + ruff green.

## 5 · 🗄️ Archive — *resolved blocks + decided forks, for traceability*

- ✅ 2026-06-27 — GitHub Actions billing block → resolved by going public (free CI on public repos).
- ✅ 2026-07-04 — VS C++/CMake desktop toolchain → **installed** by you; `flutter doctor` green (VS 2022
  17.14, Win10 SDK 10.0.26100). Unblocked the Windows build, live GUI runs, and the P2.6 installer path.
- ✅ 2026-07-05 — `phase-2 → main` merge → **you approved; Phase 2 shipped.** (Completeness-critic clean;
  close-out doc refresh + hybrid-mix artifact landed with it.)
