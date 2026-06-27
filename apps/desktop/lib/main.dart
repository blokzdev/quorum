import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'ui/brand.dart';
import 'ui/quorum_colors.dart';
import 'ui/quorum_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  const opts = WindowOptions(
    size: Size(1320, 860),
    minimumSize: Size(1040, 680),
    center: true,
    // Opaque dark background (NOT transparent) — avoids the Windows white-flash / compositor-artifact
    // class of bugs while still giving us a frameless, custom-title-bar window.
    backgroundColor: QC.bg,
    titleBarStyle: TitleBarStyle.hidden,
  );
  await windowManager.waitUntilReadyToShow(opts, () async {
    // Arm the close hook BEFORE showing so the sidecar always gets a chance to tear down on close.
    await windowManager.setPreventClose(true);
    await windowManager.show();
    await windowManager.focus();
  });
  runApp(const ProviderScope(child: QuorumApp()));
}

class QuorumApp extends StatelessWidget {
  const QuorumApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData.dark(useMaterial3: true);
    return MaterialApp(
      title: 'Quorum',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        scaffoldBackgroundColor: QC.bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: QC.accent,
          brightness: Brightness.dark,
          surface: QC.bg,
        ),
        // Inter app-wide; numeric widgets opt into JetBrains Mono via QC.fontMono.
        textTheme: base.textTheme.apply(fontFamily: QC.fontUi),
        primaryTextTheme: base.primaryTextTheme.apply(fontFamily: QC.fontUi),
        // Brand tokens for new surfaces (Hub, Settings/Model Studio) via Theme.of(context).extension.
        extensions: const [QuorumBrand.dark()],
      ),
      home: const QuorumShell(),
    );
  }
}
