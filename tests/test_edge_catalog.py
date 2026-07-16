"""P5.1a seed-data invariants for the Edge Model Draft Board catalog.

These lock the PLAN'S product decisions into red/green: tier names + floors (A2/A5), exactly one
analyst-capable default per tier, verification-status semantics (P5.4a: a "none" default can't ship),
and the A2 consistency rule — every tier's DEFAULT must pass the fit math at its own tier floor
(a default that badges won't-fit at its own floor is an internal contradiction).
"""

import re

from tradingagents.llm_clients.edge_catalog import (
    CATALOG_VERSION,
    KV_CTX,
    get_edge_catalog,
)

# Mirrors the Dart device_fit constants (packages/quorum_core/lib/src/device_fit.dart) — the A2
# invariant is checked with the same arithmetic the client uses.
_FITS_HEADROOM = 4 * 1024**3
_MIB = 1024**2

_VERSION_RE = re.compile(r"^\d+\.\d+(\.\d+)?$")


def _kv_bytes(m: dict, ctx: int = KV_CTX) -> int:
    p = m["kv_params"]
    return p["block_count"] * p["head_count_kv"] * (p["key_length"] + p["value_length"]) * ctx * 2


def _all_models(catalog: dict):
    for tier in catalog["tiers"]:
        for m in tier["models"]:
            yield tier, m


def test_catalog_shape_and_versions():
    cat = get_edge_catalog()
    assert cat["catalog_version"] == CATALOG_VERSION >= 1
    assert cat["kv_ctx"] == 4096  # A6: the engine sets no num_ctx, so Ollama's default IS the ctx
    assert [t["tier"] for t in cat["tiers"]] == ["lite", "core", "max"]  # A5: one triple; "pro" banned


def test_tier_floors_are_ascending_decimal_mib():
    # Decimal-thousand floors (12000/32000), NOT binary (12288/32768): a physical "32GB" machine
    # reports ~31.7GiB usable, and binary floors would lock the max tier out of exactly the machines
    # it targets (A2). This test goes red if anyone "fixes" the floors to binary.
    floors = [t["min_device_ram_mb"] for t in get_edge_catalog()["tiers"]]
    assert floors == [0, 12_000, 32_000]


def test_every_tier_has_exactly_one_default_and_it_is_analyst():
    for tier in get_edge_catalog()["tiers"]:
        defaults = [m for m in tier["models"] if m["default"]]
        assert len(defaults) == 1, f"tier {tier['tier']} must have exactly one default"
        assert defaults[0]["capability"] == "analyst", f"tier {tier['tier']} default must be analyst"


def test_default_verification_is_never_none():
    # P5.4a: defaults ship tag-only (upgraded-or-demoted by the real-run gate) or real-run — a
    # default with NO tool claim at all is a curation bug.
    for tier in get_edge_catalog()["tiers"]:
        default = next(m for m in tier["models"] if m["default"])
        assert default["verified"] in {"real-run", "tag-only"}


def test_entry_field_integrity():
    ids = set()
    for _tier, m in _all_models(get_edge_catalog()):
        assert m["id"] and m["id"] not in ids, "ids must be unique"
        ids.add(m["id"])
        assert m["ollama_tag"] and m["display"] and m["license"] and m["blurb"]
        assert m["bytes"] > 0
        assert m["capability"] in {"analyst", "text_only"}
        assert m["verified"] in {"real-run", "tag-only", "none"}
        p = m["kv_params"]
        assert all(p[k] > 0 for k in ("block_count", "head_count_kv", "key_length", "value_length"))
        if m["min_ollama_version"] is not None:
            assert _VERSION_RE.match(m["min_ollama_version"]), m["id"]
        if m["capability"] == "text_only":
            assert m["verified"] == "none"  # text-only rows make no tool claim


def test_llama32_kv_anchor():
    # The live-verified worked example (Ollama /api/show, plan P5.1c): 28 x 8 x 256 x 4096 x 2.
    cat = get_edge_catalog()
    llama = next(m for _t, m in _all_models(cat) if m["id"] == "llama3.2-3b")
    assert _kv_bytes(llama) == 469_762_048
    assert llama["verified"] == "real-run"  # P3.2's live gate run seeds the one real-run row


def test_a2_every_default_fits_at_its_own_tier_floor():
    # A2: bytes + KV@4096 + full headroom must fit the tier's own floor (lite's floor is 0 -> check
    # against a nominal 8GB device, the tier's stated audience). A default that badges won't-fit at
    # its own floor is the exact contradiction the plan amendment removed.
    for tier in get_edge_catalog()["tiers"]:
        default = next(m for m in tier["models"] if m["default"])
        floor_mb = tier["min_device_ram_mb"] or 8_192
        need = default["bytes"] + _kv_bytes(default) + _FITS_HEADROOM
        assert need <= floor_mb * _MIB, (
            f"{tier['tier']} default {default['id']} needs {need} bytes but the tier floor is "
            f"{floor_mb} MiB"
        )
