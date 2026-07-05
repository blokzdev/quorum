# Quorum — monetization (one-page spec)

> Strategy doc, not a commitment to ship. Pricing numbers are starting anchors to validate, not
> final. Decision record: [ADR 0003](decisions/0003-open-source-and-open-core-monetization.md).

## The sentence

> **Quorum is for the self-directed retail/prosumer investor who wants a structured second opinion
> before a trade. They pay ~$15–20/month because Quorum runs a multi-agent bull/bear/risk debate on
> their ticker *and* keeps a track record of how its past calls performed — something raw ChatGPT
> can't give them and they can't easily build themselves.**

## Model: open-core, freemium → subscription

The local client is open-source and free; paid value lives behind a server we operate (auth +
entitlement). The key economic fact is **BYO-key → ~zero marginal cost**, so the free tier is cheap
to run and the free-vs-paid split is about *compounding value and our infrastructure*, not API cost.

### Free — the open-source desktop app
- Run analyses with your own provider keys (keys stay local).
- Demo mode (cost-free synthetic run), basic Model Studio (provider / quick+deep / effort).
- Local run history.
- **Purpose:** distribution engine + the verifiable "your keys never leave your machine" trust proof.

### Quorum Pro — ~$15–20/mo or ~$150–180/yr
The features that compound or need *our* infrastructure:
- **Track Record** scorecard — realized hit-rate / alpha of past verdicts, **synced across devices**.
  This is the anchor: it accumulates with use and is lost on switching.
- **Cloud sync + mobile remote** — run on desktop, review on phone (our relay; a legit recurring cost).
- **Dream Team** — per-agent model assignment.
- **Signal layer** — FRED macro + Polymarket, plumbing we maintain.
- Watchlists / alerts; priority model-catalog updates.

### Hosted runs — usage-based (later)
For non-technical users who won't manage API keys: we run the engine in our cloud and charge credits.
This is the **only** tier with real inference cost, so it must be **usage-based with margin**, not
flat. It's also the path to the market beyond the narrow BYO-key crowd.

## Two segments, two motions
- **BYO-key prosumers** → flat subscription (Pro). Technical, already pay providers per token.
- **Non-technical retail** → hosted runs, usage-based credits. The bigger but costlier market.

Don't try to serve both with one flat price.

## What we explicitly do NOT do
- **No one-time closed-binary sale** as the primary model — the value accumulates; recurring captures it.
- **No selling "advice" or "signals."** We price the *tooling*. Regulatory line is load-bearing:
  "how our past research outputs scored" is fine; "subscribe for buy signals" makes us look like an
  unregistered investment adviser. Quorum stays research/educational, you decide.
- **No restrictive client license** (see ADR 0003) — the moat is the server + data + brand.

## Moat (memory-as-moat)
**Track Record** is the keystone: every run compounds into the user's own scorecard, which they lose
by switching to a competitor or a raw LLM. Protect and prioritize it. It is already a planned
signature bet, and P2.4's persistence seeds its fields with no backfill required.

## Honest risks
1. **Distribution, not the model, is the real risk.** Desktop + "trading research" is a hard
   discovery surface. Open-sourcing helps (HN / GitHub trending / r/algotrading / fintwit /
   Product Hunt). Pick ~2 channels, not 10.
2. **Regulatory.** Keep the not-financial-advice posture explicit in product and pricing.
3. **BYO-key segment is narrow** (technical users). Hosted runs are how the larger market is reached.

## Architecture implication (for the build)
Persist Track Record data (verdict / date / entry-price context / model) with an eventual
**server-sync + per-user identity seam** in mind, even though V1 is local-only. This is a framing
note for P2.4's `run.json` manifest design — not added scope.
