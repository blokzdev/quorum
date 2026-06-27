/// Immutable run request for the Quorum engine — the typed value-object behind `POST /runs`.
///
/// Mirrors `services/api/app.py` `RunRequest` field-for-field. Pure Dart (no Flutter), so the
/// desktop app and a future mobile client share it. [toJson] is the exact wire body.
library;

class RunConfig {
  /// `demo` | `pro` | `vibe`. ALWAYS serialized: the sidecar defaults `mode` to `vibe`, so omitting
  /// it would silently turn a demo into a real (cost-incurring) run.
  final String mode;
  final String? intent;
  final String? ticker;
  final String? tradeDate;
  final String? assetType;
  final List<String>? analysts;

  /// Always serialized (server-safe default); keeps the body explicit.
  final int researchDepth;
  final String? provider;
  final String? deepModel;
  final String? quickModel;
  final String? backendUrl;

  /// Always serialized (server-safe default).
  final String outputLanguage;

  /// BYO provider keys ({provider: key}); request-scoped, never persisted server-side.
  final Map<String, String>? apiKeys;

  /// Demo-only per-step delay (seconds). Omitted for real runs.
  final double? stepDelay;

  // P2.5 "Dream Team" seam (per-agent model assignment) — additive, not yet wired:
  // final Map<String, String>? agentModels;

  const RunConfig({
    this.mode = 'demo',
    this.intent,
    this.ticker,
    this.tradeDate,
    this.assetType,
    this.analysts,
    this.researchDepth = 1,
    this.provider,
    this.deepModel,
    this.quickModel,
    this.backendUrl,
    this.outputLanguage = 'English',
    this.apiKeys,
    this.stepDelay,
    // this.agentModels,
  });

  /// The exact `POST /runs` body. `mode` / `research_depth` / `output_language` are always present
  /// (safe server defaults, but explicit); every other field is emitted only when non-null, under the
  /// snake_case keys the sidecar `RunRequest` expects.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'mode': mode,
      'research_depth': researchDepth,
      'output_language': outputLanguage,
    };
    if (intent != null) json['intent'] = intent;
    if (ticker != null) json['ticker'] = ticker;
    if (tradeDate != null) json['trade_date'] = tradeDate;
    if (assetType != null) json['asset_type'] = assetType;
    if (analysts != null) json['analysts'] = analysts;
    if (provider != null) json['provider'] = provider;
    if (deepModel != null) json['deep_model'] = deepModel;
    if (quickModel != null) json['quick_model'] = quickModel;
    if (backendUrl != null) json['backend_url'] = backendUrl;
    if (apiKeys != null) json['api_keys'] = apiKeys;
    if (stepDelay != null) json['step_delay'] = stepDelay;
    // if (agentModels != null) json['agent_models'] = agentModels;
    return json;
  }

  RunConfig copyWith({
    String? mode,
    String? intent,
    String? ticker,
    String? tradeDate,
    String? assetType,
    List<String>? analysts,
    int? researchDepth,
    String? provider,
    String? deepModel,
    String? quickModel,
    String? backendUrl,
    String? outputLanguage,
    Map<String, String>? apiKeys,
    double? stepDelay,
  }) {
    return RunConfig(
      mode: mode ?? this.mode,
      intent: intent ?? this.intent,
      ticker: ticker ?? this.ticker,
      tradeDate: tradeDate ?? this.tradeDate,
      assetType: assetType ?? this.assetType,
      analysts: analysts ?? this.analysts,
      researchDepth: researchDepth ?? this.researchDepth,
      provider: provider ?? this.provider,
      deepModel: deepModel ?? this.deepModel,
      quickModel: quickModel ?? this.quickModel,
      backendUrl: backendUrl ?? this.backendUrl,
      outputLanguage: outputLanguage ?? this.outputLanguage,
      apiKeys: apiKeys ?? this.apiKeys,
      stepDelay: stepDelay ?? this.stepDelay,
    );
  }
}
