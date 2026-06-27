import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quorum/dream_team_roster.dart';
import 'package:quorum/state/settings_controller.dart';
import 'package:quorum/ui/brand.dart';
import 'package:quorum/ui/quorum_colors.dart';
import 'package:quorum/ui/settings_surface.dart';
import 'package:quorum_core/quorum_core.dart';

/// Goldens for the Dream Team roster (P2.5c1 exit criterion 1: "renders all 12 with correct fallback
/// chips — all-default + partially-assigned"). The roster is collapsed by default; `forceExpandDreamTeam`
/// is the deterministic test seam that opens it (no tap/animation). Each role row is rendered COLLAPSED
/// (label + chip), so all 12 chips are visible without 12 open pickers — keeping the surface bounded.
// Models flagged tool_capable:true (the real-world default — the engine denylist is empty), so an
// assigned tool role resolves OK (accent chip), keeping these goldens byte-identical to c1.
final _catalog = Catalog(
  contractVersion: 1,
  analysts: const ['market', 'social', 'news', 'fundamentals'],
  providers: {
    'google': const ProviderCatalog('google', {
      'quick': [ModelOption('Gemini 3.5 Flash', 'gemini-3.5-flash', toolCapable: true)],
      'deep': [ModelOption('Gemini 3.1 Pro', 'gemini-3.1-pro-preview', toolCapable: true)],
    }),
    'anthropic': const ProviderCatalog('anthropic', {
      'quick': [ModelOption('Claude Sonnet 4.6', 'claude-sonnet-4-6', toolCapable: true)],
      'deep': [ModelOption('Claude Opus 4.8', 'claude-opus-4-8', toolCapable: true)],
    }),
    'ollama': const ProviderCatalog('ollama', {
      'quick': [ModelOption('Qwen3', 'qwen3:latest', toolCapable: true), ModelOption('Custom model ID', 'custom')],
      'deep': [ModelOption('GLM', 'glm-4.7-flash:latest', toolCapable: true), ModelOption('Custom model ID', 'custom')],
    }),
    // An explicitly non-tool model so the capability golden can show the red/amber chip states.
    'legacy': const ProviderCatalog('legacy', {
      'quick': [ModelOption('NoTool', 'old-x', toolCapable: false)],
      'deep': [ModelOption('NoTool', 'old-x', toolCapable: false)],
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
        // provider:null keeps Model Studio short (no key field / vault) so the focus is the roster.
        home: Scaffold(
          backgroundColor: QC.bg,
          body: SettingsBody(catalog: _catalog, forceExpandDreamTeam: true),
        ),
      ),
    );

void main() {
  testWidgets('dream team — all default (12 muted quick/deep fallback chips)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(820, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(const SettingsState(demoMode: false)));
    await tester.pumpAndSettle();

    // A label/mirror drift fails here as a finder, not just a pixel diff.
    for (final label in dreamTeamRoleLabels.values) {
      expect(find.text(label), findsOneWidget, reason: 'missing role row "$label"');
    }
    // The two judges fall back to DEEP, everyone else to QUICK.
    expect(find.text('Falls back · DEEP'), findsNWidgets(2));
    expect(find.text('Falls back · QUICK'), findsNWidgets(10));

    await expectLater(
        find.byType(SettingsBody), matchesGoldenFile('goldens/dream_team_all_default.png'));
  });

  testWidgets('dream team — partially assigned (solid chips span stages)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(820, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(const SettingsState(
      demoMode: false,
      agentModels: {
        'market_analyst': AgentModel(provider: 'anthropic', model: 'claude-sonnet-4-6'),
        'bull_researcher': AgentModel(provider: 'anthropic', model: 'claude-opus-4-8'),
        'portfolio_manager': AgentModel(provider: 'google', model: 'gemini-3.1-pro-preview'),
      },
    )));
    await tester.pumpAndSettle();

    for (final label in dreamTeamRoleLabels.values) {
      expect(find.text(label), findsOneWidget);
    }
    // 3 assigned (solid provider·model chips), 9 unassigned. portfolio_manager assigned, so the only
    // remaining DEEP-tier fallback chip is research_manager.
    expect(find.text('Anthropic · claude-sonnet-4-6'), findsOneWidget);
    expect(find.text('Anthropic · claude-opus-4-8'), findsOneWidget);
    expect(find.text('Google Gemini · gemini-3.1-pro-preview'), findsOneWidget);
    expect(find.text('Falls back · DEEP'), findsOneWidget); // research_manager only
    expect(find.text('Falls back · QUICK'), findsNWidgets(8));

    await expectLater(
        find.byType(SettingsBody), matchesGoldenFile('goldens/dream_team_partial.png'));
  });

  testWidgets('dream team — capability gate chips (red block / amber degrade)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(820, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(const SettingsState(
      demoMode: false,
      agentModels: {
        // A tool role holding a non-tool model -> RED error chip (the block surfaces even collapsed).
        'fundamentals_analyst': AgentModel(provider: 'legacy', model: 'old-x'),
        // A structured role holding a non-tool model -> AMBER degrade chip.
        'portfolio_manager': AgentModel(provider: 'legacy', model: 'old-x'),
        // A valid assignment -> normal accent chip (contrast).
        'bull_researcher': AgentModel(provider: 'anthropic', model: 'claude-opus-4-8'),
      },
    )));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.error_outline), findsOneWidget); // fundamentals (tool, block)
    expect(find.byIcon(Icons.warning_amber), findsOneWidget); // portfolio (structured, degrade)
    await expectLater(
        find.byType(SettingsBody), matchesGoldenFile('goldens/dream_team_capability.png'));
  });
}
