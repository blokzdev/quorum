import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quorum_core/quorum_core.dart';

import '../state/run_controller.dart';
import 'quorum_colors.dart';

/// The live screen: watches the run and wires the Run/Cancel actions + orphan-free exit teardown.
class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({super.key});
  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> with WidgetsBindingObserver {
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
    final state = ref.watch(runControllerProvider);
    final ctrl = ref.read(runControllerProvider.notifier);
    return TerminalBody(
      state: state,
      onRun: () => ctrl.start(),
      onCancel: ctrl.cancel,
    );
  }
}

/// The pure 3-pane research terminal, rendered from a [RunViewState]. No providers → golden-testable.
class TerminalBody extends StatelessWidget {
  final RunViewState state;
  final VoidCallback? onRun;
  final VoidCallback? onCancel;

  const TerminalBody({super.key, required this.state, this.onRun, this.onCancel});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: QC.bg,
      child: Column(
        children: [
          _Header(state: state, onRun: onRun, onCancel: onCancel),
          const Divider(height: 1, color: QC.border),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 264, child: _PipelineRail(state)),
                const VerticalDivider(width: 1, color: QC.border),
                Expanded(child: _ReasoningPane(state)),
                const VerticalDivider(width: 1, color: QC.border),
                SizedBox(width: 340, child: _VerdictRail(state)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final RunViewState state;
  final VoidCallback? onRun;
  final VoidCallback? onCancel;
  const _Header({required this.state, this.onRun, this.onCancel});

  @override
  Widget build(BuildContext context) {
    final running = state.phase == RunPhase.running;
    return Container(
      height: 56,
      color: QC.surface1,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          const _Wordmark(),
          const SizedBox(width: 20),
          if (state.ticker != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: QC.surface2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: QC.border),
              ),
              child: Text(state.ticker!,
                  style: const TextStyle(
                      color: QC.textHi, fontFeatures: [FontFeature.tabularFigures()], fontWeight: FontWeight.w600)),
            ),
          const SizedBox(width: 12),
          _PhaseChip(state.phase),
          const Spacer(),
          if (running)
            TextButton.icon(
              onPressed: onCancel,
              icon: const Icon(Icons.stop_circle_outlined, size: 18, color: QC.textMid),
              label: const Text('Cancel', style: TextStyle(color: QC.textMid)),
            )
          else
            FilledButton.icon(
              onPressed: onRun,
              style: FilledButton.styleFrom(backgroundColor: QC.accent),
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text('Run analysis'),
            ),
        ],
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      // The ascending-bars mark.
      SizedBox(
        width: 22,
        height: 22,
        child: CustomPaint(painter: _BarsMarkPainter()),
      ),
      const SizedBox(width: 10),
      const Text('Quorum',
          style: TextStyle(color: QC.textHi, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
    ]);
  }
}

class _BarsMarkPainter extends CustomPainter {
  static const _bars = [
    (0.05, 0.35, Color(0xFF3D7DFF)),
    (0.38, 0.55, Color(0xFF36A6C6)),
    (0.71, 0.95, Color(0xFF2BC57E)),
  ];
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width * 0.22;
    for (final (x, h, c) in _bars) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(s.width * x, s.height * (1 - h), w, s.height * h),
        const Radius.circular(2),
      );
      canvas.drawRRect(rect, Paint()..color = c);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _PhaseChip extends StatelessWidget {
  final RunPhase phase;
  const _PhaseChip(this.phase);
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (phase) {
      RunPhase.running => ('Running', QC.accent),
      RunPhase.done => ('Complete', QC.up),
      RunPhase.cancelled => ('Cancelled', QC.textMid),
      RunPhase.error => ('Error', QC.down),
      RunPhase.idle => ('Idle', QC.textLo),
    };
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.circle, size: 8, color: color),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(color: color, fontSize: 13)),
    ]);
  }
}

class _PipelineRail extends StatelessWidget {
  final RunViewState state;
  const _PipelineRail(this.state);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: QC.surface1,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        children: [
          for (final entry in stageMeta.entries) ...[
            _StageHeader(entry.value.$1, state.stages[entry.key]),
            for (final agent in entry.value.$2) _AgentRow(agent, state.agents[agent]),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

class _StageHeader extends StatelessWidget {
  final String label;
  final NodeStatus? status;
  const _StageHeader(this.label, this.status);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w700,
              color: status == NodeStatus.done ? QC.textMid : QC.textLo,
            )),
      );
}

class _AgentRow extends StatelessWidget {
  final AgentId agent;
  final NodeStatus? status;
  const _AgentRow(this.agent, this.status);

