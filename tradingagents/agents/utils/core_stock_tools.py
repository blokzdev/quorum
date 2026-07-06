from typing import Annotated

from langchain_core.tools import tool

from tradingagents.agents.utils.as_of_guard import clamp_end_to_as_of
from tradingagents.dataflows.interface import route_to_vendor


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
    # Look-ahead guard (P3.5b): the analyst is TOLD the as-of date is "now", but nothing enforced it for
    # the raw tool — a stray end_date would leak future rows into the model's context. Clamp it to the
    # run's as-of date engine-side (LLM-independent), so a historical run can't see past its date.
    end_date = clamp_end_to_as_of(end_date)
    return route_to_vendor("get_stock_data", symbol, start_date, end_date)
