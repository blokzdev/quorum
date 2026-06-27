"""Tool-calling capability lookup for catalog models — the data source for the Dream Team UI gate.

The market / news / fundamentals analyst roles ``bind_tools`` and loop on tool calls, so a model that
cannot do tool-calling silently produces an empty / hallucinated report (``bind_tools`` does not
raise). The desktop reads this (surfaced on each ``/catalog/providers`` option) to BLOCK a non-tool
model for those three roles.

Kept Quorum-side, deliberately NOT in ``model_catalog.MODEL_OPTIONS``: that table's ``(label, value)``
tuple shape and the ``/catalog`` wire contract must stay additive and upstream-mergeable.
"""

from __future__ import annotations

# Catalog model VALUES known to lack tool-calling. The curated frontier catalog is tool-capable, so
# this denylist starts empty; it is the extension point as known non-tool (typically older local)
# models surface (e.g. a legacy Llama-3 8B entered as a custom Ollama model id).
_NON_TOOL_MODELS: frozenset[str] = frozenset()


def model_supports_tools(provider: str, model: str) -> bool | None:
    """Whether ``(provider, model)`` can do tool-calling.

    Returns ``True``/``False`` when known, and ``None`` when unknown — i.e. a user-supplied
    ``custom`` / local model id we can't classify, which the UI should WARN on (not hard-block) for
    the tool-analyst roles rather than guess. Frontier catalog models resolve ``True``.
    """
    if not model or model == "custom":
        return None
    return model not in _NON_TOOL_MODELS
