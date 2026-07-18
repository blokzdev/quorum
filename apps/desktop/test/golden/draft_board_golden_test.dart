// P5.1d — Draft Board goldens: tiers + fit badges + installed marker (exit criterion), the
// old-Ollama version gate, the Ollama-absent degraded state, and the A7 anchor made visible
// (gemma4:e2b badges Won't-fit on an 8GB device).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quorum/state/pull_controller.dart';
import 'package:quorum/state/settings_controller.dart';
import 'package:quorum/ui/brand.dart';
import 'package:quorum/ui/quorum_colors.dart';
import 'package:quorum/ui/settings_surface.dart';
import 'package:quorum_core/quorum_core.dart';

const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

final _catalog = Catalog(
  contractVersion: 1,
  analysts: const ['market', 'social', 'news', 'fundamentals'],
  providers: {
    'anthropic': const ProviderCatalog('anthropic', {
      'quick': [ModelOption('Claude Sonnet 4.6', 'claude-sonnet-4-6')],
      'deep': [ModelOption('Claude Opus 4.8', 'claude-opus-4-8')],
    }),
  },
);

/// A compact 8-entry fixture spanning all tiers (fixture, not the shipped seed): mixed
/// verified/tag-only, per-entry version gates on the qwen3.5/3.6 + gemma4 rows, one text-only row,
/// and one oversized row so a 16GB device shows the full Fits/Tight/Won't-fit spread.
Map<String, dynamic> _edgeJson({String? ollamaVersion}) => {
      'contract_version': 1,
      'catalog_version': 1,
      'ollama_version': ollamaVersion,
      'kv_ctx': 8192,
      'tiers': [
        {
          'tier': 'lite',
          'min_device_ram_mb': 0,
          'models': [
            {
              'id': 'qwen3.5-2b', 'ollama_tag': 'qwen3.5:2b', 'display': 'Qwen3.5 2B',
              'bytes': 2741180928,
              'kv_params': {'block_count': 24, 'head_count_kv': 2, 'key_length': 256, 'value_length': 256},
              'capability': 'analyst', 'license': 'Apache-2.0',
              'blurb': 'The low-RAM analyst pick.',
              'verified': 'tag-only', 'default': true, 'min_ollama_version': '0.17.6',
            },
            {
              'id': 'llama3.2-3b', 'ollama_tag': 'llama3.2', 'display': 'Llama 3.2 3B',
              'bytes': 2019377376,
              'kv_params': {'block_count': 28, 'head_count_kv': 8, 'key_length': 128, 'value_length': 128},
              'capability': 'analyst', 'license': 'Llama 3.2 Community',
              'blurb': 'The proven fallback — real-run verified.',
              'verified': 'real-run', 'default': false, 'min_ollama_version': null,
            },
            {
              'id': 'minicpm5-1b', 'ollama_tag': 'openbmb/minicpm5:q4_K_M', 'display': 'MiniCPM5 1B',
              'bytes': 688065920,
              'kv_params': {'block_count': 24, 'head_count_kv': 2, 'key_length': 128, 'value_length': 128},
              'capability': 'text_only', 'license': 'Apache-2.0',
              'blurb': 'Tiny debate-role specialist; no tool path through Ollama.',
              'verified': 'none', 'default': false, 'min_ollama_version': null,
            },
          ],
        },
        {
          'tier': 'core',
          'min_device_ram_mb': 12000,
          'models': [
            {
              'id': 'qwen3.5-9b', 'ollama_tag': 'qwen3.5:9b', 'display': 'Qwen3.5 9B',
              'bytes': 6594462816,
              'kv_params': {'block_count': 32, 'head_count_kv': 4, 'key_length': 256, 'value_length': 256},
              'capability': 'analyst', 'license': 'Apache-2.0',
              'blurb': 'The flagship free-local pick (66.1 BFCL-V4).',
              'verified': 'tag-only', 'default': true, 'min_ollama_version': '0.17.6',
            },
            {
              'id': 'gemma4-e2b', 'ollama_tag': 'gemma4:e2b', 'display': 'Gemma 4 E2B',
              'bytes': 7162394016,
              'kv_params': {'block_count': 35, 'head_count_kv': 1, 'key_length': 512, 'value_length': 512},
              'capability': 'analyst', 'license': 'Apache-2.0',
              'blurb': 'Thinking mode included; bigger on disk than its name suggests.',
              'verified': 'tag-only', 'default': false, 'min_ollama_version': '0.20.0',
            },
            {
              // Fixture-sized so a 16GB device shows the TIGHT band (12e9 + KV + tight headroom fits;
              // full headroom misses by a hair).
              'id': 'qwen3-14b', 'ollama_tag': 'qwen3:14b', 'display': 'Qwen3 14B',
              'bytes': 12000000000,
              'kv_params': {'block_count': 28, 'head_count_kv': 8, 'key_length': 128, 'value_length': 128},
              'capability': 'analyst', 'license': 'Apache-2.0',
              'blurb': 'The biggest dense option for this tier.',
              'verified': 'tag-only', 'default': false, 'min_ollama_version': null,
            },
          ],
        },
        {
          'tier': 'max',
          'min_device_ram_mb': 32000,
          'models': [
            {
              'id': 'qwen3.6-35b', 'ollama_tag': 'qwen3.6:35b', 'display': 'Qwen3.6 35B-A3B',
              'bytes': 23938321664,
              'kv_params': {'block_count': 40, 'head_count_kv': 2, 'key_length': 256, 'value_length': 256},
              'capability': 'analyst', 'license': 'Apache-2.0',
              'blurb': 'Newest-gen MoE for 32GB+ machines.',
              'verified': 'tag-only', 'default': true, 'min_ollama_version': '0.17.7',
            },
          ],
        },
      ],
    };

