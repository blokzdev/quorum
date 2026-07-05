import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:quorum/ui/contrast.dart';
import 'package:quorum/ui/quorum_colors.dart';

/// P3.4b: the "Run analysis" filled-accent button label must clear WCAG AA-normal (≥4.5:1). This is the
/// falsification test — it fails for the old white label (3.77:1) and passes for the new onAccent ink.
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
}
