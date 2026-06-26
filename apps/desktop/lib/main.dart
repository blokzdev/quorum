import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quorum_core/quorum_core.dart';

import 'state/run_controller.dart';

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
        scaffoldBackgroundColor: const Color(0xFF0A0C10),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF12151C)),
      ),
      home: const DebugScreen(),
    );
  }
}

/// S2 throwaway: a live dump of [RunViewState] proving the app spawns the sidecar and streams a run.
/// The real 3-pane UI is S3.
class DebugScreen extends ConsumerStatefulWidget {
  const DebugScreen({super.key});
  @override
  ConsumerState<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends ConsumerState<DebugScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // The close button on desktop routes through here — tear the sidecar down before exiting.
  @override
  Future<AppExitResponse> didRequestAppExit() async {
    await ref.read(runControllerProvider.notifier).shutdown();
    return AppExitResponse.exit;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      ref.read(runControllerProvider.notifier).shutdown();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(runControllerProvider);
    final log = ref.watch(sidecarLogProvider);
    final ctrl = ref.read(runControllerProvider.notifier);
    final running = s.phase == RunPhase.running;

    return Scaffold(
      appBar: AppBar(
        title: Text('Quorum — S2 debug  ·  ${s.phase.name}'
            '${s.ticker != null ? '  ·  ${s.ticker}' : ''}'),
        actions: [
          if (running)
            TextButton.icon(
              onPressed: ctrl.cancel,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('Cancel'),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: running ? null : () => ctrl.start(),
        icon: const Icon(Icons.play_arrow),
        label: Text(running ? 'Running…' : 'Run demo'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: ListView(
                children: [
                  const _H('Stages'),
                  for (final stage in _orderedStages) _StatusRow(stage.name, s.stages[stage]),
                  const SizedBox(height: 12),
                  const _H('Agents'),
                  for (final agent in s.agents.keys) _StatusRow(agent.name, s.agents[agent]),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 3,
              child: ListView(
                children: [
                  const _H('Verdict'),
                  if (s.verdict != null)
                    Text('${s.verdict!.rating ?? '—'}  ·  ${s.verdict!.finalDecision}',
                        style: const TextStyle(fontSize: 16, color: Color(0xFF26C281)))
                  else
                    const Text('—', style: TextStyle(color: Color(0xFF9AA4B2))),
                  if (s.error != null) ...[
                    const SizedBox(height: 8),
                    Text('error: ${s.error}', style: const TextStyle(color: Color(0xFFFF5C5C))),
                  ],
                  const SizedBox(height: 12),
                  const _H('Reports'),
                  for (final entry in s.reports.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('• ${entry.key}: ${_trim(entry.value.markdown)}',
                          style: const TextStyle(color: Color(0xFFE6EAF2))),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _H('Sidecar log'),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      color: const Color(0xFF12151C),
                      child: ListView(
                        children: [
                          for (final line in log.reversed.take(40))
                            Text(line,
                                style: const TextStyle(
                                    fontFamily: 'monospace', fontSize: 11, color: Color(0xFF9AA4B2))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _orderedStages = [
    Stage.analysts, Stage.researchDebate, Stage.trader, Stage.riskDebate, Stage.portfolio,
  ];

  static String _trim(String s) => s.length > 80 ? '${s.substring(0, 80)}…' : s;
}

class _H extends StatelessWidget {
  final String text;
  const _H(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 11, letterSpacing: 1.5, color: Color(0xFF5B6473),
                fontWeight: FontWeight.w600)),
      );
}

class _StatusRow extends StatelessWidget {
  final String label;
  final NodeStatus? status;
  const _StatusRow(this.label, this.status);

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      NodeStatus.done => const Color(0xFF26C281),
      NodeStatus.running => const Color(0xFF3D7DFF),
      NodeStatus.error => const Color(0xFFFF5C5C),
      _ => const Color(0xFF5B6473),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Color(0xFFE6EAF2))),
          const Spacer(),
          Text(status?.name ?? 'pending', style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}
