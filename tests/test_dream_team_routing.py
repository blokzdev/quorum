"""P2.5a — Dream Team per-role model routing (additive engine change)."""

from unittest.mock import MagicMock

import pytest

from tradingagents.graph.agent_roles import ROLE_TO_NODE
from tradingagents.graph.conditional_logic import ConditionalLogic
from tradingagents.graph.setup import GraphSetup
from tradingagents.graph.trading_graph import build_role_llms
from tradingagents.llm_clients.tool_capability import model_supports_tools

pytestmark = pytest.mark.unit

_ANALYSTS = ("market", "social", "news", "fundamentals")


def _graph_setup(role_llms=None):
    return GraphSetup(
        quick_thinking_llm=MagicMock(name="quick"),
        deep_thinking_llm=MagicMock(name="deep"),
        tool_nodes={k: MagicMock(name=f"tools_{k}") for k in _ANALYSTS},
        conditional_logic=ConditionalLogic(max_debate_rounds=1, max_risk_discuss_rounds=1),
        role_llms=role_llms,
    )


# --- Roster integrity: every ROLE_TO_NODE node is a real graph node -------------------------------

def test_roster_integrity_every_role_maps_to_a_real_node():
    """Guards the social/'Sentiment Analyst' rename trap: each frozen role node must be an actual
    node added in setup_graph()."""
    workflow = _graph_setup().setup_graph(_ANALYSTS)
    graph_nodes = set(workflow.nodes)
    assert len(ROLE_TO_NODE) == 12
    for role, node in ROLE_TO_NODE.items():
        assert node in graph_nodes, f"role {role!r} -> node {node!r} is not a real graph node"


# --- Additivity: empty role_llms == today's quick/deep --------------------------------------------

def test_llm_for_falls_back_to_quick_deep_when_unset():
    gs = _graph_setup()  # no role_llms
    assert gs.role_llms == {}
    assert gs._llm_for("Market Analyst", gs.quick_thinking_llm) is gs.quick_thinking_llm
    assert gs._llm_for("Research Manager", gs.deep_thinking_llm) is gs.deep_thinking_llm


def test_llm_for_override_wins_others_fall_back():
    override = MagicMock(name="opus")
    gs = _graph_setup(role_llms={"Portfolio Manager": override})
    assert gs._llm_for("Portfolio Manager", gs.deep_thinking_llm) is override
    assert gs._llm_for("Bull Researcher", gs.quick_thinking_llm) is gs.quick_thinking_llm  # unset


# --- The resolver: build_role_llms (multi-provider, dedup, base_url fix, effort, callbacks) --------

def _recording_create(record):
    class _Client:
        def __init__(self, sentinel):
            self._s = sentinel

        def get_llm(self):
            return self._s

    def create(provider, model, base_url=None, **kwargs):
        record.append({"provider": provider, "model": model, "base_url": base_url, "kwargs": kwargs})
        return _Client(("llm", provider, model))

    return create


def test_build_role_llms_empty_when_unset():
    assert build_role_llms({}, None, create_client=lambda **k: None) == {}
    assert build_role_llms({"agent_models": {}}, None, create_client=lambda **k: None) == {}


def test_build_role_llms_multi_provider_dedup_basurl_effort_callbacks():
    record = []
    cb = ["CB"]  # the run's shared callbacks list
    config = {
        "llm_provider": "ollama",
        "backend_url": "http://localhost:11434/v1",
        "anthropic_effort": "high",  # global per-provider knob
        "agent_models": {
            "portfolio_manager": {"provider": "anthropic", "model": "claude-opus-4-8"},
            "research_manager": {"provider": "anthropic", "model": "claude-opus-4-8"},  # same -> dedup
            "market_analyst": {"provider": "ollama", "model": "llama3.2:latest"},  # shares global provider
            "bull_researcher": {"provider": "xai", "model": "grok-x"},  # cloud, no per-role backend
        },
    }
    role_llms = build_role_llms(config, cb, create_client=_recording_create(record))

    # Keyed by graph NODE name, resolved correctly.
    assert role_llms["Portfolio Manager"] == ("llm", "anthropic", "claude-opus-4-8")
    assert role_llms["Market Analyst"] == ("llm", "ollama", "llama3.2:latest")
    assert role_llms["Bull Researcher"] == ("llm", "xai", "grok-x")

    # Dedup: anthropic opus built once; PM and RM share the SAME client instance.
    anthropic = [c for c in record if c["provider"] == "anthropic"]
    assert len(anthropic) == 1
    assert role_llms["Research Manager"] is role_llms["Portfolio Manager"]

    # base_url fix: the ollama role (shares the global provider) inherits the global backend_url;
    # the xai cloud role does NOT inherit the global local endpoint (would be wrong) -> None.
    ollama = next(c for c in record if c["provider"] == "ollama")
    assert ollama["base_url"] == "http://localhost:11434/v1"
    xai = next(c for c in record if c["provider"] == "xai")
    assert xai["base_url"] is None

    # Effort: anthropic role with no per-role effort picks up the global anthropic_effort knob.
    assert anthropic[0]["kwargs"].get("effort") == "high"
    # Callbacks: every per-role client gets the run's shared callbacks object.
    assert all(c["kwargs"].get("callbacks") is cb for c in record)


def test_build_role_llms_per_role_effort_overrides_global():
    record = []
    config = {
        "llm_provider": "openai",
        "openai_reasoning_effort": "low",
        "agent_models": {"trader": {"provider": "openai", "model": "gpt-5.5", "effort": "high"}},
    }
    build_role_llms(config, None, create_client=_recording_create(record))
    assert record[0]["kwargs"].get("reasoning_effort") == "high"  # per-role wins over global "low"


def test_build_role_llms_ignores_unknown_and_malformed_roles():
    record = []
    config = {
        "agent_models": {
            "not_a_role": {"provider": "openai", "model": "x"},
            "trader": {"provider": "openai"},  # missing model
            "bull_researcher": {"provider": "xai", "model": "grok-x"},  # valid
        }
    }
    role_llms = build_role_llms(config, None, create_client=_recording_create(record))
    assert set(role_llms) == {"Bull Researcher"}
    assert len(record) == 1


# --- Tool-capability flag (the Dream Team gate's data source) -------------------------------------

def test_model_supports_tools():
    assert model_supports_tools("anthropic", "claude-opus-4-8") is True
    assert model_supports_tools("ollama", "custom") is None  # user-specified -> warn, don't block
    assert model_supports_tools("openai", "") is None
