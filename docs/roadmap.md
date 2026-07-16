# Quorum — Product Vision & Roadmap

The canonical product roadmap. For the in-flight phase detail, see [phase-5-plan.md](phase-5-plan.md)
(The Free Local Tier → then the unsigned 1.0.0 Windows GA per [phase-4-plan.md](phase-4-plan.md)); for
decisions, see [decisions/](decisions/). This doc holds the *why it's world-class* and the long arc.

## What Quorum is

A premium desktop research terminal: a user picks a ticker, a council of LLM agents (analysts →
bull/bear debate → trader → risk team → portfolio manager) debate it live, and you get a
**BUY / HOLD / SELL** verdict with full drill-down. Models are user-selectable across many frontier
providers. It is a **research / educational** tool — **not financial advice**, no real-money
execution in early versions (a paper-trading sandbox precedes any brokerage work).

## The three signature bets

Beyond "watch agents debate → get a verdict", three things make Quorum genuinely differentiated. The
engine already has the raw material for all three.

1. **Track Record — "did the team's calls actually work?"** A running scorecard of the AI council's
   realized hit-rate and alpha (return vs. benchmark). The engine already keeps a decision log and
   self-reflects on realized return vs. benchmark. **No retail AI tool shows you whether its past
   advice worked** — surfacing this is the trust flagship. *Built post-V1; Phase 2's Hub (P2.4) seeds
   its data so there's no backfill.*

