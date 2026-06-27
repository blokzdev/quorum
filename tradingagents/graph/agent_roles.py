"""Frozen Dream-Team role roster: the 12 user-assignable agent roles → their graph node name.

Single source of truth shared by the engine (per-role model routing in ``trading_graph`` /
``setup``) and the sidecar run manifest, so the desktop's role keys and the engine's node names can
never drift. The node names here MUST match the exact strings passed to ``workflow.add_node`` in
``setup.py`` (a roster-integrity test asserts this).

Excludes ``reflector`` + ``signal_processor``: ``signal_processor`` no longer makes an LLM call (its
rating parse is deterministic) and ``reflector`` is out-of-band Track-Record machinery invoked between
runs, not a debate participant.
"""

from __future__ import annotations

from typing import Any

# role_key (wire / UI) -> graph node name (the string passed to workflow.add_node in setup.py).
ROLE_TO_NODE: dict[str, str] = {
    "market_analyst": "Market Analyst",
    "social_analyst": "Sentiment Analyst",  # wire selection key is "social"; node label is "Sentiment Analyst"
    "news_analyst": "News Analyst",
    "fundamentals_analyst": "Fundamentals Analyst",
    "bull_researcher": "Bull Researcher",
    "bear_researcher": "Bear Researcher",
    "research_manager": "Research Manager",
    "trader": "Trader",
    "aggressive_analyst": "Aggressive Analyst",
    "neutral_analyst": "Neutral Analyst",
    "conservative_analyst": "Conservative Analyst",
    "portfolio_manager": "Portfolio Manager",
}

# The two judge roles that default to the DEEP client today; every other role defaults to quick. This
# is documentation of the existing setup.py tiering (the actual fallback lives in GraphSetup) — useful
# for resolving the *effective* model of an unset role when recording manifest provenance (P2.5b).
DEEP_ROLES: frozenset[str] = frozenset({"research_manager", "portfolio_manager"})

ROLE_KEYS: tuple[str, ...] = tuple(ROLE_TO_NODE)


def resolve_agent_models(
    overrides: dict[str, dict[str, Any]] | None,
    config: dict[str, Any],
) -> dict[str, dict[str, Any]]:
    """The **effective** ``{provider, model[, effort]}`` for each of the 12 roles after fallback —
    self-describing provenance the manifest records (the Hub "cast list" + Track Record).

    An overridden role records its spec; an unset role records the global provider + the quick/deep
    model that actually ran it (``deep_think_llm`` for the two judge roles, else ``quick_think_llm``).
    """
    overrides = overrides or {}
    global_provider = config.get("llm_provider")
    deep_model = config.get("deep_think_llm")
    quick_model = config.get("quick_think_llm")
    resolved: dict[str, dict[str, Any]] = {}
    for role_key in ROLE_TO_NODE:
        spec = overrides.get(role_key)
        if isinstance(spec, dict) and spec.get("provider") and spec.get("model"):
            entry = {"provider": spec["provider"], "model": spec["model"]}
            if spec.get("effort"):
                entry["effort"] = spec["effort"]
            resolved[role_key] = entry
        else:
            resolved[role_key] = {
                "provider": global_provider,
                "model": deep_model if role_key in DEEP_ROLES else quick_model,
            }
    return resolved
