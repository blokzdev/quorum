// P5.3b — roster-fit: the max-not-sum rule (Ollama swaps models per-request; only the largest
// single model + KV must fit), the honesty posture for tags without full numbers, and the
// swap-latency note. Test 1 is the plan's named falsifier: a sum-based implementation fails it.
import 'package:quorum_core/quorum_core.dart';
import 'package:test/test.dart';

// A device with 16,000 MiB reported RAM -> 16,384,000,000-ish bytes of budget; the fit constants
// (4GiB fits-headroom / 2GiB tight-headroom) come straight from device_fit.dart.
const int ramMb = 16000;
const int ramBytes = ramMb * 1024 * 1024;

/// A curated catalog with two analyst entries whose KV geometry is trivial to reason about:
/// kvBytesAt(ctx) = blockCount(1) * headCountKv(1) * (key+value=2) * ctx * 2 = 4 * ctx.
EdgeModelCatalog _catalog({int kvCtx = 8192}) => EdgeModelCatalog.fromJson({
      'kv_ctx': kvCtx,
      'tiers': [
        {
          'tier': 'core',
          'min_device_ram_mb': 12000,
          'models': [
            {
              'id': 'a',
              'ollama_tag': 'qwen3.5:9b',
              'bytes': 6000000000,
              'kv_params': {'block_count': 1, 'head_count_kv': 1, 'key_length': 1, 'value_length': 1},
              'capability': 'analyst',
            },
            {
              'id': 'b',
              'ollama_tag': 'qwen3.5:2b',
              'bytes': 1500000000,
              'kv_params': {'block_count': 1, 'head_count_kv': 1, 'key_length': 1, 'value_length': 1},
              'capability': 'analyst',
            },
            {
              'id': 'bare',
              'ollama_tag': 'llama3.2',
              'bytes': 2000000000,
              'kv_params': {'block_count': 1, 'head_count_kv': 1, 'key_length': 1, 'value_length': 1},
              'capability': 'analyst',
            },
          ],
        },
      ],
    });

AgentModel _ollama(String tag) => AgentModel(provider: 'ollama', model: tag);

