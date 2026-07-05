"""Unit tests for the TUI-free streaming runtime (tradingagents.runtime).

Drives the StreamMapper with synthetic accumulated-state chunks (stream_mode="values" shape) and
asserts the event contract: sections announced once, agent/stage transitions fire in order, and a
fake graph run emits run_started first and run_done last.
"""

import pytest

from tradingagents.runtime import events as ev
from tradingagents.runtime.events import AgentId, EventType, Stage
from tradingagents.runtime.runner import StreamMapper, extract_content_string, run_streaming

pytestmark = pytest.mark.unit


def _sections(events, etype=EventType.REPORT_SECTION_DONE):
    return [e.data["section"] for e in events if e.type == etype]


def _types(events):
    return [e.type for e in events]


def _run_mapper(chunks, selected=("market", "social")):
    mapper = StreamMapper(selected)
    all_events = []
    for chunk in chunks:
        all_events.extend(mapper.process_chunk(chunk))
    return all_events


FULL_RUN_CHUNKS = [
    {},
    {"market_report": "MKT"},
    {"market_report": "MKT", "sentiment_report": "SENT"},
    {"market_report": "MKT", "sentiment_report": "SENT",
     "investment_debate_state": {"bull_history": "BULL", "bear_history": "", "judge_decision": ""}},
    {"market_report": "MKT", "sentiment_report": "SENT",
     "investment_debate_state": {"bull_history": "BULL", "bear_history": "BEAR", "judge_decision": "PLAN"}},
    {"trader_investment_plan": "TRADE"},
    {"risk_debate_state": {"aggressive_history": "AGG", "conservative_history": "CON",
                           "neutral_history": "NEU", "judge_decision": "DECISION"},
     # The portfolio_manager node mirrors its decision into the top-level field too.
     "final_trade_decision": "DECISION"},
]


def test_full_run_emits_all_canonical_sections_once():
    events = _run_mapper(FULL_RUN_CHUNKS)
    sections = _sections(events)
    expected = {
        "market_report", "sentiment_report", "bull", "bear", "investment_plan",
        "trader_investment_plan", "aggressive", "conservative", "neutral", "final_trade_decision",
    }
    assert expected.issubset(set(sections))
    # Each section announced exactly once (content was stable across chunks).
    for section in expected:
        assert sections.count(section) == 1, f"{section} emitted {sections.count(section)} times"


def test_all_stages_open_and_close_in_order():
    events = _run_mapper(FULL_RUN_CHUNKS)
    started = [e.data["stage"] for e in events if e.type == EventType.STAGE_STARTED]
    done = [e.data["stage"] for e in events if e.type == EventType.STAGE_DONE]
    order = [s.value for s in (Stage.ANALYSTS, Stage.RESEARCH_DEBATE, Stage.TRADER,
                               Stage.RISK_DEBATE, Stage.PORTFOLIO)]
    assert started == order
    assert done == order


def test_agent_lifecycle_started_then_done():
    events = _run_mapper(FULL_RUN_CHUNKS)
    started = [e.data["agent"] for e in events if e.type == EventType.AGENT_STARTED]
    done = [e.data["agent"] for e in events if e.type == EventType.AGENT_DONE]
    for agent in (AgentId.MARKET, AgentId.SOCIAL, AgentId.PORTFOLIO, AgentId.TRADER):
        assert agent.value in started
        assert agent.value in done
    # market must start before it finishes
    assert started.index("market") <= done.index("market")


def _debate_turns(events):
    return [e for e in events if e.type == EventType.DEBATE_TURN]


def test_debate_history_decomposed_into_ordered_turns():
    # P3.3a: the interleaved `history` (each turn prefixed 'Bull/Bear Analyst:') splits into per-turn
    # events in speaking order; a bull+bear pair shares a round (idx 0,1 -> round 1; 2,3 -> round 2).
    history = ("\nBull Analyst: bull round one"
               "\nBear Analyst: bear round one"
               "\nBull Analyst: bull round two"
               "\nBear Analyst: bear round two")
    events = _run_mapper([
        {"investment_debate_state": {"bull_history": "b", "bear_history": "r", "history": history,
                                     "judge_decision": ""}},
    ], selected=("market",))
    turns = _debate_turns(events)
    assert [t.data["side"] for t in turns] == ["bull", "bear", "bull", "bear"]
    assert [t.data["round"] for t in turns] == [1, 1, 2, 2]
    assert turns[0].data["markdown"] == "bull round one"
    assert turns[-1].data["markdown"] == "bear round two"  # multi-line-safe body extraction


