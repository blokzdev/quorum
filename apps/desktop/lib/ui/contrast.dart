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
