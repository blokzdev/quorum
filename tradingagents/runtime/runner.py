"""TUI-free streaming runner: turn a graph run into a stream of typed events.

This is the canonical extraction of the chunk -> status/section mapping that used to live inline in
``cli/main.py`` (``run_analysis``). Both the Rich CLI and the FastAPI sidecar drive their displays
from the events produced here, so the mapping lives in exactly one place.

The graph is run with ``stream_mode="values"``: each chunk is the *accumulated* state, so we diff
against what we've already emitted to produce incremental events (a section is announced once, when
its content first appears or changes; agent/stage transitions fire once).
"""

from __future__ import annotations

import ast
import logging
import re
from collections.abc import Callable, Iterable
from typing import Any

from tradingagents.runtime import events as ev
from tradingagents.runtime.events import AgentId, Event, Stage

logger = logging.getLogger(__name__)

Emit = Callable[[Event], None]

# Analyst pipeline order and the state field / wire-agent each one maps to.
ANALYST_ORDER: tuple[str, ...] = ("market", "social", "news", "fundamentals")
ANALYST_REPORT_KEY: dict[str, str] = {
    "market": "market_report",
    "social": "sentiment_report",
    "news": "news_report",
    "fundamentals": "fundamentals_report",
}
ANALYST_AGENT: dict[str, AgentId] = {
    "market": AgentId.MARKET,
    "social": AgentId.SOCIAL,
    "news": AgentId.NEWS,
    "fundamentals": AgentId.FUNDAMENTALS,
}

# Report sections backed by a typed Pydantic output, keyed by the ``agent_name`` passed to
# ``invoke_structured_or_freetext`` — so captured JSON can be attached to that section's event.
SECTION_STRUCTURED_AGENT: dict[str, str] = {
    "sentiment_report": "Sentiment Analyst",
    "investment_plan": "Research Manager",
    "trader_investment_plan": "Trader",
    "final_trade_decision": "Portfolio Manager",
}


# --- Pure message helpers (moved verbatim-in-spirit from cli/main.py; no Rich dependency). ---

def extract_content_string(content: Any) -> str | None:
    """Extract a meaningful text string from the many LangChain message content shapes.

    Returns ``None`` when the content is empty or carries no human-readable text (e.g. a bare tool
    invocation), so callers can skip emitting empty token events.
    """

    def is_empty(val: Any) -> bool:
        if val is None or val == "":
            return True
        if isinstance(val, str):
            s = val.strip()
            if not s:
                return True
            try:
                return not bool(ast.literal_eval(s))
            except (ValueError, SyntaxError):
                return False
        return not bool(val)

    if is_empty(content):
        return None
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, dict):
        text = content.get("text", "")
        return text.strip() if not is_empty(text) else None
    if isinstance(content, list):
        parts = [
            item.get("text", "").strip()
            if isinstance(item, dict) and item.get("type") == "text"
            else (item.strip() if isinstance(item, str) else "")
            for item in content
        ]
        result = " ".join(p for p in parts if p and not is_empty(p))
        return result or None
    return str(content).strip() if not is_empty(content) else None


def format_tool_args(args: Any, max_length: int = 80) -> str:
    """Compactly summarize tool-call arguments for display/transport."""
    result = str(args)
    return result[: max_length - 3] + "..." if len(result) > max_length else result


