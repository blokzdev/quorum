import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quorum/state/settings_controller.dart';
import 'package:quorum/ui/brand.dart';
import 'package:quorum/ui/settings_surface.dart';
import 'package:quorum_core/quorum_core.dart';

/// flutter_secure_storage's platform channel, backed by an in-memory map (no real OS keystore).
const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

final _catalog = Catalog(
  contractVersion: 1,
  analysts: const ['market', 'social', 'news', 'fundamentals'],
  providers: {
    'google': const ProviderCatalog('google', {
      'quick': [ModelOption('Gemini 3.5 Flash', 'gemini-3.5-flash')],
      'deep': [ModelOption('Gemini 3.1 Pro', 'gemini-3.1-pro-preview')],
    }),
    'ollama': const ProviderCatalog('ollama', {
      'quick': [ModelOption('Qwen3', 'qwen3:latest'), ModelOption('Custom model ID', 'custom')],
      'deep': [ModelOption('GLM', 'glm-4.7-flash:latest'), ModelOption('Custom model ID', 'custom')],
    }),
    'openai_compatible': const ProviderCatalog('openai_compatible', {
      'quick': [ModelOption('Custom model ID', 'custom')],
      'deep': [ModelOption('Custom model ID', 'custom')],
    }),
    'deepseek': const ProviderCatalog('deepseek', {
      'quick': [ModelOption('V4 Flash', 'deepseek-v4-flash'), ModelOption('Custom model ID', 'custom')],
      'deep': [ModelOption('V4 Pro', 'deepseek-v4-pro'), ModelOption('Custom model ID', 'custom')],
    }),
  },
);