/// Injects deterministic pull states for the P5.2 goldens (no network, no timers).
class _FixturePulls extends PullController {
  final Map<String, PullSnapshot> fixture;
  _FixturePulls(this.fixture);
  @override
  Map<String, PullSnapshot> build() => fixture;
}

Widget _wrap({
  required EdgeModelCatalog edgeCatalog,
  int? deviceRamMb,
  List<LocalModel> localModels = const [],
  Map<String, PullSnapshot> pulls = const {},
}) =>
    ProviderScope(
      overrides: [
        initialSettingsProvider.overrideWithValue(const SettingsState(
          demoMode: true,
          ticker: 'NVDA',
          provider: 'anthropic',
          deepModel: 'claude-opus-4-8',
          quickModel: 'claude-sonnet-4-6',
        )),
        pullControllerProvider.overrideWith(() => _FixturePulls(pulls)),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          fontFamily: 'Inter',
          scaffoldBackgroundColor: QC.bg,
          extensions: const [QuorumBrand.dark()],
        ),
        home: Scaffold(
          backgroundColor: QC.bg,
          body: SettingsBody(
            catalog: _catalog,
            localModels: localModels,
            edgeCatalog: edgeCatalog,
            deviceRamMb: deviceRamMb,
          ),
        ),
      ),
    );

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'readAll') return <String, String>{};
      if (call.method == 'containsKey') return false;
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  testWidgets('draft board — tiers, fit badges, installed marker (16GB core device)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(820, 2450));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(
      edgeCatalog: EdgeModelCatalog.fromJson(_edgeJson(ollamaVersion: '0.32.0')),
      deviceRamMb: 16384,
      localModels: const [LocalModel('llama3.2:latest', toolCapable: true)],
    ));
    await tester.pumpAndSettle();

    expect(find.text('THIS MACHINE'), findsOneWidget); // core is the detected tier
    expect(find.text('Installed ✓'), findsOneWidget); // llama3.2 only (tag ⇄ :latest normalization)
    expect(find.text('Tight'), findsOneWidget); // the fixture 14B on 16GB
    // The 35B MoE card + the Max preset row's badge (P5.3a: preset rows carry fit badges too).
    expect(find.text("Won't fit"), findsNWidgets(2));
    await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/draft_board_tiers.png'));
  });

  testWidgets('draft board — old Ollama gates the versioned entries', (tester) async {
    await tester.binding.setSurfaceSize(const Size(820, 2450));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(
      edgeCatalog: EdgeModelCatalog.fromJson(_edgeJson(ollamaVersion: '0.15.0')),
      deviceRamMb: 16384,
    ));
    await tester.pumpAndSettle();

    // qwen3.5 (x2) + gemma4 + qwen3.6 CARDS carry the gate line; llama3.2/minicpm5/qwen3:14b do
    // not. P5.3a: the qwen3.5/qwen3.6 tier-DEFAULT rows repeat it on their preset rows (gemma4 is
    // not a default -> no preset row), so 0.17.6 = 2 cards + 2 presets, 0.17.7 = card + preset.
    expect(find.textContaining('Requires Ollama ≥ 0.17.6'), findsNWidgets(4));
    expect(find.textContaining('Requires Ollama ≥ 0.20.0'), findsOneWidget);
    expect(find.textContaining('Requires Ollama ≥ 0.17.7'), findsNWidgets(2));
    await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/draft_board_old_ollama.png'));
  });

  testWidgets('draft board — Ollama absent renders guidance + re-detect, never a broken board',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(820, 2450));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(
      edgeCatalog: EdgeModelCatalog.fromJson(_edgeJson(ollamaVersion: null)),
      deviceRamMb: 16384,
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('install it from ollama.com/download'), findsOneWidget);
    expect(find.text('Re-detect'), findsOneWidget);
    expect(find.textContaining('Requires Ollama'), findsNothing); // absent ≠ old — no double warning
    expect(find.text('Installed ✓'), findsNothing);
    await expectLater(
        find.byType(Scaffold), matchesGoldenFile('goldens/draft_board_ollama_absent.png'));
  });

  testWidgets('draft board — the A7 anchor visible: gemma4:e2b badges Won\'t fit on an 8GB device',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(820, 2450));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(
      edgeCatalog: EdgeModelCatalog.fromJson(_edgeJson(ollamaVersion: '0.32.0')),
      deviceRamMb: 8062, // a real "8GB" machine reports under nominal
    ));
    await tester.pumpAndSettle();

    // Lite is the detected tier; every core/max heavyweight badges Won't fit (incl. gemma4:e2b).
    expect(find.text('THIS MACHINE'), findsOneWidget);
    // Cards: 9b, e2b, 14b-fixture, 35b. P5.3a preset rows: Core (9b) + Max (35b) repeat their
    // default's badge; the Lite preset (2b) fits an 8GB device.
    expect(find.text("Won't fit"), findsNWidgets(6));
    await expectLater(
        find.byType(Scaffold), matchesGoldenFile('goldens/draft_board_lite_device.png'));
  });

  testWidgets('draft board — a pull in flight: progress + cancel; other buttons disabled',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(820, 2450));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(
      edgeCatalog: EdgeModelCatalog.fromJson(_edgeJson(ollamaVersion: '0.32.0')),
      deviceRamMb: 16384,
      pulls: {
        'qwen3.5:9b': PullSnapshot.fromJson(const {
          'tag': 'qwen3.5:9b', 'status': 'pulling',
          'total': 6594462816, 'completed': 3297231408,
        }),
      },
    ));
    await tester.pumpAndSettle();
    // The board card AND the Core preset row mirror the SAME pull (P5.3a routes the preset's
    // needs-pull state through the shared affordance) — both show live progress.
    expect(find.text('Cancel'), findsNWidgets(2));
    expect(find.text('3.3 GB / 6.6 GB'), findsNWidgets(2)); // honest byte counts, mono
    await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/draft_board_pulling.png'));
  });

  testWidgets('draft board — a failed pull shows the server error verbatim + Retry',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(820, 2450));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(
      edgeCatalog: EdgeModelCatalog.fromJson(_edgeJson(ollamaVersion: '0.32.0')),
      deviceRamMb: 16384,
      pulls: {
        'qwen3.5:9b': PullSnapshot.fromJson(const {
          'tag': 'qwen3.5:9b', 'status': 'error',
          'error': 'write /models/blobs: no space left on device',
          'error_kind': 'ollama_error',
        }),
      },
    ));
    await tester.pumpAndSettle();
    // Board card + Core preset row both surface the same failed pull (P5.3a shared affordance).
    expect(find.textContaining('no space left on device'), findsNWidgets(2));
    expect(find.text('Retry'), findsNWidgets(2));
    await expectLater(
        find.byType(Scaffold), matchesGoldenFile('goldens/draft_board_pull_error.png'));
  });

  testWidgets('draft board — a drifted pull warns even after success', (tester) async {
    await tester.binding.setSurfaceSize(const Size(820, 2450));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(
      edgeCatalog: EdgeModelCatalog.fromJson(_edgeJson(ollamaVersion: '0.32.0')),
      deviceRamMb: 16384,
      pulls: {
        'qwen3.5:2b': PullSnapshot.fromJson(const {
          'tag': 'qwen3.5:2b', 'status': 'success',
          'total': 2841180928, 'completed': 2841180928,
          'catalog_bytes': 2741180928,
          'drift': true, 'drift_reason': 'no layer matched catalog bytes',
        }),
      },
    ));
    await tester.pumpAndSettle();
    // Board card + Lite preset row both keep the drift warning visible (P5.3a shared affordance).
    expect(find.textContaining('differs from the curated catalog'), findsNWidgets(2));
    await expectLater(
        find.byType(Scaffold), matchesGoldenFile('goldens/draft_board_pull_drift.png'));
  });

  testWidgets("draft board — a Won't-fit pull needs a second, informed tap", (tester) async {
    await tester.binding.setSurfaceSize(const Size(820, 2450));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(
      edgeCatalog: EdgeModelCatalog.fromJson(_edgeJson(ollamaVersion: '0.32.0')),
      deviceRamMb: 8062, // gemma4:e2b badges Won't fit here
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pull · 7.2 GB')); // first tap does NOT start the pull
    await tester.pumpAndSettle();
    expect(find.textContaining('May not run on this machine'), findsOneWidget);
    expect(find.text('Pull anyway · 7.2 GB'), findsOneWidget);
    expect(find.text('Keep browsing'), findsOneWidget);
    await expectLater(
        find.byType(Scaffold), matchesGoldenFile('goldens/draft_board_wontfit_confirm.png'));
  });

  testWidgets('P5.3a preset rows — installed Apply vs needs-pull routing (16GB core device)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(820, 2450));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(
      edgeCatalog: EdgeModelCatalog.fromJson(_edgeJson(ollamaVersion: '0.32.0')),
      deviceRamMb: 16384,
      // The CORE tier default is installed -> its preset row shows Apply; Lite/Max defaults are
      // not -> their rows route through the P5.2 pull affordance instead.
      localModels: const [LocalModel('qwen3.5:9b', toolCapable: true)],
    ));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Free local team — Max'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    expect(find.text('Free local team — Lite'), findsOneWidget);
    expect(find.text('Free local team — Core'), findsOneWidget);
    expect(find.text('Free local team — Max'), findsOneWidget);
    expect(find.text('Apply — switches to real local runs'), findsOneWidget); // core only
    expect(find.textContaining('first — Apply unlocks'), findsNWidgets(2)); // lite + max
    expect(find.text('Your tier'), findsOneWidget); // 16GB -> core is the detected tier
    await expectLater(
        find.byType(Scaffold), matchesGoldenFile('goldens/draft_board_preset_rows.png'));
  });
}
