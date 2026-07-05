# ADR 0004 — Per-agent model routing ("Dream Team")

- **Status:** Accepted (2026-06-27) — plan-lock for P2.5
- **Context:** Phase 2 P2.5 ([phase-2-plan.md](../phase-2-plan.md#p25--dream-team-per-agent-model-assignment-signature-bet-needs-engine-work)); a signature product bet.
- **Deciders:** Quorum engine + desktop tracks
- **Validation:** planning workflow (engine + contract recon, web research, 3 adversarial critics — all "sound-with-fixes"); the fixes are folded in below.

## Context

Today a run uses **one** LLM provider and a shared **quick/deep** split: `trading_graph.py` builds
two clients (`quick_thinking_llm`, `deep_thinking_llm`) and `GraphSetup` hands each of the **12 agent
roles** either the quick or the deep client (only the two judges — Research Manager and Portfolio
Manager — get deep; the other 10 get quick). "Dream Team" lets the user assign a **different model,
from a different provider, to each role** — e.g. Opus on the Portfolio Manager, Grok on the Bull,
local Ollama on the analysts.

Two facts make this feasible **additively** (verified first-hand):
- `llm_clients.factory.create_llm_client(provider, model, base_url, **kwargs)` takes the provider
  **per call**, so multiple different-provider clients can be built in one run.
- `runtime.isolation.JobIsolationContext` injects **all** keys from the run's `api_keys` map into
  `os.environ` before graph construction (`build_api_keys_dict` maps `{provider: key}` → `{ENV: key}`),
  and each provider reads its own env var. So one run can carry keys for several providers at once —
  **the engine side needs no key-handling change.** Jobs are serialized (no in-process concurrency).

Web research frames the bet: a **heterogeneous team (cheap "workers" + a strong "judge/aggregator")**
is the canonical, cost-positive pattern (≈98% of all-frontier quality at ~half the cost in on-domain
multi-agent studies), and it maps exactly onto the engine's existing quick/deep topology. Dream Team
is **static per-role routing**, *not* a confidence-based cascade — so it adds **no latency**. The
dominant risk is **capability variance**: tool-calling and structured-output support differ by
model/provider and fail **silently downstream**, so a capability gate is load-bearing.

## Decision

**Route per role via an additive per-role client resolver in the engine, fed by a structured
`agent_models` map that threads UI → RunConfig → RunRequest → config → graph; unset roles fall back to
today's quick/deep client (byte-for-byte unchanged).**

### Wire contract (additive)

A new optional top-level field on `POST /runs` / `RunConfig` / `RunSummary` / `SettingsState`+`Bench`:

```jsonc
"agent_models": {
  "portfolio_manager": { "provider": "anthropic", "model": "claude-opus-4-8", "effort": "high" },
  "bull_researcher":   { "provider": "xai",       "model": "grok-..." },
  "market_analyst":    { "provider": "ollama", "model": "llama3.2:latest",
                         "backend_url": "http://127.0.0.1:11434/v1" }
  // roles omitted → fall back to quick/deep, exactly as today
}
```

A **structured object** per role (`provider`, `model`, optional `backend_url`, optional `effort`) —
not a flat `"provider:model"` string — because `backend_url` and `effort` are inseparable from a model
choice here, and the object stays additively extensible. Inner type on the wire is permissive
(`dict[str, dict[str, Any]]`) so a future field never 422s the request.

### Role roster (frozen)

A new `tradingagents/graph/agent_roles.py` defines a **frozen `ROLE_TO_NODE`** of exactly **12 visible
roles** (market/social/news/fundamentals analysts; bull/bear researchers; research_manager; trader;
aggressive/neutral/conservative; portfolio_manager), imported by both `setup.py` and the manifest so
the UI ↔ engine role keys can never drift. `reflector` and `signal_processor` are **excluded**:
`signal_processor` no longer makes an LLM call (deterministic `parse_rating`), and `reflector` is
out-of-band Track-Record machinery, not a debate participant.

### Engine routing (the only frozen-package change — additive, 2 files + 1 new file)

- `trading_graph.py`: build quick/deep as today, plus a `_resolve_role_llm(role_key)` that returns the
  per-role client (memoized in a cache keyed on `(provider, model, base_url, effort)`) or the quick/deep
  fallback. Per-role effort is dispatched off **the role's own provider** (a per-role `_role_kwargs`
  mirroring `_get_provider_kwargs`); the shared `callbacks` are threaded into every per-role client.
- `setup.py`: `GraphSetup` gains an optional `role_llms=None` kwarg (keyword-defaulted → byte-compatible
  with upstream's positional call); each `create_*()` resolves `role_llms.get(node) or <quick|deep>`.
- **`base_url` fix:** a per-role client falls back to the global `config["backend_url"]` **only when the
  role's provider equals the global `llm_provider`**; otherwise `base_url=None` (provider-registry
  default), so a cloud role never inherits a global local-Ollama endpoint. (This is in the cache key.)

### Capability gating (the load-bearing correctness piece)

`market`/`news`/`fundamentals` **hard-require tool-calling** (they `bind_tools` and loop on tool calls);
a non-tool model there produces a silently empty/hallucinated report (no crash). `bind_tools` does not
raise, so the only defense is a **catalog tool-capable flag** the UI reads to **block** those three
slots for non-tool models. The four structured-output roles (`social`, `research_manager`, `trader`,
`portfolio_manager`) **degrade gracefully** to free text (`bind_structured`/`invoke_structured_or_freetext`
catch and fall back) → the UI **warns** (does not block); the Portfolio Manager warning notes that a
degraded free-text verdict can weaken `parse_rating`'s BUY/HOLD/SELL extraction (the Track Record seed).
The flag lives in a **new Quorum-side annotation**, **not** in `MODEL_OPTIONS` (whose `(label, value)`
tuple shape and `/catalog/providers` contract must stay additive/upstream-mergeable); `supports_tool_calling`
on `ModelCapabilities` is the engine-side backstop.

### Desktop: multi-provider keys + provenance

- `SettingsController.buildLaunchConfig` must merge OS-vault keys for **every provider referenced** across
  the per-role map (∪ the global provider), not just the one chosen provider.
- A **pre-launch gate** diffs the referenced providers against the vault and surfaces a consolidated
  "needs keys for: X, Y" before `POST /runs` — never a mid-run, post-spend auth failure.
- **Provenance:** `plan_run` computes the **resolved** per-role map (effective `{provider, model}` after
  fallback, for all 12 roles) into `params`; `_manifest_dict` (the actual manifest builder — **not**
  `_persist`) emits an `agent_models` field; `RunSummary.fromJson` reads it (null on old manifests).
  The Hub/verdict rail shows a post-run "cast list" (which model played which role).
- `agentModels` rides on `RunConfig`, `Bench`, and `SettingsState` — **three** independent
  toJson/fromJson pairs, plus `toBench`/`applyBench` and `withProvider` (which must **not** clear it).

## Alternatives considered

- **Flat `"provider:model"` string per role** — rejected: no room for `backend_url`/`effort`, fragile
  delimiter against model IDs containing `:`/`-`.
- **A resolver callable into GraphSetup** (vs a node-keyed `role_llms` dict) — the dict keeps GraphSetup
  a passive consumer and is byte-compatible with upstream's positional ctor; chosen.
- **Per-role effort UI control in V1** — deferred: effort is naturally per-*provider* (only Google models
  read `thinking_level`, etc.); V1 drives per-role effort from the existing per-provider knobs and ships
  `spec.effort` dormant (forward-compatible).
- **Auto-escalation / model cascade** (try cheap, escalate on low confidence) — rejected: adds latency,
  and self-reported confidence is poorly calibrated. Dream Team stays **explicit static assignment**.
- **Mutating `MODEL_OPTIONS` to carry the tool-capable flag** — rejected: breaks the `/catalog` tuple
  contract + upstream-mergeability. The flag lives Quorum-side.

## Consequences

- **Additive + upstream-mergeable:** with `agent_models` unset, the graph is constructed identically
  (same two clients, same bindings) — quick/deep runs and goldens stay byte-identical. Engine edits are
  confined to `trading_graph.py`, `setup.py`, a new `agent_roles.py`, and an additive `capabilities`
  field; `create_llm_client` is called exactly as upstream calls it, just N times.
- **The real work is the capability gate + multi-provider key UX, not the routing** (~20 lines). A
  non-tool model on a tool-analyst role is a silent footgun without the gate.
- **Cost provenance:** per-role clients must share the run's `callbacks` so a future cost seed counts all
  roles (callbacks aren't wired into the sidecar path *today*, so the V1 test asserts "per-role clients
  receive the same callbacks object," not a cost-accounting effect).
- **P2.5c is split** (roster UI vs capability/key gate) — see the plan doc. The capability-data work is
  scheduled in P2.5a/b (the UI gate is untestable until the flag exists end-to-end).
- **Validation:** hybrid run (local Ollama on the debaters/analyst-where-tool-capable + a cloud judge),
  the additivity golden (empty map → identical wiring), roster-integrity test (every `ROLE_TO_NODE` node
  is a real `add_node` string — guards the `social`/"Sentiment Analyst" rename trap), and three
  round-trip tests (RunConfig/Bench/SettingsState).

## Sources

- Engine recon: `tradingagents/graph/{trading_graph,setup}.py`, `agents/*`, `llm_clients/{factory,openai_client,capabilities,structured}.py`, `runtime/isolation.py`.
- Mixture-of-Agents / hierarchical supervisor-worker cost-quality (cheap workers + strong judge): ICLR 2025 MoA; on-domain financial multi-agent benchmark.
- Routing vs cascades (no latency for static routing; provider-dependency + calibration pitfalls): tianpan.co LLM routing notes.
- Structured-output / tool-calling provider variance: agenta.ai structured-outputs guide.
- Per-agent-model UX (per-node model picker gated to credentialed providers; muted-fallback defaults; presets; BYOK per-provider key cards): CrewAI, Flowise AgentFlow V2, Langflow, ui-patterns Good Defaults, AirOps BYOK.
