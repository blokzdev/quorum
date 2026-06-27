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