def test_debate_turns_emitted_incrementally_across_chunks():
    # Each streamed chunk carries the FULL accumulated history; only the NEW turns are emitted.
    mapper = StreamMapper(["market"])
    e1 = _debate_turns(mapper.process_chunk(
        {"investment_debate_state": {"bull_history": "x", "history": "\nBull Analyst: one"}}))
    e2 = _debate_turns(mapper.process_chunk(
        {"investment_debate_state": {"bull_history": "x",
                                     "history": "\nBull Analyst: one\nBear Analyst: two"}}))
    assert len(e1) == 1 and e1[0].data["side"] == "bull"
    assert len(e2) == 1 and e2[0].data["side"] == "bear"  # only the newly-added turn, no re-emit


def test_debate_turn_count_scales_with_debate_rounds():
    # depth-1 (1 round = 2 turns) vs depth-3 (3 rounds = 6 turns) — count scales with max_debate_rounds.
    def turns_for(rounds):
        history = "".join(f"\nBull Analyst: b{r}\nBear Analyst: r{r}" for r in range(rounds))
        return _debate_turns(_run_mapper(
            [{"investment_debate_state": {"bull_history": "x", "history": history}}], selected=("market",)))

    assert len(turns_for(1)) == 2
    assert len(turns_for(3)) == 6


def test_unchanged_section_not_re_emitted():
    mapper = StreamMapper(["market"])
    first = mapper.process_chunk({"market_report": "SAME"})
    second = mapper.process_chunk({"market_report": "SAME"})
    assert "market_report" in _sections(first)
    assert "market_report" not in _sections(second)


def test_changed_section_re_emitted():
    mapper = StreamMapper(["market"])
    mapper.process_chunk({"market_report": "v1"})
    second = mapper.process_chunk({"market_report": "v1 plus more"})
    assert "market_report" in _sections(second)


class _FakeMessage:
    def __init__(self, id_, content, tool_calls=None):
        self.id = id_
        self.content = content
        self.tool_calls = tool_calls or []


def test_messages_become_token_and_tool_events_deduped():
    mapper = StreamMapper(["market"])
    msg = _FakeMessage("m1", "thinking out loud",
                       tool_calls=[{"name": "get_stock_data", "args": {"ticker": "SPY"}}])
    e1 = mapper.process_chunk({"messages": [msg]})
    assert any(e.type == EventType.TOKEN and e.data["delta"] == "thinking out loud" for e in e1)
    assert any(e.type == EventType.TOOL_CALL and e.data["tool"] == "get_stock_data" for e in e1)
    # Same message id on the next chunk is not re-emitted.
    e2 = mapper.process_chunk({"messages": [msg]})
    assert not any(e.type == EventType.TOKEN for e in e2)


@pytest.mark.parametrize("content,expected", [
    ("hello", "hello"),
    ("  spaced  ", "spaced"),
    ("", None),
    ([{"type": "text", "text": "a"}, {"type": "text", "text": "b"}], "a b"),
    ({"text": "boxed"}, "boxed"),
    (None, None),
])
def test_extract_content_string(content, expected):
    assert extract_content_string(content) == expected


class _FakeGraphInner:
    def __init__(self, chunks):
        self._chunks = chunks

    def stream(self, init_state, **kwargs):
        yield from self._chunks


class _FakeGraph:
    def __init__(self, chunks):
        self.graph = _FakeGraphInner(chunks)

    def process_signal(self, decision):
        return "Buy" if decision else "Hold"


def test_run_streaming_brackets_with_run_started_and_run_done():
    emitted = []
    graph = _FakeGraph(FULL_RUN_CHUNKS)
    final = run_streaming(
        graph, {}, {}, emitted.append,
        selected_analysts=["market", "social"],
        ticker="SPY", trade_date="2026-06-26",
    )
    assert emitted[0].type == EventType.RUN_STARTED
    assert emitted[-1].type == EventType.RUN_DONE
    assert emitted[-1].data["rating"] == "Buy"
    assert final["final_trade_decision"] == "DECISION"


def test_run_streaming_emits_error_event_then_raises():
    class _Boom:
        def stream(self, *a, **k):
            yield {"market_report": "ok"}
            raise RuntimeError("kaboom")

    class _G:
        graph = _Boom()

    emitted = []
    with pytest.raises(RuntimeError, match="kaboom"):
        run_streaming(_G(), {}, {}, emitted.append,
                      selected_analysts=["market"], ticker="X", trade_date="2026-06-26")
    assert any(e.type == EventType.ERROR for e in emitted)


def test_event_to_dict_is_json_shaped():
    e = ev.agent_started(AgentId.MARKET)
    d = e.to_dict()
    assert d["type"] == "agent_started"
    assert d["data"] == {"agent": "market"}
    assert set(d) == {"type", "seq", "run_id", "ts", "data"}