2. **Dream Team — your AI dream team.** Assign a different frontier model to each agent role (Opus on
   the portfolio manager, a fast cheap model on the analysts, Grok on the bull, …). Novel, deeply
   on-brand, and the provider layer already supports many models — but per-role routing needs an
   additive engine change. *A dedicated V1 phase: [P2.5](phase-2-plan.md#p25--dream-team-per-agent-model-assignment-signature-bet-needs-engine-work).*

3. **The debate-as-spectacle terminal** *(shipped in Phase 1)* — the live bull-vs-bear tug-of-war,
   drill-down, and verdict rail — **plus** surfacing the engine's **FRED macro** and **Polymarket
   prediction-market** signals, which almost no retail tool does. *The signal layer is post-V1 (needs
   the engine to emit them as structured events).*

## Roadmap bands

Quorum uses a compressed macro-phase structure (Phase 1/2/3 + post-V1). The mapping below also notes
the original `P#` IDs from the first roadmap draft, for continuity.

### Band A — Foundation *(complete)*
- **Phase 1** *(≈ old P0 engine seam + P1 vertical slice + P2 research terminal)* — the sidecar +
  runtime + event contract, and the frameless 3-pane streaming terminal. De-forked 2026-06-26.

### Band B — Core V1
- **Phase 2** ✅ *(complete, merged to `main` 2026-07-05)* — Hub & navigation, Settings/Model Studio,
  the **Dream Team** per-agent roster + capability/key gates, applied brand, a validated debug-signed
  Windows installer, and a Flutter CI gate. Detail: [phase-2-plan.md](phase-2-plan.md).
- **Phase 3 — Depth & Refinement** ✅ *(complete, merged to `main` 2026-07-06 — PR #29)* — surfaced the untapped TradingAgents
  engine + deepen the product: **P3.1** BYO-key data-vendor selection + asset-type toggle, **P3.2**
  local/edge model discovery (Ollama `/api/tags`) + a live capability gate, **P3.3** debate-terminal depth
  (turn-structured debate + risk synthesis — bet #2), **P3.4** UI/UX + a11y (keyboard, AA contrast, error
  surface), **P3.5** historical as-of analysis + the look-ahead clamp. Open-core line locked:
  **BYO-key raw = free, hosted-curated = paid** ([ADR 0006](decisions/0006-open-core-signal-boundary.md)).
  Detail: [phase-3-plan.md](phase-3-plan.md).
- **Phase 4 — V1 Release & Hardening** ✅ *(≈ old P6; complete except the publish → [phase-4-plan.md](phase-4-plan.md))* —
  security sweep + a secret-scan CI gate (the shared Gemini test-key rotation is **post-V1** — a dev/CI-only
  credential that never ships), release CI (+ end-to-end
  `packaging.yml` verification, a clean-VM install smoke, a per-provider freeze regression test), a bounded
  **UX-integrity** pass (the 4 V1-blocking defects from the Phase-4 recon audit), unsigned-release readiness,
  and an **unsigned 1.0.0 Windows GA**. **Production code-signing is deferred to a 1.x/V2 fast-follow**
  ([ADR 0007](decisions/0007-defer-code-signing-to-v2.md)) — the `-Sign` seam is retained. macOS is a
  **separate post-V1 port (P13)** — Windows-first GA. *(2026-07-16 founder call: the **GA publish now
  follows Phase 5** so V1 ships the complete free-local story; hardening itself is done.)*
- **Phase 5 — The Free Local Tier** *(current; pulled forward from Band C by founder call 2026-07-16;
  plan-locked → [phase-5-plan.md](phase-5-plan.md))* — the **Edge Model Draft Board core, in V1**: use
  Quorum **completely free + locally** with on-device edge models, **tier-matched to the device**
  (Lite/Core/Max by detected RAM). A **curated** tool-capable shortlist (Qwen3.5 anchor family; Gemma 4
  alternates — genuinely Apache-2.0 since Apr 2026; MiniCPM5 text-only; VibeThinker excluded — all
  live-verified 2026-07-16), per-model **fit badges** (exact GGUF bytes + KV-cache-honest sizing),
  **one-click `ollama pull`** (streamed progress + verified resume), tiered **"Free local team" preset
  Benches**, **roster-fit** ("can this machine run my whole Dream Team?" — max-not-sum), and **zero-key
  onboarding**. Every analyst default is **real-run verified** through the live capability gate before it
  ships. Hard scope wall: curated draft board, **NOT a model browser**.

> **Business model:** open-core (local client free + open; paid value server-side) —
> [monetization.md](monetization.md), [ADR 0003](decisions/0003-open-source-and-open-core-monetization.md),
> and the raw-vs-curated boundary in [ADR 0006](decisions/0006-open-core-signal-boundary.md).

### Band C — Post-V1 platform *(the maximality)*
- **Track Record & intelligence** *(P7)* — decision log + reflection/memory surfaced; realized alpha;
  cost/usage analytics. (Signature bet #1; P2.4 seeds the manifest, **P3.1 seeds vendor provenance** —
  record which data source served each category so the scorecard can attribute a verdict to its inputs
  [drained from `docs/backlog.md`].)
- **Hosted signal layer** — the **curated/aggregated/synced** FRED + Polymarket signal intelligence
  (no-key hosted, cross-run history) — the **paid** half of signature bet #3, per
  [ADR 0006](decisions/0006-open-core-signal-boundary.md). (The *raw BYO-key* half ships free in Phase 3.)
- **Real crypto pipeline** — crypto-specific data vendors / tools / routing (not just the Phase-3 prompt
  relabel): a genuine crypto data path so a crypto ticker gets crypto-native analysis. A **dedicated future
  phase** (surfaced by the P3 planning fan-out; today `asset_type` only relabels agent prompts).
- **Backtesting & historical replay** *(P8)* — timeline scrub + performance attribution (Phase 3 ships
  as-of-date analysis + the look-ahead clamp; this is the full replay/attribution layer on top).
- **Automation & alerts** *(P9)* — scheduled runs; verdict-change & price alerts; notifications.
- **Paper trading & portfolio** *(P10)* — simulated P&L; the bridge toward real trading.
- **Real brokerage execution** *(P11)* — Alpaca/SnapTrade + the compliance work. **Far future,
  compliance-gated**; keeps the "not financial advice / no early real-money" posture intact.
- **Advanced AI & extensibility** *(P12)* — custom agents/prompts, add analysts, MCP tools/data
  sources, ensemble debate.
- **Edge Model Draft Board — post-V1 remainder** *(the core shipped in **Phase 5** → [phase-5-plan.md](phase-5-plan.md);
  this line holds what stays post-V1)* — **(a)** the defensibility north star: rank edge models by their
  **realized Track Record** on the trading task (needs P7) — a "which local models actually made good
  calls" list only Quorum can produce; **(b)** LM Studio / vLLM / llama.cpp discovery beyond Ollama;
  **(c)** VRAM-aware fit refinement (dxgi FFI or sidecar-side) on top of the shipped RAM tiers;
  **(d)** hosted/curated catalog updates decoupled from app releases (the open-core seam P5.1a's
  engine-served catalog deliberately keeps open). *(Provenance: the P3.2 local-model discovery fan-out;
  a 2026-07-05 research pass on Ollama 0.30.11; the 2026-07-16 five-agent live-verified model/mechanics
  fan-out that seeded the Phase-5 catalog.)*
- **macOS release** *(P13)* · **Mobile remote** *(P14, Android→iOS over LAN/WAN, same SSE API)* ·
  **Auto-update & distribution maturity** *(P15)*.

## Posture (non-negotiable)

- **Research / educational, not financial advice.** Disclaimers in-product; no real-money execution in
  early versions; the paper-trading sandbox precedes any brokerage integration.
- **Engine is the source of truth** — extend, don't rewrite; the `tradingagents` package name is
  frozen for upstream merge-ability.
- **Provider keys stay on the user's machine** (BYO; see [ADR 0001](decisions/0001-byo-api-key-storage.md)).
