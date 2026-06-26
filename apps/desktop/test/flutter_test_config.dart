import 'dart:async';
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
  await testMain();
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
