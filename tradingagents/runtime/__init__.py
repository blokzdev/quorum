"""Quorum runtime: a TUI-free, transport-agnostic layer over the TradingAgents graph.

This package turns a graph run into a stream of typed :class:`~tradingagents.runtime.events.Event`
objects and provides per-job config/credential isolation, so the same engine can be driven by the
Rich CLI, a FastAPI sidecar, or any other consumer without dragging in Rich/questionary/FastAPI.

It is intentionally dependency-light (standard library only) so it imports cleanly in any context.
"""

from tradingagents.runtime.events import (
    CONTRACT_VERSION,
    AgentId,
    Event,
    EventType,
    Stage,
)

__all__ = [
    "CONTRACT_VERSION",
    "AgentId",
    "Event",
    "EventType",
    "Stage",
]