class StreamMapper:
    """Stateful translator: feed it accumulated-state chunks, get incremental events.

    Kept separate from the run loop so it can be unit-tested with synthetic chunks. Holds no graph
    or I/O — purely the bookkeeping that decides which events a chunk implies.
    """

    def __init__(self, selected_analysts: Iterable[str]):
        self.selected = [a.lower() for a in selected_analysts]
        self._status: dict[AgentId, str] = {}          # agent -> pending|in_progress|done
        self._sections: dict[str, str] = {}            # section -> last emitted markdown
        self._stages_started: set[Stage] = set()
        self._stages_done: set[Stage] = set()
        self._seen_message_ids: set[str] = set()
        self._current_agent: AgentId | None = None
        self._debate_turns_emitted = 0                 # P3.3a: count of per-turn debate events already sent
        self._started = False

    # -- status / stage / section transition helpers (each emits only on change) --

    def _agent(self, agent: AgentId, status: str, out: list[Event]) -> None:
        if self._status.get(agent) == status:
            return
        self._status[agent] = status
        if status == "in_progress":
            self._current_agent = agent
            out.append(ev.agent_started(agent))
        elif status == "done":
            out.append(ev.agent_done(agent))

    def _stage_start(self, stage: Stage, out: list[Event]) -> None:
        if stage not in self._stages_started:
            self._stages_started.add(stage)
            out.append(ev.stage_started(stage))

    def _stage_finish(self, stage: Stage, out: list[Event]) -> None:
        if stage not in self._stages_done:
            self._stages_done.add(stage)
            out.append(ev.stage_done(stage))

    def _section(self, section: str, markdown: str | None, out: list[Event]) -> None:
        text = (markdown or "").strip()
        if not text or self._sections.get(section) == text:
            return
        self._sections[section] = text
        out.append(ev.report_section_done(section, text))

    # -- main entry point --

    def process_chunk(self, chunk: dict[str, Any]) -> list[Event]:
        """Return the events implied by this accumulated-state chunk (may be empty)."""
        out: list[Event] = []
        if not self._started:
            self._started = True
            self._stage_start(Stage.ANALYSTS, out)
            for key in self.selected:  # mark the first selected analyst active up-front
                self._agent(ANALYST_AGENT[key], "in_progress", out)
                break

        self._handle_messages(chunk, out)
        self._handle_analysts(chunk, out)
        self._handle_research_debate(chunk, out)
        self._handle_trader(chunk, out)
        self._handle_risk_debate(chunk, out)
        return out

    # -- per-section handlers (mirror cli/main.py run_analysis) --

    def _handle_messages(self, chunk: dict[str, Any], out: list[Event]) -> None:
        for message in chunk.get("messages", []) or []:
            msg_id = getattr(message, "id", None)
            if msg_id is not None:
                if msg_id in self._seen_message_ids:
                    continue
                self._seen_message_ids.add(msg_id)
            content = extract_content_string(getattr(message, "content", None))
            if content:
                agent = self._current_agent.value if self._current_agent else "system"
                out.append(ev.token(agent, content))
            for tc in getattr(message, "tool_calls", None) or []:
                name = tc["name"] if isinstance(tc, dict) else tc.name
                args = tc["args"] if isinstance(tc, dict) else tc.args
                agent = self._current_agent.value if self._current_agent else "system"
                out.append(ev.tool_call(agent, name, format_tool_args(args)))

    def _handle_analysts(self, chunk: dict[str, Any], out: list[Event]) -> None:
        found_active = False
        for key in ANALYST_ORDER:
            if key not in self.selected:
                continue
            agent = ANALYST_AGENT[key]
            report_key = ANALYST_REPORT_KEY[key]
            self._section(report_key, chunk.get(report_key), out)
            if self._sections.get(report_key):
                self._agent(agent, "done", out)
            elif not found_active:
                self._agent(agent, "in_progress", out)
                found_active = True
            # else: leave pending
        # all analysts done -> close the analyst stage and open the debate
        if self.selected and not found_active and all(
            self._status.get(ANALYST_AGENT[k]) == "done" for k in self.selected
        ):
            self._stage_finish(Stage.ANALYSTS, out)
            self._stage_start(Stage.RESEARCH_DEBATE, out)

    def _handle_research_debate(self, chunk: dict[str, Any], out: list[Event]) -> None:
        debate = chunk.get("investment_debate_state")
        if not debate:
            return
        bull = (debate.get("bull_history") or "").strip()
        bear = (debate.get("bear_history") or "").strip()
        judge = (debate.get("judge_decision") or "").strip()
        if bull or bear:
            self._stage_finish(Stage.ANALYSTS, out)
            self._stage_start(Stage.RESEARCH_DEBATE, out)
        if bull:
            self._agent(AgentId.BULL, "in_progress", out)
            self._section("bull", bull, out)
        if bear:
            self._agent(AgentId.BEAR, "in_progress", out)
            self._section("bear", bear, out)
        # P3.3a: decompose the interleaved `history` into per-turn events (in speaking order), emitting
        # only the turns not sent yet so the terminal renders an alternating thread that grows with depth.
        self._emit_new_debate_turns(debate.get("history") or "", out)
        if judge:
            self._section("investment_plan", judge, out)
            self._agent(AgentId.BULL, "done", out)
            self._agent(AgentId.BEAR, "done", out)
            self._agent(AgentId.RESEARCH_MANAGER, "done", out)
            self._stage_finish(Stage.RESEARCH_DEBATE, out)
            self._stage_start(Stage.TRADER, out)
            self._agent(AgentId.TRADER, "in_progress", out)

    #: The per-turn prefix each researcher node prepends to its argument (bull_researcher/bear_researcher),
    #: appended as ``history + "\n" + argument`` — so the prefix is ALWAYS at a line start. Anchoring the
    #: split to ``^`` (MULTILINE) means a body that merely mentions "…the Bear Analyst: said…" mid-line
    #: can't inject a false turn boundary.
    _DEBATE_TURN_RE = re.compile(r"^(Bull Analyst:|Bear Analyst:)\s*", re.MULTILINE)

    @classmethod
    def _split_debate_turns(cls, history: str) -> list[tuple[str, str]]:
        """Split accumulated debate ``history`` into ordered ``(side, markdown)`` turns, ``side`` ∈
        {bull, bear}. Content between two prefixes (may span newlines) is the turn body."""
        matches = list(cls._DEBATE_TURN_RE.finditer(history or ""))
        turns: list[tuple[str, str]] = []
        for i, m in enumerate(matches):
            side = "bull" if m.group(1).startswith("Bull") else "bear"
            end = matches[i + 1].start() if i + 1 < len(matches) else len(history)
            body = history[m.end():end].strip()
            if body:
                turns.append((side, body))
        return turns

    def _emit_new_debate_turns(self, history: str, out: list[Event]) -> None:
        turns = self._split_debate_turns(history)
        for idx in range(self._debate_turns_emitted, len(turns)):
            side, body = turns[idx]
            # Round groups a bull+bear pair (idx 0,1 → round 1; 2,3 → round 2), regardless of who starts.
            out.append(ev.debate_turn(idx // 2 + 1, side, body))
        self._debate_turns_emitted = max(self._debate_turns_emitted, len(turns))

    def _handle_trader(self, chunk: dict[str, Any], out: list[Event]) -> None:
        plan = (chunk.get("trader_investment_plan") or "").strip()
        if not plan:
            return
        self._section("trader_investment_plan", plan, out)
        self._agent(AgentId.TRADER, "done", out)
        self._stage_finish(Stage.TRADER, out)
        self._stage_start(Stage.RISK_DEBATE, out)
        self._agent(AgentId.AGGRESSIVE, "in_progress", out)

    def _handle_risk_debate(self, chunk: dict[str, Any], out: list[Event]) -> None:
        risk = chunk.get("risk_debate_state")
        if not risk:
            return
        agg = (risk.get("aggressive_history") or "").strip()
        con = (risk.get("conservative_history") or "").strip()
        neu = (risk.get("neutral_history") or "").strip()
        judge = (risk.get("judge_decision") or "").strip()
        if agg:
            self._agent(AgentId.AGGRESSIVE, "in_progress", out)
            self._section("aggressive", agg, out)
        if con:
            self._agent(AgentId.CONSERVATIVE, "in_progress", out)
            self._section("conservative", con, out)
        if neu:
            self._agent(AgentId.NEUTRAL, "in_progress", out)
            self._section("neutral", neu, out)
        if judge:
            self._stage_finish(Stage.RISK_DEBATE, out)
            self._stage_start(Stage.PORTFOLIO, out)
            self._agent(AgentId.PORTFOLIO, "in_progress", out)
            self._section("final_trade_decision", judge, out)
            for agent in (AgentId.AGGRESSIVE, AgentId.CONSERVATIVE, AgentId.NEUTRAL, AgentId.PORTFOLIO):
                self._agent(agent, "done", out)
            self._stage_finish(Stage.PORTFOLIO, out)


def run_streaming(
    graph: Any,
    init_state: dict[str, Any],
    args: dict[str, Any],
    emit: Emit,
    *,
    selected_analysts: Iterable[str],
    ticker: str,
    trade_date: str,
    asset_type: str = "stock",
    params: dict[str, Any] | None = None,
    stats_handler: Any | None = None,
    on_chunk: Callable[[dict[str, Any]], None] | None = None,
    should_cancel: Callable[[], bool] | None = None,
) -> dict[str, Any]:
    """Drive ``graph.stream`` and push typed events to ``emit``; return the merged final state.

    ``graph`` is a :class:`tradingagents.graph.trading_graph.TradingAgentsGraph`. ``args`` come from
    ``graph.propagator.get_graph_args(...)``. ``stats_handler`` (a ``StatsCallbackHandler``) is read
    for the cost event; pass the same instance that was bound to the graph's LLMs/tools.

    ``on_chunk`` is an optional escape hatch given the raw accumulated-state chunk after its events
    are emitted — the CLI uses it for its message panel and wall-time tracker without re-implementing
    the state mapping.
    """
    # Lazy import keeps this module importable without pulling the agents package eagerly.
    from tradingagents.agents.utils.structured import capture_structured

    selected = list(selected_analysts)
    mapper = StreamMapper(selected)
    structured: dict[str, dict[str, Any]] = {}  # agent_name -> model_dump JSON

    def _emit(event: Event) -> None:
        # Enrich a finished section with its captured typed output, if any.
        if event.type == ev.EventType.REPORT_SECTION_DONE:
            agent_name = SECTION_STRUCTURED_AGENT.get(event.data.get("section", ""))
            if agent_name and agent_name in structured:
                event.data["structured"] = structured[agent_name]
        emit(event)

    _emit(ev.run_started(ticker, trade_date, asset_type, params or {}))

    trace: list[dict[str, Any]] = []
    cancelled = False
    try:
        with capture_structured(lambda name, data: structured.__setitem__(name, data)):
            for chunk in graph.graph.stream(init_state, **args):
                for event in mapper.process_chunk(chunk):
                    _emit(event)
                if on_chunk is not None:
                    on_chunk(chunk)
                trace.append(chunk)
                # Cooperative cancellation: we can only stop between nodes, never mid-LLM-call.
                if should_cancel is not None and should_cancel():
                    cancelled = True
                    break
    except Exception as exc:  # surface engine failures as a terminal event, then re-raise
        _emit(ev.error("graph.stream", str(exc)))
        raise

    final_state: dict[str, Any] = {}
    for chunk in trace:
        final_state.update(chunk)

    if stats_handler is not None:
        try:
            s = stats_handler.get_stats()
            _emit(ev.cost(s.get("llm_calls", 0), s.get("tool_calls", 0),
                          s.get("tokens_in", 0), s.get("tokens_out", 0)))
        except Exception:  # cost is best-effort; never fail a run over telemetry
            logger.debug("cost event skipped: stats handler unavailable", exc_info=True)

    decision = final_state.get("final_trade_decision", "")
    rating = None
    try:
        rating = graph.process_signal(decision) if decision else None
    except Exception:
        logger.debug("rating extraction failed", exc_info=True)
    pm = structured.get("Portfolio Manager") or {}
    done_event = ev.run_done(
        decision,
        rating=rating or pm.get("rating"),
        thesis=pm.get("investment_thesis") or pm.get("executive_summary"),
        structured=pm or None,
    )
    done_event.data["cancelled"] = cancelled
    _emit(done_event)
    return final_state
