import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quorum/dream_team_roster.dart';
import 'package:quorum/state/hub_provider.dart';
import 'package:quorum/state/settings_controller.dart';
import 'package:quorum/ui/hub_surface.dart';
import 'package:quorum/ui/terminal_screen.dart';
import 'package:quorum_core/quorum_core.dart';

RunSummary _run(String id, String ticker, String rating,
        {String mode = 'pro', Map<String, AgentModel>? agentModels}) =>
    RunSummary(
      runId: id, status: 'done', mode: mode, ticker: ticker, tradeDate: '2026-05-10',
      provider: 'anthropic', deepModel: 'claude-opus-4-8', quickModel: 'claude-sonnet-4-6',
      verdict: Verdict(
        finalDecision: '$rating $ticker', rating: rating, confidence: 0.72, thesis: 'thesis',
        structured: const {'entry_price': 124.0, 'price_target': 152.0},
      ),
      cost: const CostSnapshot(llmCalls: 14, toolCalls: 8, tokensIn: 24800, tokensOut: 13200, estUsd: 0.42),
      agentModels: agentModels,
    );

/// A resolved 12-role lineup as the manifest records it: every role on the global anthropic quick/deep
/// model except the given [overrides]. Mirrors `resolve_agent_models` (all 12 present on a pro run).
Map<String, AgentModel> _resolvedLineup({Map<String, AgentModel> overrides = const {}}) => {
      for (final k in dreamTeamRoleKeys)
        k: overrides[k] ??
            AgentModel(
                provider: 'anthropic',
                model: dreamTeamDeepRoles.contains(k) ? 'claude-opus-4-8' : 'claude-sonnet-4-6'),
    };

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

  testWidgets('opening a run shows the cached review with the full debate (no placeholders)',
      (tester) async {
    // The cached review embeds the full 3-pane terminal, so render at the terminal's real width.
    await tester.binding.setSurfaceSize(const Size(1320, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(settings, [_run('r1', 'NVDA', 'Buy')], reports: {
      'r1': {
        'final_trade_decision': 'BUY NVDA — starter long.',
        'investment_plan': 'Lean constructive with sizing discipline.',
        'bull': 'The bull case: durable growth and operating leverage.',
        'bear': 'The bear case: rich multiple leaves no room for error.',
        'market_report': 'MKT context',
      },
    }));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NVDA'));
    await tester.pumpAndSettle();
    expect(find.text('Cached run · NVDA'), findsOneWidget);
    expect(find.byType(TerminalBody), findsOneWidget);
    expect(find.text('BUY'), findsWidgets); // the verdict rail rating pill
    expect(find.textContaining('starter long'), findsWidgets);
    // The bull/bear tug-of-war renders its content — NOT the stuck/awaiting placeholder.
    expect(find.textContaining('durable growth'), findsWidgets);
    expect(find.textContaining('no room for error'), findsWidgets);
    expect(find.text('Awaiting rebuttal…'), findsNothing);
    // Read-only review re-runs (not a fresh "Run analysis" launch).
    expect(find.text('Re-run NVDA'), findsOneWidget);
  });

  testWidgets('cached review shows the Dream Team cast list and flags inferred overrides',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1320, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final run = _run('rc', 'NVDA', 'Buy', agentModels: _resolvedLineup(overrides: {
      'bull_researcher': const AgentModel(provider: 'xai', model: 'grok-x'),
    }));
    await tester.pumpWidget(_wrap(settings, [run], reports: {
      'rc': {'final_trade_decision': 'BUY NVDA — starter long.'},
    }));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NVDA'));
    await tester.pumpAndSettle();

    // 12 resolved roles, exactly 1 inferred override (provider differs from the run's anthropic global).
    expect(find.text('Cast · 12 roles'), findsOneWidget);
    expect(find.text('1 pinned'), findsOneWidget);

    await tester.tap(find.text('Cast · 12 roles')); // expand
    await tester.pumpAndSettle();
    // 'Bull Researcher' also labels the terminal pipeline node, so match >=1; the model id is unique.
    expect(find.text('Bull Researcher'), findsWidgets);
    expect(find.textContaining('grok-x'), findsOneWidget); // the overridden model, only in the cast list
  });

  testWidgets('a demo / no-lineup review renders no cast bar', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1320, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(settings, [_run('r1', 'NVDA', 'Buy', mode: 'demo')], reports: {
      'r1': {'final_trade_decision': 'demo decision'},
    }));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NVDA'));
    await tester.pumpAndSettle();
    expect(find.text('Cached run · NVDA'), findsOneWidget); // the review opened
    expect(find.textContaining('Cast ·'), findsNothing); // agentModels null -> SizedBox.shrink
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

  testWidgets('watchlist Add is add-only (re-adding a tracked ticker keeps it)', (tester) async {
    await _pump(
      tester,
      _wrap(const SettingsState(ticker: 'SPY', watchlist: ['NVDA']), [_run('r1', 'NVDA', 'Buy')]),
    );
    final container = ProviderScope.containerOf(tester.element(find.byType(HubSurface)));
    final addField =
        find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Add ticker');
    await tester.enterText(addField, 'NVDA'); // already tracked
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(container.read(settingsControllerProvider).watchlist, ['NVDA']); // kept, not toggled off
  });

  testWidgets('launch is disabled when demo is off and no provider is set', (tester) async {
    await _pump(tester, _wrap(const SettingsState(ticker: 'SPY', demoMode: false), const <RunSummary>[]));
    // FilledButton.icon builds a private FilledButton subclass, so match by is-check, not byType.
    final btn = tester.widget<FilledButton>(find.byWidgetPredicate((w) => w is FilledButton));
    expect(btn.onPressed, isNull);
  });
}
