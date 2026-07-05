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
    // Carries an explicitly non-tool model so the capability gate's BLOCK path is exercisable (the real
    // engine denylist is empty, so no live catalog model is false today).
    'legacy': const ProviderCatalog('legacy', {
      'quick': [
        ModelOption('NoTool', 'old-x', toolCapable: false),
        ModelOption('HasTool', 'new-x', toolCapable: true),
      ],
      'deep': [ModelOption('NoTool', 'old-x', toolCapable: false)],
    }),
  },
);

/// A minimal `GET /catalog/vendors` mirror: one core category (yfinance default + keyed alpha_vantage)
/// and both optional categories (macro=fred keyed, prediction=polymarket keyless).
const _vendorCatalog = VendorCatalog(contractVersion: 1, categories: [
  VendorCategory('core_stock_apis', 'OHLCV stock price data', vendors: [
    VendorOption('alpha_vantage', needsKey: true, keyEnv: 'ALPHA_VANTAGE_API_KEY'),
    VendorOption('yfinance'),
  ], defaultVendor: 'yfinance'),
  VendorCategory('macro_data', 'Macroeconomic indicators', optional: true,
      vendors: [VendorOption('fred', needsKey: true, keyEnv: 'FRED_API_KEY')], defaultVendor: 'fred'),
  VendorCategory('prediction_markets', 'Prediction markets', optional: true,
      vendors: [VendorOption('polymarket')], defaultVendor: 'polymarket'),
]);

