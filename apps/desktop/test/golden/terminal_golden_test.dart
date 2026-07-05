import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quorum/ui/quorum_colors.dart';
import 'package:quorum/ui/terminal_screen.dart';
import 'package:quorum_core/quorum_core.dart';

Widget _wrap(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark, fontFamily: 'Inter'),
      home: Scaffold(backgroundColor: QC.bg, body: child),
    );

const _analystReports = {
  'market_report': ReportSection('market_report',
      'NVDA reclaimed its 50-day moving average on rising volume; RSI 58 with room to run and a '
      'fresh MACD bullish crossover. Key support 118, resistance 135.', null),
  'sentiment_report': ReportSection('sentiment_report',
      'Social sentiment skews bullish (7.4/10). StockTwits mentions +22% w/w and constructive '
      'Reddit threads on the product cycle.', null),
  'news_report': ReportSection('news_report',
      'Macro backdrop supportive: soft-landing narrative intact, sector tailwinds from new orders.', null),
  'fundamentals_report': ReportSection('fundamentals_report',
      'Revenue +18% YoY, gross margin expanding to 71%, free cash flow positive.', null),
};

final _completed = RunViewState(
  phase: RunPhase.done,
  ticker: 'NVDA',
  tradeDate: '2024-05-10',
  lastSeq: 62,
  cost: const CostSnapshot(llmCalls: 14, toolCalls: 8, tokensIn: 24800, tokensOut: 13200, estUsd: 0.42),
  stages: {for (final s in stageMeta.keys) s: NodeStatus.done},
  agents: {
    for (final agents in stageMeta.values)
      for (final a in agents.$2) a: NodeStatus.done,
  },
  reports: {
    ..._analystReports,
    'bull': const ReportSection('bull',
        'The order backlog and 71% gross margin give NVDA room to compound through the cycle, and the '
        'reclaimed 50-day MA confirms buyers stepping in on dips. Durable growth and operating leverage '
        'justify a constructive stance even at a premium.', null),
    'bear': const ReportSection('bear',
        'At ~38x forward, NVDA leaves no margin for error. Any normalization in data-center demand or '
        'supply would compress estimates and the multiple at once — thin support at the 50-day is little '
        'comfort against that.', null),
    'investment_plan': const ReportSection('investment_plan',
        'On balance the bull thesis on NVDA is better supported this quarter; lean constructive '
        'with sizing discipline.', null),
    'trader_investment_plan': const ReportSection('trader_investment_plan',
        'Buy a starter position in NVDA: entry ~124, stop 113, target 152, size 5% of book.', null),
    'aggressive': const ReportSection('aggressive',
        'Press the long on confirmation above 135 — momentum and rising estimates favor continuation.', null),
    'neutral': const ReportSection('neutral',
        "The proposed entry/stop/target is a reasonable risk/reward as written; no change to the plan.", null),
    'conservative': const ReportSection('conservative',
        'Cap risk at a starter with a hard stop at 113; the rich multiple warrants patience over size.', null),
    'final_trade_decision': const ReportSection('final_trade_decision',
        'BUY NVDA — starter long. Entry ~124, stop 113, target 152, time horizon 3-6 months.', null),
  },
  verdict: const Verdict(
    finalDecision: 'BUY NVDA — starter long.',
    rating: 'Buy',
    confidence: 0.72,
    thesis: "NVDA's momentum and durable growth outweigh a rich multiple.",
    structured: {'price_target': 152.0, 'entry_price': 124.0, 'stop_loss': 113.0, 'time_horizon': '3-6 months'},
  ),
);

final _midRun = RunViewState(
  phase: RunPhase.running,
  ticker: 'NVDA',
  tradeDate: '2024-05-10',
  lastSeq: 38,
  cost: const CostSnapshot(llmCalls: 8, toolCalls: 5, tokensIn: 14200, tokensOut: 6100, estUsd: 0.27),
  stages: const {Stage.analysts: NodeStatus.done, Stage.researchDebate: NodeStatus.running},
  agents: const {
    AgentId.market: NodeStatus.done,
    AgentId.social: NodeStatus.done,
    AgentId.news: NodeStatus.done,
    AgentId.fundamentals: NodeStatus.done,
    AgentId.bull: NodeStatus.done,
    AgentId.bear: NodeStatus.running,
  },
  reasoningByAgent: const {
    'bear': 'Counterpoint: at ~38x forward the bar is set high. If data-center growth normalizes even '
        'modestly, estimates and the multiple compress together — the reclaimed 50-day MA is thin '
        'support against that, and competitive supply is catching up faster than consensus assumes…',
  },
  reports: {
    ..._analystReports,
    'bull': const ReportSection('bull',
        'The order backlog and 71% gross margin give NVDA room to compound through the cycle; the '
        'reclaimed 50-day MA confirms buyers are stepping in on dips. Durable growth and operating '
        'leverage justify a constructive stance.', null),
  },
);

