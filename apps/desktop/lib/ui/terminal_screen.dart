import 'package:flutter/material.dart';
import 'package:quorum_core/quorum_core.dart';

import 'quorum_colors.dart';

/// Motion budget (calm-luxury): fast 120 / normal 180 / slow 240ms, ease-out. All animations are
/// FINITE (they settle) so golden pumpAndSettle never hangs; honour the OS reduce-motion setting.
const _motionNormal = Duration(milliseconds: 180);
const _motionSlow = Duration(milliseconds: 240);
Duration _motion(BuildContext ctx, Duration d) =>
    (MediaQuery.maybeOf(ctx)?.disableAnimations ?? false) ? Duration.zero : d;

/// A one-shot finite entrance — fade + a few-px rise — played once when a child first mounts. Built on
/// TweenAnimationBuilder (no controller, no Timer), so it settles in a single pass: golden
/// pumpAndSettle reaches the end frame, where Opacity(1)/translate(0) is pixel-identical to the bare
/// child (goldens don't move), and reduce-motion collapses it to an instant end-frame via [_motion].
class _Reveal extends StatelessWidget {
  final Widget child;
  const _Reveal({required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: _motion(context, _motionNormal),
      curve: Curves.easeOut,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, (1 - t) * 6), child: child),
      ),
    );
  }
}

/// The pure 3-pane research terminal, rendered from a [RunViewState]. No providers → golden-testable.
class TerminalBody extends StatelessWidget {
  final RunViewState state;
  final VoidCallback? onRun;
  final VoidCallback? onCancel;

  /// Test seam for golden determinism: a fixed elapsed value for the header timer. Null in production
  /// (the header derives elapsed from [RunViewState.startedAtTs] against the wall clock, ticked by
  /// the shell's [TerminalSurface]); the golden harness always passes a fixed value, so no
  /// `DateTime.now()` is ever reached in a golden.
  final Duration? elapsedOverride;

  /// Label for the primary action button (when not running). Defaults to "Run analysis"; the Hub's
  /// cached review passes "Re-run …" so a read-only past run doesn't present the same fresh-run CTA.
  final String runLabel;
  const TerminalBody({
    super.key,
    required this.state,
    this.onRun,
    this.onCancel,
    this.elapsedOverride,
    this.runLabel = 'Run analysis',
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: QC.bg,
      child: Column(
        children: [
          _Header(
              state: state,
              onRun: onRun,
              onCancel: onCancel,
              elapsedOverride: elapsedOverride,
              runLabel: runLabel),
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

/// Formats an elapsed [Duration] as mm:ss (zero-padded).
String _fmtElapsed(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

class _Header extends StatelessWidget {
  final RunViewState state;
  final VoidCallback? onRun;
  final VoidCallback? onCancel;
  final Duration? elapsedOverride;
  final String runLabel;
  const _Header(
      {required this.state, this.onRun, this.onCancel, this.elapsedOverride, this.runLabel = 'Run analysis'});

  /// Elapsed since the run started: the fixed [elapsedOverride] if given (goldens), else derived live
  /// from [RunViewState.startedAtTs]. Null when there is no valid start (e.g. demo before the seed).
  Duration? _elapsed() {
    if (elapsedOverride != null) return elapsedOverride;
    final ts = state.startedAtTs;
    if (ts == null || ts <= 0) return null;
    final secs = (DateTime.now().millisecondsSinceEpoch / 1000.0 - ts).round();
    return secs >= 0 ? Duration(seconds: secs) : null;
  }

  @override
  Widget build(BuildContext context) {
    final running = state.phase == RunPhase.running;
    final elapsed = _elapsed();
    return Container(
      height: 56,
      color: QC.surface1,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          const _Wordmark(),
          const SizedBox(width: 20),
          if (state.ticker != null) ...[
            Container(
              constraints: const BoxConstraints(maxWidth: 120),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: QC.surface2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: QC.border),
              ),
              child: Text(state.ticker!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: QC.textHi,
                      fontFamily: QC.fontMono,
                      fontWeight: FontWeight.w600)),
            ),
            if (state.tradeDate != null) ...[
              const SizedBox(width: 10),
              _AsOfBadge(state.tradeDate!),
            ],
          ],
          const SizedBox(width: 14),
          _PhaseChip(state.phase),
          if (running && elapsed != null) ...[
            const SizedBox(width: 12),
            Text(_fmtElapsed(elapsed),
                style: const TextStyle(color: QC.textMid, fontFamily: QC.fontMono, fontSize: 13)),
          ],
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
              label: Text(runLabel),
            ),
        ],
      ),
    );
  }
}

