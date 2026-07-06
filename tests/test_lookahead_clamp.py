"""P3.5b look-ahead clamp: the raw OHLCV tool (``get_stock_data``) must not fetch rows after the run's
as-of date, even when the LLM asks for a later ``end_date``.

Falsifies the leak the recon confirmed: ``get_stock_data`` had no date bound (unlike ``get_indicators``,
whose deep ``load_ohlcv`` path clamps ``Date <= curr_date``), so a past-date run could pull future rows
into the model's tool calls. The fix records the as-of date on the config (``plan_run``) and clamps
``end_date`` engine-side in the tool — LLM-independent.
"""
import copy
import unittest
from unittest import mock

import pytest

import tradingagents.dataflows.config as config_module
import tradingagents.default_config as default_config
from services.api.jobs import plan_run
from tradingagents.agents.utils import core_stock_tools, news_data_tools
from tradingagents.agents.utils.as_of_guard import clamp_end_to_as_of


@pytest.mark.unit
class LookAheadClampTests(unittest.TestCase):
    def setUp(self):
        config_module._config = copy.deepcopy(default_config.DEFAULT_CONFIG)

    def _call(self, start, end):
        """Invoke get_stock_data with the vendor router stubbed; return the args it dispatched."""
        captured = {}

        def fake_route(method, symbol, start_date, end_date):
            captured.update(method=method, symbol=symbol, start=start_date, end=end_date)
            return "OK"

        with mock.patch.object(core_stock_tools, "route_to_vendor", fake_route):
            core_stock_tools.get_stock_data.invoke(
                {"symbol": "AAPL", "start_date": start, "end_date": end})
        return captured

    def test_end_after_as_of_is_clamped(self):
        config_module._config["as_of_date"] = "2024-06-10"
        cap = self._call("2024-06-01", "2024-12-31")
        assert cap["end"] == "2024-06-10"  # future window clamped back to the as-of date
        assert cap["start"] == "2024-06-01"  # start is untouched

    def test_end_on_as_of_boundary_is_unchanged(self):
        config_module._config["as_of_date"] = "2024-06-10"
        assert self._call("2024-06-01", "2024-06-10")["end"] == "2024-06-10"  # == is not "after"

    def test_end_before_as_of_is_unchanged(self):
        config_module._config["as_of_date"] = "2024-06-10"
        assert self._call("2024-06-01", "2024-06-05")["end"] == "2024-06-05"

    def test_no_as_of_means_no_clamp(self):
        # A bare engine call (no planned run) leaves as_of_date unset -> end passes through untouched.
        config_module._config.pop("as_of_date", None)
        assert self._call("2024-06-01", "2024-12-31")["end"] == "2024-12-31"

    def test_malformed_end_date_skips_clamp_gracefully(self):
        # Never break a live run over a date-format quirk — an unparseable end just isn't clamped.
        config_module._config["as_of_date"] = "2024-06-10"
        assert self._call("2024-06-01", "not-a-date")["end"] == "not-a-date"

    def _call_news(self, start, end):
        """Invoke get_news with the vendor router stubbed; return the args it dispatched."""
        captured = {}

        def fake_route(method, ticker, start_date, end_date):
            captured.update(method=method, ticker=ticker, start=start_date, end=end_date)
            return "OK"

        with mock.patch.object(news_data_tools, "route_to_vendor", fake_route):
            news_data_tools.get_news.invoke(
                {"ticker": "AAPL", "start_date": start, "end_date": end})
        return captured

    def test_news_tool_shares_the_same_look_ahead_guard(self):
        # get_news is the sibling (ticker, start_date, end_date) tool — a historical run must not pull
        # future ARTICLES either. Same guard, so the clamp applies identically.
        config_module._config["as_of_date"] = "2024-06-10"
        assert self._call_news("2024-06-01", "2024-12-31")["end"] == "2024-06-10"  # clamped
        assert self._call_news("2024-06-01", "2024-06-05")["end"] == "2024-06-05"  # within bound

    def test_clamp_helper_reads_config_directly(self):
        # The shared guard reads config['as_of_date'] itself (no arg) — the single source both tools use.
        config_module._config["as_of_date"] = "2024-06-10"
        assert clamp_end_to_as_of("2024-12-31") == "2024-06-10"
        assert clamp_end_to_as_of("2024-01-01") == "2024-01-01"
        config_module._config.pop("as_of_date", None)
        assert clamp_end_to_as_of("2024-12-31") == "2024-12-31"  # no as-of -> untouched

    def test_plan_run_records_the_as_of_date_on_config(self):
        # Explicit trade_date is recorded verbatim; an omitted one defaults to today (ISO YYYY-MM-DD).
        assert plan_run({"ticker": "AAPL", "trade_date": "2024-06-10"})["config"]["as_of_date"] \
            == "2024-06-10"
        default = plan_run({"ticker": "AAPL"})["config"]["as_of_date"]
        assert len(default) == 10 and default[4] == "-" and default[7] == "-"