Widget _wrap(SettingsState initial,
        {VendorCatalog? vendorCatalog, List<LocalModel> localModels = const []}) =>
    ProviderScope(
      overrides: [initialSettingsProvider.overrideWithValue(initial)],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          fontFamily: 'Inter',
          extensions: const [QuorumBrand.dark()],
        ),
        home: Scaffold(
            body: SettingsBody(
                catalog: _catalog, vendorCatalog: vendorCatalog, localModels: localModels)),
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

  // --- Data sources (P3.1) --------------------------------------------------------------------------

  testWidgets('data sources: hidden when no vendor catalog is available', (tester) async {
    await tester.pumpWidget(_wrap(const SettingsState(demoMode: false))); // no vendorCatalog
    await tester.pumpAndSettle();
    expect(find.text('DATA SOURCES'), findsNothing);
    expect(find.text('Asset type'), findsOneWidget); // the Run-section toggle is independent, still shows
  });

  testWidgets('data sources: shown with a catalog — core dropdown, FRED field, Polymarket note',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(const SettingsState(demoMode: false), vendorCatalog: _vendorCatalog));
    await tester.pumpAndSettle();
    expect(find.text('DATA SOURCES'), findsOneWidget);
    expect(find.text('OHLCV stock price data'), findsOneWidget); // the core category label
    // The optional macro (FRED) key field is always offered; Polymarket is a keyless default-on note.
    expect(find.text('Macroeconomic indicators'), findsOneWidget);
    expect(find.textContaining('Polymarket signals are on by default'), findsOneWidget);
    // No CORE alpha_vantage key field yet (default is keyless yfinance) → exactly one 'API key' (FRED).
    expect(find.text('API key'), findsOneWidget);
  });

  testWidgets('data sources: selecting a keyed core vendor reveals its required key field',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(const SettingsState(demoMode: false), vendorCatalog: _vendorCatalog));
    await tester.pumpAndSettle();
    expect(find.text('API key'), findsOneWidget); // FRED only

    final container = ProviderScope.containerOf(tester.element(find.byType(SettingsBody)));
    container.read(settingsControllerProvider.notifier).setDataVendor('core_stock_apis', 'alpha_vantage');
    await tester.pumpAndSettle();

    // Now Alpha Vantage's required key field appears too → two 'API key' labels (AV + FRED).
    expect(find.text('API key'), findsNWidgets(2));
    expect(container.read(settingsControllerProvider).dataVendors, {'core_stock_apis': 'alpha_vantage'});
  });

  testWidgets('data sources: a stored vendor key value is NEVER painted (write-only)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    store['quorum_apikey_alpha_vantage'] = 'sk-SECRET-av-value';
    store['quorum_apikey_fred'] = 'sk-SECRET-fred-value';
    await tester.pumpWidget(_wrap(
      const SettingsState(demoMode: false, dataVendors: {'core_stock_apis': 'alpha_vantage'}),
      vendorCatalog: _vendorCatalog,
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('SECRET'), findsNothing);
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(field.controller?.text ?? '', isNot(contains('SECRET')));
    }
    // Both keyed vendors show a "Stored" badge (AV required + FRED macro).
    expect(find.text('Stored'), findsNWidgets(2));
  });

  testWidgets('asset type: the Run toggle wires assetType through the controller', (tester) async {
    await tester.pumpWidget(_wrap(const SettingsState(demoMode: false)));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(SettingsBody)));
    expect(container.read(settingsControllerProvider).assetType, 'stock');
    container.read(settingsControllerProvider.notifier).setAssetType('crypto');
    await tester.pumpAndSettle();
    expect(container.read(settingsControllerProvider).assetType, 'crypto');
  });

  // --- Dream Team roster picker wiring --------------------------------------------------------------
  // The all-default/partial GOLDENS prove rendering; these prove the per-role picker mutates state.
  // The apply-to-all panel also shows a 'Provider' hint, so the role-row dropdown is the .last one.

  testWidgets('roster: assigning a role provider+model wires the AgentModel through the controller',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(const SettingsState(demoMode: false)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('DREAM TEAM')); // expand the section
    await tester.pumpAndSettle();
    await tester.tap(find.text('Market Analyst')); // open the role row
    await tester.pumpAndSettle();

    await tester.tap(find.text('— Default').last); // the role-row provider dropdown (not apply-to-all)
    await tester.pumpAndSettle();
    await tester.tap(find.text('DeepSeek').last, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Model'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('V4 Pro').last, warnIfMissed: false);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(tester.element(find.byType(SettingsBody)));
    expect(container.read(settingsControllerProvider).agentModels!['market_analyst'],
        const AgentModel(provider: 'deepseek', model: 'deepseek-v4-pro'));
  });

  testWidgets('roster: a custom model id lands directly in AgentModel.model; empty unassigns',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(const SettingsState(demoMode: false)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('DREAM TEAM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trader')); // the role row (the stage header is 'TRADER')
    await tester.pumpAndSettle();

    await tester.tap(find.text('— Default').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ollama (local)').last, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Model'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom model ID').last, warnIfMissed: false); // the catalog's 'custom' sentinel
    await tester.pumpAndSettle();

    final customField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Custom model id (e.g. llama3.2:latest)');
    await tester.enterText(customField, 'my-local:latest');
    await tester.pump();

    final container = ProviderScope.containerOf(tester.element(find.byType(SettingsBody)));
    expect(container.read(settingsControllerProvider).agentModels!['trader'],
        const AgentModel(provider: 'ollama', model: 'my-local:latest')); // raw id, NOT 'custom'

    await tester.enterText(customField, '   '); // whitespace -> unassign (never AgentModel(model:''))
    await tester.pump();
    expect(container.read(settingsControllerProvider).agentModels, isNull);
  });

  testWidgets('roster: changing a role provider drops the now-stale model (unassigns)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(const SettingsState(demoMode: false)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('DREAM TEAM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Market Analyst'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('— Default').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('DeepSeek').last, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Model'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('V4 Pro').last, warnIfMissed: false);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(tester.element(find.byType(SettingsBody)));
    expect(container.read(settingsControllerProvider).agentModels!['market_analyst'],
        const AgentModel(provider: 'deepseek', model: 'deepseek-v4-pro'));

    // Re-open the (now 'DeepSeek') provider dropdown and switch — the deepseek model is invalid now.
    await tester.tap(find.text('DeepSeek')); // the role-row selected display (unique)
    await tester.pumpAndSettle();
    await tester.tap(find.text('Google Gemini').last, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(container.read(settingsControllerProvider).agentModels, isNull); // dropped, not carried
  });

  // --- Capability gate (P2.5c2) ---------------------------------------------------------------------

  testWidgets('gate: a non-tool model is DISABLED in a tool-analyst role picker (blocked)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(const SettingsState(demoMode: false)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('DREAM TEAM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Market Analyst')); // a TOOL role (RoleGate.block)
    await tester.pumpAndSettle();
    await tester.tap(find.text('— Default').last); // role provider dropdown
    await tester.pumpAndSettle();
    await tester.tap(find.text('legacy').last, warnIfMissed: false); // provider with a non-tool model
    await tester.pumpAndSettle();
    await tester.tap(find.text('Model'), warnIfMissed: false);
    await tester.pumpAndSettle();

    // The non-tool model renders with a "no tools" tag and a DISABLED DropdownMenuItem.
    final noTool = find.textContaining('no tools');
    expect(noTool, findsWidgets);
    final item = tester.widget<DropdownMenuItem<String?>>(find
        .ancestor(of: noTool.first, matching: find.byType(DropdownMenuItem<String?>))
        .first);
    expect(item.enabled, isFalse); // structurally un-pickable
    // The tool-capable sibling is selectable.
    await tester.tap(find.text('HasTool').last, warnIfMissed: false);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(SettingsBody)));
    expect(container.read(settingsControllerProvider).agentModels!['market_analyst'],
        const AgentModel(provider: 'legacy', model: 'new-x'));
  });

  testWidgets('gate: a custom id on a tool role WARNS but is NOT blocked (null = unknown)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(const SettingsState(demoMode: false)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('DREAM TEAM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('News Analyst')); // a TOOL role
    await tester.pumpAndSettle();
    await tester.tap(find.text('— Default').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ollama (local)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Model'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom model ID').last, warnIfMissed: false);
    await tester.pumpAndSettle();
    final customField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Custom model id (e.g. llama3.2:latest)');
    await tester.enterText(customField, 'tiny-local:latest');
    await tester.pump();

    // Warned (unverified) but the assignment still committed — custom must never hard-block.
    expect(find.textContaining('Tool support unverified'), findsOneWidget);
    final container = ProviderScope.containerOf(tester.element(find.byType(SettingsBody)));
    expect(container.read(settingsControllerProvider).agentModels!['news_analyst'],
        const AgentModel(provider: 'ollama', model: 'tiny-local:latest'));
  });

  testWidgets('gate: a non-tool model on a STRUCTURED role warns (degraded), never blocks',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(const SettingsState(demoMode: false)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('DREAM TEAM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Portfolio Manager')); // a STRUCTURED role (RoleGate.warn)
    await tester.pumpAndSettle();
    await tester.tap(find.text('— Default').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('legacy').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Model'), warnIfMissed: false);
    await tester.pumpAndSettle();
    // On a structured role the non-tool model is NOT disabled — selectable, with a degrade warning.
    await tester.tap(find.text('NoTool').last, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.textContaining('degrade to free-text'), findsOneWidget);
    final container = ProviderScope.containerOf(tester.element(find.byType(SettingsBody)));
    expect(container.read(settingsControllerProvider).agentModels!['portfolio_manager'],
        const AgentModel(provider: 'legacy', model: 'old-x'));
  });

  testWidgets('P3.2: discovered Ollama models fold into the roster picker; a non-tool one is DISABLED',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // The device's real models replace the static Ollama guesses, each with its real tool-capability.
    await tester.pumpWidget(_wrap(const SettingsState(demoMode: false), localModels: const [
      LocalModel('llama3.2:latest', toolCapable: true),
      LocalModel('dolphin-llama3:latest', toolCapable: false), // a plain llama3 8B — no tools
    ]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('DREAM TEAM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Market Analyst')); // a TOOL role (RoleGate.block)
    await tester.pumpAndSettle();
    await tester.tap(find.text('— Default').last); // role provider dropdown
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ollama (local)').last, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Model'), warnIfMissed: false);
    await tester.pumpAndSettle();

    // The discovered non-tool model renders with a "no tools" tag on a DISABLED item.
    final noTool = find.textContaining('no tools');
    expect(noTool, findsWidgets);
    final item = tester.widget<DropdownMenuItem<String?>>(find
        .ancestor(of: noTool.first, matching: find.byType(DropdownMenuItem<String?>))
        .first);
    expect(item.enabled, isFalse); // dolphin is structurally un-pickable on a tool role
    // The tool-capable discovered model IS pickable and commits.
    await tester.tap(find.text('llama3.2:latest').last, warnIfMissed: false);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(SettingsBody)));
    expect(container.read(settingsControllerProvider).agentModels!['market_analyst'],
        const AgentModel(provider: 'ollama', model: 'llama3.2:latest'));
  });

  testWidgets('gate: a stale non-tool assignment on a tool role surfaces as a red error chip',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // A Bench/applied combo the picker would now block, loaded directly into state.
    await tester.pumpWidget(_wrap(const SettingsState(
      demoMode: false,
      agentModels: {'fundamentals_analyst': AgentModel(provider: 'legacy', model: 'old-x')},
    )));
    await tester.pumpAndSettle();
    // The roster auto-expands (agentModels != null); the invalid row shows the error icon on its chip.
    expect(find.byIcon(Icons.error_outline), findsWidgets);
  });
}
