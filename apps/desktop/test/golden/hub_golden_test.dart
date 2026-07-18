import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quorum/state/catalog_provider.dart';
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

Widget _hub({
  required SettingsState initial,
  List<RunSummary> history = const [],
  Catalog? catalog,
  List<LocalModel>? localModels,
  EdgeModelCatalog? edgeCatalog,
}) =>
    ProviderScope(
      overrides: [
        initialSettingsProvider.overrideWithValue(initial),
        runHistoryProvider.overrideWith((ref) => Future.value(history)),
        if (catalog != null) catalogProvider.overrideWith((ref) => Future.value(catalog)),
        if (localModels != null)
          localModelsProvider.overrideWith((ref) => Future.value(localModels)),
        if (edgeCatalog != null)
          edgeModelCatalogProvider.overrideWith((ref) => Future.value(edgeCatalog)),
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

    // P5.3c: a stored key retires the free-local onboarding card (keeps this golden byte-stable).
    // (_CardLabel uppercases its text — match the rendered form.)
    expect(find.textContaining('RUN QUORUM FREE'), findsNothing);
    await expectLater(find.byType(HubSurface), matchesGoldenFile('goldens/hub_home.png'));
  });

  testWidgets('hub — pre-launch key gate (needs keys, Run disabled)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(960, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // An unrelated key exists (P5.3c: anyKeysStored=true hides the free-local onboarding card and
    // keeps this golden byte-stable) while anthropic + google — the providers this run actually
    // references — are missing, which is exactly the state the key gate exists for.
    store['quorum_apikey_openai'] = 'present';
    // Empty vault for the referenced providers: a real run (provider=anthropic + a Dream Team role
    // on google) references two uncredentialed providers -> the gate lists them and disables Run.
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

  testWidgets('hub — capability backstop: non-tool local model refuses launch', (tester) async {
    await tester.binding.setSurfaceSize(const Size(960, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // The global quick model is a discovered non-tool Ollama model → every tool-analyst role would run
    // it and produce empty reports, so the launch backstop refuses the run before POST /runs.
    await tester.pumpWidget(_hub(
      initial: const SettingsState(
        demoMode: false, ticker: 'NVDA', provider: 'ollama', quickModel: 'dolphin-llama3:latest',
        backendUrl: 'http://localhost:11434/v1',
      ),
      catalog: Catalog(contractVersion: 1, providers: {
        'ollama': const ProviderCatalog('ollama', {'quick': [], 'deep': []}),
      }),
      localModels: const [LocalModel('dolphin-llama3:latest', toolCapable: false)],
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('No tool support'), findsOneWidget);
    // P5.3c: provider == ollama means the user is already on the local path — no onboarding card
    // even with an empty vault (and this golden stays byte-stable).
    expect(find.textContaining('RUN QUORUM FREE'), findsNothing);
    await expectLater(find.byType(HubSurface), matchesGoldenFile('goldens/hub_capability_gate.png'));
  });

  // --- P5.3c: the zero-key onboarding card ---------------------------------------------------------

  testWidgets('hub — keyless + Ollama present: the free-local path is offered (P5.3c)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(960, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // A genuinely fresh install: empty vault, default settings (demo, no provider), Ollama found.
    await tester.pumpWidget(_hub(
      initial: const SettingsState(),
      edgeCatalog: EdgeModelCatalog.fromJson(const {'ollama_version': '0.32.1', 'tiers': []}),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('RUN QUORUM FREE'), findsOneWidget); // _CardLabel uppercases
    expect(find.textContaining('Ollama 0.32.1 detected'), findsOneWidget);
    expect(find.text('Open the Draft Board'), findsOneWidget);
    expect(find.textContaining('slower and less capable'), findsOneWidget); // honest copy
    await expectLater(
        find.byType(HubSurface), matchesGoldenFile('goldens/hub_onboarding_ollama_present.png'));
  });

  testWidgets('hub — keyless + Ollama ABSENT: install guidance + re-detect, never a dead end '
      '(P5.3c falsifier)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(960, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_hub(
      initial: const SettingsState(),
      edgeCatalog: const EdgeModelCatalog(), // ollamaVersion null = absent
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('no local model runtime detected'), findsOneWidget);
    expect(find.textContaining('ollama.com/download'), findsOneWidget);
    expect(find.textContaining('outside Quorum'), findsOneWidget); // honest install copy
    expect(find.text('Re-detect Ollama'), findsOneWidget);
    await expectLater(
        find.byType(HubSurface), matchesGoldenFile('goldens/hub_onboarding_ollama_absent.png'));
  });

  testWidgets('hub — Re-detect refetches the catalog + discovery (P5.3c)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(960, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var edgeFetches = 0, localFetches = 0;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        initialSettingsProvider.overrideWithValue(const SettingsState()),
        runHistoryProvider.overrideWith((ref) => Future.value(const <RunSummary>[])),
        edgeModelCatalogProvider.overrideWith((ref) async {
          edgeFetches++;
          return const EdgeModelCatalog();
        }),
        localModelsProvider.overrideWith((ref) async {
          localFetches++;
          return const <LocalModel>[];
        }),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true, brightness: Brightness.dark, fontFamily: 'Inter',
          scaffoldBackgroundColor: QC.bg,
        ),
        home: const Scaffold(backgroundColor: QC.bg, body: HubSurface()),
      ),
    ));
    await tester.pumpAndSettle();
    // Discovery has no watcher on a keyless Hub (correct lazy behavior: invalidate defers the
    // refetch to the next watch) — hold a listener so the invalidation is observable here, the
    // way the Draft Board's own watch makes it observable in the app.
    final container = ProviderScope.containerOf(tester.element(find.byType(HubSurface)));
    final sub = container.listen(localModelsProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(localModelsProvider.future);
    final before = (edgeFetches, localFetches);

    await tester.tap(find.text('Re-detect Ollama'));
    await tester.pumpAndSettle();
    expect(edgeFetches, before.$1 + 1, reason: 'Re-detect must refetch the edge catalog');
    expect(localFetches, before.$2 + 1, reason: 'Re-detect must refetch discovery');
  });
}