  @override
  Widget build(BuildContext context) {
    final dot = switch (status) {
      NodeStatus.done => QC.up,
      NodeStatus.running => agentColor(agent),
      NodeStatus.error => QC.down,
      _ => QC.textLo,
    };
    final running = status == NodeStatus.running;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: running ? dot : (status == NodeStatus.done ? dot : Colors.transparent),
              shape: BoxShape.circle,
              border: Border.all(color: dot, width: 1.5),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(agentName(agent),
                style: TextStyle(
                  color: status == null || status == NodeStatus.pending ? QC.textLo : QC.textHi,
                  fontSize: 13.5,
                  fontWeight: running ? FontWeight.w600 : FontWeight.w400,
                )),
          ),
          if (running)
            const Text('•••', style: TextStyle(color: QC.accent, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ReasoningPane extends StatelessWidget {
  final RunViewState state;
  const _ReasoningPane(this.state);

  @override
  Widget build(BuildContext context) {
    // The currently-streaming agent (if any) shows its live reasoning at the top.
    final active = state.agents.entries
        .where((e) => e.value == NodeStatus.running)
        .map((e) => e.key)
        .firstOrNull;
    final liveText = active != null ? state.reasoningByAgent[active.name] : null;

    final sections = [
      for (final key in sectionTitle.keys)
        if (state.reports[key] != null) state.reports[key]!,
    ];

    if (sections.isEmpty && liveText == null) {
      return const Center(
        child: Text('Run an analysis to watch the council deliberate.',
            style: TextStyle(color: QC.textLo, fontSize: 15)),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (active != null && liveText != null && liveText.isNotEmpty)
          _LiveReasoningCard(agent: active, text: liveText),
        for (final s in sections.reversed) _SectionCard(s),
      ],
    );
  }
}

class _LiveReasoningCard extends StatelessWidget {
  final AgentId agent;
  final String text;
  const _LiveReasoningCard({required this.agent, required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: QC.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: agentColor(agent).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.bolt, size: 14, color: agentColor(agent)),
            const SizedBox(width: 6),
            Text('${agentName(agent)} · thinking',
                style: TextStyle(color: agentColor(agent), fontWeight: FontWeight.w600, fontSize: 13)),
          ]),
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(color: QC.textHi, height: 1.5, fontSize: 14)),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final ReportSection section;
  const _SectionCard(this.section);
  @override
  Widget build(BuildContext context) {
    final title = sectionTitle[section.section] ?? section.section;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: QC.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: QC.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
              style: const TextStyle(
                  color: QC.textMid, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(section.markdown, style: const TextStyle(color: QC.textHi, height: 1.5, fontSize: 14)),
        ],
      ),
    );
  }
}

class _VerdictRail extends StatelessWidget {
  final RunViewState state;
  const _VerdictRail(this.state);

  @override
  Widget build(BuildContext context) {
    final v = state.verdict;
    return Container(
      color: QC.surface1,
      padding: const EdgeInsets.all(20),
      child: v == null
          ? Center(
              child: Text(
                state.phase == RunPhase.running ? 'Deliberating…' : 'No verdict yet',
                style: const TextStyle(color: QC.textLo, fontSize: 15),
              ),
            )
          : ListView(
              children: [
                const Text('VERDICT',
                    style: TextStyle(
                        color: QC.textLo, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                _RatingPill(v.rating),
                if (v.confidence != null) ...[
                  const SizedBox(height: 16),
                  _Confidence(v.confidence!),
                ],
                if (v.thesis != null) ...[
                  const SizedBox(height: 16),
                  Text(v.thesis!,
                      style: const TextStyle(
                          color: QC.textHi, fontSize: 15, height: 1.5, fontStyle: FontStyle.italic)),
                ],
                const SizedBox(height: 20),
                _Levels(v),
              ],
            ),
    );
  }
}

class _RatingPill extends StatelessWidget {
  final String? rating;
  const _RatingPill(this.rating);
  @override
  Widget build(BuildContext context) {
    final color = ratingColor(rating);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text((rating ?? '—').toUpperCase(),
          style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 1)),
    );
  }
}

class _Confidence extends StatelessWidget {
  final double value; // 0..1
  const _Confidence(this.value);
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Text('Confidence', style: TextStyle(color: QC.textMid, fontSize: 13)),
          const Spacer(),
          Text('${(value * 100).round()}%',
              style: const TextStyle(
                  color: QC.textHi, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 6,
            backgroundColor: QC.surface2,
            valueColor: const AlwaysStoppedAnimation(QC.accent),
          ),
        ),
      ],
    );
  }
}

class _Levels extends StatelessWidget {
  final Verdict v;
  const _Levels(this.v);
  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      if (v.entryPrice != null) ('Entry', v.entryPrice!.toStringAsFixed(0)),
      if (v.priceTarget != null) ('Target', v.priceTarget!.toStringAsFixed(0)),
      if (v.stopLoss != null) ('Stop', v.stopLoss!.toStringAsFixed(0)),
      if (v.timeHorizon != null) ('Horizon', v.timeHorizon!),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: QC.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: QC.border),
      ),
      child: Column(
        children: [
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Text(label, style: const TextStyle(color: QC.textMid, fontSize: 13)),
                const Spacer(),
                Text(value,
                    style: const TextStyle(
                        color: QC.textHi,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()])),
              ]),
            ),
        ],
      ),
    );
  }
}
