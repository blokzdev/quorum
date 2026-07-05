/// P3.2b launch-time capability backstop — the run-create gate the per-role picker can't be.
///
/// The picker blocks a non-tool model as you *assign* it, but a run's EFFECTIVE tool-analyst model can
/// still be a known-non-tool one via a path the picker never touched: the GLOBAL quick model that runs
/// every unassigned tool role, or a Bench/apply combo loaded straight into state. This re-checks the
/// effective model for each tool role at launch and refuses the run — closing the P2.5c2 backlog item
/// now that discovered local models make the block path live (a plain llama3 8B has no tools).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quorum_core/quorum_core.dart';

import '../dream_team_roster.dart' show dreamTeamRoleLabel, dreamTeamToolRoles;
import 'catalog_provider.dart';
import 'settings_controller.dart';

/// The tool-analyst roles whose EFFECTIVE model is a KNOWN non-tool model (returns role labels for the
/// launch notice). Effective model = the per-role override if assigned, else the global quick model
/// (analysts run on the quick tier). A model we can't classify (`null` = unknown/custom) is NOT a
/// violation — the gate WARNS on unknown, never blocks, so a legitimate custom/local id still launches.
List<String> toolRoleCapabilityViolations({
  required String? provider,
  required String? quickModel,
  required Map<String, AgentModel>? agentModels,
  required Catalog catalog,
  required List<LocalModel> localModels,
}) {
  final out = <String>[];
  for (final role in dreamTeamToolRoles) {
    final assigned = agentModels?[role];
    final isAssigned = assigned != null && assigned.model.trim().isNotEmpty;
    final effProvider = isAssigned ? assigned.provider : provider;
    final effModel = isAssigned ? assigned.model : quickModel;
    // No model resolved (no global quick + no override) → the engine falls back to its own default;
    // nothing for us to classify, so don't gate.
    if (effProvider == null || effModel == null || effModel.trim().isEmpty) continue;
    if (toolCapabilityOf(catalog, effProvider, effModel, localModels) == false) {
      out.add(dreamTeamRoleLabel(role));
    }
  }
  out.sort();
  return out;
}

/// Reactive launch gate: the tool-role labels whose effective model is known-non-tool, or empty. Empty
/// in demo mode (no engine models run) and whenever the catalog can't be resolved (can't classify →
/// don't false-block). Recomputes when the model selection, discovered models, or catalog change.
final capabilityGateProvider = FutureProvider<List<String>>((ref) async {
  final (demoMode, provider, quickModel, customQuickModel, agentModels) = ref.watch(
    settingsControllerProvider.select(
      (s) => (s.demoMode, s.provider, s.quickModel, s.customQuickModel, s.agentModels),
    ),
  );
  if (demoMode) return const [];
  // A `custom` quick selection resolves to the typed id (mirrors buildLaunchConfig); anything else is
  // the option value itself.
  final resolvedQuick = quickModel == 'custom' ? (customQuickModel ?? '') : quickModel;

  final catalog = ref.watch(catalogProvider).value;
  if (catalog == null) return const []; // catalog not ready → can't classify → don't gate
  final localModels = ref.watch(localModelsProvider).value ?? const <LocalModel>[];

  return toolRoleCapabilityViolations(
    provider: provider,
    quickModel: resolvedQuick,
    agentModels: agentModels,
    catalog: catalog,
    localModels: localModels,
  );
});
