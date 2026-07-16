/// Device-tier + fit-badge math for the Edge Model Draft Board (P5.1b/c) — pure functions, zero
/// imports, so every product-facing verdict here is unit-testable arithmetic.
library;

/// Device tiers for the curated free-local lineup (plan A5: ONE triple — these same names label the
/// P5.3 presets; "pro" is banned for this feature).
enum DeviceTier { lite, core, max }

/// Will a model fit this machine? [tight] = loads, but the OS is under memory pressure (swap risk).
enum FitBadge { fits, tight, wontFit }

/// Ollama's server-default context length. The engine sets no `num_ctx` anywhere on its OpenAI-compat
/// path (verified by grep — plan A6), so this IS the effective context the KV term is computed at.
/// If P5.4a hits context-truncation failures, the raised value lands HERE (one constant; the catalog
/// ships raw kv_params precisely so re-badging is this change, not a catalog regen).
const int kDefaultOllamaCtx = 4096;

/// Tier floors in MiB — DECIMAL-thousand values deliberately below the binary GiB marks (12288/32768):
/// device RAM reads report *usable* physical memory, which on Windows runs ~0.3–1 GiB under nominal
/// (a physical "32GB" machine reports ~31.7 GiB ≈ 32,460 MiB). Binary floors would make the max tier
/// unreachable on exactly the machines it targets (plan A2). These mirror the catalog's served
/// `min_device_ram_mb` values; the seed test in `tests/test_edge_catalog.py` locks the same numbers
/// engine-side so the two can't drift silently.
const int kCoreTierFloorMb = 12000;
const int kMaxTierFloorMb = 32000;

/// Full headroom reserved for everything that isn't model weights + KV: Windows baseline ~2–2.5 GiB
/// + the Flutter shell + the Python sidecar + Ollama's compute/graph buffers beyond weights (plan A7 —
/// bytes-vs-RAM alone would badge a 7.2GB model "Fits" on an 8GB machine and thrash).
const int kFitsHeadroomBytes = 4 * 1024 * 1024 * 1024;

/// The absolute floor — below this the model may load but Windows can't breathe (hard swap risk).
/// Must stay large enough that the gemma4:e2b-on-8GB plan anchor badges wontFit, not tight.
const int kTightHeadroomBytes = 2 * 1024 * 1024 * 1024;

/// RAM (MiB, as reported by the device — e.g. `device_info_plus.systemMemoryInMegabytes`) → tier.
DeviceTier deviceTier(int ramMb) {
  if (ramMb >= kMaxTierFloorMb) return DeviceTier.max;
  if (ramMb >= kCoreTierFloorMb) return DeviceTier.core;
  return DeviceTier.lite;
}

/// KV-cache bytes for a model at [ctx]: `blockCount × headCountKv × (keyLength + valueLength) × ctx
/// × 2` (f16 — Ollama's default KV cache type). Inputs ride the catalog (`kv_params`, curated from
/// each model's public config; the llama3.2 row is live-verified against `/api/show`).
int kvBytes({
  required int blockCount,
  required int headCountKv,
  required int keyLength,
  required int valueLength,
  int ctx = kDefaultOllamaCtx,
}) =>
    blockCount * headCountKv * (keyLength + valueLength) * ctx * 2;

/// The badge: model weights + KV + headroom vs the device's reported RAM.
FitBadge fitBadge({required int modelBytes, required int kvBytes, required int deviceRamMb}) {
  final ramBytes = deviceRamMb * 1024 * 1024;
  if (modelBytes + kvBytes + kFitsHeadroomBytes <= ramBytes) return FitBadge.fits;
  if (modelBytes + kvBytes + kTightHeadroomBytes <= ramBytes) return FitBadge.tight;
  return FitBadge.wontFit;
}
