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
    return MaterialApp(
      title: 'Quorum',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: QC.bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: QC.accent,
          brightness: Brightness.dark,
          surface: QC.bg,
        ),
      ),
      home: const Scaffold(body: TerminalScreen()),
    );
  }
}
