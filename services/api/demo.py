"""A cost-free synthetic run ("demo" mode).

Streams a realistic multi-agent debate over the *real* SSE pipeline without touching the engine or
any API keys — so the desktop UI can be built, screenshotted, and demoed with zero spend. A real run
(`mode: "pro"`/`"vibe"`) produces the identical event shape; this just fabricates the content.
"""

from __future__ import annotations

import time
from collections.abc import Callable
from typing import Any

from tradingagents.runtime import events as ev
from tradingagents.runtime.events import AgentId, Stage

# (agent, state-section key, sample report) for the four analysts.
_ANALYSTS = [
    (AgentId.MARKET, "market_report",
     "{t} reclaimed its 50-day moving average on rising volume; RSI 58 with room to run and a fresh "
     "MACD bullish crossover. Key support 118, resistance 135."),
    (AgentId.SOCIAL, "sentiment_report",
     "Social sentiment skews bullish (7.4/10). StockTwits mentions +22% w/w and constructive Reddit "
     "threads on the product cycle. Confidence: medium."),
    (AgentId.NEWS, "news_report",
     "Macro backdrop supportive: soft-landing narrative intact, sector tailwinds from new orders, and "
     "no company-specific red flags this week."),
    (AgentId.FUNDAMENTALS, "fundamentals_report",
     "Revenue +18% YoY, gross margin expanding to 71%, free cash flow positive. Valuation is rich "
     "(38x forward) but defensible given growth durability."),
]


def _emit_agent(emit, agent: AgentId, text: str, pace) -> None:
    emit(ev.agent_started(agent))
    pace()
    # A couple of token deltas so the reasoning pane has something to stream.
    head, sep, tail = text.partition(". ")
    emit(ev.token(agent, head + sep))
    pace()
    if tail:
        emit(ev.token(agent, tail))
    emit(ev.agent_done(agent))


def run_demo(
    event_log: Any,
    ticker: str,
    should_cancel: Callable[[], bool],
    *,
    step_delay: float = 0.25,
) -> dict[str, str]:
    """Emit a full synthetic run to ``event_log``; returns a final_state-like dict of sections."""
    t = (ticker or "NVDA").upper()
    emit = event_log.append
    state: dict[str, str] = {}

    def pace() -> None:
        if step_delay:
            time.sleep(step_delay)

    def section(key: str, body: str) -> None:
        state[key] = body
        emit(ev.report_section_done(key, body))

    def stop_here() -> bool:
        return should_cancel()

    def finish(cancelled: bool) -> dict[str, str]:
        decision = state.get("final_trade_decision", "")
        emit(ev.cost(llm_calls=0, tool_calls=0, tokens_in=0, tokens_out=0, est_usd=0.0))
        done = ev.run_done(
            decision or "Run cancelled.",
            rating=None if cancelled else "Buy",
            confidence=None if cancelled else 0.72,
            thesis=None if cancelled else f"{t}'s momentum and durable growth outweigh a rich multiple.",
            structured=None if cancelled else {
                "rating": "Buy", "executive_summary": f"Initiate a starter long in {t}.",
                "investment_thesis": f"{t} pairs improving technicals with accelerating fundamentals.",
                "price_target": 152.0, "time_horizon": "3-6 months",
                "entry_price": 124.0, "stop_loss": 113.0,
            },
        )
        done.data["cancelled"] = cancelled
        emit(done)
        return state

    emit(ev.run_started(t, "2024-05-10", "stock", {"mode": "demo"}))

    # Stage 1 — analysts
    emit(ev.stage_started(Stage.ANALYSTS))
    for agent, key, text in _ANALYSTS:
        if stop_here():
            return finish(cancelled=True)
        body = text.format(t=t)
        _emit_agent(emit, agent, body, pace)
        section(key, body)
        pace()
    emit(ev.stage_done(Stage.ANALYSTS))

    # Stage 2 — research debate (bull vs bear -> manager)
    emit(ev.stage_started(Stage.RESEARCH_DEBATE))
    if stop_here():
        return finish(cancelled=True)
    _emit_agent(emit, AgentId.BULL, f"Bull: {t}'s margin expansion and order backlog support multiple persistence.", pace)
    section("bull", f"The order backlog and 71% gross margin give {t} room to compound through the cycle.")
    _emit_agent(emit, AgentId.BEAR, f"Bear: {t} is priced for perfection; any growth wobble re-rates it lower.", pace)
    section("bear", f"At 38x forward, {t} leaves no margin for error if growth decelerates.")
    _emit_agent(emit, AgentId.RESEARCH_MANAGER, "Manager: the bull case is better supported this quarter.", pace)
    section("investment_plan", f"On balance the bull thesis on {t} is better supported; lean constructive with sizing discipline.")
    emit(ev.stage_done(Stage.RESEARCH_DEBATE))

    # Stage 3 — trader
    emit(ev.stage_started(Stage.TRADER))
    if stop_here():
        return finish(cancelled=True)
    _emit_agent(emit, AgentId.TRADER, f"Trader: starter long {t}, entry ~124, stop 113, target 152.", pace)
    section("trader_investment_plan", f"Buy a starter position in {t}: entry ~124, stop 113, target 152, size 5% of book.")
    emit(ev.stage_done(Stage.TRADER))

    # Stage 4 — risk debate
    emit(ev.stage_started(Stage.RISK_DEBATE))
    if stop_here():
        return finish(cancelled=True)
    _emit_agent(emit, AgentId.AGGRESSIVE, "Aggressive: add on strength; the trend is your friend.", pace)
    section("aggressive", f"Press the {t} long on confirmation above 135; momentum favors continuation.")
    _emit_agent(emit, AgentId.CONSERVATIVE, "Conservative: keep the starter small; valuation is stretched.", pace)
    section("conservative", f"Cap {t} risk at a starter; a stop at 113 bounds the downside.")
    _emit_agent(emit, AgentId.NEUTRAL, "Neutral: the trader's plan is balanced as written.", pace)
    section("neutral", f"The proposed {t} entry/stop/target is a reasonable risk/reward as written.")
    emit(ev.stage_done(Stage.RISK_DEBATE))

    # Stage 5 — portfolio decision
    emit(ev.stage_started(Stage.PORTFOLIO))
    if stop_here():
        return finish(cancelled=True)
    emit(ev.agent_started(AgentId.PORTFOLIO))
    decision = (f"BUY {t} — starter long. Entry ~124, stop 113, target 152, time horizon 3-6 months. "
                f"Momentum and durable growth outweigh a rich multiple.")
    section("final_trade_decision", decision)
    emit(ev.agent_done(AgentId.PORTFOLIO))
    emit(ev.stage_done(Stage.PORTFOLIO))

    return finish(cancelled=False)