void main() {
  group('rosterFit — max-not-sum (the falsifier)', () {
    test('two models whose SUM exceeds RAM but whose MAX fits -> fits', () {
      // max requirement = 6e9 + KV(4*8192 = 32,768) ~= 6.0e9; + 4GiB headroom = 10.33e9 bytes.
      // sum requirement = 7.5e9 + KV; + 4GiB = 11.83e9 bytes.
      // 10,500 MiB = 11.01e9 bytes budget: the MAX fits (10.33e9 <= 11.01e9) while the SUM does
      // not (11.83e9 > 11.01e9) — a sum-based implementation fails this test.
      final r = rosterFit(
        slots: [_ollama('qwen3.5:9b'), _ollama('qwen3.5:2b')],
        catalog: _catalog(),
        localModels: const [],
        deviceRamMb: 10500,
      );
      expect(r.verdict, FitBadge.fits, reason: 'only the largest model is resident at once');
      expect(r.limitingTag, 'qwen3.5:9b');
      expect(r.distinctLocalModels, 2);
    });

    test('the limiting model is chosen by bytes+KV total, not bytes alone', () {
      // A: bigger bytes, tiny KV. B: smaller bytes, huge KV -> B has the larger total.
      final catalog = EdgeModelCatalog.fromJson({
        'kv_ctx': 8192,
        'tiers': [
          {
            'tier': 'core',
            'min_device_ram_mb': 0,
            'models': [
              {
                'id': 'a',
                'ollama_tag': 'a:1',
                'bytes': 5000000000,
                'kv_params': {'block_count': 1, 'head_count_kv': 1, 'key_length': 1, 'value_length': 1},
                'capability': 'analyst',
              },
              {
                'id': 'b',
                'ollama_tag': 'b:1',
                'bytes': 4000000000,
                // kv = 48*8*(128+128)*8192*2 = 1.61e9 -> total 5.61e9 > A's 5.0e9
                'kv_params': {'block_count': 48, 'head_count_kv': 8, 'key_length': 128, 'value_length': 128},
                'capability': 'analyst',
              },
            ],
          },
        ],
      });
      final r = rosterFit(
        slots: [_ollama('a:1'), _ollama('b:1')],
        catalog: catalog,
        localModels: const [],
        deviceRamMb: 16000,
      );
      expect(r.limitingTag, 'b:1');
    });

    test('ctx is honored: raising it flips the verdict (the A6 re-tier lever)', () {
      final catalog = EdgeModelCatalog.fromJson({
        'kv_ctx': 8192,
        'tiers': [
          {
            'tier': 'core',
            'min_device_ram_mb': 0,
            'models': [
              {
                'id': 'a',
                'ollama_tag': 'a:1',
                'bytes': 6000000000,
                // kv at ctx: 48*8*(128+128)*ctx*2 = 196,608*ctx. 8192 -> 1.61e9; 32768 -> 6.44e9.
                'kv_params': {'block_count': 48, 'head_count_kv': 8, 'key_length': 128, 'value_length': 128},
                'capability': 'analyst',
              },
            ],
          },
        ],
      });
      // Budget 12,000 MiB = 12.58e9. At 8192: 6e9+1.61e9+4.29e9 = 11.9e9 -> fits.
      final low = rosterFit(
          slots: [_ollama('a:1')], catalog: catalog, localModels: const [], deviceRamMb: 12000);
      expect(low.verdict, FitBadge.fits);
      // At 32768: 6e9+6.44e9+4.29e9 = 16.7e9 -> exceeds even the 2GiB tight floor -> wontFit.
      final high = rosterFit(
          slots: [_ollama('a:1')],
          catalog: catalog,
          localModels: const [],
          deviceRamMb: 12000,
          ctx: 32768);
      expect(high.verdict, FitBadge.wontFit);
    });
  });

  group('rosterFit — slot filtering + expansion', () {
    test('cloud slots are excluded; an all-cloud roster renders nothing', () {
      final mixed = rosterFit(
        slots: [
          const AgentModel(provider: 'openai', model: 'gpt-5.5'),
          _ollama('qwen3.5:2b'),
        ],
        catalog: _catalog(),
        localModels: const [],
        deviceRamMb: ramMb,
      );
      expect(mixed.distinctLocalModels, 1);
      final cloud = rosterFit(
        slots: [const AgentModel(provider: 'openai', model: 'gpt-5.5')],
        catalog: _catalog(),
        localModels: const [],
        deviceRamMb: ramMb,
      );
      expect(cloud.verdict, isNull);
      expect(cloud.distinctLocalModels, 0);
      expect(cloud.swapLatencyNote, isFalse);
    });

    test('effectiveSlots: overrides win; unassigned roles fall back to quick, deep roles to deep',
        () {
      final slots = effectiveSlots(
        roleKeys: ['market', 'news', 'research_manager'],
        deepRoles: {'research_manager'},
        agentModels: {'market': _ollama('qwen3.5:9b')},
        globalProvider: 'ollama',
        quickModel: 'qwen3.5:2b',
        deepModel: 'qwen3.6:35b',
      );
      expect(slots.map((s) => s.model).toList(),
          ['qwen3.5:9b', 'qwen3.5:2b', 'qwen3.6:35b']);
    });

    test('effectiveSlots: no global provider or blank models contribute nothing', () {
      expect(
          effectiveSlots(
            roleKeys: ['market', 'news'],
            deepRoles: const {},
            agentModels: {'market': const AgentModel(provider: 'ollama', model: '  ')},
          ),
          isEmpty);
    });

    test('effectiveSlots: a present-but-BLANK override falls back to the global model — exactly '
        'what the engine runs (#54 review)', () {
      final slots = effectiveSlots(
        roleKeys: ['market'],
        deepRoles: const {},
        agentModels: {'market': const AgentModel(provider: 'ollama', model: '  ')},
        globalProvider: 'ollama',
        quickModel: 'qwen3.6:35b',
      );
      expect(slots.map((s) => s.model).toList(), ['qwen3.6:35b'],
          reason: 'the engine drops a blank-model spec and runs the global fallback');
    });

    test(':latest normalization dedupes bare and tagged forms and matches the curated entry', () {
      final r = rosterFit(
        slots: [_ollama('llama3.2'), _ollama('llama3.2:latest')],
        catalog: _catalog(),
        localModels: const [],
        deviceRamMb: ramMb,
      );
      expect(r.distinctLocalModels, 1, reason: 'llama3.2 == llama3.2:latest');
      expect(r.unknownTags, isEmpty, reason: 'the bare curated tag must resolve');
      expect(r.verdict, isNotNull);
    });
  });

  group('rosterFit — honesty for unknown tags', () {
    test('non-curated installed tag whose bytes-only bound already exceeds RAM -> wontFit', () {
      final r = rosterFit(
        slots: [_ollama('mystery:70b')],
        catalog: _catalog(),
        localModels: const [LocalModel('mystery:70b', size: 40000000000)],
        deviceRamMb: ramMb, // 16.8e9 budget; 40e9 bound alone fails even the tight floor
      );
      expect(r.verdict, FitBadge.wontFit,
          reason: 'an understated number that still fails is an honest fail');
      expect(r.limitingTag, 'mystery:70b');
    });

    test('non-curated installed tag whose bound fits -> null verdict + tag in unknownTags', () {
      final r = rosterFit(
        slots: [_ollama('mystery:1b')],
        catalog: _catalog(),
        localModels: const [LocalModel('mystery:1b', size: 1000000000)],
        deviceRamMb: ramMb,
      );
      expect(r.verdict, isNull, reason: 'no KV geometry -> never promise a fit');
      expect(r.unknownTags, ['mystery:1b']);
    });

    test('uninstalled custom tag -> null verdict + tag in unknownTags', () {
      final r = rosterFit(
        slots: [_ollama('ghost:7b')],
        catalog: _catalog(),
        localModels: const [],
        deviceRamMb: ramMb,
      );
      expect(r.verdict, isNull);
      expect(r.limitingBytes, isNull);
      expect(r.unknownTags, ['ghost:7b']);
    });

    test('a mixed roster with one unknown tag cannot promise fits even if the curated max fits',
        () {
      final r = rosterFit(
        slots: [_ollama('qwen3.5:2b'), _ollama('mystery:1b')],
        catalog: _catalog(),
        localModels: const [LocalModel('mystery:1b', size: 1000000000)],
        deviceRamMb: ramMb,
      );
      expect(r.verdict, isNull);
      expect(r.unknownTags, ['mystery:1b']);
    });

    test('an UNINSTALLED curated entry with bytes but broken KV geometry still proves wontFit '
        '(#54 review)', () {
      final broken = EdgeModelCatalog.fromJson({
        'kv_ctx': 8192,
        'tiers': [
          {
            'tier': 'max',
            'min_device_ram_mb': 0,
            'models': [
              {
                'id': 'big',
                'ollama_tag': 'big:70b',
                'bytes': 40000000000,
                'kv_params': {'block_count': 48}, // value_length etc. missing -> kvBytesAt null
                'capability': 'analyst',
              },
            ],
          },
        ],
      });
      final r = rosterFit(
        slots: [_ollama('big:70b')],
        catalog: broken,
        localModels: const [], // NOT installed — the served bytes alone must carry the bound
        deviceRamMb: ramMb,
      );
      expect(r.verdict, FitBadge.wontFit,
          reason: 'a provable wontFit must not degrade to silence');
      expect(r.limitingIncludesKv, isFalse, reason: 'the bound excludes context memory');
      expect(r.unknownTags, ['big:70b']);
    });

    test('a slot pinned to a REMOTE Ollama is never charged to local RAM (#54 review)', () {
      final r = rosterFit(
        slots: [
          const AgentModel(
              provider: 'ollama', model: 'qwen3.5:9b', backendUrl: 'http://192.168.1.50:11434/v1'),
          _ollama('qwen3.5:2b'),
        ],
        catalog: _catalog(),
        localModels: const [],
        deviceRamMb: ramMb,
      );
      expect(r.distinctLocalModels, 1, reason: 'only the local slot counts');
      expect(r.limitingTag, 'qwen3.5:2b');
      expect(r.limitingIncludesKv, isTrue);
    });

    test('isLoopbackBackendUrl: null/empty/localhost forms are local; LAN hosts are not', () {
      expect(isLoopbackBackendUrl(null), isTrue);
      expect(isLoopbackBackendUrl('  '), isTrue);
      expect(isLoopbackBackendUrl('http://localhost:11434/v1'), isTrue);
      expect(isLoopbackBackendUrl('http://127.0.0.1:11434/v1'), isTrue);
      expect(isLoopbackBackendUrl('http://[::1]:11434/v1'), isTrue);
      expect(isLoopbackBackendUrl('http://192.168.1.50:11434/v1'), isFalse);
      expect(isLoopbackBackendUrl('https://ollama.example.com/v1'), isFalse);
    });

    test('unknown device RAM -> null verdict', () {
      final r = rosterFit(
        slots: [_ollama('qwen3.5:2b')],
        catalog: _catalog(),
        localModels: const [],
        deviceRamMb: null,
      );
      expect(r.verdict, isNull);
      expect(r.limitingTag, 'qwen3.5:2b', reason: 'the number is known even if RAM is not');
    });
  });

  group('rosterFit — swap note + boundary math', () {
    test('swap note: 1 distinct model -> false; 2 distinct -> true (kSwapNoteThreshold)', () {
      final one = rosterFit(
          slots: [_ollama('qwen3.5:2b'), _ollama('qwen3.5:2b')],
          catalog: _catalog(),
          localModels: const [],
          deviceRamMb: ramMb);
      expect(one.distinctLocalModels, 1);
      expect(one.swapLatencyNote, isFalse);
      final two = rosterFit(
          slots: [_ollama('qwen3.5:2b'), _ollama('qwen3.5:9b')],
          catalog: _catalog(),
          localModels: const [],
          deviceRamMb: ramMb);
      expect(two.swapLatencyNote, isTrue);
    });

    test('boundary math delegates to the fitBadge constants exactly', () {
      // requirement = bytes + kv(4*8192 = 32,768). Choose RAM so requirement + 4GiB == budget
      // exactly -> fits; one MiB less -> tight; below the 2GiB floor -> wontFit.
      const bytes = 6000000000;
      const kv = 4 * 8192;
      const requirement = bytes + kv;
      final exactFitsMb = (requirement + kFitsHeadroomBytes) ~/ (1024 * 1024);
      final atFits = rosterFit(
          slots: [_ollama('qwen3.5:9b')],
          catalog: _catalog(),
          localModels: const [],
          deviceRamMb: exactFitsMb + 1); // +1 MiB: integer floor put budget just under the line
      expect(atFits.verdict, FitBadge.fits);
      final justUnder = rosterFit(
          slots: [_ollama('qwen3.5:9b')],
          catalog: _catalog(),
          localModels: const [],
          deviceRamMb: exactFitsMb - 1);
      expect(justUnder.verdict, FitBadge.tight);
      final belowTight = rosterFit(
          slots: [_ollama('qwen3.5:9b')],
          catalog: _catalog(),
          localModels: const [],
          deviceRamMb: (requirement + kTightHeadroomBytes) ~/ (1024 * 1024) - 1);
      expect(belowTight.verdict, FitBadge.wontFit);
    });
  });

  group('entryForTag + canonicalTag (slice 1)', () {
    test('entryForTag resolves exact, bare, and :latest forms; unknown -> null', () {
      final c = _catalog();
      expect(c.entryForTag('qwen3.5:9b')?.id, 'a');
      expect(c.entryForTag('llama3.2')?.id, 'bare');
      expect(c.entryForTag('llama3.2:latest')?.id, 'bare',
          reason: 'a :latest lookup must find the bare curated tag');
      expect(c.entryForTag('qwen3.5:0.6b'), isNull);
      expect(c.entryForTag(''), isNull);
    });

    test('canonicalTag: bare names expand to :latest; tagged names pass through', () {
      expect(canonicalTag('llama3.2'), 'llama3.2:latest');
      expect(canonicalTag('qwen3.5:2b'), 'qwen3.5:2b');
    });
  });
}
