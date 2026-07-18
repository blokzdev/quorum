// P5.1d widget tests — the SCOPE-WALL falsifier (no text input can exist in the Draft Board
// subtree), section visibility, null-RAM suppression, and Re-detect invalidation.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quorum/state/catalog_provider.dart';
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

Map<String, dynamic> _edgeJson({String? ollamaVersion}) => {
      'contract_version': 1,
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
              'capability': 'analyst', 'license': 'Apache-2.0', 'blurb': 'Pick.',
              'verified': 'tag-only', 'default': true, 'min_ollama_version': '0.17.6',
            },
          ],
        },
      ],
    };

class _FixturePulls extends PullController {
  final Map<String, PullSnapshot> fixture;
  _FixturePulls(this.fixture);
  @override
  Map<String, PullSnapshot> build() => fixture;
}

Widget _wrap({
  EdgeModelCatalog? edgeCatalog,
  int? deviceRamMb,
  Map<String, PullSnapshot> pulls = const {},
  void Function()? onEdgeFetch,
  void Function()? onLocalFetch,
}) =>
    ProviderScope(
      overrides: [
        pullControllerProvider.overrideWith(() => _FixturePulls(pulls)),
        initialSettingsProvider.overrideWithValue(const SettingsState(
          demoMode: true,
          ticker: 'NVDA',
          provider: 'anthropic',
        )),
        // Counter hooks for the Re-detect test (the Override type isn't exported by
        // flutter_riverpod 3.x, so the overrides stay an inferred literal).
        if (onEdgeFetch != null)
          edgeModelCatalogProvider.overrideWith((ref) async {
            onEdgeFetch();
            return const EdgeModelCatalog();
          }),
        if (onLocalFetch != null)
          localModelsProvider.overrideWith((ref) async {
            onLocalFetch();
            return const <LocalModel>[];
          }),
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
            edgeCatalog: edgeCatalog,
            deviceRamMb: deviceRamMb,
          ),
        ),
      ),
    );

