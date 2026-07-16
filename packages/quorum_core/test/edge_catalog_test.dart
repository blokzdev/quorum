// P5.1a client side — tolerant parsing of `GET /catalog/edge-models` + the version gate.
import 'package:quorum_core/quorum_core.dart';
import 'package:test/test.dart';

Map<String, dynamic> _payload() => {
      'contract_version': 1,
      'catalog_version': 1,
      'ollama_version': '0.32.0',
      'kv_ctx': 8192,
      'tiers': [
        {
          'tier': 'lite',
          'min_device_ram_mb': 0,
          'models': [
            {
              'id': 'qwen3.5-2b',
              'ollama_tag': 'qwen3.5:2b',
              'display': 'Qwen3.5 2B',
              'bytes': 2741180928,
              'kv_params': {'block_count': 24, 'head_count_kv': 2, 'key_length': 256, 'value_length': 256},
              'capability': 'analyst',
              'license': 'Apache-2.0',
              'blurb': 'The low-RAM analyst pick.',
              'verified': 'tag-only',
              'default': true,
              'min_ollama_version': '0.17.6',
            },
            {
              'id': 'minicpm5-1b',
              'ollama_tag': 'openbmb/minicpm5:q4_K_M',
              'display': 'MiniCPM5 1B',
              'bytes': 688065920,
              'kv_params': {'block_count': 24, 'head_count_kv': 2, 'key_length': 128, 'value_length': 128},
              'capability': 'text_only',
              'license': 'Apache-2.0',
              'blurb': 'Tiny debate-role specialist.',
              'verified': 'none',
              'default': false,
              'min_ollama_version': null,
            },
          ],
        },
        {'tier': 'core', 'min_device_ram_mb': 12000, 'models': []},
      ],
    };

void main() {
  group('EdgeModelCatalog.fromJson', () {
    test('parses every field of a full payload', () {
      final c = EdgeModelCatalog.fromJson(_payload());
      expect(c.contractVersion, 1);
      expect(c.catalogVersion, 1);
      expect(c.ollamaVersion, '0.32.0');
      expect(c.kvCtx, 8192);
      expect(c.tiers, hasLength(2));
      final lite = c.forTier(DeviceTier.lite)!;
      expect(lite.minDeviceRamMb, 0);
      final m = lite.defaultModel!;
      expect(m.id, 'qwen3.5-2b');
      expect(m.ollamaTag, 'qwen3.5:2b');
      expect(m.bytes, 2741180928);
      expect(m.capability, EdgeRoleCapability.analyst);
      expect(m.verified, 'tag-only');
      expect(m.minOllamaVersion, '0.17.6');
      // KV from served params at the default ctx (8192): 24×2×512×8192×2.
      expect(m.kvBytesAt(), 402653184);
      // And the badge composes: the lite default fits a 16GB device.
      expect(m.fitBadgeFor(16384), FitBadge.fits);
    });

    test('tolerates an empty payload — defaults, no throw (a catalog bump never hard-fails)', () {
      final c = EdgeModelCatalog.fromJson(const {});
      expect(c.contractVersion, 0);
      expect(c.ollamaVersion, isNull);
      expect(c.kvCtx, kDefaultOllamaCtx);
      expect(c.tiers, isEmpty);
      expect(c.forTier(DeviceTier.max), isNull);
    });

    test('ollama_version null round-trips (the Ollama-absent onboarding discriminator)', () {
      final j = _payload()..['ollama_version'] = null;
      expect(EdgeModelCatalog.fromJson(j).ollamaVersion, isNull);
    });

    test('unknown tier/capability strings degrade, never crash (forward-compat)', () {
      final j = _payload();
      (j['tiers'] as List).add({'tier': 'ultra', 'min_device_ram_mb': 64000, 'models': []});
      ((j['tiers'] as List)[0]['models'] as List)[0]['capability'] = 'wizard';
      final c = EdgeModelCatalog.fromJson(j);
      expect(c.tiers.last.tier, isNull); // 'ultra' buckets nowhere
      expect(c.tiers.first.models.first.capability, EdgeRoleCapability.unknown);
    });

    test('a model with missing kv_params/bytes yields null KV and a null badge — never a fabricated verdict',
        () {
      final j = _payload();
      final m = ((j['tiers'] as List)[0]['models'] as List)[0] as Map<String, dynamic>;
      m['kv_params'] = <String, dynamic>{};
      m.remove('bytes');
      final parsed = EdgeModelCatalog.fromJson(j).tiers.first.models.first;
      expect(parsed.kvBytesAt(), isNull);
      expect(parsed.fitBadgeFor(16384), isNull);
      expect(parsed.fitBadgeFor(null), isNull);
    });

    test('a tier with no default yields defaultModel == null', () {
      final j = _payload();
      (((j['tiers'] as List)[0]['models'] as List)[0] as Map)['default'] = false;
      expect(EdgeModelCatalog.fromJson(j).tiers.first.defaultModel, isNull);
    });
  });

  group('ollamaVersionAtLeast', () {
    test('the lexicographic trap: 0.9.5 is NOT >= 0.17.6 (string compare says 9 > 1)', () {
      expect(ollamaVersionAtLeast('0.9.5', '0.17.6'), isFalse);
    });

    test('numeric compare across segment counts', () {
      expect(ollamaVersionAtLeast('0.32.0', '0.17.6'), isTrue);
      expect(ollamaVersionAtLeast('0.17.6', '0.17.6'), isTrue); // equal passes
      expect(ollamaVersionAtLeast('0.17', '0.17.6'), isFalse); // missing segment reads as 0
      expect(ollamaVersionAtLeast('1.0', '0.20.0'), isTrue);
    });

    test('null / garbage detected → false (gate, never grant on the unknown)', () {
      expect(ollamaVersionAtLeast(null, '0.17.6'), isFalse);
      expect(ollamaVersionAtLeast('dev-build', '0.17.6'), isFalse);
      expect(ollamaVersionAtLeast('', '0.17.6'), isFalse);
    });
  });
}
