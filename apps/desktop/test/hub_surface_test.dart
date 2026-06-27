import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quorum/state/hub_provider.dart';
import 'package:quorum/state/settings_controller.dart';
import 'package:quorum/ui/hub_surface.dart';
import 'package:quorum/ui/terminal_screen.dart';
import 'package:quorum_core/quorum_core.dart';

RunSummary _run(String id, String ticker, String rating, {String mode = 'pro'}) => RunSummary(
      runId: id, status: 'done', mode: mode, ticker: ticker, tradeDate: '2026-05-10',
      provider: 'anthropic', deepModel: 'claude-opus-4-8',
      verdict: Verdict(
        finalDecision: '$rating $ticker', rating: rating, confidence: 0.72, thesis: 'thesis',
        structured: const {'entry_price': 124.0, 'price_target': 152.0},
      ),
      cost: const CostSnapshot(llmCalls: 14, toolCalls: 8, tokensIn: 24800, tokensOut: 13200, estUsd: 0.42),
    );

Widget _wrap(SettingsState initial, List<RunSummary> history,
        {Map<String, Map<String, String>>? reports}) =>
    ProviderScope(
      overrides: [
        initialSettingsProvider.overrideWithValue(initial),
        runHistoryProvider.overrideWith((ref) => Future.value(history)),
        if (reports != null)
          for (final e in reports.entries)
            runReportsProvider(e.key).overrideWith((ref) => Future.value(e.value)),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark, fontFamily: 'Inter'),
        home: const Scaffold(body: HubSurface()),
      ),
    );

Future<void> _pump(WidgetTester t, Widget w) async {
  await t.binding.setSurfaceSize(const Size(1000, 900));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(w);
  await t.pumpAndSettle();
}

void main() {
  // A launch ticker that never collides with the history rows below (the launch field shows it).
  const settings = SettingsState(ticker: 'SPY');

  testWidgets('history renders rows with ticker + rating family + demo badge', (tester) async {
    await _pump(tester, _wrap(settings, [
      _run('r1', 'NVDA', 'Buy'),
      _run('r2', 'TSLA', 'Sell'),
      _run('r3', 'AAPL', 'Hold', mode: 'demo'),
    ]));
    expect(find.text('NVDA'), findsOneWidget);
    expect(find.text('TSLA'), findsOneWidget);
    expect(find.text('BUY'), findsWidgets);
    expect(find.text('SELL'), findsWidgets);
    expect(find.text('DEMO'), findsOneWidget); // only the demo run is badged
  });

  testWidgets('rating filter chip narrows the list', (tester) async {
    await _pump(tester, _wrap(settings, [
      _run('r1', 'NVDA', 'Buy'),
      _run('r2', 'TSLA', 'Sell'),
    ]));
    await tester.tap(find.text('Sell')); // the filter chip (label is title-case; the pill is BUY/SELL)
    await tester.pumpAndSettle();
    expect(find.text('NVDA'), findsNothing);
    expect(find.text('TSLA'), findsOneWidget);
  });

  testWidgets('opening a run shows the cached review rendered through TerminalBody', (tester) async {
    await _pump(
      tester,
      _wrap(settings, [_run('r1', 'NVDA', 'Buy')], reports: {
        'r1': {'final_trade_decision': 'BUY NVDA — starter long.', 'market_report': 'MKT context'},
      }),
    );
    await tester.tap(find.text('NVDA'));
    await tester.pumpAndSettle();
    expect(find.text('Cached run · NVDA'), findsOneWidget);
    expect(find.byType(TerminalBody), findsOneWidget);
    expect(find.text('BUY'), findsWidgets); // the verdict rail rating pill
    expect(find.textContaining('starter long'), findsWidgets); // the rendered report
  });

  testWidgets('star on a run row toggles the watchlist', (tester) async {
    await _pump(tester, _wrap(settings, [_run('r1', 'NVDA', 'Buy')]));
    final container = ProviderScope.containerOf(tester.element(find.byType(HubSurface)));
    expect(container.read(settingsControllerProvider).watchlist, isEmpty);
    await tester.tap(find.byTooltip('Watch'));
    await tester.pumpAndSettle();
    expect(container.read(settingsControllerProvider).watchlist, contains('NVDA'));
  });

  testWidgets('empty history shows the no-runs notice', (tester) async {
    await _pump(tester, _wrap(settings, const <RunSummary>[]));
    expect(find.text('No runs yet'), findsOneWidget);
  });

  testWidgets('watchlist chip renders for a tracked ticker with its latest rating', (tester) async {
    await _pump(
      tester,
      _wrap(const SettingsState(ticker: 'SPY', watchlist: ['NVDA']), [_run('r1', 'NVDA', 'Buy')]),
    );
    // The watchlist chip shows the ticker and a rating dot (title-case family).
    expect(find.widgetWithText(Row, 'NVDA'), findsWidgets);
    expect(find.byTooltip('Re-run NVDA'), findsOneWidget);
  });
}
