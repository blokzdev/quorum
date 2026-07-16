// P5.1b/c — tier + fit-badge math. These lock the plan's anchor cases red/green:
// the llama3.2 worked example must FIT a 16GB machine, and gemma4:e2b (7.2GB "2B") must
// badge WON'T-FIT on 8GB (the A7 headroom rationale). Tier floors are decimal-MiB by design (A2).
import 'package:quorum_core/quorum_core.dart';
import 'package:test/test.dart';

void main() {
  group('deviceTier', () {
    test('boundaries: 11.9GB → lite, 12000 → core (inclusive), 32000 → max (inclusive)', () {
      expect(deviceTier(11900), DeviceTier.lite);
      expect(deviceTier(12000), DeviceTier.core);
      expect(deviceTier(31999), DeviceTier.core);
      expect(deviceTier(32000), DeviceTier.max);
    });

    test('A2 codified: a physical 32GB machine reporting ~31.7GiB usable is STILL... core? No — max', () {
      // Windows reserves ~0.3–1GiB, so a nominal-32GB machine reports ~32,460 MiB. The decimal
      // floors (32000, not binary 32768) exist precisely so this machine lands in max. This test
      // goes red if anyone "fixes" the floors to binary GiB marks.
      expect(deviceTier(32460), DeviceTier.max);
    });

    test('extremes clamp sanely', () {
      expect(deviceTier(0), DeviceTier.lite);
      expect(deviceTier(4096), DeviceTier.lite);
      expect(deviceTier(131072), DeviceTier.max);
    });
  });

  group('kvBytes', () {
    test('reproduces the live-verified llama3.2 anchor (28×8×256×4096×2) — ctx-explicit', () {
      expect(
        kvBytes(blockCount: 28, headCountKv: 8, keyLength: 128, valueLength: 128, ctx: 4096),
        469762048,
      );
      // The same anchor at the current default ctx (8192, measured on Ollama 0.32).
      expect(
        kvBytes(blockCount: 28, headCountKv: 8, keyLength: 128, valueLength: 128),
        939524096,
      );
    });
  });

  group('fitBadge', () {
    test('plan anchor 1: llama3.2 (1.9GB + 0.44GiB KV) FITS a 16GB machine', () {
      expect(
        fitBadge(modelBytes: 1900000000, kvBytes: 469762048, deviceRamMb: 16384),
        FitBadge.fits,
      );
    });

    test('plan anchor 2: gemma4:e2b (7.2GB) WON\'T FIT an 8GB machine — even at realistic reported RAM', () {
      // KV at the corrected /api/show geometry (35×1×1024×8192×2); the badge verdict is also
      // empirically anchored: CPU-only RSS measured 7,346 MiB on 2026-07-16 — a real 8GB machine
      // pages per-token (the cited field report's multi-minute responses corroborate).
      expect(
        fitBadge(modelBytes: 7162394016, kvBytes: 587202560, deviceRamMb: 8192),
        FitBadge.wontFit,
      );
      // A real "8GB" machine reports less than nominal — still wontFit.
      expect(
        fitBadge(modelBytes: 7162394016, kvBytes: 587202560, deviceRamMb: 8062),
        FitBadge.wontFit,
      );
    });

    test('the tight band exists: a 14B-class model on a 12GiB device loads but is under pressure', () {
      expect(
        fitBadge(modelBytes: 9300000000, kvBytes: 1342177280, deviceRamMb: 12288),
        FitBadge.tight,
      );
    });

    test('exact boundary semantics at both headroom bounds', () {
      const ramMb = 16000;
      final ramBytes = ramMb * 1024 * 1024;
      final atFits = ramBytes - kFitsHeadroomBytes; // model+kv exactly consumes the fits bound
      expect(fitBadge(modelBytes: atFits, kvBytes: 0, deviceRamMb: ramMb), FitBadge.fits);
      expect(fitBadge(modelBytes: atFits + 1, kvBytes: 0, deviceRamMb: ramMb), FitBadge.tight);
      final atTight = ramBytes - kTightHeadroomBytes;
      expect(fitBadge(modelBytes: atTight, kvBytes: 0, deviceRamMb: ramMb), FitBadge.tight);
      expect(fitBadge(modelBytes: atTight + 1, kvBytes: 0, deviceRamMb: ramMb), FitBadge.wontFit);
    });

    test('A2 regression tripwire: each tier default fits at its own tier floor', () {
      // Goes red if a future headroom bump silently breaks the tier table's internal consistency.
      // KV values at the served KV_CTX (8192). lite default (qwen3.5:2b) on a realistic reported
      // "8GB" device (8062 MiB — real machines report under nominal):
      expect(
        fitBadge(modelBytes: 2741180928, kvBytes: 402653184, deviceRamMb: 8062),
        FitBadge.fits,
      );
      // core default (qwen3.5:9b) at the core floor:
      expect(
        fitBadge(modelBytes: 6594462816, kvBytes: 1073741824, deviceRamMb: kCoreTierFloorMb),
        FitBadge.fits,
      );
      // max default (qwen3.6:35b) at the max floor:
      expect(
        fitBadge(modelBytes: 23938321664, kvBytes: 671088640, deviceRamMb: kMaxTierFloorMb),
        FitBadge.fits,
      );
    });
  });
}
