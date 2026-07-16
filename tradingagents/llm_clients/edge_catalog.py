"""The curated Edge Model Draft Board catalog (P5.1a) — versioned, frozen seed data.

Engine-side (beside model_catalog.py) so the open-core hosted-update seam stays possible: a future
hosted path can serve a newer ``CATALOG_VERSION`` and :func:`get_edge_catalog` is the single override
point — the sidecar endpoint calls the accessor, never the constant. Ships frozen defaults.

Curation provenance (2026-07-16, all rows LIVE-verified):
- ``bytes`` = the EXACT model-layer size from ``registry.ollama.ai/v2/<ns>/<name>/manifests/<tag>``
  (``application/vnd.ollama.image.model``) — exact so the P5.2c pull-stream cross-check (the
  catalog-drift tripwire: Ollama tags are repointable post-ship) compares real numbers.
- ``kv_params`` = attention config from each model's public HF ``config.json`` (``text_config`` for
  the multimodal Qwen3.5/Gemma-4 families); llama3.2's row was live-verified against a local Ollama
  ``/api/show``. KV bytes at ctx = block_count x head_count_kv x (key_length + value_length) x ctx x 2
  (f16). HONESTY CAVEAT: Qwen3.5/3.6 use hybrid attention (~1/4 of layers hold a growing KV cache),
  so the literal formula OVERSTATES their KV ~4x — the safe direction for a fit badge (errs toward
  "won't fit"); revisit only if it ever demotes a default at its own tier floor (A2 invariant-tested).
- ``min_ollama_version``: qwen3.5 tool-call parsing was only fully fixed in Ollama 0.17.6 (more
  accurate than the registry's ``requires: 0.17.1`` load-minimum); qwen3.6:35b's qwen35moe arch +
  thinking fixes land at 0.17.7; gemma4's registry config declares ``requires: 0.20.0``.
- ``verified``: "real-run" = passed a real gated analyst run on this repo (llama3.2, P3.2);
  "tag-only" = Ollama tools capability observed, reliability unproven (P5.4a upgrades or demotes
  every DEFAULT — tag-only defaults may not survive to GA); "none" = no tool claim (text-only rows).

Tier floors are DECIMAL-thousand MiB, deliberately below the binary GiB marks: device RAM reads
(GlobalMemoryStatusEx) report usable physical memory, which on Windows runs ~0.3-1 GiB under nominal —
a physical "32GB" machine reports ~31.7 GiB, and binary floors (32768) would make the max tier
unreachable on exactly the machines it targets (plan A2/A5; regression-locked in the Dart tests).

The scope wall (phase-5-plan.md): this is a CURATED list — additions are product decisions
(founder-visible forks), never drive-by edits.
"""

CATALOG_VERSION = 1

# The context length the client's fit-badge math assumes (Ollama's server default; the engine sets no
# num_ctx on its OpenAI-compat path — verified by grep, plan A6). Served as data so the assumption is
# visible client-side and a future raised-ctx re-tier is a data change.
KV_CTX = 4096


def _model(
    id_: str,
    tag: str,
    display: str,
    bytes_: int,
    kv: tuple[int, int, int, int],  # (block_count, head_count_kv, key_length, value_length)
    capability: str,  # "analyst" | "text_only"
    license_: str,
    blurb: str,
    *,
    default: bool = False,
    verified: str = "tag-only",  # "real-run" | "tag-only" | "none"
    min_ollama_version: str | None = None,
) -> dict:
    block_count, head_count_kv, key_length, value_length = kv
    return {
        "id": id_,
        "ollama_tag": tag,
        "display": display,
        "bytes": bytes_,
        "kv_params": {
            "block_count": block_count,
            "head_count_kv": head_count_kv,
            "key_length": key_length,
            "value_length": value_length,
        },
        "capability": capability,
        "license": license_,
        "blurb": blurb,
        "verified": verified,
        "default": default,
        "min_ollama_version": min_ollama_version,
    }