/// The run's data date beside the ticker, always labelled "as-of DATE" so a historical run's date is
/// unmistakable (a live run reads "as-of &lt;today&gt;", which is accurate). Deliberately does NOT recompute
/// "is this historical?" from `DateTime.now()` — that would be non-deterministic (drifting with the wall
/// clock, and retroactively re-flagging fixed-date goldens). The live-vs-historical *distinction* with
/// warning emphasis lives on the Hub launch card, where "today" is unambiguous at pick time.
class _AsOfBadge extends StatelessWidget {
  final String tradeDate;
  const _AsOfBadge(this.tradeDate);

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.event_outlined, size: 13, color: QC.textLo),
      const SizedBox(width: 5),
      Text('as-of $tradeDate', style: const TextStyle(color: QC.textMid, fontSize: 13)),
    ]);
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      SizedBox(width: 22, height: 22, child: CustomPaint(painter: _BarsMarkPainter())),
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
    return Semantics(
      label: 'Run status: $label',
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.circle, size: 8, color: color),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color, fontSize: 13)),
      ]),
    );
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
    final running = status == NodeStatus.running;
    final color = switch (status) {
      NodeStatus.done => agentColor(agent),
      NodeStatus.running => agentColor(agent),
      NodeStatus.error => QC.down,
      _ => QC.textLo,
    };
    final icon = switch (status) {
      NodeStatus.done => Icons.check_circle,
      NodeStatus.running => Icons.circle,
      NodeStatus.error => Icons.error,
      _ => Icons.radio_button_unchecked,
    };
    final label = '${agentName(agent)}: ${status?.name ?? 'pending'}';
    return Semantics(
      label: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 11),
            Expanded(
              child: Text(agentName(agent),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: status == null || status == NodeStatus.pending ? QC.textLo : QC.textHi,
                    fontSize: 13.5,
                    fontWeight: running ? FontWeight.w600 : FontWeight.w400,
                  )),
            ),
            if (running) const Text('•••', style: TextStyle(color: QC.accent, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _ReasoningPane extends StatelessWidget {
  final RunViewState state;
  const _ReasoningPane(this.state);

  static const _decisionKeys = ['final_trade_decision', 'trader_investment_plan'];
  static const _riskKeys = ['aggressive', 'neutral', 'conservative'];
  static const _analystKeys = ['fundamentals_report', 'news_report', 'sentiment_report', 'market_report'];

  @override
  Widget build(BuildContext context) {
    final active = state.agents.entries
        .where((e) => e.value == NodeStatus.running)
        .map((e) => e.key)
        .firstOrNull;
    final liveText = active != null ? state.reasoningByAgent[active.name] : null;

    ReportSection? rep(String k) => state.reports[k];
    final decision = [for (final k in _decisionKeys) if (rep(k) != null) rep(k)!];
    final bull = rep('bull');
    final bear = rep('bear');
    final rmPlan = rep('investment_plan');
    final hasDebate = bull != null || bear != null || rmPlan != null;
    final riskViews = [for (final k in _riskKeys) if (rep(k) != null) rep(k)!];
    final analyst = [for (final k in _analystKeys) if (rep(k) != null) rep(k)!];
    final ratingAccent = ratingColor(state.verdict?.rating);

    final hasLive = active != null && liveText != null && liveText.isNotEmpty;
    if (decision.isEmpty && !hasDebate && riskViews.isEmpty && analyst.isEmpty && !hasLive) {
      return const Center(
        child: Text('Run an analysis to watch the council deliberate.',
            style: TextStyle(color: QC.textLo, fontSize: 15)),
      );
    }

    // IA: the answer (decision) first, then the research debate as a tug-of-war, then the risk
    // debate, then the raw analyst evidence as supporting drill-down.
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (hasLive) _Reveal(child: _LiveReasoningCard(agent: active, text: liveText)),
        for (final s in decision)
          _Reveal(
            child: _SectionCard(s, emphasis: s.section == 'final_trade_decision', accent: ratingAccent),
          ),
        if (hasDebate) ...[
          const _Reveal(child: _GroupLabel('Research Debate')),
          _Reveal(
            child: _TugOfWar(
              bull: bull,
              bear: bear,
              managerPlan: rmPlan,
              bullLive: active == AgentId.bull,
              bearLive: active == AgentId.bear,
            ),
          ),
        ],
        if (riskViews.isNotEmpty) ...[
          const _Reveal(child: _GroupLabel('Risk Debate')),
          for (final s in riskViews) _Reveal(child: _SectionCard(s)),
        ],
        if (analyst.isNotEmpty) ...[
          const _Reveal(child: _GroupLabel('Analyst Evidence')),
          for (final s in analyst) _Reveal(child: _SectionCard(s)),
        ],
      ],
    );
  }
}