Widget _wrap(SettingsState initial) => ProviderScope(
      overrides: [initialSettingsProvider.overrideWithValue(initial)],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          fontFamily: 'Inter',
          extensions: const [QuorumBrand.dark()],
        ),
        home: Scaffold(body: SettingsBody(catalog: _catalog)),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, String> store;

  setUp(() {
    store = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
      switch (call.method) {
        case 'write':
          store[args['key'] as String] = args['value'] as String;
          return null;
        case 'read':
          return store[args['key'] as String];
        case 'delete':
          store.remove(args['key'] as String);
          return null;
        case 'readAll':
          return Map<String, String>.from(store);
        case 'deleteAll':
          store.clear();
          return null;
        case 'containsKey':
          return store.containsKey(args['key'] as String);
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  testWidgets('a stored API key NEVER appears anywhere in the widget tree (write-only field)',
      (tester) async {
    const secret = 'sk-SECRET-do-not-render-0xDEADBEEF';
    store['quorum_apikey_google'] = secret;
    await tester.pumpWidget(_wrap(const SettingsState(
      demoMode: false,
      provider: 'google',
      deepModel: 'gemini-3.1-pro-preview',
      quickModel: 'gemini-3.5-flash',
      effort: 'high',
    )));
    await tester.pumpAndSettle();

    // The key value must not be on screen, and the field must not be pre-filled with it.
    expect(find.text(secret), findsNothing);
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(field.controller?.text ?? '', isNot(contains('SECRET')));
    }
    // The presence of a key is surfaced only as a boolean ("Stored").
    expect(find.text('Stored'), findsOneWidget);
  });

  testWidgets('google → effort + key fields shown, no backend URL', (tester) async {
    await tester.pumpWidget(_wrap(const SettingsState(demoMode: false, provider: 'google')));
    await tester.pumpAndSettle();
    expect(find.text('Thinking level'), findsOneWidget);
    expect(find.text('API key'), findsOneWidget);
    expect(find.text('Backend URL'), findsNothing);
    expect(find.text('Deep model'), findsOneWidget);
  });

  testWidgets('ollama → backend URL shown, no key field, no effort', (tester) async {
    await tester.pumpWidget(_wrap(const SettingsState(demoMode: false, provider: 'ollama')));
    await tester.pumpAndSettle();
    expect(find.text('Backend URL'), findsOneWidget);
    expect(find.text('API key'), findsNothing);
    expect(find.text('Thinking level'), findsNothing);
    expect(find.text('Effort'), findsNothing);
  });

  testWidgets('openai_compatible → backend URL is required (warns when empty) + key field',
      (tester) async {
    await tester.pumpWidget(
        _wrap(const SettingsState(demoMode: false, provider: 'openai_compatible')));
    await tester.pumpAndSettle();
    expect(find.text('Backend URL'), findsOneWidget);
    expect(find.text('Required for this provider'), findsOneWidget);
    expect(find.text('API key'), findsOneWidget); // OPENAI_COMPATIBLE_API_KEY exists (optional)
  });

  testWidgets('custom model selection reveals the custom-id field', (tester) async {
    await tester.pumpWidget(_wrap(const SettingsState(
      demoMode: false,
      provider: 'deepseek',
      deepModel: 'custom',
    )));
    await tester.pumpAndSettle();
    expect(find.text('Custom model id (e.g. llama3.2:latest)'), findsOneWidget);
  });

  testWidgets('no provider selected → prompt to pick one, no model dropdowns', (tester) async {
    await tester.pumpWidget(_wrap(const SettingsState()));
    await tester.pumpAndSettle();
    expect(find.text('Pick a provider to choose its models.'), findsOneWidget);
    expect(find.text('Deep model'), findsNothing);
  });

  // Regression for the C6 review's top finding: uncontrolled custom-model / backend-URL fields used to
  // keep stale text after an external state change (Apply bench / provider switch), diverging from the
  // launched config and suppressing the "Required" warning.
  testWidgets('applyBench refreshes the backend-URL and custom-model fields (no stale text)',
      (tester) async {
    await tester.pumpWidget(_wrap(const SettingsState(
      demoMode: false,
      provider: 'openai_compatible',
      backendUrl: 'https://typed-by-user/v1',
      deepModel: 'custom',
      customDeepModel: 'typed-model',
      benches: [
        Bench(
          name: 'B',
          provider: 'openai_compatible',
          backendUrl: 'https://from-bench/v1',
          deepModel: 'custom',
          customDeepModel: 'bench-model',
        ),
      ],
    )));
    await tester.pumpAndSettle();
    expect(find.text('https://typed-by-user/v1'), findsOneWidget);
    expect(find.text('typed-model'), findsOneWidget);

    final container = ProviderScope.containerOf(tester.element(find.byType(SettingsBody)));
    container
        .read(settingsControllerProvider.notifier)
        .applyBench(container.read(settingsControllerProvider).benches.single);
    await tester.pumpAndSettle();

    // The boxes now show the bench values, the stale text is gone, and (URL non-empty) no warning.
    expect(find.text('https://from-bench/v1'), findsOneWidget);
    expect(find.text('https://typed-by-user/v1'), findsNothing);
    expect(find.text('bench-model'), findsOneWidget);
    expect(find.text('typed-model'), findsNothing);
    expect(find.text('Required for this provider'), findsNothing);
  });

  testWidgets('switching ollama→openai_compatible clears the stale backend URL', (tester) async {
    // A non-default host so the typed value can't collide with the ollama hint text in the finder.
    await tester.pumpWidget(_wrap(const SettingsState(
      demoMode: false,
      provider: 'ollama',
      backendUrl: 'http://10.0.0.5:11434/v1',
    )));
    await tester.pumpAndSettle();
    expect(find.text('http://10.0.0.5:11434/v1'), findsOneWidget);

    final container = ProviderScope.containerOf(tester.element(find.byType(SettingsBody)));
    container.read(settingsControllerProvider.notifier).setProvider('openai_compatible');
    await tester.pumpAndSettle();

    // withProvider() cleared backendUrl → the field is empty and the required warning shows.
    expect(find.text('http://10.0.0.5:11434/v1'), findsNothing);
    expect(find.text('Required for this provider'), findsOneWidget);
  });

  // Regression for the "Stored" badge going stale when keys change outside the field (seed / forget-all).
  testWidgets('stored badge refreshes on external key add and forget-all', (tester) async {
    await tester.pumpWidget(_wrap(const SettingsState(demoMode: false, provider: 'google')));
    await tester.pumpAndSettle();
    expect(find.text('Not stored'), findsOneWidget);

    final container = ProviderScope.containerOf(tester.element(find.byType(SettingsBody)));
    await container.read(settingsControllerProvider.notifier).saveKey('google', 'k'); // e.g. .env seed
    await tester.pumpAndSettle();
    expect(find.text('Stored'), findsOneWidget);

    await container.read(settingsControllerProvider.notifier).forgetAllKeys();
    await tester.pumpAndSettle();
    expect(find.text('Not stored'), findsOneWidget);
  });
}
