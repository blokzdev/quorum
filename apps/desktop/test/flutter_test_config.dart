import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Load the bundled brand fonts so golden renders use the SAME type as the shipping app (Flutter's
/// test font renders glyphs as boxes otherwise). Paths are relative to the test cwd (apps/desktop),
/// matching the `fonts/` assets declared in pubspec.yaml — so committed goldens are now portable
/// across machines/CI instead of depending on installed system fonts.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _load('Inter', [
    'fonts/Inter-Regular.ttf',
    'fonts/Inter-Medium.ttf',
    'fonts/Inter-SemiBold.ttf',
    'fonts/Inter-Bold.ttf',
    'fonts/Inter-ExtraBold.ttf',
  ]);
  await _load('JetBrainsMono', ['fonts/JetBrainsMono-Regular.ttf', 'fonts/JetBrainsMono-Medium.ttf']);
  // Load the icon font(s) from the test asset bundle too, so Material glyphs (dropdown chevrons,
  // check/stop/gavel icons, …) render as real icons in goldens instead of tofu boxes.
  await _loadBundledIconFonts();
  await testMain();
}

/// Load MaterialIcons (and Cupertino, if present) from the built asset bundle via FontManifest.json.
/// Best-effort: if the manifest can't be read the glyphs simply fall back to boxes (non-fatal).
Future<void> _loadBundledIconFonts() async {
  try {
    final manifest = json.decode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final family = entry['family'] as String? ?? '';
      if (!family.contains('MaterialIcons') && !family.contains('CupertinoIcons')) continue;
      final loader = FontLoader(family);
      for (final font in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        final asset = font['asset'] as String?;
        if (asset != null) loader.addFont(rootBundle.load(asset));
      }
      await loader.load();
    }
  } catch (_) {/* icon glyphs fall back to boxes; non-fatal */}
}

Future<void> _load(String family, List<String> paths) async {
  final loader = FontLoader(family);
  var any = false;
  for (final path in paths) {
    final file = File(path);
    if (file.existsSync()) {
      loader.addFont(Future.value(file.readAsBytesSync().buffer.asByteData()));
      any = true;
    }
  }
  if (any) await loader.load();
}
