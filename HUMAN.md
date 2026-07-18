# HUMAN.md — Co-founder log (ganesh ⇄ Opus 4.8)

> The async standup between the human founder (ganesh) and the AI co-founder/PM (Opus 4.8). Opus
> writes; ganesh reads top-down and acts on §1/§2. This file is a **router + queue, never a source of
> truth** — anything durable lives in an ADR, the plan doc, or `CHANGELOG.md`; here we keep a one-line
> pointer + the human-action delta. If an entry needs more than ~3 lines, it belongs in an ADR and this
> links it. **§1 (blockers) and §2 (forks) are also surfaced in the chat turn** the moment they arise;
> §3/§4/§5 are pull-only. Rules: see CLAUDE.md → *Operating doctrine*.

**Last AI update:** 2026-07-18 (**P5.3 MERGED (PR #54) — the free-local story works end-to-end**: a keyless machine pulled qwen3.5:9b through the app's pull lane and ran a real 12-role all-local analysis to a "Rating: Buy" verdict in 27min. **P5.4 (the verification sweep) is now in flight with a concrete diagnosis**: 6 of 45 requests in that run hit the 8192-token context ceiling (`truncated = 1` in Ollama's log) and 3 of 4 analyst desks produced no report — the plan's predicted A6 context-truncation risk, observed live; the sweep opens by settling truncation-vs-tool per desk and re-badging at a raised context. §3/§4)
**Spend (Phase 4):** **entirely free tier — zero paid spend.** Ollama + demo + the shared Gemini test key +
free data-vendor keys + free public-repo CI. **Production code-signing is deferred to V2** (ADR 0007), so no
cert purchase this phase; the `-Sign` seam is retained for later. If anything would cost money it stops and
surfaces first. (Phase-2/3 spend was ~cents on the Gemini test key only.)

---

## 1 · ⛔ Blocked on you — *only-human steps; these gate progress*

- _(nothing blocking my current work)_ — merge authority delegated + `main` branch-protected, so I self-merge
  verified work (full CI green + fresh review). Gemini rotation → post-V1, signing → V2 (both §3). **The
  GA-path items below need you, but they're queued behind Phase 5 — nothing blocks the Phase-5 build.**
- **The GA runway's 2 human steps are now queued BEHIND Phase 5 (your 2026-07-16 call)** — **full
  walkthrough in [`SETUP.md`](SETUP.md) §3:** (1) **submit the built installer to Microsoft Defender**
  ([file submission](https://www.microsoft.com/en-us/wdsi/filesubmission)) — now on the **post-Phase-5
  binaries** (the sidecar/app change, so submitting the current build would be wasted); (2) the **1.0.0 GA
  publish itself** (tag + GitHub release + distribute) — the one outward-facing act I never self-approve.
  Nothing for you to do until Phase 5 lands; I'll tee both up one-click then.
- **New: [`SETUP.md`](SETUP.md) answers your setup questions** — the credential map (short version: **you need
  no API keys/accounts to ship or run**; BYOK + local-first; the only optional adds are free FRED/Alpha Vantage
  keys), the installer-build + Defender-submission walkthrough, and the analytics call (§2 below).
- **Optional (non-gating), 1-click:** make **`secret-scan`** (and, if you like, `ruff` / `tests`) required
  status checks on `main` alongside the flutter check. The secret-scan gate (P4.1) runs on every PR
  regardless; this just hard-enforces it. My merge discipline covers the interim, so it doesn't block me.

## 2 · 🔱 Want your input — *genuine forks; I have a recommendation*

- **2026-07-18 — How shipped users get the raised context window (P5.4).** The e2e run proved the
  A6 risk real: at Ollama's 8192-token default, analyst prompts get silently truncated (6/45
  requests) and 3 of 4 desks produced empty reports. The verification sweep runs at 16384 on this
  machine (a local Ollama setting — no code). But the probe **falsified every zero-surface way for
  the PRODUCT to set ctx programmatically** on the OpenAI-compat path (Ollama /v1 ignores ctx
  fields — live-verified on 0.32.1). Options: **(i) docs-guidance + an in-app detectable warning
  when the served ctx is below what the badges assume (my recommendation — zero new surface,
  honest, reversible)**; (ii) derived-model tags (`ollama create` with a baked num_ctx — works via
  /v1 unchanged but adds create-surface + a second catalog identity); (iii) switch the ollama path
  to the native /api/chat (new dep, exits the shared compat registry — an architecture fork). The
  sweep does not block on this; V1 can ship (i) and revisit.
- **2026-07-18 — Correctness (surfaced same-session per doctrine): the engine accepts an EMPTY
  analyst report and marks the run `done`** — run 15d074ab shipped a Buy verdict over three empty
  desks with `error: null`. The sweep's harness grades on report content so P5.4 can't be fooled,
  but the *product* can still present a verdict built on silence. A minimal engine guard (flag or
  fail a run whose analyst sections are empty) is NEW surface, so it's yours to call: guard in V1,
  or ship with the disclaimer posture and guard in V1.x. My recommendation: a lightweight
  warning-level flag on the run (UI shows "partial analysis"), not a hard fail.

- **Analytics — Firebase vs Google Analytics vs none (your question 2026-07-06).** Two problems with the
  framing: (a) **Firebase Analytics doesn't support Windows desktop** (`firebase_analytics` = Android/iOS/
  macOS/web only — [FlutterFire #12847](https://github.com/firebase/flutterfire/issues/12847)), so a Firebase
  project won't give you analytics on the Windows app; (b) **direct GA4** (via the Measurement Protocol) *is*
  possible, but it's Google telemetry on a **local-first, privacy-first** product — a posture/privacy fork,
  not plumbing. **My recommendation:** **ship 1.0.0 with no analytics** (not needed for GA, most posture-
  consistent), and *if* you later want usage insight, use **[Aptabase](https://aptabase.com/for-flutter)**
  (open-source, privacy-first, anonymous, real Windows+Flutter SDK) **opt-in with disclosure** — not Firebase/
  GA. This is a **post-GA (V1.x)** call; I won't wire any telemetry until you decide. Full reasoning +
  alternatives in [`SETUP.md`](SETUP.md) §4. *(hub-03 disclaimer + signing + Windows-first are all decided — §3.)*

## 3 · ✅ Decisions I made — *FYI; self-approved consequential calls. Newest first; ADR-linked.*

- 2026-07-17 — **Applying a "Free local team" preset turns demo mode OFF** (P5.3a). A preset that left
  demo on would "apply" and then visibly do nothing — the preset's whole point is a real free local
  run. The button copy says so ("Apply — switches to real local runs"); demo-preserving semantics is a
  one-line revert if you prefer it. It also resets data vendors to the keyless defaults (a stored
  Alpha-Vantage pick would re-block the keyless Run button).
- 2026-07-17 — **PR #52's fresh-context review (killed by your reboot) was re-run post-merge → PR #53
  fixed forward**: 1 MAJOR (a pull-stream hiccup closed the app-wide HTTP client — bricked all
  networking until restart) + reconnect/race/timeout/gate fixes; the resumed-pull drift question
  closed empirically (Ollama re-emits every layer on resume — verified twice, live). Triage table in
  [PR #53](https://github.com/blokzdev/quorum/pull/53); two NITs backlogged.
- 2026-07-16 — **Phase 5 (The Free Local Tier) plan-locked — YOUR call: complete before GA, so V1 ships
  the world-class free-local implementation.** The Edge Model Draft Board core pulls forward from post-V1
  into V1: device-tiered (Lite/Core/Pro) curated local models, fit badges, one-click `ollama pull`,
  tiered free-team presets, roster-fit, zero-key onboarding. Seeded by a 5-agent **live-verified**
  research pass (your model picks checked: **Gemma 4 = genuinely Apache-2.0 ✓**, Qwen3.5 = the anchor
  family ✓, MiniCPM5-1B = text-only roles only (Ollama can't reach its tool-calling), VibeThinker-3B =
  excluded (its own card disclaims tool-calling)). Hard walls: **curated draft board, NOT a model
  browser**; no analyst default ships without a **real gated run** (tag ≠ reliability). GA publish +
  Defender submission re-sequenced after P5. Plan: [docs/phase-5-plan.md](docs/phase-5-plan.md).
- 2026-07-06 — **hub-03 disclaimer: you said "proceed with inapp shell footer" → shipped** (PR #46). A
  persistent, always-visible `DisclaimerBar` in the shell chrome (below every surface): *"Research &
  educational tool — not financial advice. No real-money execution."* textMid on surface1 = **7.24:1** (passes
  AA + AAA); golden-tested + a `wcagContrast` unit test locks the AA claim. Closes the last open §2 fork and
  the audit's top GA-runway item — the regulatory posture now lives **in the product**, not just the README.
- 2026-07-06 — **Merge authority delegated to me (your call) + `main` branch-protected.** Going forward I
  **self-merge** verified subphase work to `main` as-you-go (no integration branch), gated on **full CI green
  + a fresh-context pre-merge review**; you added the **flutter (analyze+test+goldens+build)** job as a
  *required status check* on `main`, so a red build can't land. **Still surfaced (not self-merged):** the GA
  publish/tag of 1.0.0 + anything security/cost/contract/scope. Recorded in CLAUDE.md doctrine rule 13 + the
  phase-4 cadence.
- 2026-07-06 — **Phase-4 subphase reorder (your prompt: "release CI shouldn't be #2").** Split the old
  "release CI" into (a) **merge/repo guards** → **P4.1** (secret-scan gate + the required-flutter merge gate),
  early, to protect merge-as-you-go, and (b) **release-artifact validation** (packaging e2e + install smoke +
  per-provider freeze) → **P4.3**, late, to validate the *final* installer. New order: **P4.1** security + CI
  merge-hardening · **P4.2** UX-integrity · **P4.3** release pipeline e2e · **P4.4** unsigned-release readiness
  · **P4.5** GA close-out. Rationale in [phase-4-plan.md](docs/phase-4-plan.md).
- 2026-07-06 — **Keep the shared dev Gemini key; defer rotation to post-V1 (your call).** Clarified the
  architecture: the `.env` `GOOGLE_API_KEY` is a **dev/CI-only** credential (engine auto-loads `.env` via
  `tradingagents/__init__.py`) — it is **not** the product key and **never ships** (gitignored, not in the
  PyInstaller spec). Users' keys go the separate write-only-keychain → per-run-injection BYOK path
  (`jobs.py` `build_api_keys_dict`). So rotation is dev-hygiene, not a GA gate. P4.1a keeps the genuinely
  valuable **secret-scan CI gate** (protects the public repo); rotation stays in `docs/backlog.md` → post-V1.
- 2026-07-06 — **Defer production code-signing → V2; ship an unsigned 1.0.0 GA (your call)** →
  [ADR 0007](docs/decisions/0007-defer-code-signing-to-v2.md). After a researched options pass (free
  **SignPath Foundation** — but it shows "SignPath Foundation" as the publisher + our open-core model risks
  its eligibility; **Certum Open Source** ~€29/yr; **Azure Artifact Signing** ~$120/yr), you chose to defer
  rather than spend/set up a cert at GA. Unsigned works 100% functionally (our per-user installer even avoids
  the UAC prompt); the cost is a first-run SmartScreen "Run anyway" warning + no publisher reputation + higher
  PyInstaller AV-FP risk — mitigated in **P4.4** (Run-anyway docs + Defender pre-submission) with the `-Sign`
  seam retained. **Net: Phase 4 = zero paid spend.** Revisit signing when distribution traction warrants.
- 2026-07-06 — **Windows-first 1.0.0 GA (your call).** macOS stays a separate post-V1 port (roadmap P13);
  1.0.0 does not wait for a multi-platform signed launch (that would add Apple notarization + $99/yr + delay).
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

### 2026-07-06 — **hub-03 disclaimer + a UX quick-wins sweep** — *every AI-ownable Phase-4 task now done (#46/#47)*
- **hub-03 disclaimer** (#46): a persistent `DisclaimerBar` in the shell chrome, present across all surfaces
  (research/educational — not financial advice — no real-money execution). Contrast 7.24:1; golden + a
  `wcagContrast` unit test. The fresh review's one kept nit (lock the AA claim in unit-land, not just the
  golden) was folded in before merge; the magic-numbers nit was rejected → the tok-02 token-scale backlog item.
- **UX quick-wins sweep** (Workflow, 4 fresh-context agents, every finding golden-grounded): 13 findings →
  **4 shipped** (#47), 2 backlogged, rest dropped/already-tracked. Shipped: DEMO-row cost-column **alignment**;
  the verdict **Confidence bar tinted to the rating color** (was a stray blue under a green BUY); a **title-bar
  divider** (drains backlog shell-03); and **one filled primary on the error screen** (demoted the duplicate
  Retry to tonal). 5 goldens re-baselined — each Read + visual-diff-justified.
- **Honest coverage note:** the sweep's Settings/DreamTeam agent returned a broken stub, so I **re-swept those
  two surfaces** with a focused follow-up — came back **clean** (0 net-new; all items already = set-03/dt-01..03).
- Both PRs self-merged (CI-green + fresh-context APPROVE each); the **combined `main` re-verified green**
  (analyze + 153 tests + all goldens) since each PR's CI ran without the other's changes.

### 2026-07-06 — **P4-GA readiness audit + P4.4a/P4.5a close-out docs** — *Phase 4 all but the GA publish*
- **GA-readiness audit** (Workflow, 4 fresh-context agents): **every P4.1/P4.2/P4.3 exit criterion is
  genuinely met** (verified against code/CI/goldens), **zero scope creep**, all deferrals correctly tracked.
  2 GA-blockers + should-fixes were all doc/version drift → fixed in P4.5a. The audit also caught a guard:
  do **not** bump `pyproject.toml` (engine `0.3.0` stays for upstream merge-ability).
- **P4.4a** ✅ — README "Installing on Windows (first run)" section with the honest SmartScreen "Run anyway"
  walkthrough. *(A real-dialog screenshot is a founder/real-install follow-up — can't capture the GUI here.)*
- **P4.5a** ✅ — reconciled README (Phase-2→Phase-4/1.0.0 GA), CHANGELOG (a `[1.0.0]` entry + app-vs-engine
  dual-versioning note), CLAUDE.md status, roadmap pointer, and the 3 packaging files (`0.2.0`→`1.0.0`,
  "Phase 3 signing"→"V2/ADR 0007").
- **P4.5b** ✅ (audit part) — completeness-critic + scope audit done. **Remaining = the founder-gated GA
  publish** (§1) + the **hub-03** disclaimer (§2, the audit's top GA-runway item). After those, Phase 4 = GA.

### 2026-07-06 — **P4.3 Release-pipeline CI COMPLETE** — *installer built + proven end-to-end (#41/#42/#43)*
- **P4.3a** (#41/#42): the first real `packaging.yml` run **caught + fixed 2 never-exercised bugs** (dev-only
  `.venv` python path; VS-redist-only CRT staging) — both would have blocked any release build. It now builds
  a **61 MB installer e2e**, and a **clean-install smoke** (silent install → run the installed frozen sidecar
  → `/healthz` → uninstall) validates it on real CI.
- **P4.3b** (#43): a key-free **freeze regression check** — the *frozen* sidecar's `--check-freeze` imports
  every bundled provider SDK (anthropic/google/openai) and fails if one is dropped from the spec (the P2.6b
  HIGH). Ran green in the frozen bundle. Fresh review even monkeypatched a missing package to prove it catches.
- **The hardening is done.** Remaining: **P4.4** (unsigned-release readiness — Run-anyway docs + Defender
  submission) and **P4.5** (GA close-out). Both have **founder-gated actions** — see §1/§2.

### 2026-07-06 — **P4.2 UX-integrity COMPLETE** — *all 4 audit blockers closed (#37/#38/#39)*
- **P4.2b Settings-H1** (#37): root-caused (empirical bisection) a **golden-harness capture bug** — capturing
  the non-RepaintBoundary `SettingsBody` rasterised the H1 at a fractional offset (faint/ghosted). Test-only
  fix (capture the Scaffold); the H1 code was always correct. 5 goldens re-baselined + Read-verified.
- **P4.2d vendor-key label** (#38): data-source key fields now vendor-attributed ("Alpha Vantage API key" /
  "FRED API key") so a stored key is always identifiable.
- **P4.2c shell-chrome golden** (#39): extracted a pure `ShellChrome` (behaviour-preserving) + 2 goldens
  (windowed + maximized) — closed the zero-coverage gap on the frameless chrome. Surfaced **hub-03** (no
  persistent disclaimer) → §2.
- **P4.1 ✅ + P4.2 ✅** = 6 self-merged PRs, each CI-green + fresh-context-reviewed; the review caught real
  defects in P4.1 (gitleaks tree-masking blind spot) and P4.2a (Sell risk-ribbon still sub-AA). Next: P4.3.

### 2026-07-06 — **P4.1 security + P4.2a a11y contrast shipped** — *first Phase-4 implementation, self-merged*
- **P4.1 (#34)** — a `gitleaks` **secret-scan CI gate** (so no key can land in the public repo), `SECURITY.md`
  (private-advisory disclosure policy), and `docs/security.md` (threat model: assets, 5 trust boundaries, the
  loopback bearer/ephemeral-port/parent-PID model, BYO-key never-on-disk). Recon-grounded; I **rejected** two
  false "untested residual" findings (keys-never-on-disk + `/env-keys` were already regression-tested). The
  fresh review caught a real gitleaks blind spot (a path allowlist masked whole test trees) → fixed to
  allowlist by value.
- **P4.2a (#35)** — lifted sub-AA tinted chips to WCAG AA-normal via a pure, tested `accessibleTint`. The
  fresh review caught that the risk-verdict-ribbon chip sits on its own tint (a Sell verdict stayed ~4.2:1)
  → fixed to target the composited bg. One golden re-baselined (isolated-diff-verified).
- **Both self-merged** on the delegated workflow (full CI green + fresh-context review each). The keystone
  review earned its cost — it caught a real defect in *both* PRs that my own context missed.

### 2026-07-06 — **Phase 4 kickoff: docs #31 merged + Phase-4 plan-locked** — *V1 Release & Hardening opened*
- Merged the Phase-3 close-out docs PR [#31](https://github.com/blokzdev/quorum/pull/31) to `main`
  (`b60c00b`); §1 is clean of the resolved Phase-3 blocker.
- **Release-hardening recon (inline):** signing is still debug **self-signed** (`build_installer.ps1` — needs
  a production cert — would've been the first real spend, now deferred to V2 per your call below); `packaging.yml` is unverified e2e + has no clean-VM install smoke
  or per-provider freeze test; `ci.yml` says "8 goldens" but there are now **14**. **Secret hygiene clean** —
  `.env` untracked + never in history, PyInstaller `build/dist` untracked, a tracked-file scan found **zero**
  committed keys (so the Gemini item is a *shared-key rotation*, not a leak). No `SECURITY.md`/threat model.
  Version is already `1.0.0+1` (GA target).
- **Phase-4 recon UI/UX/a11y audit** (Workflow, 7 surfaces, find → adversarial-verify, every finding grounded
  in a committed golden PNG or code file:line): **23 findings, 21 CONFIRMED / 2 REJECTED / 0 UNGROUNDED**
  (no hallucinated pixels; the verifier caught a phantom-chip miscite that the finding survived on corrected
  evidence). Executive triage → **4 KEEP** (P4.3 exit criteria: sub-AA chips, washed-out Settings H1 in the
  committed goldens [I Read both + confirmed], shell chrome has zero golden coverage, data-sources key has no
  vendor label), **2 REJECT**, **16 DEFER → backlog** (`P4-recon`). Blocking set is small + coherent →
  absorbed as a bounded subphase, **not** a separate UX phase.
- **Signing researched → you chose to defer** ([ADR 0007](docs/decisions/0007-defer-code-signing-to-v2.md)):
  free **SignPath Foundation** exists but shows "SignPath Foundation" as the publisher + our open-core model
  risks its eligibility; cheap paths are **Certum Open Source** (~€29/yr) / **Azure Artifact Signing**
  (~$120/yr). You opted to **ship unsigned 1.0.0** and sign in V2 — so **Phase 4 is zero paid spend** and the
  `-Sign` seam is retained; the SmartScreen "Run anyway" + AV-FP tradeoffs are mitigated in P4.4.
- **Plan-locked + restructured** [docs/phase-4-plan.md](docs/phase-4-plan.md): 5 subphases (P4.1 security ·
  P4.2 release CI · P4.3 UX-integrity · P4.4 unsigned-release readiness · P4.5 GA close-out), falsifiable exit
  criteria, unsigned Windows-first 1.0.0. **Awaiting you: §1** (plan-PR merge only — Gemini rotation deferred
  post-V1). No implementation started.

### 2026-07-06 — **Phase 3 MERGED to `main`** (PR #29 → merge commit `0a7ad57`) — *Band B core V1 depth landed*
- You authorized the founder-gated merge on the **slice-by-slice visual review** (6 fresh-context reviewers,
  one per slice #23–#28, each Reading its golden PNGs; full CI suite green). `phase-3` branch deleted.
- **Pre-merge catch:** flutter CI was actually RED on #29 — `flutter analyze` (fatal-info) tripped on a
  `_ollamaCatalog` lint from P3.2b that had *skipped* the P3.3/P3.4 flutter test step at their sub-PR merges.
  Fixed in `15c025c`; the current `main` tip is fully green. (Lesson saved: run `flutter analyze`, not just
  `flutter test`, before claiming flutter-green.)
- **Post-merge hygiene:** durable CI phrasing (dropped the brittle "385 pytest" counts) + two backlog captures
  — *CI-gate hardening* (gate sub-PR merges on the full flutter job → Phase 4) and *true separate risk-manager
  verdict node* (advanced-AI / debate-depth). Also captured this session: the **Edge Model Draft Board**
  post-V1 roadmap capability (Band C).
- **Two documented non-blockers:** P3.3's "risk-ribbon = risk judge, not PM decision" criterion is
  unsatisfiable (engine sets them equal, `portfolio_manager.py:75` — ribbon is correct); and #26/#27 had
  self-merged red (now resolved).

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
