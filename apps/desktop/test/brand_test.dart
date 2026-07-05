import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quorum/ui/brand.dart';
import 'package:quorum/ui/quorum_colors.dart';

void main() {
  test('QuorumBrand.dark() mirrors the QC consts (single numeric source of truth)', () {
    const b = QuorumBrand.dark();
    expect(b.bg, QC.bg);
    expect(b.surface1, QC.surface1);
    expect(b.surface2, QC.surface2);
    expect(b.border, QC.border);
    expect(b.textHi, QC.textHi);
    expect(b.textMid, QC.textMid);
    expect(b.textLo, QC.textLo);
    expect(b.accent, QC.accent);
    expect(b.up, QC.up);
    expect(b.down, QC.down);
    expect(b.warning, QC.warning);
    expect(b.fontUi, QC.fontUi);
    expect(b.fontMono, QC.fontMono);
  });

  testWidgets('QuorumBrand is registered on the theme and readable via extension', (tester) async {
    QuorumBrand? brand;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: const [QuorumBrand.dark()]),
      home: Builder(builder: (context) {
        brand = Theme.of(context).extension<QuorumBrand>();
        return const SizedBox();
      }),
    ));
    expect(brand, isNotNull);
    expect(brand!.accent, QC.accent);
    expect(brand!.fontMono, QC.fontMono);
  });

  test('copyWith overrides only the given field', () {
    const b = QuorumBrand.dark();
    final n = b.copyWith(accent: const Color(0xFF000000));
    expect(n.accent, const Color(0xFF000000));
    expect(n.bg, QC.bg);
  });
}
