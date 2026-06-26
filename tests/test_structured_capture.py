"""Unit tests for structured-output capture (P0.6).

Covers the capture chokepoint in ``agents/utils/structured.py`` and the runner attaching the captured
JSON to ``report_section_done`` / ``run_done`` events.
"""

import pytest
from pydantic import BaseModel

import tradingagents.agents.utils.structured as structmod
from tradingagents.agents.utils.structured import capture_structured, invoke_structured_or_freetext
from tradingagents.runtime.events import EventType
from tradingagents.runtime.runner import run_streaming

pytestmark = pytest.mark.unit


class _Demo(BaseModel):
    rating: str
    investment_thesis: str


class _FakeStructuredLLM:
    def __init__(self, result):
        self._result = result

    def invoke(self, _prompt):
        return self._result


def test_capture_reports_model_dump_and_still_renders():
    captured: dict[str, dict] = {}
    demo = _Demo(rating="Buy", investment_thesis="strong moat")
    with capture_structured(lambda name, data: captured.__setitem__(name, data)):
        out = invoke_structured_or_freetext(
            _FakeStructuredLLM(demo), None, "prompt",
            lambda m: f"Rating: {m.rating}", "Portfolio Manager",
        )
    assert out == "Rating: Buy"  # markdown rendering unchanged
    assert captured["Portfolio Manager"] == {"rating": "Buy", "investment_thesis": "strong moat"}


def test_no_capture_when_sink_unset():
    # Without an active capture context, the sink contextvar is None and nothing is collected/raised.
    demo = _Demo(rating="Hold", investment_thesis="wait")
    out = invoke_structured_or_freetext(
        _FakeStructuredLLM(demo), None, "p", lambda m: m.rating, "Trader")
    assert out == "Hold"
    assert structmod._structured_sink.get() is None


class _StructuredFakeInner:
    """A fake graph stream that simulates the PM agent capturing structured output mid-run."""

    def stream(self, _init_state, **_kw):
        sink = structmod._structured_sink.get()
        if sink is not None:
            sink("Portfolio Manager", {"rating": "Sell", "investment_thesis": "overvalued"})
        yield {"risk_debate_state": {"judge_decision": "DECISION"}, "final_trade_decision": "DECISION"}


class _StructuredFakeGraph:
    graph = _StructuredFakeInner()

    def process_signal(self, _decision):
        return "Sell"


def test_run_streaming_attaches_structured_to_section_and_verdict():
    events = []
    run_streaming(_StructuredFakeGraph(), {}, {}, events.append,
                  selected_analysts=[], ticker="X", trade_date="2026-06-26")

    sections = [e for e in events
                if e.type == EventType.REPORT_SECTION_DONE
                and e.data["section"] == "final_trade_decision"]
    assert sections, "final_trade_decision section not emitted"
    assert sections[0].data.get("structured") == {"rating": "Sell", "investment_thesis": "overvalued"}

    done = [e for e in events if e.type == EventType.RUN_DONE][0]
    assert done.data["structured"]["rating"] == "Sell"
    assert done.data["rating"] == "Sell"
    assert done.data["thesis"] == "overvalued"
