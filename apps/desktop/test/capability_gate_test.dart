import 'package:flutter_test/flutter_test.dart';
import 'package:quorum/state/capability_gate.dart';
import 'package:quorum_core/quorum_core.dart';

/// P3.2b launch backstop: the pure resolver that gates a run whose EFFECTIVE tool-analyst model is a
/// known-non-tool one — the case the per-role picker can't catch (the global quick model on unassigned
/// tool roles, or a bench/apply combo loaded straight into state).
void main() {
  final catalog = Catalog(contractVersion: 1, providers: {
    'anthropic': const ProviderCatalog('anthropic', {
      'quick': [ModelOption('Sonnet', 'claude-sonnet-4-6', toolCapable: true)],
      'deep': [ModelOption('Opus', 'claude-opus-4-8', toolCapable: true)],
    }),
  });
  const discovered = [
    LocalModel('llama3.2:latest', toolCapable: true),
    LocalModel('dolphin-llama3:latest', toolCapable: false), // a plain llama3 8B — no tools
  ];

  List<String> violations({
    String? provider,
    String? quickModel,
    Map<String, AgentModel>? agentModels,
  }) =>
      toolRoleCapabilityViolations(
        provider: provider,
        quickModel: quickModel,
        agentModels: agentModels,
        catalog: catalog,
        localModels: discovered,
      );

  test('a non-tool GLOBAL quick model flags every unassigned tool role', () {
    final v = violations(provider: 'ollama', quickModel: 'dolphin-llama3:latest');
    // All three tool-analyst desks (market/news/fundamentals) run on the global quick model → all flagged.
    expect(v.length, 3);
    expect(v, containsAll(['Market Analyst', 'News Analyst', 'Fundamentals Analyst']));
  });

  test('a tool-capable global quick model → no violations', () {
    expect(violations(provider: 'ollama', quickModel: 'llama3.2:latest'), isEmpty);
    expect(violations(provider: 'anthropic', quickModel: 'claude-sonnet-4-6'), isEmpty);
  });

  test('a per-role tool-capable override RESCUES a role from a non-tool global', () {
    final v = violations(
      provider: 'ollama',
      quickModel: 'dolphin-llama3:latest', // non-tool global
      agentModels: const {
        'market_analyst': AgentModel(provider: 'ollama', model: 'llama3.2:latest'), // tool-capable override
      },
    );
    // Market is rescued; news + fundamentals still fall back to the non-tool global.
    expect(v, isNot(contains('Market Analyst')));
    expect(v, containsAll(['News Analyst', 'Fundamentals Analyst']));
  });

  test('a per-role NON-tool override flags that role even under a tool-capable global', () {
    final v = violations(
      provider: 'ollama',
      quickModel: 'llama3.2:latest', // tool-capable global
      agentModels: const {
        'news_analyst': AgentModel(provider: 'ollama', model: 'dolphin-llama3:latest'),
      },
    );
    expect(v, ['News Analyst']); // only the explicitly-bad role
  });

  test('an unknown/custom effective model is NOT a violation (warn, never block)', () {
    // A custom/undiscovered id classifies as null → the backstop never blocks it.
    expect(violations(provider: 'ollama', quickModel: 'mystery:latest'), isEmpty);
  });

  test('no resolvable model (no global quick, no override) → no gate (engine default runs)', () {
    expect(violations(provider: 'ollama', quickModel: null), isEmpty);
    expect(violations(provider: 'ollama', quickModel: ''), isEmpty);
  });
}