EDGE_MODEL_TIERS: list[dict] = [
    {
        "tier": "lite",
        "min_device_ram_mb": 0,
        "models": [
            _model(
                "qwen3.5-2b", "qwen3.5:2b", "Qwen3.5 2B", 2_741_180_928, (24, 2, 256, 256),
                "analyst", "Apache-2.0",
                "The low-RAM analyst pick — smallest tools-flagged model with real headroom.",
                default=True, min_ollama_version="0.17.6",
            ),
            _model(
                "qwen3.5-0.8b", "qwen3.5:0.8b", "Qwen3.5 0.8B", 1_036_034_688, (24, 2, 256, 256),
                "analyst", "Apache-2.0",
                "The absolute floor for ~4GB machines; expect shallow reports.",
                min_ollama_version="0.17.6",
            ),
            _model(
                "llama3.2-3b", "llama3.2", "Llama 3.2 3B", 2_019_377_376, (28, 8, 128, 128),
                "analyst", "Llama 3.2 Community License",
                "The proven fallback — real-run verified on this machine's gate (P3.2).",
                verified="real-run",
            ),
            _model(
                "minicpm5-1b", "openbmb/minicpm5:q4_K_M", "MiniCPM5 1B", 688_065_920, (24, 2, 128, 128),
                "text_only", "Apache-2.0",
                "Tiny debate-role specialist; its tool-calling is unreachable through Ollama.",
                verified="none",
            ),
        ],
    },
    {
        "tier": "core",
        "min_device_ram_mb": 12_000,
        "models": [
            _model(
                "qwen3.5-9b", "qwen3.5:9b", "Qwen3.5 9B", 6_594_462_816, (32, 4, 256, 256),
                "analyst", "Apache-2.0",
                "The flagship free-local pick — best verified small tool-caller (66.1 BFCL-V4).",
                default=True, min_ollama_version="0.17.6",
            ),
            _model(
                "qwen3.5-4b", "qwen3.5:4b", "Qwen3.5 4B", 3_389_971_840, (32, 4, 256, 256),
                "analyst", "Apache-2.0",
                "Faster turns on slower Core machines; Qwen's own lightweight-agent tier.",
                min_ollama_version="0.17.6",
            ),
            _model(
                "gemma4-e2b", "gemma4:e2b", "Gemma 4 E2B", 7_162_394_016, (35, 1, 256, 256),
                "analyst", "Apache-2.0",
                "Google's on-device family with a thinking mode; bigger on disk than its name suggests.",
                min_ollama_version="0.20.0",
            ),
            _model(
                "qwen3-14b", "qwen3:14b", "Qwen3 14B", 9_276_184_896, (40, 8, 128, 128),
                "analyst", "Apache-2.0",
                "Previous-gen 14B — the biggest dense option that fits a 16GB machine.",
            ),
        ],
    },
    {
        "tier": "max",
        "min_device_ram_mb": 32_000,
        "models": [
            _model(
                "qwen3.6-35b", "qwen3.6:35b", "Qwen3.6 35B-A3B", 23_938_321_664, (40, 2, 256, 256),
                "analyst", "Apache-2.0",
                "Newest-gen MoE — 35B quality with ~3B-active speed on 32GB+ machines.",
                default=True, min_ollama_version="0.17.7",
            ),
            _model(
                "qwen3.5-27b", "qwen3.5:27b", "Qwen3.5 27B", 17_420_420_832, (64, 4, 256, 256),
                "analyst", "Apache-2.0",
                "The dense fallback if the MoE underperforms on your hardware.",
                min_ollama_version="0.17.6",
            ),
            _model(
                "gemma4-e4b", "gemma4:e4b", "Gemma 4 E4B", 9_608_338_848, (42, 2, 256, 256),
                "analyst", "Apache-2.0",
                "Gemma's larger on-device tier — a lighter Max alternative with thinking + vision.",
                min_ollama_version="0.20.0",
            ),
        ],
    },
]


def get_edge_catalog() -> dict:
    """The versioned Draft Board catalog — the single accessor the sidecar serves (and the single
    override point for a future hosted/curated update path)."""
    return {
        "catalog_version": CATALOG_VERSION,
        "kv_ctx": KV_CTX,
        "tiers": EDGE_MODEL_TIERS,
    }
