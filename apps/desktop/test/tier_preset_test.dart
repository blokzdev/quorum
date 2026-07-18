// P5.3a/b — tier presets + the reactive providers. The apply falsifier seeds every stale field the
// partial-merge hazard would leak (backendUrl / effort / custom ids / keyed vendor / demo / a mixed
// roster) and asserts a complete valid all-local config lands in ONE call — reusing applyBench
// instead of applyTierPreset fails this test on backendUrl/effort/vendors.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quorum/dream_team_roster.dart';
import 'package:quorum/state/catalog_provider.dart';
import 'package:quorum/state/device_ram_provider.dart';
import 'package:quorum/state/roster_fit_provider.dart';
import 'package:quorum/state/settings_controller.dart';
import 'package:quorum/state/tier_presets.dart';
import 'package:quorum_core/quorum_core.dart';

const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

Map<String, dynamic> _edgeJson() => {
      'kv_ctx': 8192,
      'ollama_version': '0.32.1',
      'tiers': [
        {
          'tier': 'lite',
          'min_device_ram_mb': 0,
          'models': [
            {
              'id': 'qwen35-2b',
              'ollama_tag': 'qwen3.5:2b',
              'bytes': 1500000000,
              'kv_params': {'block_count': 1, 'head_count_kv': 1, 'key_length': 1, 'value_length': 1},
              'capability': 'analyst',
              'default': true,
            },
          ],
        },
        {
          'tier': 'core',
          'min_device_ram_mb': 12000,
          'models': [
            {
              'id': 'qwen35-9b',
              'ollama_tag': 'qwen3.5:9b',
              'bytes': 6000000000,
              'kv_params': {'block_count': 1, 'head_count_kv': 1, 'key_length': 1, 'value_length': 1},
              'capability': 'analyst',
              'default': true,
            },
          ],
        },
        {
          'tier': 'max',
          'min_device_ram_mb': 32000,
          'models': [
            // No default -> this tier must contribute NO preset (never fabricate one).
            {
              'id': 'qwen36-35b',
              'ollama_tag': 'qwen3.6:35b',
              'bytes': 24000000000,
              'kv_params': {'block_count': 1, 'head_count_kv': 1, 'key_length': 1, 'value_length': 1},
              'capability': 'analyst',
            },
          ],
        },
      ],
    };

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
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('buildTierPresets', () {
    test('one preset per tier with a usable default, named by the A5 triple', () {
      final presets = buildTierPresets(EdgeModelCatalog.fromJson(_edgeJson()));
      expect(presets.map((p) => p.name).toList(),
          ['Free local team — Lite', 'Free local team — Core'],
          reason: 'the defaultless max tier contributes no preset');
      final core = presets[1];
      expect(core.tier, DeviceTier.core);
      expect(core.model.ollamaTag, 'qwen3.5:9b');
      expect(core.agentModels.length, dreamTeamRoleKeys.length);
      for (final role in dreamTeamRoleKeys) {
        expect(core.agentModels[role]!.provider, 'ollama');
        expect(core.agentModels[role]!.model, 'qwen3.5:9b');
      }
    });
  });

  group('applyTierPreset (the one-click falsifier)', () {
    test('scrubs every stale field and lands a complete valid all-local config', () {
      const stale = SettingsState(
        demoMode: true,
        provider: 'openai',
        deepModel: 'gpt-5.5',
        quickModel: 'custom',
        customQuickModel: 'my-relay-model',
        effort: 'high',
        backendUrl: 'https://relay.example', // would poison ollama roles via the global fallback
        dataVendors: {'fundamentals_data': 'alpha_vantage'}, // keyed -> would re-block keyless Run
        agentModels: {'market_analyst': AgentModel(provider: 'google', model: 'gemini-3.1-pro')},
        benches: [Bench(name: 'Mine', provider: 'openai')],
      );
      final c = ProviderContainer(
          overrides: [initialSettingsProvider.overrideWithValue(stale)]);
      addTearDown(c.dispose);
      final presets = buildTierPresets(EdgeModelCatalog.fromJson(_edgeJson()));
      final core = presets.singleWhere((p) => p.tier == DeviceTier.core);

      c.read(settingsControllerProvider.notifier).applyTierPreset(core);

      final s = c.read(settingsControllerProvider);
      expect(s.provider, 'ollama');
      expect(s.quickModel, 'qwen3.5:9b');
      expect(s.deepModel, 'qwen3.5:9b');
      expect(s.customQuickModel, isNull);
      expect(s.customDeepModel, isNull);
      expect(s.effort, isNull, reason: 'a stale cloud effort must not survive');
      expect(s.backendUrl, isNull, reason: 'a stale relay URL would hit every ollama role');
      expect(s.dataVendors, isNull, reason: 'back to keyless engine defaults');
      expect(s.demoMode, isFalse, reason: 'the preset exists to run REAL local analysis');
      expect(s.agentModels!.length, dreamTeamRoleKeys.length);
      for (final role in dreamTeamRoleKeys) {
        expect(s.agentModels![role]!.provider, 'ollama');
        expect(s.agentModels![role]!.model, 'qwen3.5:9b');
      }
      expect(s.benches.map((b) => b.name).toList(), ['Mine'],
          reason: 'presets are synthesized, never persisted into the bench list');
    });
  });

  group('anyKeysStoredProvider (the P5.3c keyless discriminator)', () {
    test('false on an empty vault; the first stored key flips it true; delete flips back',
        () async {
      final c = ProviderContainer(
          overrides: [initialSettingsProvider.overrideWithValue(const SettingsState())]);
      addTearDown(c.dispose);
      final sub = c.listen(anyKeysStoredProvider, (_, _) {});
      addTearDown(sub.close);
      expect(await c.read(anyKeysStoredProvider.future), isFalse);

      await c.read(settingsControllerProvider.notifier).saveKey('openai', 'sk-test');
      expect(await c.read(anyKeysStoredProvider.future), isTrue,
          reason: 'the vault-revision bump must re-check');

      await c.read(settingsControllerProvider.notifier).deleteKey('openai');
      expect(await c.read(anyKeysStoredProvider.future), isFalse);
    });
  });

  group('rosterFitProvider', () {
    ProviderContainer wired(SettingsState initial, {Map<String, dynamic>? edge, int? ramMb}) {
      final c = ProviderContainer(overrides: [
        initialSettingsProvider.overrideWithValue(initial),
        edgeModelCatalogProvider.overrideWith((ref) async =>
            edge == null ? const EdgeModelCatalog() : EdgeModelCatalog.fromJson(edge)),
        localModelsProvider.overrideWith((ref) async => const <LocalModel>[]),
        deviceRamMbProvider.overrideWith((ref) async => ramMb),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('a REMOTE global Ollama endpoint suppresses local-fit claims (#54 review)', () async {
      const remote = SettingsState(
        demoMode: false,
        provider: 'ollama',
        quickModel: 'qwen3.5:2b',
        backendUrl: 'http://192.168.1.50:11434/v1', // the models load on the LAN box, not here
      );
      final c = wired(remote, edge: _edgeJson(), ramMb: 16000);
      await c.read(edgeModelCatalogProvider.future);
      await c.read(localModelsProvider.future);
      await c.read(deviceRamMbProvider.future);
      expect(c.read(rosterFitProvider), isNull,
          reason: 'no honest local-RAM claim exists for a remote endpoint');
    });

    test('null in demo mode and when the catalog is empty; a real verdict otherwise', () async {
      const local = SettingsState(
          demoMode: false, provider: 'ollama', quickModel: 'qwen3.5:2b', deepModel: 'qwen3.5:9b');

      final demo = wired(
          const SettingsState(demoMode: true, provider: 'ollama', quickModel: 'qwen3.5:2b'),
          edge: _edgeJson(),
          ramMb: 16000);
      await demo.read(edgeModelCatalogProvider.future);
      expect(demo.read(rosterFitProvider), isNull);

      final noCatalog = wired(local, ramMb: 16000);
      await noCatalog.read(edgeModelCatalogProvider.future);
      expect(noCatalog.read(rosterFitProvider), isNull);

      final live = wired(local, edge: _edgeJson(), ramMb: 16000);
      await live.read(edgeModelCatalogProvider.future);
      await live.read(localModelsProvider.future);
      await live.read(deviceRamMbProvider.future);
      final r = live.read(rosterFitProvider);
      expect(r, isNotNull);
      expect(r!.distinctLocalModels, 2, reason: 'quick 2b + deep 9b across the 12 roles');
      expect(r.swapLatencyNote, isTrue);
      expect(r.limitingTag, 'qwen3.5:9b');
      expect(r.verdict, FitBadge.fits, reason: '6GB + KV + 4GiB headroom fits 16,000 MiB');
    });
  });
}