/// The bull-vs-bear "tug-of-war": two facing tinted columns (bull green / bear red) showing each
/// case, a balance bar leaning toward the side the Research Manager favored, resolving into the
/// manager's verdict ribbon.
class _TugOfWar extends StatelessWidget {
  final ReportSection? bull;
  final ReportSection? bear;
  final ReportSection? managerPlan;
  final bool bullLive;
  final bool bearLive;
  const _TugOfWar({this.bull, this.bear, this.managerPlan, this.bullLive = false, this.bearLive = false});

  @override
  Widget build(BuildContext context) {
    final lean = _lean(managerPlan?.markdown);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _DebateColumn(agent: AgentId.bull, section: bull, live: bullLive)),
                const SizedBox(width: 12),
                Expanded(child: _DebateColumn(agent: AgentId.bear, section: bear, live: bearLive)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _TugBar(lean: lean),
          if (managerPlan != null) ...[
            const SizedBox(height: 16),
            _DecisionRibbon(section: managerPlan!, lean: lean),
          ],
        ],
      ),
    );
  }

  /// Lean in [0,1] (0 = fully bear, 1 = fully bull), inferred from the manager's decision text.
  static double _lean(String? text) {
    if (text == null) return 0.5;
    final t = text.toLowerCase();
    const bullWords = ['bull', 'buy', 'long', 'constructive', 'upside', 'accumulate', 'outperform', 'overweight'];
    const bearWords = ['bear', 'sell', 'short', 'caution', 'downside', 'overvalued', 'underperform', 'underweight'];
    var score = 0;
    for (final w in bullWords) {
      if (t.contains(w)) score++;
    }
    for (final w in bearWords) {
      if (t.contains(w)) score--;
    }
    return (0.5 + 0.11 * score).clamp(0.22, 0.78);
  }
}

class _DebateColumn extends StatelessWidget {
  final AgentId agent;
  final ReportSection? section;
  final bool live;
  const _DebateColumn({required this.agent, this.section, this.live = false});

