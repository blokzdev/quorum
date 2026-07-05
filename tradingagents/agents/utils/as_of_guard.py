"""Shared as-of (look-ahead) guard for date-bounded data tools (P3.5b).

A tool whose ``end_date`` is chosen freely by the LLM must never fetch data past the run's as-of date,
or a historical run leaks future rows into the model's context. The engine records that date on the
config (``as_of_date``, set per run inside ``JobIsolationContext``); clamp ``end_date`` to it before
routing to the vendor — engine-side, so the LLM cannot defeat it.

Only the ``(start_date, end_date)`` tools need this (``get_stock_data``, ``get_news``): their end is
unbounded. The structurally as-of-aware tools that take ``curr_date`` as the window end
(``get_indicators``, ``get_fundamentals``, ``get_macro_indicators``, …) already bound to the as-of date
by construction.
"""
from datetime import datetime

from tradingagents.dataflows.config import get_config


def clamp_end_to_as_of(end_date: str) -> str:
    """Clamp ``end_date`` back to the run's as-of date when it runs past it.

    Reads ``config['as_of_date']`` (``YYYY-MM-DD``). No as-of set (a bare engine call outside a planned
    run) or an unparseable value → returns ``end_date`` unchanged (never break a live run over a format
    quirk). A live run's as-of is today, so an in-range request is a no-op.
    """
    as_of = get_config().get("as_of_date")
    if not as_of:
        return end_date
    try:
        end = datetime.strptime(end_date, "%Y-%m-%d")
        bound = datetime.strptime(as_of, "%Y-%m-%d")
    except (ValueError, TypeError):
        return end_date
    return as_of if end > bound else end_date
