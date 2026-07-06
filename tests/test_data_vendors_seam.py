"""P3.1 data-vendor seam: request -> plan_run config -> router.

Falsifies the P3.1a contract seam: a per-category ``data_vendors`` override on the run request must
reach ``config["data_vendors"]`` (partial, non-clobbering) WITHOUT mutating the process-global
``DEFAULT_CONFIG`` (the ``config = dict(DEFAULT_CONFIG)`` shallow-copy trap), and the tool-time router
must then dispatch to the chosen vendor.
"""
import copy
import unittest
from unittest import mock

import pytest

import tradingagents.dataflows.config as config_module
import tradingagents.default_config as default_config
from services.api.jobs import plan_run
from tradingagents.dataflows import interface


@pytest.mark.unit
class DataVendorSeamTests(unittest.TestCase):
    def setUp(self):
        config_module._config = copy.deepcopy(default_config.DEFAULT_CONFIG)

    def test_partial_override_reaches_config_without_clobbering_other_categories(self):
        plan = plan_run({"ticker": "AAPL", "data_vendors": {"core_stock_apis": "alpha_vantage"}})
        dv = plan["config"]["data_vendors"]
        assert dv["core_stock_apis"] == "alpha_vantage"  # the override took
        assert dv["news_data"] == "yfinance"             # an unspecified category stays at default

    def test_blank_values_are_ignored(self):
        plan = plan_run({"ticker": "AAPL", "data_vendors": {"core_stock_apis": ""}})
        assert plan["config"]["data_vendors"]["core_stock_apis"] == "yfinance"  # blank -> keep default

    def test_no_override_leaves_config_at_engine_default(self):
        plan = plan_run({"ticker": "AAPL"})
        assert plan["config"]["data_vendors"]["core_stock_apis"] == "yfinance"

    def test_plan_run_never_mutates_the_global_default_config(self):
        # The shallow-copy trap: an in-place merge would leak the choice into every later run.
        before = copy.deepcopy(default_config.DEFAULT_CONFIG["data_vendors"])
        plan_run({"ticker": "AAPL", "data_vendors": {"core_stock_apis": "alpha_vantage"}})
        plan_run({"ticker": "MSFT", "data_vendors": {"fundamental_data": "alpha_vantage"}})
        assert default_config.DEFAULT_CONFIG["data_vendors"] == before

    def test_config_selection_drives_the_router(self):
        # A core_stock_apis method served by both vendors — discover one so the test can't drift.
        method = next(
            m for m, v in interface.VENDOR_METHODS.items()
            if "alpha_vantage" in v and "yfinance" in v
            and interface.get_category_for_method(m) == "core_stock_apis"
        )
        plan = plan_run({"ticker": "AAPL", "data_vendors": {"core_stock_apis": "alpha_vantage"}})
        config_module.set_config(plan["config"])  # the router reads the process global, not plan['config']

        sentinel = mock.Mock(return_value="AV-DATA")
        with mock.patch.dict(interface.VENDOR_METHODS[method], {"alpha_vantage": sentinel}):
            result = interface.route_to_vendor(method, "AAPL")
        assert result == "AV-DATA"
        sentinel.assert_called_once()

    # --- P3.1c: request -> env_keys (vendor keys) ---------------------------------------------------

    def test_vendor_api_keys_reach_env_keys_via_plan_run(self):
        # The desktop sends vendor keys in the SAME api_keys map as provider keys; plan_run must map each
        # to its engine env var (build_api_keys_dict), so JobIsolationContext can inject them at run time.
        plan = plan_run({
            "ticker": "AAPL",
            "data_vendors": {"core_stock_apis": "alpha_vantage"},
            "api_keys": {"anthropic": "sk-anth", "alpha_vantage": "av-key", "fred": "fred-key"},
        })
        env = plan["env_keys"]
        assert env["ALPHA_VANTAGE_API_KEY"] == "av-key"
        assert env["FRED_API_KEY"] == "fred-key"
        assert env["ANTHROPIC_API_KEY"] == "sk-anth"  # provider keys still map alongside vendor keys

    # --- P3.1c: asset-type honesty (frames prompts, does NOT reroute data) --------------------------

    def test_explicit_asset_type_overrides_ticker_autodetect(self):
        # An explicit request asset_type wins over the '-USD' heuristic (and vice-versa for a plain ticker).
        assert plan_run({"ticker": "AAPL", "asset_type": "crypto"})["asset_type"] == "crypto"
        assert plan_run({"ticker": "BTC-USD"})["asset_type"] == "crypto"  # auto-detect still works
        assert plan_run({"ticker": "AAPL"})["asset_type"] == "stock"

    def test_asset_type_crypto_does_not_reroute_data_vendors(self):
        # The honest-scope contract: choosing crypto must NOT silently switch data vendors — a crypto run
        # still hits the same (default) vendors. Only the agent PROMPTS change (asserted below).
        default_dv = copy.deepcopy(default_config.DEFAULT_CONFIG["data_vendors"])
        plan = plan_run({"ticker": "BTC-USD", "asset_type": "crypto"})
        assert plan["config"]["data_vendors"] == default_dv  # unchanged — no crypto-specific routing

    def test_asset_type_crypto_reflected_in_agent_prompt_framing(self):
        # "the run's prompts reflect it" (exit criterion): the instrument context an agent sees is crypto-
        # framed and explicitly drops the company-fundamentals assumption.
        from tradingagents.agents.utils.agent_utils import build_instrument_context
        crypto_ctx = build_instrument_context("BTC-USD", "crypto")
        stock_ctx = build_instrument_context("AAPL", "stock")
        assert "crypto asset" in crypto_ctx and "company fundamentals" in crypto_ctx
        assert "crypto asset" not in stock_ctx  # a stock run is NOT crypto-framed

    # --- P3.1c: optional KEYLESS vendor (Polymarket) routes with no key -----------------------------

    def test_keyless_prediction_market_vendor_routes_without_a_key(self):
        # prediction_markets (polymarket) is optional AND keyless — it must dispatch with no key in env,
        # so the UI is right to keep it default-on and never gate a launch on it.
        import os
        method = "get_prediction_markets"
        assert interface.get_category_for_method(method) == "prediction_markets"
        config_module.set_config(copy.deepcopy(default_config.DEFAULT_CONFIG))  # polymarket is the default
        os.environ.pop("POLYMARKET_API_KEY", None)  # prove no key is consulted

        sentinel = mock.Mock(return_value="PM-DATA")
        with mock.patch.dict(interface.VENDOR_METHODS[method], {"polymarket": sentinel}):
            result = interface.route_to_vendor(method, "AAPL")
        assert result == "PM-DATA"
        sentinel.assert_called_once()
