import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/quorum_colors.dart';
import 'ui/terminal_screen.dart';

void main() {
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
      ),
      home: const Scaffold(body: TerminalScreen()),
    );
  }
}
