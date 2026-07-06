import 'dart:math' as math;

import 'package:flutter/painting.dart' show Color;

/// WCAG 2.x relative-luminance + contrast ratio — pure Dart (no Flutter binding), so the design's
/// colour-accessibility can be unit-tested. Used to prove the on-accent button label clears AA-normal
/// (≥4.5:1), which white-on-accent did not (3.77:1).
double _channel(int v) {
  final c = v / 255.0;
  return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double relativeLuminance(Color c) =>
    0.2126 * _channel((c.r * 255).round()) +
    0.7152 * _channel((c.g * 255).round()) +
    0.0722 * _channel((c.b * 255).round());

/// The WCAG contrast ratio between two colours, in [1, 21]. Order-independent.
double wcagContrast(Color a, Color b) {
  final la = relativeLuminance(a), lb = relativeLuminance(b);
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// AA-safe text ink for a **tinted chip** — a pill whose fill is the same [hue] at low [fillAlpha]
/// over [surface], with [hue] itself as the label. A saturated/recessive hue on its own faint tint
/// can fall below WCAG AA-normal (e.g. accent 4.0:1, textLo 4.22:1); this returns [hue] unchanged when
/// it already clears [target], else lightens it toward white just enough to clear the bar. Pass the
/// **lightest** surface the chip renders on (the worst case for a lightened ink), so the result also
/// holds on any darker surface. Pure (unit-tested in contrast_test.dart), like [wcagContrast].
Color accessibleTint(Color hue, Color surface, {double fillAlpha = 0.14, double target = 4.5}) {
  final bg = Color.alphaBlend(hue.withValues(alpha: fillAlpha), surface);
  if (wcagContrast(hue, bg) >= target) return hue;
  const white = Color(0xFFFFFFFF);
  for (var t = 0.06; t < 1.0; t += 0.04) {
    final ink = Color.lerp(hue, white, t)!;
    if (wcagContrast(ink, bg) >= target) return ink;
  }
  return white;
}
