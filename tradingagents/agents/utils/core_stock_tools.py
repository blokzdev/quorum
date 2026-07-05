from datetime import datetime
from typing import Annotated

from langchain_core.tools import tool

from tradingagents.dataflows.config import get_config
from tradingagents.dataflows.interface import route_to_vendor


def _clamp_end_to_as_of(end_date: str, as_of_date: str | None) -> str:
    """Never let a raw OHLCV request run past the as-of date (look-ahead guard, P3.5b).

    The engine records the run's as-of date on the config (``as_of_date``); if the requested
    ``end_date`` is after it, clamp it back. Both are ``YYYY-MM-DD``; comparison is on parsed dates so a
    malformed value simply skips the clamp (never breaks a live run over a format quirk). No as-of set
    (a bare engine call outside a planned run) → no clamp, preserving the prior behaviour.
    """
    if not as_of_date:
        return end_date
    try:
        end = datetime.strptime(end_date, "%Y-%m-%d")
        as_of = datetime.strptime(as_of_date, "%Y-%m-%d")
    except (ValueError, TypeError):
        return end_date
    return as_of_date if end > as_of else end_date


@tool
def get_stock_data(
    symbol: Annotated[str, "ticker symbol of the company"],
    start_date: Annotated[str, "Start date in yyyy-mm-dd format"],
    end_date: Annotated[str, "End date in yyyy-mm-dd format"],
) -> str:
    """
    Retrieve stock price data (OHLCV) for a given ticker symbol.
    Uses the configured core_stock_apis vendor.
    Args:
        symbol (str): Ticker symbol of the company, e.g. AAPL, TSM
        start_date (str): Start date in yyyy-mm-dd format
        end_date (str): End date in yyyy-mm-dd format
    Returns:
        str: A formatted dataframe containing the stock price data for the specified ticker symbol in the specified date range.
    """
    # Look-ahead guard (P3.5b): the market analyst is TOLD the as-of date is "now", but nothing enforced
    # it for the raw tool — a stray end_date would leak future rows into the model's context. Clamp it to
    # the run's as-of date engine-side (LLM-independent), so a historical run can't see past its date.
    end_date = _clamp_end_to_as_of(end_date, get_config().get("as_of_date"))
    return route_to_vendor("get_stock_data", symbol, start_date, end_date)