/// P3.3a: a running debate decomposed into ordered turns, with the Research Manager's structured 5-tier
/// [recommendation] driving the balance bar. [rounds] turns × 2 (bull+bear) prove the decomposition
/// scales with research_depth.
RunViewState _debateState({required int rounds, required String recommendation}) => RunViewState(
      phase: RunPhase.running,
      ticker: 'NVDA',
      tradeDate: '2024-05-10',
      lastSeq: 40,
      stages: const {Stage.analysts: NodeStatus.done, Stage.researchDebate: NodeStatus.running},
      agents: const {AgentId.bull: NodeStatus.done, AgentId.bear: NodeStatus.done},
      debateTurns: [
        for (var r = 1; r <= rounds; r++) ...[
          DebateTurnView(r, 'bull',
              'Round $r bull: the backlog and 71% gross margin compound through the cycle; buyers '
              'defended the reclaimed 50-day MA on volume.'),
          DebateTurnView(r, 'bear',
              'Round $r bear: at ~38x forward there is no margin for error — any data-center '
              'normalization compresses estimates and the multiple together.'),
        ],
      ],
      reports: {
        'investment_plan': ReportSection('investment_plan',
            'On balance the debate resolves $recommendation with sizing discipline.',
            {'recommendation': recommendation}),
      },
    );

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  testWidgets('terminal — debate turn thread scales with depth (depth-1 vs depth-2)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // depth-1 → 1 round: exactly 2 turn blocks (bull + bear, round 1), no round 2.
    await tester.pumpWidget(_wrap(TerminalBody(
        state: _debateState(rounds: 1, recommendation: 'Overweight'),
        elapsedOverride: const Duration(seconds: 30))));
    await tester.pumpAndSettle();
    expect(find.textContaining('· ROUND 1'), findsNWidgets(2)); // bull + bear headers
    expect(find.textContaining('· ROUND 2'), findsNothing);
    await expectLater(
        find.byType(TerminalBody), matchesGoldenFile('goldens/terminal_debate_depth1.png'));

    // depth-2 → 2 rounds: ≥4 distinct turn blocks in speaking order (proves the decomposition is real).
    await tester.pumpWidget(_wrap(TerminalBody(
        state: _debateState(rounds: 2, recommendation: 'Overweight'),
        elapsedOverride: const Duration(seconds: 30))));
    await tester.pumpAndSettle();
    expect(find.textContaining('· ROUND 1'), findsNWidgets(2));
    expect(find.textContaining('· ROUND 2'), findsNWidgets(2)); // 4 turn blocks total
    await expectLater(
        find.byType(TerminalBody), matchesGoldenFile('goldens/terminal_debate_depth2.png'));
  });

  test('structured recommendation drives the balance lean — Buy vs Sell flip it (P3.3a)', () {
    // Two plans differing ONLY in the structured recommendation flip the lean across the 0.5 midpoint.
    ReportSection plan(String rec) => ReportSection('investment_plan', 'resolves $rec', {'recommendation': rec});
    expect(debateLean(plan('Buy')), greaterThan(0.5), reason: 'Buy leans bull');
    expect(debateLean(plan('Sell')), lessThan(0.5), reason: 'Sell leans bear');
    expect(debateLean(plan('Overweight')), greaterThan(0.5));
    expect(debateLean(plan('Underweight')), lessThan(0.5));
    expect(debateLean(plan('Hold')), 0.5);
    // No structured recommendation → falls back to keyword-scoring on the prose (unchanged legacy path).
    expect(debateLean(const ReportSection('investment_plan', 'lean constructive, accumulate', null)),
        greaterThan(0.5));
    expect(debateLean(null), 0.5);
  });

  testWidgets('terminal — completed verdict', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1320, 820));
    await tester.pumpWidget(_wrap(TerminalBody(state: _completed)));
    await tester.pumpAndSettle();
    await expectLater(find.byType(TerminalBody), matchesGoldenFile('goldens/terminal_completed.png'));
  });

  testWidgets('terminal — mid-run streaming', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1320, 820));
    // Fixed elapsed so the header timer is golden-deterministic (no live clock in the harness).
    await tester.pumpWidget(
        _wrap(TerminalBody(state: _midRun, elapsedOverride: const Duration(minutes: 2, seconds: 14))));
    await tester.pumpAndSettle();
    await expectLater(find.byType(TerminalBody), matchesGoldenFile('goldens/terminal_midrun.png'));
  });
}
