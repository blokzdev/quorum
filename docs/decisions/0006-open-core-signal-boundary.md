# ADR 0006 — Open-core signal boundary: BYO-key raw is free, hosted-curated is paid

- **Status:** Accepted (2026-07-05) — plan-lock for Phase 3
- **Context:** Phase 3 ([phase-3-plan.md](../phase-3-plan.md)) surfaces the engine's data vendors (incl.
  FRED / Polymarket — signature bet #3's raw ingredients) in the desktop app, which forces a monetization
  boundary. Builds on the open-core model in [ADR 0003](0003-open-source-and-open-core-monetization.md).
- **Deciders:** ganesh (founder) + product/desktop track.

## Context

The TradingAgents engine already computes macro (FRED) and prediction-market (Polymarket) signals locally,
per run, from raw vendor data — and Quorum's per-job key injection (`isolation.py:_VENDOR_API_KEY_ENV`)
already supports vendor keys the same way it supports LLM keys. So Phase 3 *could* drop the full signal
capability into the free local client. But the roadmap earmarks the **signal layer** (and Track Record sync
+ hosted runs) as the **paid** server-side value — the open-core moat. Surfacing raw FRED/Polymarket in the
free client risks giving that moat away; hiding it entirely leaves a signature bet dark in the free product.

## Decision

Draw the line at **raw-vs-curated**, not at the data source:

- **Free (open, local client):** raw data vendors computed **locally with the user's own key** —
  yfinance (keyless), Alpha Vantage / FRED (the user's own free-tier key), Polymarket (keyless), StockTwits /
  Reddit. This is *engine power the user already owns*, identical in kind to the BYO LLM keys ([ADR 0001](0001-byo-api-key-storage.md)):
  keys are injected per-run and **never persisted server-side**. Phase 3 (P3.1) surfaces this.
- **Paid (server-side, behind entitlement):** the **hosted, curated, aggregated, and synced signal
  intelligence** — Quorum-computed signals with no key required, cross-run/cross-device Track Record sync,
  hosted runs, and any proprietary signal enrichment. **Not designed or built in Phase 3.**

The distinction: the free client lets you *bring your own raw feed*; the paid tier is the *managed
intelligence on top* (curation, aggregation, no-key convenience, sync, history).

## Consequences

- **+** Phase 3 can honestly deliver "tap the full engine power" (BYO-key FRED/Polymarket) without eroding
  Phase-4+ revenue. Consistent with the existing BYO-LLM-key posture — no new trust/persistence model.
- **+** A clear, defensible line for future contributors: "does this require the user's own key and run
  locally?" → free; "is this hosted/curated/synced value?" → paid.
- **−** The free product's signal experience depends on the user having their own vendor keys (free tier,
  but a setup step). The paid tier's value proposition must be the *curation + convenience + sync*, not mere
  access to the data — a real bar for the paid layer to clear.
- Price the **tooling/curation/convenience**, never *advice* (regulatory posture, unchanged).

## Alternatives considered

- **Keep the whole signal layer paid** (don't surface FRED/Polymarket in the free client). Rejected: leaves
  a signature bet entirely dark in the free product and wastes engine capability the user could run themselves.
- **Build the full signal layer free now.** Rejected: gives away a designated paid moat with no monetization
  rethink — the founder explicitly chose against this.
