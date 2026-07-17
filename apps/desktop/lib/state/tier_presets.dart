/// P5.3a — the "Free local team" tier presets: one per catalog tier (Lite / Core / Max — the A5
/// naming, same triple as the Draft Board), each pinning the tier's DEFAULT curated model across all
/// 12 Dream Team roles ("one download serves analysts + debaters" — plan-locked).
///
/// Presets are SYNTHESIZED from the served catalog at render time and never persisted: they never
/// enter `SettingsState.benches` / settings.json, so save/delete/rename only ever see user Benches
/// and no name-collision or deletion semantics exist to design. Applying one goes through
/// [SettingsController.applyTierPreset] — NOT `applyBench`, whose copyWith merge would keep a stale
/// `backendUrl`/effort (the engine applies a global backend_url to ollama roles when the global
/// provider is ollama, so a stale URL poisons the whole all-local run).
library;

import 'package:quorum_core/quorum_core.dart';

import '../dream_team_roster.dart' show dreamTeamRoleKeys;

class TierPreset {
  final DeviceTier tier;

  /// 'Free local team — Core' (the A5 tier triple; "Pro" is banned for this feature).
  final String name;

  /// The tier's curated default entry — the one model every role runs on.
  final EdgeModel model;

  /// All 12 roles pinned to `{provider: ollama, model: [model].ollamaTag}`.
  final Map<String, AgentModel> agentModels;

  const TierPreset({
    required this.tier,
    required this.name,
    required this.model,
    required this.agentModels,
  });
}

String _tierLabel(DeviceTier t) => switch (t) {
      DeviceTier.lite => 'Lite',
      DeviceTier.core => 'Core',
      DeviceTier.max => 'Max',
    };

/// The presets the served catalog defines: one per recognized tier that carries a usable default
/// (a tier with no default, or a default with no tag, contributes nothing — never fabricate a
/// preset the catalog doesn't back).
List<TierPreset> buildTierPresets(EdgeModelCatalog catalog) {
  final out = <TierPreset>[];
  for (final tier in catalog.tiers) {
    final t = tier.tier;
    final m = tier.defaultModel;
    if (t == null || m == null || m.ollamaTag.isEmpty) continue;
    out.add(TierPreset(
      tier: t,
      name: 'Free local team — ${_tierLabel(t)}',
      model: m,
      agentModels: {
        for (final role in dreamTeamRoleKeys)
          role: AgentModel(provider: 'ollama', model: m.ollamaTag),
      },
    ));
  }
  return out;
}
