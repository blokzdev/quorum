import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quorum/dream_team_roster.dart';
import 'package:quorum/state/settings_controller.dart';
import 'package:quorum_core/quorum_core.dart';

/// flutter_secure_storage's platform MethodChannel, backed by an in-memory map so the controller's
/// vault reads/writes never touch the real OS keystore.
const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

ProviderContainer _container(SettingsState initial) {
  final c = ProviderContainer(overrides: [initialSettingsProvider.overrideWithValue(initial)]);
  addTearDown(c.dispose);
  return c;
}

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

  group('SettingsState (de)serialization', () {
    test('toJson/fromJson round-trips including benches', () {
      const s = SettingsState(
        demoMode: false,
        ticker: 'TSLA',
        provider: 'google',
        deepModel: 'gemini-3.1-pro-preview',
        quickModel: 'custom',
        customQuickModel: 'gemini-x',
        effort: 'high',
        backendUrl: 'https://x',
        researchDepth: 3,
        analysts: ['market', 'news'],
        outputLanguage: 'English',
        benches: [Bench(name: 'Fast', provider: 'openai', quickModel: 'gpt-5.4-mini', effort: 'low')],
        watchlist: ['NVDA', 'TSLA'],
        seededFromEnv: true,
      );
      final back = SettingsState.fromJson(s.toJson());
      expect(back.demoMode, false);
      expect(back.ticker, 'TSLA');
      expect(back.provider, 'google');
      expect(back.deepModel, 'gemini-3.1-pro-preview');
      expect(back.quickModel, 'custom');
      expect(back.customQuickModel, 'gemini-x');
      expect(back.effort, 'high');
      expect(back.backendUrl, 'https://x');
      expect(back.researchDepth, 3);
      expect(back.analysts, ['market', 'news']);
      expect(back.seededFromEnv, true);
      expect(back.benches.single.name, 'Fast');
      expect(back.benches.single.provider, 'openai');
      expect(back.benches.single.effort, 'low');
      expect(back.watchlist, ['NVDA', 'TSLA']);
    });

    test('defaults are demo-safe (cost-free, no provider)', () {
      const s = SettingsState();
      expect(s.demoMode, true);
      expect(s.ticker, 'NVDA');
      expect(s.provider, isNull);
      expect(s.seededFromEnv, false);
    });
  });

  test('setProvider clears the now-invalid model/effort/endpoint selections', () {
    final c = _container(const SettingsState(
      provider: 'google', deepModel: 'gemini-3.1-pro-preview', effort: 'high', backendUrl: 'https://x'));
    final ctrl = c.read(settingsControllerProvider.notifier);
    ctrl.setProvider('openai');
    final s = c.read(settingsControllerProvider);
    expect(s.provider, 'openai');
    expect(s.deepModel, isNull);
    expect(s.effort, isNull);
    expect(s.backendUrl, isNull);
  });

  group('buildLaunchConfig', () {
    test('demo mode → cost-free demo config, never attaches keys', () async {
      final c = _container(const SettingsState(demoMode: true, ticker: 'aapl'));
      // A stored key must NOT leak into a demo run.
      await c.read(settingsControllerProvider.notifier).saveKey('google', 'g-key');
      final cfg = await c.read(settingsControllerProvider.notifier).buildLaunchConfig();
      expect(cfg.mode, 'demo');
      expect(cfg.ticker, 'AAPL');
      expect(cfg.stepDelay, 0.2);
      expect(cfg.apiKeys, isNull);
    });

    test('real (google) → merges vault key, sets ONLY google knob, resolves models', () async {
      final c = _container(const SettingsState(
        demoMode: false,
        ticker: 'NVDA',
        provider: 'google',
        deepModel: 'gemini-3.1-pro-preview',
        quickModel: 'gemini-3.5-flash',
        effort: 'high',
        researchDepth: 2,
      ));
      final ctrl = c.read(settingsControllerProvider.notifier);
      await ctrl.saveKey('google', 'g-key');
      final cfg = await ctrl.buildLaunchConfig();
      expect(cfg.mode, 'pro');
      expect(cfg.provider, 'google');
      expect(cfg.deepModel, 'gemini-3.1-pro-preview');
      expect(cfg.quickModel, 'gemini-3.5-flash');
      expect(cfg.researchDepth, 2);
      expect(cfg.apiKeys, {'google': 'g-key'});
      expect(cfg.googleThinkingLevel, 'high');
      expect(cfg.openaiReasoningEffort, isNull);
      expect(cfg.anthropicEffort, isNull);
      // toJson omits the unset knobs.
      final j = cfg.toJson();
      expect(j['google_thinking_level'], 'high');
      expect(j.containsKey('openai_reasoning_effort'), isFalse);
    });

    test('real (ollama) → no key in vault means no api_keys; backend_url passes through', () async {
      final c = _container(const SettingsState(
        demoMode: false,
        provider: 'ollama',
        deepModel: 'custom',
        customDeepModel: 'llama3.2:latest',
        quickModel: 'custom',
        customQuickModel: 'llama3.2:latest',
        backendUrl: 'http://localhost:11434/v1',
      ));
      final cfg = await c.read(settingsControllerProvider.notifier).buildLaunchConfig();
      expect(cfg.provider, 'ollama');
      expect(cfg.apiKeys, isNull);
      expect(cfg.deepModel, 'llama3.2:latest'); // custom resolved
      expect(cfg.quickModel, 'llama3.2:latest');
      expect(cfg.backendUrl, 'http://localhost:11434/v1');
      expect(cfg.googleThinkingLevel, isNull);
    });

    test('custom model with blank override resolves to null (engine default)', () async {
      final c = _container(const SettingsState(
        demoMode: false, provider: 'deepseek', deepModel: 'custom', customDeepModel: '   '));
      final cfg = await c.read(settingsControllerProvider.notifier).buildLaunchConfig();
      expect(cfg.deepModel, isNull);
    });
  });

  group('maybeSeedKeysFromEnv', () {
    test('imports env keys into the vault once, then is idempotent', () async {
      final c = _container(const SettingsState());
      final ctrl = c.read(settingsControllerProvider.notifier);

      await ctrl.maybeSeedKeysFromEnv(() async => {'google': 'seed-g', 'openai': 'seed-o', 'x': ''});
      expect(store['quorum_apikey_google'], 'seed-g');
      expect(store['quorum_apikey_openai'], 'seed-o');
      expect(store.containsKey('quorum_apikey_x'), isFalse); // empty value skipped
      expect(c.read(settingsControllerProvider).seededFromEnv, true);

      var calledAgain = false;
      await ctrl.maybeSeedKeysFromEnv(() async {
        calledAgain = true;
        return {'google': 'OVERWRITE'};
      });
      expect(calledAgain, isFalse); // latch prevents a second fetch
      expect(store['quorum_apikey_google'], 'seed-g'); // not overwritten
    });

    test('a fetch failure leaves the latch unset so it can retry', () async {
      final c = _container(const SettingsState());
      final ctrl = c.read(settingsControllerProvider.notifier);
      await ctrl.maybeSeedKeysFromEnv(() async => throw Exception('sidecar down'));
      expect(c.read(settingsControllerProvider).seededFromEnv, false);
    });
  });

  group('benches', () {
    test('save snapshots the current model config; apply restores it; delete removes it', () {
      final c = _container(const SettingsState(
        provider: 'anthropic', deepModel: 'claude-opus-4-8', effort: 'high', researchDepth: 4));
      final ctrl = c.read(settingsControllerProvider.notifier);

      ctrl.saveBench('Deep');
      expect(c.read(settingsControllerProvider).benches.single.name, 'Deep');

      ctrl.setProvider('openai'); // wipes the selection
      expect(c.read(settingsControllerProvider).deepModel, isNull);

      ctrl.applyBench(c.read(settingsControllerProvider).benches.single);
      final s = c.read(settingsControllerProvider);
      expect(s.provider, 'anthropic');
      expect(s.deepModel, 'claude-opus-4-8');
      expect(s.effort, 'high');
      expect(s.researchDepth, 4);

      ctrl.deleteBench('Deep');
      expect(c.read(settingsControllerProvider).benches, isEmpty);
    });
  });

  group('Dream Team (agent models)', () {
    test('setAgentModel assigns/unassigns; clearAgentModels resets; empty collapses to null', () {
      final c = _container(const SettingsState());
      final ctrl = c.read(settingsControllerProvider.notifier);
      ctrl.setAgentModel('bull_researcher', const AgentModel(provider: 'xai', model: 'grok-x'));
      expect(c.read(settingsControllerProvider).agentModels!['bull_researcher'],
          const AgentModel(provider: 'xai', model: 'grok-x'));
      ctrl.setAgentModel('bull_researcher', null); // unassign the only role -> null
      expect(c.read(settingsControllerProvider).agentModels, isNull);
      ctrl.setAgentModel('trader', const AgentModel(provider: 'openai', model: 'gpt-5.5'));
      ctrl.clearAgentModels();
      expect(c.read(settingsControllerProvider).agentModels, isNull);
    });

    test('SettingsState + Bench round-trip the lineup', () {
      const lineup = {'portfolio_manager': AgentModel(provider: 'anthropic', model: 'claude-opus-4-8')};
      const s = SettingsState(agentModels: lineup);
      expect(SettingsState.fromJson(s.toJson()).agentModels!['portfolio_manager'],
          const AgentModel(provider: 'anthropic', model: 'claude-opus-4-8'));
      final bench = s.toBench('Frontier');
      expect(Bench.fromJson(bench.toJson()).agentModels!['portfolio_manager']!.provider, 'anthropic');
    });

    test('applyBench with no lineup CLEARS the current one; setProvider does NOT', () {
      const lineup = {'bull_researcher': AgentModel(provider: 'xai', model: 'grok-x')};
      final c = _container(const SettingsState(provider: 'google', agentModels: lineup));
      final ctrl = c.read(settingsControllerProvider.notifier);
      ctrl.setProvider('openai'); // global provider change keeps the lineup
      expect(c.read(settingsControllerProvider).agentModels, lineup);
      ctrl.applyBench(const Bench(name: 'plain', provider: 'openai')); // a bench with no lineup clears it
      expect(c.read(settingsControllerProvider).agentModels, isNull);
    });

    test('buildLaunchConfig merges vault keys for EVERY referenced provider (keyless omitted)', () async {
      final c = _container(const SettingsState(
        demoMode: false, provider: 'google', deepModel: 'gemini-3.1-pro-preview',
        agentModels: {
          'portfolio_manager': AgentModel(provider: 'anthropic', model: 'claude-opus-4-8'),
          'market_analyst': AgentModel(provider: 'ollama', model: 'llama3.2:latest'), // keyless
        },
      ));
      final ctrl = c.read(settingsControllerProvider.notifier);
      await ctrl.saveKey('google', 'g-key');
      await ctrl.saveKey('anthropic', 'a-key');
      final cfg = await ctrl.buildLaunchConfig();
      expect(cfg.apiKeys, {'google': 'g-key', 'anthropic': 'a-key'}); // ollama omitted (no key)
      expect(cfg.agentModels!['portfolio_manager']!.provider, 'anthropic');
    });

    test('setAllAgentModels pins one model to every one of the 12 roles', () {
      final c = _container(const SettingsState());
      final ctrl = c.read(settingsControllerProvider.notifier);
      ctrl.setAllAgentModels(const AgentModel(provider: 'xai', model: 'grok-x'));
      final models = c.read(settingsControllerProvider).agentModels!;
      expect(models.length, 12);
      expect(models.keys.toSet(), dreamTeamRoleKeys.toSet()); // exactly the frozen roster
      expect(models['portfolio_manager'], const AgentModel(provider: 'xai', model: 'grok-x'));
      expect(models['market_analyst'], const AgentModel(provider: 'xai', model: 'grok-x'));
    });

    test('a saved Bench round-trips the FULL 12-role lineup through save/apply/disk', () {
      final c = _container(const SettingsState());
      final ctrl = c.read(settingsControllerProvider.notifier);
      ctrl.setAllAgentModels(const AgentModel(provider: 'xai', model: 'grok-x'));
      ctrl.saveBench('Dream');
      final bench = c.read(settingsControllerProvider).benches.single;
      expect(bench.agentModels!.length, 12);
      // Disk round-trip preserves all 12.
      expect(Bench.fromJson(bench.toJson()).agentModels!.length, 12);
      // Apply after a clear re-hydrates the whole lineup.
      ctrl.clearAgentModels();
      expect(c.read(settingsControllerProvider).agentModels, isNull);
      ctrl.applyBench(bench);
      expect(c.read(settingsControllerProvider).agentModels!.length, 12);
      expect(c.read(settingsControllerProvider).agentModels!['trader'],
          const AgentModel(provider: 'xai', model: 'grok-x'));
    });

    test('a blank-model assignment never survives in state (invariant)', () {
      final c = _container(const SettingsState());
      final ctrl = c.read(settingsControllerProvider.notifier);
      // A blank/whitespace model must unassign, not persist as AgentModel(model:'') — the engine and
      // manifest both drop it, so a stored blank would make the roster lie about what ran.
      ctrl.setAgentModel('trader', const AgentModel(provider: 'openai', model: '  '));
      expect(c.read(settingsControllerProvider).agentModels, isNull);
      ctrl.setAllAgentModels(const AgentModel(provider: 'openai', model: ''));
      expect(c.read(settingsControllerProvider).agentModels, isNull); // no-op
    });
  });

  group('data sources (P3.1 vendors + asset type)', () {
    test('setDataVendor stores an override; null/empty removes it; last removal collapses to null', () {
      final c = _container(const SettingsState());
      final ctrl = c.read(settingsControllerProvider.notifier);
      ctrl.setDataVendor('core_stock_apis', 'alpha_vantage');
      ctrl.setDataVendor('news_data', 'alpha_vantage');
      expect(c.read(settingsControllerProvider).dataVendors,
          {'core_stock_apis': 'alpha_vantage', 'news_data': 'alpha_vantage'});
      ctrl.setDataVendor('news_data', null); // remove one
      expect(c.read(settingsControllerProvider).dataVendors, {'core_stock_apis': 'alpha_vantage'});
      ctrl.setDataVendor('core_stock_apis', ''); // empty also removes; map now empty -> null
      expect(c.read(settingsControllerProvider).dataVendors, isNull);
    });

    test('setAssetType flips the framing; default is stock', () {
      final c = _container(const SettingsState());
      final ctrl = c.read(settingsControllerProvider.notifier);
      expect(c.read(settingsControllerProvider).assetType, 'stock');
      ctrl.setAssetType('crypto');
      expect(c.read(settingsControllerProvider).assetType, 'crypto');
    });

    test('referencedVendorKeys always includes macro (fred); requiredVendorKeys never does', () {
      // The gate asymmetry: fred is MERGED whenever stored (enables macro) but never BLOCKS a launch.
      expect(referencedVendorKeys(null), {'fred'});
      expect(referencedVendorKeys({'core_stock_apis': 'alpha_vantage'}), {'fred', 'alpha_vantage'});
      expect(referencedVendorKeys({'news_data': 'yfinance'}), {'fred'}); // keyless vendor omitted

      expect(requiredVendorKeys(null), isEmpty);
      expect(requiredVendorKeys({'core_stock_apis': 'alpha_vantage'}), {'alpha_vantage'});
      // Even if fred somehow lands in dataVendors (stale bench), it is NOT required.
      expect(requiredVendorKeys({'macro_data': 'fred'}), isEmpty);
    });

    test('SettingsState + Bench round-trip dataVendors; assetType round-trips on state', () {
      const s = SettingsState(
        assetType: 'crypto',
        dataVendors: {'core_stock_apis': 'alpha_vantage', 'fundamental_data': 'alpha_vantage'},
      );
      final back = SettingsState.fromJson(s.toJson());
      expect(back.assetType, 'crypto');
      expect(back.dataVendors, {'core_stock_apis': 'alpha_vantage', 'fundamental_data': 'alpha_vantage'});
      // Bench carries the vendor preset (but not assetType — that's per-run framing, like ticker).
      final bench = s.toBench('AV');
      expect(Bench.fromJson(bench.toJson()).dataVendors,
          {'core_stock_apis': 'alpha_vantage', 'fundamental_data': 'alpha_vantage'});
    });

    test('applyBench restores a vendor preset; a bench with no vendors CLEARS the current one', () {
      final c = _container(const SettingsState(dataVendors: {'core_stock_apis': 'alpha_vantage'}));
      final ctrl = c.read(settingsControllerProvider.notifier);
      ctrl.applyBench(const Bench(name: 'plain', provider: 'openai')); // no vendors -> clears
      expect(c.read(settingsControllerProvider).dataVendors, isNull);
      ctrl.applyBench(const Bench(name: 'AV', provider: 'openai', dataVendors: {'news_data': 'alpha_vantage'}));
      expect(c.read(settingsControllerProvider).dataVendors, {'news_data': 'alpha_vantage'});
    });

    test('buildLaunchConfig merges vendor keys (core + macro), passes dataVendors + assetType', () async {
      final c = _container(const SettingsState(
        demoMode: false,
        provider: 'ollama', // keyless LLM so only vendor keys show up in api_keys
        deepModel: 'custom',
        customDeepModel: 'llama3.2:latest',
        assetType: 'crypto',
        dataVendors: {'core_stock_apis': 'alpha_vantage'},
      ));
      final ctrl = c.read(settingsControllerProvider.notifier);
      await ctrl.saveKey('alpha_vantage', 'av-key'); // core vendor (required)
      await ctrl.saveKey('fred', 'fred-key'); // macro vendor (enables macro; always merged)
      final cfg = await ctrl.buildLaunchConfig();
      expect(cfg.mode, 'pro');
      expect(cfg.assetType, 'crypto');
      expect(cfg.dataVendors, {'core_stock_apis': 'alpha_vantage'});
      expect(cfg.apiKeys, {'alpha_vantage': 'av-key', 'fred': 'fred-key'});
    });

    test('buildLaunchConfig omits an unstored vendor key; macro key merged only when stored', () async {
      final c = _container(const SettingsState(
        demoMode: false,
        provider: 'ollama',
        deepModel: 'custom',
        customDeepModel: 'llama3.2:latest',
        dataVendors: {'core_stock_apis': 'alpha_vantage'},
      ));
      // No keys stored at all.
      final cfg = await c.read(settingsControllerProvider.notifier).buildLaunchConfig();
      expect(cfg.apiKeys, isNull); // alpha_vantage + fred both unstored -> nothing merged
      expect(cfg.assetType, 'stock'); // default still sent
      expect(cfg.dataVendors, {'core_stock_apis': 'alpha_vantage'});
    });

    test('missingKeysProvider gates a keyed core vendor but never the macro vendor; empty in demo', () async {
      final c = _container(const SettingsState(
        demoMode: false,
        provider: 'ollama', // keyless LLM -> isolates vendor gating
        dataVendors: {'core_stock_apis': 'alpha_vantage'},
      ));
      // fred stored (macro), alpha_vantage NOT stored.
      await c.read(settingsControllerProvider.notifier).saveKey('fred', 'fred-key');
      final missing = await c.read(missingKeysProvider.future);
      expect(missing, ['alpha_vantage']); // core keyed vendor gated; fred never gated
    });

    test('missingKeysProvider is empty in demo mode even with a keyed vendor selected', () async {
      final c = _container(const SettingsState(
        demoMode: true,
        dataVendors: {'core_stock_apis': 'alpha_vantage'},
      ));
      expect(await c.read(missingKeysProvider.future), isEmpty);
    });
  });

  group('watchlist', () {
    test('toggleWatch adds (uppercased) then toggles off; removeWatch deletes', () {
      final c = _container(const SettingsState());
      final ctrl = c.read(settingsControllerProvider.notifier);
      ctrl.toggleWatch('nvda');
      expect(c.read(settingsControllerProvider).watchlist, ['NVDA']);
      ctrl.toggleWatch('NVDA'); // already present -> removed
      expect(c.read(settingsControllerProvider).watchlist, isEmpty);
      ctrl.toggleWatch('TSLA');
      ctrl.removeWatch('TSLA');
      expect(c.read(settingsControllerProvider).watchlist, isEmpty);
    });
  });
}
