import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quorum/state/hub_provider.dart';
import 'package:quorum/state/settings_controller.dart';
import 'package:quorum/ui/hub_surface.dart';
import 'package:quorum/ui/quorum_colors.dart';
import 'package:quorum_core/quorum_core.dart';

const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

RunSummary _run(String id, String ticker, String rating, {String mode = 'pro', double? cost = 0.42}) =>
    RunSummary(
      runId: id, status: 'done', mode: mode, ticker: ticker, tradeDate: '2026-05-10',
      provider: 'anthropic', deepModel: 'claude-opus-4-8',
      verdict: Verdict(finalDecision: '$rating $ticker', rating: rating, confidence: 0.72),
      cost: CostSnapshot(llmCalls: 14, toolCalls: 8, tokensIn: 24800, tokensOut: 13200, estUsd: cost),
    );

Widget _hub({required SettingsState initial, List<RunSummary> history = const []}) => ProviderScope(
      overrides: [
        initialSettingsProvider.overrideWithValue(initial),
        runHistoryProvider.overrideWith((ref) => Future.value(history)),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true, brightness: Brightness.dark, fontFamily: 'Inter',
          scaffoldBackgroundColor: QC.bg,
        ),
        home: const Scaffold(backgroundColor: QC.bg, body: HubSurface()),
      ),
    );

void main() {
  late Map<String, String> store;
  setUp(() {
    store = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
      if (call.method == 'read') return store[args['key'] as String];
      if (call.method == 'readAll') return Map<String, String>.from(store);
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null));

  testWidgets('hub — launch, watchlist, and run history', (tester) async {
    await tester.binding.setSurfaceSize(const Size(960, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    store['quorum_apikey_anthropic'] = 'present'; // credentialed -> no key-gate notice (happy state)

    await tester.pumpWidget(_hub(
      initial: const SettingsState(
        demoMode: false, ticker: 'NVDA', provider: 'anthropic', deepModel: 'claude-opus-4-8',
        watchlist: ['NVDA', 'TSLA'],
      ),
      history: [
        _run('r1', 'NVDA', 'Buy'),
        _run('r2', 'TSLA', 'Sell'),
        _run('r3', 'AAPL', 'Hold', mode: 'demo', cost: null),
        _run('r4', 'MSFT', 'Buy'),
      ],
    ));
    await tester.pumpAndSettle();

    await expectLater(find.byType(HubSurface), matchesGoldenFile('goldens/hub_home.png'));
  });

  testWidgets('hub — pre-launch key gate (needs keys, Run disabled)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(960, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Empty vault: a real run (provider=anthropic + a Dream Team role on google) references two
    // uncredentialed providers -> the gate lists them and disables Run before POST /runs.
    await tester.pumpWidget(_hub(
      initial: const SettingsState(
        demoMode: false, ticker: 'NVDA', provider: 'anthropic', deepModel: 'claude-opus-4-8',
        agentModels: {'bull_researcher': AgentModel(provider: 'google', model: 'gemini-3.1-pro-preview')},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Needs keys for'), findsOneWidget);
    await expectLater(find.byType(HubSurface), matchesGoldenFile('goldens/hub_needs_keys.png'));
  });

  testWidgets('hub — as-of (historical) launch: warning chip + Polymarket live-source caveat',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(960, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    store['quorum_apikey_anthropic'] = 'present';

    await tester.pumpWidget(_hub(
      initial: const SettingsState(
        demoMode: false, ticker: 'NVDA', provider: 'anthropic', deepModel: 'claude-opus-4-8',
        tradeDate: '2024-05-10', // a past as-of -> the launch card flags the historical run
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('As-of 2024-05-10'), findsOneWidget);
    await expectLater(find.byType(HubSurface), matchesGoldenFile('goldens/hub_as_of.png'));
  });
}
