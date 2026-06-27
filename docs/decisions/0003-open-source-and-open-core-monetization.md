# ADR 0003 — Open-source posture & open-core monetization

- **Status:** Accepted (2026-06-27)
- **Context:** Phase 2; triggered by a GitHub Actions billing block on the private repo and a
  founder decision on licensing + monetization.
- **Deciders:** ganesh (founder) + Quorum product track
- **Related:** [`docs/monetization.md`](../monetization.md), [ADR 0001](0001-byo-api-key-storage.md)
  (BYO keys), [`docs/roadmap.md`](../roadmap.md)

## Context

The repository was private. GitHub Actions CI (the `ruff` + `pytest` gate) became unrunnable when
the account hit a billing block — every job failed in ~2 s with *"recent account payments have
failed or your spending limit needs to be increased."* Public repositories get free, unlimited
GitHub-hosted Actions, which would restore CI at no cost.

That forced the broader question the project had deferred: **what is Quorum's license and
monetization model?** Two facts constrain the answer:

1. **The engine is already open.** `tradingagents/` is derived from the Apache-2.0 TradingAgents
   framework; that portion must remain Apache-2.0. Source secrecy of the engine was never available
   as a moat.
2. **BYO-key economics.** Users supply their own provider API keys, so the user pays for all
   inference. Quorum's marginal cost to serve a local run is ≈ zero, and a free tier costs almost
   nothing to operate — unusual leverage most freemium AI apps lack.

A pre-flight audit confirmed the history is safe to publish: the literal `.env` was never committed
(only `.env.example` / `.env.enterprise.example` templates), no provider-key patterns appear in any
historical diff, and the current shared Gemini test key appears zero times in history.

## Decision

**Go public under the existing Apache License 2.0, and monetize via open-core.**

- **License:** keep Apache-2.0 for the whole repo (client + engine). No switch to a source-available
  or non-compete license — the Apache-2.0 engine portion cannot be relicensed, and a mixed-license
  monorepo is not worth the complexity for a solo founder at this stage.
- **Open-core boundary:** the **local desktop client stays open and free**. Paid value lives
  **server-side**, behind authentication + entitlement on infrastructure we operate — not behind a
  restrictive client license. An open client cannot clone the closed backend, the accumulated
  Track Record data, or the brand.
- **Revenue model:** **freemium → subscription** (see [`docs/monetization.md`](../monetization.md)),
  *not* a one-time closed-binary purchase (the product's value accumulates, so recurring is correct).
- **Compliance:** add a `NOTICE` (Apache-2.0 attribution to TradingAgents) and replace the inherited
  upstream README with a Quorum-first README that credits the engine.

## Alternatives considered

- **Stay private, fix billing.** Viable (add a payment method) and keeps a closed-binary option open,
  but forgoes free CI, open-source distribution/credibility, and the verifiable "keys stay local"
  trust story. Rejected as the default; remains a fallback if the open posture is ever reversed.
- **Source-available / non-compete license (BSL, Elastic License 2.0) on the new client code.**
  Would deter direct commercial forks, but cannot cover the Apache-2.0 engine, producing a confusing
  mixed-license repo for marginal protection on a niche tool. Rejected for now; revisit only if a
  real cloning threat emerges.
- **Split repos (open engine, closed app).** Protects the premium UI source but loses the monorepo
  simplicity and still leaves the closed app's CI on the billing hook. Rejected.
- **One-time upfront for a closed premium binary.** Wrong shape: Track Record, the model catalog, and
  the signal layer all accrue/maintain value over time, which a single transaction leaves uncaptured.
  Rejected as the primary model (a launch-only lifetime deal is a possible tactic, used sparingly).

## Consequences

- **CI is restored for free** on the public repo; the billing block no longer gates the phase.
- **The moat must be built server-side and in data/brand**, not in client secrecy. This reinforces a
  P2.4 design note: persist Track Record with an eventual **server-sync + per-user identity seam** in
  mind (V1 stays local-only; no backfill needed — the seed fields are already planned).
- **Apache-2.0 permits commercial reuse, including by competitors, with attribution.** Accepted: for
  a niche desktop research tool the realistic cloning risk is low, and the entitlement server +
  accumulated data + brand are the defensible assets.
- **Regulatory posture is load-bearing for pricing:** we price the *tooling*, never *advice*. "How
  our past research outputs scored" is fine; "subscribe for buy signals" is not.
- **Two go-to-market segments** emerge: BYO-key prosumers (subscription) and non-technical users who
  need **hosted runs** (usage-based, the one tier with real inference cost). Don't serve both with a
  single flat price.
- The shared Gemini test key rotation stays a Phase 3 task — it lives only in the gitignored `.env`,
  so going public does not expose it.

## Sources

- GitHub Actions billing for public vs private repositories (free minutes on public repos).
- Pre-flight secret-history audit (this session): literal `.env` never committed; no key patterns or
  current key value in history.