  @override
  Widget build(BuildContext context) {
    final c = agentColor(agent);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(width: 7, height: 7, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(agentName(agent).toUpperCase(),
                style: TextStyle(color: c, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
            if (live) ...[const SizedBox(width: 8), Text('•••', style: TextStyle(color: c, fontSize: 11))],
          ]),
          const SizedBox(height: 10),
          if (section != null)
            SelectableText(section!.markdown,
                style: const TextStyle(color: QC.textHi, height: 1.5, fontSize: 13.5))
          else
            Text(live ? 'Building its case…' : 'Awaiting rebuttal…',
                style: const TextStyle(color: QC.textLo, fontSize: 13, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
}

/// A horizontal balance bar: a green (bull) segment on the left and a red (bear) segment on the
/// right, split at [lean] with a knob — the wider side is "winning" the debate.
class _TugBar extends StatelessWidget {
  final double lean; // 0 = bear, 1 = bull
  const _TugBar({required this.lean});
  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Debate balance leans ${lean >= 0.5 ? 'bull' : 'bear'}',
      child: Column(children: [
        Row(children: const [
          Text('BULL',
              style: TextStyle(color: QC.up, fontSize: 10.5, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
          Spacer(),
          Text('BEAR',
              style: TextStyle(color: QC.down, fontSize: 10.5, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 7),
        SizedBox(
          height: 12,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.5, end: lean),
            duration: _motion(context, _motionSlow),
            curve: Curves.easeOut,
            builder: (_, v, _) => CustomPaint(size: Size.infinite, painter: _TugBarPainter(v)),
          ),
        ),
      ]),
    );
  }
}

class _TugBarPainter extends CustomPainter {
  final double lean;
  _TugBarPainter(this.lean);
  @override
  void paint(Canvas canvas, Size s) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(s.height / 2));
    canvas.save();
    canvas.clipRRect(rrect);
    final split = (s.width * lean).clamp(0.0, s.width);
    canvas.drawRect(Rect.fromLTWH(0, 0, split, s.height), Paint()..color = QC.up.withValues(alpha: 0.85));
    canvas.drawRect(
        Rect.fromLTWH(split, 0, s.width - split, s.height), Paint()..color = QC.down.withValues(alpha: 0.85));
    canvas.restore();
    final cx = split.clamp(7.0, s.width - 7.0);
    canvas.drawCircle(Offset(cx, s.height / 2), s.height / 2 + 1, Paint()..color = QC.bg);
    canvas.drawCircle(Offset(cx, s.height / 2), s.height / 2 - 1.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _TugBarPainter old) => old.lean != lean;
}

/// The Research Manager's resolution of the debate, tinted by which side won.
class _DecisionRibbon extends StatelessWidget {
  final ReportSection section;
  final double lean;
  const _DecisionRibbon({required this.section, required this.lean});
  @override
  Widget build(BuildContext context) {
    final c = lean >= 0.55 ? QC.up : (lean <= 0.45 ? QC.down : QC.warning);
    return Container(
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: c),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.gavel, size: 14, color: c),
                        const SizedBox(width: 8),
                        Text('RESEARCH MANAGER · VERDICT',
                            style:
                                TextStyle(color: c, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
                      ]),
                      const SizedBox(height: 10),
                      SelectableText(section.markdown,
                          style: const TextStyle(color: QC.textHi, height: 1.5, fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  final String text;
  const _GroupLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 12),
        child: Row(children: [
          Text(text.toUpperCase(),
              style: const TextStyle(
                  color: QC.textLo, fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
          const SizedBox(width: 12),
          const Expanded(child: Divider(color: QC.border, height: 1)),
        ]),
      );
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
          SelectableText(text, style: const TextStyle(color: QC.textHi, height: 1.5, fontSize: 14)),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final ReportSection section;
  final bool emphasis;
  final Color accent;
  const _SectionCard(this.section, {this.emphasis = false, this.accent = QC.accent});

  @override
  Widget build(BuildContext context) {
    final title = sectionTitle[section.section] ?? section.section;
    final agent = sectionAgent[section.section];

    final header = Row(children: [
      if (agent != null) ...[
        Container(width: 7, height: 7, decoration: BoxDecoration(color: agentColor(agent), shape: BoxShape.circle)),
        const SizedBox(width: 8),
      ],
      Flexible(
        child: Text(title.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: emphasis ? QC.textHi : QC.textMid,
                fontSize: emphasis ? 12.5 : 11,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700)),
      ),
      if (agent != null) ...[
        const SizedBox(width: 8),
        Flexible(
          child: Text('· ${agentName(agent)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: QC.textLo, fontSize: 11)),
        ),
      ],
    ]);
    final body = SelectableText(section.markdown,
        style: TextStyle(
            color: QC.textHi,
            height: 1.5,
            fontSize: emphasis ? 15 : 14,
            fontWeight: emphasis ? FontWeight.w500 : FontWeight.w400));

    final content = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      header,
      const SizedBox(height: 8),
      body,
    ]);

    if (!emphasis) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: QC.surface1,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: QC.border),
        ),
        child: content,
      );
    }
    // Emphasised "answer" card: surface2 + a full-height accent stripe tied to the verdict colour.
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: QC.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: QC.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: accent),
              Expanded(child: Padding(padding: const EdgeInsets.all(18), child: content)),
            ],
          ),
        ),
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
      child: ListView(
        children: [
          const Text('VERDICT',
              style: TextStyle(color: QC.textLo, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (v == null)
            _PendingVerdict(state.phase)
          else ...[
            _RatingPill(v.rating),
            if (v.confidence != null) ...[
              const SizedBox(height: 16),
              _Reveal(child: _Confidence(v.confidence!)),
            ],
            if (v.thesis != null) ...[
              const SizedBox(height: 16),
              _Reveal(
                child: SelectableText(v.thesis!,
                    style: const TextStyle(
                        color: QC.textHi, fontSize: 15, height: 1.5, fontStyle: FontStyle.italic)),
              ),
            ],
            const SizedBox(height: 20),
            _Reveal(
              child: _KvCard('Key Levels', [
                if (v.entryPrice != null) ('Entry', v.entryPrice!.toStringAsFixed(0)),
                if (v.priceTarget != null) ('Target', v.priceTarget!.toStringAsFixed(0)),
                if (v.stopLoss != null) ('Stop', v.stopLoss!.toStringAsFixed(0)),
                if (v.timeHorizon != null) ('Horizon', v.timeHorizon!),
              ]),
            ),
          ],
          if (state.cost != null) _Reveal(child: _KvCard('Run Cost', _costRows(state.cost!))),
        ],
      ),
    );
  }

  static List<(String, String)> _costRows(CostSnapshot c) {
    String tokens(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';
    return [
      if (c.estUsd != null) ('Est. cost', '\$${c.estUsd!.toStringAsFixed(2)}'),
      ('LLM calls', '${c.llmCalls}'),
      ('Tool calls', '${c.toolCalls}'),
      ('Tokens', tokens(c.tokensIn + c.tokensOut)),
    ];
  }
}