Finder _boardFinder() =>
    find.byWidgetPredicate((w) => w.runtimeType.toString() == '_DraftBoardSection');

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

  testWidgets('SCOPE WALL: no text-entry widget exists in the Draft Board subtree, in ANY state',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(820, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final version in ['0.32.0', '0.15.0', null]) {
      await tester.pumpWidget(_wrap(
        edgeCatalog: EdgeModelCatalog.fromJson(_edgeJson(ollamaVersion: version)),
        deviceRamMb: 16384,
      ));
      await tester.pumpAndSettle();
      final board = _boardFinder();
      expect(board, findsOneWidget, reason: 'state $version must render the board');
      // EditableText underlies every Flutter text-entry widget (TextField, TextFormField, custom) —
      // this goes red the moment anyone sneaks a model-input field into the curated surface.
      expect(find.descendant(of: board, matching: find.byType(EditableText)), findsNothing,
          reason: 'the Draft Board is a curated list, NOT a model browser (state $version)');
    }
  });

  testWidgets('section hidden when the edge catalog is null or has no tiers', (tester) async {
    await tester.binding.setSurfaceSize(const Size(820, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(edgeCatalog: null));
    await tester.pumpAndSettle();
    expect(_boardFinder(), findsNothing);
    expect(find.text('DRAFT BOARD'), findsNothing);

    await tester.pumpWidget(_wrap(edgeCatalog: const EdgeModelCatalog())); // degraded empty
    await tester.pumpAndSettle();
    expect(_boardFinder(), findsNothing);
  });

  testWidgets('unknown device RAM suppresses fit badges and the tier highlight — never a guess',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(820, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(
      edgeCatalog: EdgeModelCatalog.fromJson(_edgeJson(ollamaVersion: '0.32.0')),
      deviceRamMb: null,
    ));
    await tester.pumpAndSettle();
    expect(_boardFinder(), findsOneWidget);
    expect(find.text('THIS MACHINE'), findsNothing);
    expect(find.text('Fits'), findsNothing);
    expect(find.text('Tight'), findsNothing);
    expect(find.text("Won't fit"), findsNothing);
  });

  testWidgets('Re-detect invalidates both the edge catalog and local-model discovery',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(820, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var edgeFetches = 0, localFetches = 0;
    await tester.pumpWidget(_wrap(
      edgeCatalog: EdgeModelCatalog.fromJson(_edgeJson(ollamaVersion: null)),
      deviceRamMb: 16384,
      onEdgeFetch: () => edgeFetches++,
      onLocalFetch: () => localFetches++,
    ));
    await tester.pumpAndSettle();
    // FutureProviders are lazy and SettingsBody takes plain params (the live watchers sit in
    // SettingsSurface, not pumped here) — hold a subscription so invalidate actually refetches.
    final container = ProviderScope.containerOf(tester.element(find.byType(SettingsBody)));
    final sub1 = container.listen(edgeModelCatalogProvider, (_, _) {});
    final sub2 = container.listen(localModelsProvider, (_, _) {});
    addTearDown(sub1.close);
    addTearDown(sub2.close);
    await tester.pumpAndSettle();
    final before = (edgeFetches, localFetches);
    expect(before.$1, greaterThan(0)); // the subscription itself fetched once
    await tester.tap(find.text('Re-detect'));
    await tester.pumpAndSettle();
    expect(edgeFetches, before.$1 + 1, reason: 'Re-detect must refetch the edge catalog');
    expect(localFetches, before.$2 + 1, reason: 'Re-detect must refetch discovery');
  });

  testWidgets('SCOPE WALL holds across every P5.2 pull state (incl. the confirm strip)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(820, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final pullStates = <String, Map<String, dynamic>>{
      'pulling': {'tag': 'qwen3.5:2b', 'status': 'pulling', 'total': 100, 'completed': 40},
      'error': {'tag': 'qwen3.5:2b', 'status': 'error', 'error': 'boom'},
      'drift-success': {'tag': 'qwen3.5:2b', 'status': 'success', 'drift': true},
      'cancelled': {'tag': 'qwen3.5:2b', 'status': 'cancelled'},
    };
    for (final entry in pullStates.entries) {
      // ProviderScope overrides are fixed per element — dispose the tree between pumps or the
      // FIRST _FixturePulls silently sticks and the loop stops exercising the states.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_wrap(
        edgeCatalog: EdgeModelCatalog.fromJson(_edgeJson(ollamaVersion: '0.32.0')),
        deviceRamMb: 16384,
        pulls: {'qwen3.5:2b': PullSnapshot.fromJson(entry.value)},
      ));
      await tester.pumpAndSettle();
      final board = _boardFinder();
      expect(board, findsOneWidget, reason: 'state ${entry.key} must render the board');
      expect(find.descendant(of: board, matching: find.byType(EditableText)), findsNothing,
          reason: 'no text input may ride in with pull state ${entry.key}');
      // P5.3a: the preset rows are a SECOND pull surface (they embed the same affordance for a
      // tier default) — the scope wall must hold there too, in every pull state.
      final presetRows =
          find.byWidgetPredicate((w) => w.runtimeType.toString() == '_TierPresetRow');
      expect(presetRows, findsWidgets, reason: 'the preset rows must render (state ${entry.key})');
      expect(find.descendant(of: presetRows, matching: find.byType(EditableText)), findsNothing,
          reason: 'no text input may ride in a preset row (state ${entry.key})');
    }
    // And the Won't-fit confirm strip (a tapped-into state, not a snapshot state):
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_wrap(
      edgeCatalog: EdgeModelCatalog.fromJson(_edgeJson(ollamaVersion: '0.32.0')),
      deviceRamMb: 4096, // the lite fixture model badges Won't fit on a tiny device
    ));
    await tester.pumpAndSettle();
    // P5.3a made 'Pull · ' ambiguous (preset rows carry the affordance too) — any Won't-fit
    // button opens the strip; take the first.
    await tester.tap(find.textContaining('Pull · ').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('May not run on this machine'), findsOneWidget);
    expect(find.descendant(of: _boardFinder(), matching: find.byType(EditableText)), findsNothing,
        reason: 'the confirm strip must not introduce a text input');
  });
}
