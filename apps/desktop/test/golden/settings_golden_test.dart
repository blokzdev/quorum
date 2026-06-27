import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quorum/state/settings_controller.dart';
import 'package:quorum/ui/brand.dart';
import 'package:quorum/ui/quorum_colors.dart';
import 'package:quorum/ui/settings_surface.dart';
import 'package:quorum_core/quorum_core.dart';

/// flutter_secure_storage's platform channel, backed by an in-memory map. The golden pre-seeds a key
/// so the "Stored" indicator renders deterministically — and so the golden visually PROVES the key
/// value itself is never painted (write-only field).
const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

final _catalog = Catalog(
  contractVersion: 1,
  analysts: const ['market', 'social', 'news', 'fundamentals'],
  providers: {
    'google': const ProviderCatalog('google', {
      'quick': [
        ModelOption('Gemini 3.5 Flash - Latest, frontier agentic + coding (GA)', 'gemini-3.5-flash'),
        ModelOption('Gemini 3.1 Flash Lite - Most cost-efficient', 'gemini-3.1-flash-lite'),
      ],
      'deep': [
        ModelOption('Gemini 3.1 Pro - Reasoning-first (preview)', 'gemini-3.1-pro-preview'),
        ModelOption('Gemini 3.5 Flash - Latest GA', 'gemini-3.5-flash'),
      ],
    }),
    'anthropic': const ProviderCatalog('anthropic', {
      'quick': [ModelOption('Claude Sonnet 4.6', 'claude-sonnet-4-6')],
      'deep': [ModelOption('Claude Opus 4.8', 'claude-opus-4-8')],
    }),
    'ollama': const ProviderCatalog('ollama', {
      'quick': [ModelOption('Qwen3:latest (8B)', 'qwen3:latest'), ModelOption('Custom model ID', 'custom')],
      'deep': [ModelOption('GLM-4.7-Flash:latest (30B)', 'glm-4.7-flash:latest'), ModelOption('Custom model ID', 'custom')],
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
          scaffoldBackgroundColor: QC.bg,
          extensions: const [QuorumBrand.dark()],
        ),
        home: Scaffold(backgroundColor: QC.bg, body: SettingsBody(catalog: _catalog)),
      ),
    );

void main() {
  late Map<String, String> store;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    store = {'quorum_apikey_google': 'sk-SECRET-must-never-be-painted'};
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

  testWidgets('model studio — google configured, key stored (no key text visible)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(820, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(const SettingsState(
      demoMode: false,
      ticker: 'NVDA',
      provider: 'google',
      deepModel: 'gemini-3.1-pro-preview',
      quickModel: 'gemini-3.5-flash',
      effort: 'high',
      researchDepth: 2,
      benches: [
        Bench(name: 'Deep dive', provider: 'anthropic', deepModel: 'claude-opus-4-8', effort: 'high', researchDepth: 4),
      ],
    )));
    await tester.pumpAndSettle();

    // Belt-and-braces: the stored key value must not be in the tree at all.
    expect(find.textContaining('SECRET'), findsNothing);
    await expectLater(find.byType(SettingsBody), matchesGoldenFile('goldens/settings_model_studio.png'));
  });
}
