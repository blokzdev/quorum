"""Unit tests for per-job config + credential isolation (tradingagents.runtime.isolation)."""

import os

import pytest

import tradingagents.dataflows.config as config_module
from tradingagents.runtime.isolation import JobIsolationContext, build_api_keys_dict

pytestmark = pytest.mark.unit


def test_build_api_keys_dict_maps_providers_and_vendors():
    env = build_api_keys_dict({
        "openai": "sk-open", "anthropic": "sk-anth", "fred": "fred-key",
        "alpha_vantage": "av-key", "unknown_provider": "x", "empty": "",
    })
    assert env["OPENAI_API_KEY"] == "sk-open"
    assert env["ANTHROPIC_API_KEY"] == "sk-anth"
    assert env["FRED_API_KEY"] == "fred-key"
    assert env["ALPHA_VANTAGE_API_KEY"] == "av-key"
    assert "unknown_provider" not in env and "x" not in env.values()
    assert "" not in env.values()  # empty keys skipped


def test_context_resets_config_to_default_plus_overrides():
    # Pollute the global config as a prior job might have.
    config_module._config["llm_provider"] = "anthropic"
    config_module._config["max_debate_rounds"] = 99
    with JobIsolationContext({"llm_provider": "openai"}):
        cfg = config_module.get_config()
        assert cfg["llm_provider"] == "openai"        # job override applied
        assert cfg["max_debate_rounds"] == 1          # reset to DEFAULT, not the polluted 99


def test_context_restores_config_on_exit():
    config_module._config["llm_provider"] = "deepseek"
    before = config_module.get_config()
    with JobIsolationContext({"llm_provider": "openai"}):
        assert config_module.get_config()["llm_provider"] == "openai"
    assert config_module.get_config() == before  # restored exactly


def test_sequential_jobs_do_not_bleed():
    # Job A sets a non-default provider; job B omits it and must see the DEFAULT, not A's value.
    with JobIsolationContext({"llm_provider": "anthropic"}):
        assert config_module.get_config()["llm_provider"] == "anthropic"
    with JobIsolationContext({"deep_think_llm": "gpt-5.5"}):
        cfg = config_module.get_config()
        assert cfg["llm_provider"] == "openai"  # DEFAULT_CONFIG default — no bleed from job A


def test_env_keys_injected_and_restored():
    os.environ.pop("XAI_API_KEY", None)
    os.environ["OPENAI_API_KEY"] = "original-openai"
    with JobIsolationContext(env_keys={"OPENAI_API_KEY": "job-key", "XAI_API_KEY": "job-xai"}):
        assert os.environ["OPENAI_API_KEY"] == "job-key"
        assert os.environ["XAI_API_KEY"] == "job-xai"
    assert os.environ["OPENAI_API_KEY"] == "original-openai"  # restored
    assert "XAI_API_KEY" not in os.environ                    # removed (was unset before)


def test_context_restores_even_on_exception():
    config_module._config["llm_provider"] = "google"
    before = config_module.get_config()
    with pytest.raises(ValueError), JobIsolationContext({"llm_provider": "openai"}):
        raise ValueError("boom")
    assert config_module.get_config() == before
