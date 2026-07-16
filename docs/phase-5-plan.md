# Phase 5 — The Free Local Tier (Edge Model Draft Board)

> Status: **plan-locked** (founder call 2026-07-16: *"complete this before GA so V1 has the complete
> world-class implementation"*; **amended pre-lock** per a fresh-context adversarial plan review — A1
> pull-concurrency, A2 tier-floor consistency, A3 unconditional default verification, A4 Ollama-absent
> onboarding, A5 naming, A6 context honesty, A7 headroom). Phase 5 pulls the **Edge Model Draft Board** forward from the post-V1
> band into **V1**: the ability to use Quorum **completely free and locally** with an on-device edge
> model, **tier-matched to the device's capability**. The **1.0.0 GA publish (P4.5b) now follows Phase 5**;
> the Defender pre-submission (P4.4b) also moves post-P5 (the binaries change). Phase 4's hardening is
> complete and `main` stays releasable throughout. **Zero paid spend** — everything here is local/free.
> Scope wall applies at full strength: this is a **curated draft board, NOT a model browser** (the
> roadmap's hard wall, re-affirmed below).

## Framing

The free-local *engine path* already works end-to-end (P3.2): Ollama discovery with real per-model
tool-capability, the capability gate + launch backstop, per-role Dream Team routing, keyless yfinance
data. What's missing is the **product**: a user without an API key gets no guidance that the free path
exists, no curated model shortlist, no "will it run on my machine" answer, no in-app install, and no
one-click free lineup. Phase 5 closes exactly that gap — onboarding + curation + device-fit — and
nothing else. It directly advances signature bet #2 (Dream Team) and is the free-tier onboarding story
for the open-core model (free local client, paid server-side value — ADR 0003/0006).

## Research provenance (2026-07-16, live-verified)

A 5-agent fan-out (VibeThinker · Gemma · MiniCPM · Qwen · tiering-tech) verified every candidate model
and mechanism against the live web + a live local Ollama 0.32.0 (including a real `/api/pull` test).
Key verified facts this plan builds on:

- **Qwen3.5 Small series** (0.8B/2B/4B/9B, Feb–Mar 2026) — Apache-2.0, **first-party Ollama library,
  every tag tools-flagged**; `qwen3.5:9b` = 66.1 BFCL-V4 (best verified small tool-caller). Qwen3.6
  (27b dense / 35b-A3B MoE) covers the top tier. **Qwen3.5 tool parsing needs Ollama ≥ 0.17.6.**
- **Gemma 4 E2B/E4B** (Apr 2026) — genuinely **Apache-2.0** (a real relicense; Gemma 1–3/3n were custom),
  Ollama `gemma4` carries the tools tag (`gemma3n` does **not**). Honest RAM: `e2b` = 7.2GB blob
  (~8–10GB RAM) — mid-tier despite the "2B" branding.
- **MiniCPM5-1B** (May 2026) — Apache-2.0, ~1.3GB RAM; tool-trained but its XML tool-calls need an
  SGLang/vLLM parser — **unreachable through Ollama** (no tools template) → text-only roles only.
- **VibeThinker-3B** (Jun 2026) — MIT, but the model card **explicitly disclaims tool-calling**, it's a
  competition-math specialist, and its 60K–100K-token reasoning chains are wrong for debate turns →
  **excluded** (documented so we don't re-litigate it).
- **Mechanics:** device RAM = one line via `device_info_plus` (`systemMemoryInMegabytes`); Ollama
  `/api/pull` streams per-layer progress with **documented + live-verified resume**; on Ollama 0.32.x
  `/api/tags` returns **per-model capabilities** (one call gates the roster; feature-detect + fall back
  to `/api/show`); there is **still no official pre-install capability/library API** (re-verified —
  issue #10693 closed wontfix-style) → **curation is forced, which is also our scope wall**; exact
  pre-install byte size is available from the (unofficial) registry-v2 manifest; KV-cache bytes =
  `block_count × head_count_kv × (key_len + value_len) × ctx × 2` — every input in `/api/show`
  `model_info` (worked example validated against live llama3.2).

## The curated catalog v1 (seed — re-verified in P5.1, real-run-gated in P5.4)

Three device tiers by detected RAM (the fit badge does fine-grained per-model work within a tier):

| Tier | Device RAM | Analyst default (tools) | Alternates / notes |
| --- | --- | --- | --- |
| **Lite** | < 12GB | `qwen3.5:2b` (2.7GB) | floor: `qwen3.5:0.8b` (1.0GB); proven fallback: `llama3.2` (2.0GB — live-verified tools on this repo); text-only debater: `minicpm5` Q4 (0.7GB) |
| **Core** | 12–32GB | `qwen3.5:9b` (6.6GB) | `qwen3.5:4b` (3.4GB) for slower machines; `gemma4:e2b` (7.2GB, thinking) alternate; `qwen3:14b` (9.3GB, prev-gen) upper option |
| **Max** | ≥ 32GB | `qwen3.6:35b` (35B-A3B MoE, 24GB blob, ~3B active) | fallback `qwen3.5:27b` dense (17GB) if the reported Ollama MoE GPU-utilization issue bites or the 35b fails P5.4a on 32GB; `gemma4:e4b`/`12b` alternates |

**(A2)** The Max floor is ≥ 32GB — set so the tier's own default *passes the tier's own fit math*
(24GB blob + KV + headroom ≈ 29–30GB): a default that badges Won't-fit at its tier floor is an internal
contradiction. **(A5)** One tier triple everywhere — **Lite / Core / Max** names both the device tiers
and the P5.3 presets ("Free local team — Core"); "Pro" is banned for this feature (it collides with the
`'pro'` run mode in `settings_controller.dart`/`app.py` and reads as a *paid* tier in an open-core
product whose *free* tier this is).

Catalog entries carry: exact Ollama tag, byte size, min-RAM, capability (analyst-capable vs text-only),
license, a one-line "why this one", and a **verification status** (see P5.4a). **Standardizing on one
family per tier** means one download serves analysts *and* debaters (the preset defaults therefore stay
on the Qwen family; `minicpm5` is a listed alternate, not a preset member).

## Scope wall (what Phase 5 is NOT)

- **NOT a model browser.** No HuggingFace/Ollama search, no free-text model discovery UI. The Draft
  Board renders **only** the curated list. (Ollama has no machine-readable library API anyway.)
- **NOT LM Studio / vLLM / llama.cpp discovery** — Ollama only (post-V1 backlog).
- **NOT Track-Record-ranked model lists** — needs P7 (post-V1 north star, roadmap Band C).
- **NOT auto-download.** Every pull is an explicit user click with visible size before it starts.
- **NOT a new LLM client seam.** The engine's existing Ollama path is untouched; Phase 5 is catalog
  data + device detection + pull UX + presets on top of shipped P3.2 machinery.

## Phase cadence (inherits Phase 4's, re-affirmed)

- **Merge model:** subphase PRs self-merged to `main` as-you-go, gated on **full CI green + a
  fresh-context pre-merge review**; golden render-to-PNG (Read the PNG) for visual changes.
- **Cost boundary: zero paid spend.** All models are free/open; verification runs are local Ollama.
  (Model downloads consume dev-machine disk — free, but large-tier pulls are noted honestly below.)
- **Sensitive ops (surface, never self-approve):** the GA publish (now post-P5), publishing, and any
  contract/scope change. The curated catalog's **model picks are product decisions** — locked here at
  plan time (founder-visible); mid-phase *additions* to the catalog are forks, not self-approved.
- **Verification:** the falsification bar — and specifically: **an Ollama "tools" tag is treated as a
  claim, not a fact.** No model ships as an analyst default without a real gated run (P5.4).

## Subphases

### P5.1 — Curated catalog + device tiers + fit badges *(read-only foundation)*

- [ ] **P5.1a Catalog data + contract** — the curated catalog as versioned data served by the sidecar
  (`GET /catalog/edge-models`, mirroring `/catalog/vendors` precedent): per-entry tag, bytes, min-RAM,
  role-capability, license, blurb, verification status. The response also carries the **detected Ollama
  version** (from `/api/version`; null when Ollama is absent) — the P5.1d version gate needs it and no
  existing endpoint exposes it. Engine-side so a future hosted/curated update path (open-core) stays
  possible; ships frozen defaults. Re-verify every seed tag/size at implementation time. **Drift caveat
  (named):** unlike `/catalog/vendors` (derived from engine constants, can't drift), this catalog is
  hand-curated against a mutable registry — Ollama tags are repointable post-ship, so P5.2c cross-checks
  pull bytes against catalog bytes as the drift tripwire.
- [ ] **P5.1b Device capability detection** — total RAM via `device_info_plus` on Windows (VRAM
  refinement is a backlog line, not V1); pure tier-assignment function (RAM → Lite/Core/Max), unit-tested.
- [ ] **P5.1c Fit badges** — per-model **Fits / Tight / Won't-fit** from exact model bytes + the KV-cache
  formula **at Ollama's default context** (the honest v1 input — the engine sets no `num_ctx` on its
  OpenAI-compat path, so Ollama's default *is* the effective context; A6. *Corrected 2026-07-16: the
  default was MEASURED at **8192** on Ollama 0.32.0 — the 4096 this plan initially cited was stale
  docs; the constant + served `kv_ctx` moved accordingly, exactly the one-constant change A6 designed*) **+ an explicit, unit-tested
  headroom constant** for OS + app + sidecar (A7 — bytes-vs-RAM alone would badge a 7.2GB model "Fits" on
  an 8GB machine and thrash). Pure Dart, unit-tested against the live-verified llama3.2 worked example
  (1.9GB file + 0.44GiB KV @4K ctx) **and** the gemma4-e2b-on-8GB case (must badge Won't-fit).
- [ ] **P5.1d Draft Board UI** — a new curated section (Settings/Model Studio) rendering the tiered
  catalog with fit badges + installed-state (already-pulled models detected via existing discovery);
  **Ollama version check** surfaced (qwen3.5 needs ≥ 0.17.6; warn + block those entries on older).
  Golden-tested (Read the PNG).
  *Exit (falsifiable):* `/catalog/edge-models` serves the seed catalog (contract-tested); the tier
  function and fit-badge math are unit-tested incl. the llama3.2 anchor case; the Draft Board golden
  shows tiers + badges + an installed marker; a too-old Ollama version visibly gates qwen3.5 entries;
  **no free-text model input exists anywhere in the new surface** (scope-wall test).

### P5.2 — One-click pull *(the install path)*

- [ ] **P5.2a Pull seam** — sidecar-proxied pull (`POST /pull` → Ollama `/api/pull`), reusing the
  EventLog/SSE *pattern* but **NOT the serialized run queue (A1, blocker-grade):** `jobs.py`'s
  `JobRegistry` runs all jobs through one worker thread, so a 6–24GB pull queued there would block every
  analysis run for the pull's duration (and vice versa) — and the reasons runs are serialized
  (process-global config/env isolation, cost capping) don't apply to a pull. Pulls execute on a
  **separate concurrent lane**, and pull events ride a **separate lightweight stream**, not the run
  event union (no `CONTRACT_VERSION` bump; the Dart side's `UnknownEvent` forward-compat is the
  backstop) — both validated at P5.2 recon.
- [ ] **P5.2b Pull UX** — per-model progress (aggregate per-layer `completed/total`; early events omit
  `completed` → default 0), cancel, and **resume proven for real** (cancel a real pull mid-flight,
  re-pull, verify it resumes — documented Ollama behavior, must be demonstrated not assumed).
- [ ] **P5.2c Post-pull integration** — a completed pull folds into the existing discovery + capability
  gate **without app restart**; pull errors (Ollama down, disk full, cancelled) surface honestly; the
  pull stream's reported `total` bytes are **cross-checked against the catalog entry's bytes** (the
  catalog-drift tripwire from P5.1a — a repointed tag surfaces as a visible mismatch, not a silent lie).
  *Exit (falsifiable):* a real curated model pulls end-to-end from the Draft Board on the dev machine
  **while an analysis run is in flight (the A1 concurrency proof — neither blocks the other)**;
  cancel→resume verified on a real download; the pulled model immediately appears role-assignable with
  its true capabilities; killing Ollama mid-pull produces a recoverable error state (not a crash); a
  seeded byte-mismatch surfaces the drift warning; goldens for pulling/installed/error states.

### P5.3 — Tiered free lineup + zero-key onboarding *(the payoff)*

- [ ] **P5.3a Preset local Benches** — one-click **"Free local team"** presets, one per tier and named
  by the tier triple (**Lite / Core / Max** — A5: one name set, no second Starter/Balanced/Max triple),
  built on the existing Bench + roster mechanics; presets stay on the Qwen family (one download serves
  analysts + debaters); the preset only offers models that are installed (or routes through P5.2 pull
  affordances).
- [ ] **P5.3b Roster-fit** — "can this machine run my whole Dream Team?" **Correctness note (locked at
  plan time):** Ollama loads models per-request and swaps them (default `OLLAMA_MAX_LOADED_MODELS`),
  so roster RAM fit = **max single model + KV**, NOT the sum — with an honest swap-latency note when a
  roster spans many distinct models. Pure function, unit-tested.
- [ ] **P5.3c Zero-key onboarding** — a keyless first-run Hub affordance surfacing the free-local path.
  Two detected states, each with its own UX (A4 — most first-run keyless users **won't have Ollama**,
  and pointing them at a Draft Board where every pull fails is a dead end, not onboarding): **Ollama
  present** → guide to the Draft Board; **Ollama absent** → an explicit install-guidance state (what
  Ollama is, the official download link, and a **re-detect** affordance for when it's installed —
  installing Ollama itself is outside the app and the copy says so honestly). Honest capability copy
  throughout (local models are slower/less capable than frontier cloud models — no over-promising).
  Golden-tested.
  *Exit (falsifiable):* on a keyless config, the Hub visibly offers the free-local path (golden); the
  **Ollama-absent state renders install guidance + re-detect (its own golden — the dead-end path is the
  falsifier)**; a tier preset applies a complete valid roster in one click; the roster-fit function is
  unit-tested for the max-not-sum rule; **a full real analysis run completes on a roster composed
  entirely of curated local models on the dev machine** (the end-to-end proof).

### P5.4 — Real-run verification sweep + close-out *(the honesty gate)*

- [ ] **P5.4a Analyst-default verification — unconditional (A3).** Every model occupying a **default
  slot** in any tier passes a **real gated run**: tool_calls actually fire and a non-empty report is
  produced through the live capability gate. **No conditional carve-out** — the earlier "verified if
  hardware allows, else `verified: tag-only`" draft auto-passed both ways and contradicted the phase's
  own headline; a default that can't be verified is **demoted to a marked alternate and the tier's
  default becomes the best verified model** (that demotion path existing is itself an exit criterion).
  `verified: tag-only` markers are legitimate for **alternates only**. Max-tier verification is feasible
  on the dev machine (31.7GB RAM — the 24GB-blob default fits by the plan's own math with other apps
  closed); if it genuinely can't run, the demotion rule applies — there is no third outcome.
- [ ] **P5.4b Docs + close-out** — README/SETUP free-tier quickstart ("run Quorum free in 10 minutes");
  roadmap/CLAUDE.md sync; backlog drain per doctrine; completeness-critic + scope audit (any shipped
  capability without an exit criterion = unsanctioned creep); then hand off to the **founder-gated GA
  publish** (P4.5b) + Defender pre-submission on the final binaries.
  *Exit (phase):* all subphase criteria pass; catalog entries carry an honest verification status; full
  CI green; the GA-readiness state of Phase 4 is re-confirmed on the post-P5 tree (installer builds,
  install smoke green); the GA publish remains founder-gated and is now unblocked.

## Load-bearing assumption (adversarial self-check, stated up front)

**The bet:** curated Qwen3.5 defaults + the existing capability gate produce *working* real analyst runs
on consumer hardware. Published tool benchmarks exist only at 9B (66.1 BFCL-V4); **sub-4B reliability is
unproven anywhere** — if `qwen3.5:2b` emits malformed tool calls under our multi-turn analyst prompts,
the Lite tier's UX is broken. This is why P5.4a is a *gate*, not a checkbox: the falsifying evidence
(a real run per pinned default) is mandatory, and the demotion path (analyst → text-only) is designed in
from the start rather than bolted on when a model fails.

**The coupled second-order risk (A6):** if P5.4a runs fail on **context truncation** rather than
tool-calling (the classic small-model-Ollama failure — long analyst tool outputs silently evict the
system prompt at the 4096 default), the fix (raising `num_ctx`) multiplies the KV term 2–8× and shifts
every fit badge — and possibly tier defaults. P5.4a therefore distinguishes *tool failure* (→ demote)
from *context failure* (→ re-run the badge math at the raised context and re-tier), and the badge
formula's context input is a named constant so that re-run is a data change, not a rewrite.
