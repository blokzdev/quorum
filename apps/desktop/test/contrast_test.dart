import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:quorum/ui/contrast.dart';
import 'package:quorum/ui/quorum_colors.dart';

/// P3.4b: the "Run analysis" filled-accent button label must clear WCAG AA-normal (≥4.5:1). This is the
/// falsification test — it fails for the old white label (3.77:1) and passes for the new onAccent ink.
/// The composited background a tinted chip paints its label on: the hue at [a] over [surface].
Color _tintBg(Color hue, Color surface, double a) =>
    Color.alphaBlend(hue.withValues(alpha: a), surface);

void main() {
  const white = Color(0xFFFFFFFF);

  test('QC.onAccent on QC.accent clears WCAG AA-normal (≥4.5:1)', () {
    final ratio = wcagContrast(QC.onAccent, QC.accent);
    expect(ratio, greaterThanOrEqualTo(4.5), reason: 'Run-button label must pass AA-normal');
  });

  test('the old white-on-accent label FAILED AA-normal (the bug this fixes)', () {
    // Locks in the regression: white on the accent fill is 3.77:1 — below 4.5.
    final ratio = wcagContrast(white, QC.accent);
    expect(ratio, lessThan(4.5));
    expect(ratio, closeTo(3.77, 0.05));
  });

  test('contrast is order-independent and self-contrast is 1.0', () {
    expect(wcagContrast(QC.accent, QC.onAccent), closeTo(wcagContrast(QC.onAccent, QC.accent), 1e-9));
    expect(wcagContrast(white, white), closeTo(1.0, 1e-9));
    // Black on white is the maximal 21:1.
    expect(wcagContrast(const Color(0xFF000000), white), closeTo(21.0, 0.1));
  });

  // P4.2a: tinted signal/rating chips (accent "pinned" badge, textLo confidence chip, rating pills)
  // put a saturated/recessive hue on its own faint tint — some fell below AA-normal. accessibleTint
  // lifts them; every chip ink must clear 4.5:1 on its composited background.
  test('accessibleTint makes every chip ink clear WCAG AA-normal (≥4.5:1)', () {
    // (hue, surface, fillAlpha) for the real chips: pinned badge, confidence, rating/stop, buy, hold, score.
    const cases = <(Color, Color, double)>[
      (QC.accent, QC.surface2, 0.16),
      (QC.textLo, QC.surface2, 0.13),
      (QC.down, QC.surface2, 0.14),
      (QC.up, QC.surface2, 0.14),
      (QC.warning, QC.surface2, 0.14),
      (QC.textMid, QC.surface2, 0.13),
    ];
    for (final (hue, surface, a) in cases) {
      final bg = _tintBg(hue, surface, a);
      expect(wcagContrast(accessibleTint(hue, surface, fillAlpha: a), bg),
          greaterThanOrEqualTo(4.5), reason: 'chip ink for $hue must pass AA-normal');
    }
  });

  test('accessibleTint lifts only the sub-AA hues; bright hues pass through unchanged', () {
    // Regression lock — these two were the audit failures (below 4.5 raw on their own tint).
    expect(wcagContrast(QC.accent, _tintBg(QC.accent, QC.surface2, 0.16)), lessThan(4.5));
    expect(wcagContrast(QC.textLo, _tintBg(QC.textLo, QC.surface2, 0.13)), lessThan(4.5));
    // Bright rating hues already pass → returned unchanged, so golden churn stays minimal.
    expect(accessibleTint(QC.up, QC.surface2, fillAlpha: 0.14), equals(QC.up));
    expect(accessibleTint(QC.warning, QC.surface2, fillAlpha: 0.14), equals(QC.warning));
  });
}