class _PendingVerdict extends StatelessWidget {
  final RunPhase phase;
  const _PendingVerdict(this.phase);
  @override
  Widget build(BuildContext context) {
    final msg = phase == RunPhase.running ? 'The council is deliberating…' : 'No verdict yet.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Skeleton keeps the rail's shape across phases instead of collapsing.
        Container(
          height: 56,
          decoration: BoxDecoration(
            color: QC.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: QC.border),
          ),
          alignment: Alignment.center,
          child: Text(msg, style: const TextStyle(color: QC.textLo, fontSize: 14)),
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          // Determinate (static) so it reads as a skeleton track and never animates.
          child: const LinearProgressIndicator(
            value: 0, minHeight: 6, backgroundColor: QC.surface2, valueColor: AlwaysStoppedAnimation(QC.surface2)),
        ),
      ],
    );
  }
}

class _RatingPill extends StatelessWidget {
  final String? rating;
  const _RatingPill(this.rating);
  @override
  Widget build(BuildContext context) {
    final color = ratingColor(rating);
    return Semantics(
      label: 'Verdict: ${rating ?? 'unknown'}',
      // Finite reveal (scale + fade) when the verdict lands — plays once at done, never re-runs.
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: _motion(context, _motionNormal),
        curve: Curves.easeOut,
        builder: (_, t, child) => Opacity(opacity: t, child: Transform.scale(scale: 0.96 + 0.04 * t, child: child)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Text((rating ?? '—').toUpperCase(),
              style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 1)),
        ),
      ),
    );
  }
}

class _Confidence extends StatelessWidget {
  final double value;
  const _Confidence(this.value);
  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Confidence ${(value * 100).round()} percent',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('Confidence', style: TextStyle(color: QC.textMid, fontSize: 13)),
            const Spacer(),
            Text('${(value * 100).round()}%',
                style: const TextStyle(
                    color: QC.textHi, fontWeight: FontWeight.w700, fontFamily: QC.fontMono)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value),
              duration: _motion(context, _motionSlow),
              curve: Curves.easeOut,
              builder: (_, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                backgroundColor: QC.surface2,
                valueColor: const AlwaysStoppedAnimation(QC.accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small key/value card (surface2, tabular figures). Used for both Key Levels and Run Cost.
class _KvCard extends StatelessWidget {
  final String title;
  final List<(String, String)> rows;
  const _KvCard(this.title, this.rows);

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: QC.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: QC.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
              style: const TextStyle(
                  color: QC.textMid, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Text(label, style: const TextStyle(color: QC.textMid, fontSize: 13)),
                const Spacer(),
                SelectableText(value,
                    style: const TextStyle(
                        color: QC.textHi,
                        fontWeight: FontWeight.w600,
                        fontFamily: QC.fontMono)),
              ]),
            ),
        ],
      ),
    );
  }
}
