"""The Quorum streaming event contract (``contract_version = 1``).

A graph run is exposed to clients (the Flutter desktop UI now, a mobile remote later) as an ordered
stream of :class:`Event` objects. Every event is JSON-serializable and carries a monotonic ``seq`` so
a reconnecting client can resume from a ``Last-Event-ID`` without gaps. The same objects are emitted
by the CLI and the FastAPI sidecar — this module is the single source of truth for their shape.

Design notes:
- One ``Event`` dataclass with a ``data`` payload dict (rather than a class per event type) keeps the
  SSE/serialization layer uniform; the module-level builder functions give type-safe construction.
- ``seq``/``run_id``/``ts`` are stamped by the emitter (see :mod:`tradingagents.runtime.runner` and the
  sidecar's event log), so builders leave ``seq = -1`` until then.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any

#: Bumped when the wire format changes in a backward-incompatible way. Clients negotiate on it.
CONTRACT_VERSION = 1


class EventType(str, Enum):
    """The closed set of streamed event types. ``str`` mixin → JSON-serializes as its value."""

    RUN_STARTED = "run_started"
    STAGE_STARTED = "stage_started"
    STAGE_DONE = "stage_done"
    AGENT_STARTED = "agent_started"
    AGENT_DONE = "agent_done"
    TOKEN = "token"
    TOOL_CALL = "tool_call"
    REPORT_SECTION_DONE = "report_section_done"
    COST = "cost"
    RUN_DONE = "run_done"
    ERROR = "error"
    HEARTBEAT = "heartbeat"


class Stage(str, Enum):
    """The five pipeline phases, in execution order. Used by ``stage_started``/``stage_done``."""

    ANALYSTS = "analysts"
    RESEARCH_DEBATE = "research_debate"
    TRADER = "trader"
    RISK_DEBATE = "risk_debate"
    PORTFOLIO = "portfolio"


class AgentId(str, Enum):
    """Stable agent identifiers used by ``agent_started``/``agent_done`` and ``token``/``tool_call``.

    These are the wire identifiers (snake_case, stable across releases); human-facing display names
    live in the UI layer, not here.
    """

    MARKET = "market"
    SOCIAL = "social"
    NEWS = "news"
    FUNDAMENTALS = "fundamentals"
    BULL = "bull"
    BEAR = "bear"
    RESEARCH_MANAGER = "research_manager"
    TRADER = "trader"
    AGGRESSIVE = "aggressive"
    NEUTRAL = "neutral"
    CONSERVATIVE = "conservative"
    PORTFOLIO = "portfolio"


@dataclass
class Event:
    """A single streamed event.

    ``seq`` is ``-1`` until an emitter/event-log assigns a monotonic value; ``run_id`` and ``ts`` are
    likewise stamped by the emitter (``ts`` defaults to creation time for standalone use/tests).
    """

    type: EventType
    data: dict[str, Any] = field(default_factory=dict)
    seq: int = -1
    run_id: str | None = None
    ts: float = field(default_factory=time.time)

    def to_dict(self) -> dict[str, Any]:
        """JSON-serializable form. ``type`` is rendered as its string value."""
        return {
            "type": self.type.value,
            "seq": self.seq,
            "run_id": self.run_id,
            "ts": self.ts,
            "data": self.data,
        }


# --- Builder functions: type-safe construction; emitter stamps seq/run_id later. ---

def run_started(ticker: str, trade_date: str, asset_type: str, params: dict[str, Any]) -> Event:
    return Event(EventType.RUN_STARTED, {
        "ticker": ticker, "trade_date": trade_date, "asset_type": asset_type,
        "params": params, "contract_version": CONTRACT_VERSION,
    })


def stage_started(stage: Stage) -> Event:
    return Event(EventType.STAGE_STARTED, {"stage": stage.value})


def stage_done(stage: Stage) -> Event:
    return Event(EventType.STAGE_DONE, {"stage": stage.value})


def agent_started(agent: AgentId) -> Event:
    return Event(EventType.AGENT_STARTED, {"agent": agent.value})


def agent_done(agent: AgentId, *, confidence: float | None = None) -> Event:
    data: dict[str, Any] = {"agent": agent.value}
    if confidence is not None:
        data["confidence"] = confidence
    return Event(EventType.AGENT_DONE, data)


def token(agent: AgentId | str, delta: str) -> Event:
    agent_value = agent.value if isinstance(agent, AgentId) else agent
    return Event(EventType.TOKEN, {"agent": agent_value, "delta": delta})


def tool_call(agent: AgentId | str, tool: str, args_summary: str, status: str = "running") -> Event:
    agent_value = agent.value if isinstance(agent, AgentId) else agent
    return Event(EventType.TOOL_CALL, {
        "agent": agent_value, "tool": tool, "args_summary": args_summary, "status": status,
    })


def report_section_done(section: str, markdown: str, structured: dict[str, Any] | None = None) -> Event:
    return Event(EventType.REPORT_SECTION_DONE, {
        "section": section, "markdown": markdown, "structured": structured,
    })


def cost(llm_calls: int, tool_calls: int, tokens_in: int, tokens_out: int,
         est_usd: float | None = None) -> Event:
    return Event(EventType.COST, {
        "llm_calls": llm_calls, "tool_calls": tool_calls,
        "tokens_in": tokens_in, "tokens_out": tokens_out, "est_usd": est_usd,
    })


def run_done(final_decision: str, *, rating: str | None = None, confidence: float | None = None,
             thesis: str | None = None, structured: dict[str, Any] | None = None) -> Event:
    return Event(EventType.RUN_DONE, {
        "final_decision": final_decision, "rating": rating, "confidence": confidence,
        "thesis": thesis, "structured": structured,
    })


def error(where: str, message: str, *, recoverable: bool = False) -> Event:
    return Event(EventType.ERROR, {"where": where, "message": message, "recoverable": recoverable})


def heartbeat() -> Event:
    return Event(EventType.HEARTBEAT, {})
