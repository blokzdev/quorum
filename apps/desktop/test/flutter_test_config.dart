import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Load real system fonts so golden renders show legible text (Flutter's test font renders glyphs as
/// boxes otherwise). S3 uses Segoe UI as a stand-in for visual critique; S4 bundles Inter/JetBrains Mono.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _load('SegoeUI', [r'C:\Windows\Fonts\segoeui.ttf', r'C:\Windows\Fonts\segoeuib.ttf']);
  await _load('Mono', [r'C:\Windows\Fonts\consola.ttf']);
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
