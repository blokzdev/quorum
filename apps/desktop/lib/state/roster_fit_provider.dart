/// P5.3b — the reactive roster-fit verdict: "can this machine run my whole Dream Team?" for the
/// CURRENT settings. Pure math lives in quorum_core's `rosterFit` (max-not-sum — Ollama swaps
/// models per-request, so only the largest single model + KV must fit); this provider just feeds it
/// the live inputs, mirroring [capabilityGateProvider]'s shape.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quorum_core/quorum_core.dart';

import '../dream_team_roster.dart' show dreamTeamDeepRoles, dreamTeamRoleKeys;
import 'catalog_provider.dart';
import 'device_ram_provider.dart';
import 'settings_controller.dart';

/// The current roster's fit, or null when nothing can be said (demo mode, or the edge catalog isn't
/// loaded). A result with `distinctLocalModels == 0` means an all-cloud roster — render nothing.
final rosterFitProvider = Provider<RosterFitResult?>((ref) {
  final (demoMode, provider, quickModel, customQuick, deepModel, customDeep, agentModels) =
      ref.watch(settingsControllerProvider.select((s) => (
            s.demoMode,
            s.provider,
            s.quickModel,
            s.customQuickModel,
            s.deepModel,
            s.customDeepModel,
            s.agentModels,
          )));
  if (demoMode) return null; // no engine models run in demo — a fit claim would be noise
  final catalog = ref.watch(edgeModelCatalogProvider).value;
  if (catalog == null || catalog.tiers.isEmpty) return null; // no curated numbers yet
  final localModels = ref.watch(localModelsProvider).value ?? const <LocalModel>[];
  final ramMb = ref.watch(deviceRamMbProvider).value;

  // Resolve the `custom` sentinel exactly as buildLaunchConfig does, so fit reasons about what
  // actually launches (the capability_gate pattern).
  String? resolved(String? selected, String? custom) =>
      selected == 'custom' ? custom?.trim() : selected;

  return rosterFit(
    slots: effectiveSlots(
      roleKeys: dreamTeamRoleKeys,
      deepRoles: dreamTeamDeepRoles,
      agentModels: agentModels,
      globalProvider: provider,
      quickModel: resolved(quickModel, customQuick),
      deepModel: resolved(deepModel, customDeep),
    ),
    catalog: catalog,
    localModels: localModels,
    deviceRamMb: ramMb,
    ctx: catalog.kvCtx, // the served curation ctx wins (the P5.1 kvCtx-consumed rule)
  );
});
