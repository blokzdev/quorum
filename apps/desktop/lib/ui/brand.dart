import 'package:flutter/material.dart';

import 'quorum_colors.dart';

/// The Quorum design system as a Material 3 [ThemeExtension]. New surfaces (Hub, Settings/Model
/// Studio) read brand tokens from `Theme.of(context).extension<QuorumBrand>()`.
///
/// The existing terminal still uses the [QC] consts directly — its `CustomPainter`s have no
/// `BuildContext`, so they can't read the extension. [QuorumBrand.dark] reads its values FROM those
/// same [QC] consts, so there is exactly one numeric source of truth (no re-typed hex). Agent /
/// section / stage metadata and the `agentColor` / `ratingColor` helpers remain top-level in
/// `quorum_colors.dart`. Retiring [QC] in favour of the extension everywhere is a tracked
/// post-P2.2 cleanup.
@immutable
class QuorumBrand extends ThemeExtension<QuorumBrand> {
  final Color bg;
  final Color surface1;
  final Color surface2;
  final Color border;
  final Color textHi;
  final Color textMid;
  final Color textLo;
  final Color accent;
  final Color onAccent;
  final Color up;
  final Color down;
  final Color warning;
  final String fontUi;
  final String fontMono;

  const QuorumBrand({
    required this.bg,
    required this.surface1,
    required this.surface2,
    required this.border,
    required this.textHi,
    required this.textMid,
    required this.textLo,
    required this.accent,
    required this.onAccent,
    required this.up,
    required this.down,
    required this.warning,
    required this.fontUi,
    required this.fontMono,
  });

  /// The dark calm-luxury brand — every value references the [QC] consts (the single source).
  const QuorumBrand.dark()
      : bg = QC.bg,
        surface1 = QC.surface1,
        surface2 = QC.surface2,
        border = QC.border,
        textHi = QC.textHi,
        textMid = QC.textMid,
        textLo = QC.textLo,
        accent = QC.accent,
        onAccent = QC.onAccent,
        up = QC.up,
        down = QC.down,
        warning = QC.warning,
        fontUi = QC.fontUi,
        fontMono = QC.fontMono;

  @override
  QuorumBrand copyWith({
    Color? bg,
    Color? surface1,
    Color? surface2,
    Color? border,
    Color? textHi,
    Color? textMid,
    Color? textLo,
    Color? accent,
    Color? onAccent,
    Color? up,
    Color? down,
    Color? warning,
    String? fontUi,
    String? fontMono,
  }) {
    return QuorumBrand(
      bg: bg ?? this.bg,
      surface1: surface1 ?? this.surface1,
      surface2: surface2 ?? this.surface2,
      border: border ?? this.border,
      textHi: textHi ?? this.textHi,
      textMid: textMid ?? this.textMid,
      textLo: textLo ?? this.textLo,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      up: up ?? this.up,
      down: down ?? this.down,
      warning: warning ?? this.warning,
      fontUi: fontUi ?? this.fontUi,
      fontMono: fontMono ?? this.fontMono,
    );
  }

  @override
  QuorumBrand lerp(ThemeExtension<QuorumBrand>? other, double t) {
    // Dark-only brand: discrete switch (there is no light variant to interpolate toward yet).
    // A future light theme must deep-copy any map-valued fields if they are added here.
    if (other is! QuorumBrand) return this;
    return t < 0.5 ? this : other;
  }
}
