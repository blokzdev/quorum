/// A single per-agent-role model assignment for "Dream Team" (P2.5) — the model (and provider) the
/// user pinned to one role. Pure Dart; mirrors the per-role object on the `agent_models` wire map
/// (`{role_key: {provider, model, backend_url?, effort?}}`) the engine resolves per role.
library;

class AgentModel {
  final String provider;
  final String model;

  /// Per-role OpenAI-compatible base URL (e.g. a role pinned to a local Ollama). Falls back to the
  /// run's global `backend_url` only when this role shares the global provider (handled engine-side).
  final String? backendUrl;

  /// Per-role effort/thinking value, routed to the role's provider knob at launch. Usually null in
  /// V1 (effort is driven by the per-provider global knobs); kept for forward-compat.
  final String? effort;

  const AgentModel({required this.provider, required this.model, this.backendUrl, this.effort});

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'model': model,
        if (backendUrl != null) 'backend_url': backendUrl,
        if (effort != null) 'effort': effort,
      };

  factory AgentModel.fromJson(Map<String, dynamic> j) => AgentModel(
        provider: j['provider'] as String? ?? '',
        model: j['model'] as String? ?? '',
        backendUrl: j['backend_url'] as String?,
        effort: j['effort'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is AgentModel &&
      other.provider == provider &&
      other.model == model &&
      other.backendUrl == backendUrl &&
      other.effort == effort;

  @override
  int get hashCode => Object.hash(provider, model, backendUrl, effort);
}

/// Encode a per-role assignment map (`role_key -> AgentModel`) to the wire object. Null/empty → null,
/// so an unused Dream Team config is simply omitted (additive).
Map<String, dynamic>? agentModelsToJson(Map<String, AgentModel>? m) =>
    (m == null || m.isEmpty) ? null : m.map((k, v) => MapEntry(k, v.toJson()));

/// Parse a per-role assignment map from JSON (manifest provenance or a saved config). Tolerant: a
/// missing/empty value → null so old payloads read as a plain quick/deep run.
Map<String, AgentModel>? agentModelsFromJson(dynamic raw) {
  if (raw is! Map || raw.isEmpty) return null;
  return raw.map(
    (k, v) => MapEntry(k as String, AgentModel.fromJson((v as Map).cast<String, dynamic>())),
  );
}
