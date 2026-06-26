import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quorum/ui/quorum_colors.dart';
import 'package:quorum/ui/terminal_screen.dart';
import 'package:quorum_core/quorum_core.dart';

Widget _wrap(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark, fontFamily: 'SegoeUI'),
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
    'investment_plan': const ReportSection('investment_plan',
        'On balance the bull thesis on NVDA is better supported this quarter; lean constructive '
        'with sizing discipline.', null),
    'trader_investment_plan': const ReportSection('trader_investment_plan',
        'Buy a starter position in NVDA: entry ~124, stop 113, target 152, size 5% of book.', null),
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
  lastSeq: 24,
  cost: const CostSnapshot(llmCalls: 5, toolCalls: 3, tokensIn: 9100, tokensOut: 3800, estUsd: 0.16),
  stages: const {Stage.analysts: NodeStatus.done, Stage.researchDebate: NodeStatus.running},
  agents: const {
    AgentId.market: NodeStatus.done,
    AgentId.social: NodeStatus.done,
    AgentId.news: NodeStatus.done,
    AgentId.fundamentals: NodeStatus.done,
    AgentId.bull: NodeStatus.running,
  },
  reasoningByAgent: const {
    'bull': 'The order backlog and 71% gross margin give NVDA room to compound through the cycle, '
        'and the reclaimed 50-day MA confirms buyers are stepping in on dips. Even at a rich '
        'multiple, durable growth and operating leverage justify a constructive stance…',
  },
  reports: _analystReports,
);

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  testWidgets('terminal — completed verdict', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1320, 820));
    await tester.pumpWidget(_wrap(TerminalBody(state: _completed)));
    await tester.pumpAndSettle();
    await expectLater(find.byType(TerminalBody), matchesGoldenFile('goldens/terminal_completed.png'));
  });

  testWidgets('terminal — mid-run streaming', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1320, 820));
    await tester.pumpWidget(_wrap(TerminalBody(state: _midRun)));
    await tester.pumpAndSettle();
    await expectLater(find.byType(TerminalBody), matchesGoldenFile('goldens/terminal_midrun.png'));
  });
}
