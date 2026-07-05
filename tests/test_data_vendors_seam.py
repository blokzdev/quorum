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
