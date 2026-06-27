/// A persisted run's summary — the typed view of one `run.json` manifest the engine writes on
/// completion (see `services/api/jobs.py`). The Hub lists these and reads the verdict/cost off them
/// without re-running; the full drill-down reports come separately from `GET /runs/{id}/reports`.
///
/// Pure Dart (no Flutter), so the desktop and a future mobile client share it. Tolerant of missing
/// keys so a manifest-shape bump never hard-fails the client.
library;

import 'agent_model.dart';
import 'run_view_state.dart';

class RunSummary {
  final String runId;

  /// `done` | `cancelled` | `error` (terminal — only finished runs get a manifest).
  final String status;

  /// `demo` | `pro` | `vibe`. Demo runs are synthetic; the Track Record scorecard excludes them.
  final String mode;
  final String ticker;
  final String? tradeDate;
  final String? assetType;

  /// ISO-8601 timestamps the manifest stamps (run creation / completion).
  final String? createdAt;
  final String? finishedAt;

  final String? provider;
  final String? deepModel;
  final String? quickModel;
  final int? researchDepth;
  final String? reportPath;

  final Verdict? verdict;
  final CostSnapshot? cost;
  final String? error;

  /// "Dream Team" provenance: the **resolved** model that actually played each role (role_key ->
  /// AgentModel), for the Hub "cast list". Null on a plain quick/deep run (and on pre-P2.5 manifests).
  final Map<String, AgentModel>? agentModels;

  const RunSummary({
    required this.runId,
    required this.status,
    required this.mode,
    required this.ticker,
    this.tradeDate,
    this.assetType,
    this.createdAt,
    this.finishedAt,
    this.provider,
    this.deepModel,
    this.quickModel,
    this.researchDepth,
    this.reportPath,
    this.verdict,
    this.cost,
    this.error,
    this.agentModels,
  });

  factory RunSummary.fromJson(Map<String, dynamic> j) {
    final v = j['verdict'];
    final c = j['cost'];
    return RunSummary(
      runId: j['run_id'] as String? ?? '',
      status: j['status'] as String? ?? 'done',
      mode: j['mode'] as String? ?? 'vibe',
      ticker: j['ticker'] as String? ?? '',
      tradeDate: j['trade_date'] as String?,
      assetType: j['asset_type'] as String?,
      createdAt: j['created_at'] as String?,
      finishedAt: j['finished_at'] as String?,
      provider: j['provider'] as String?,
      deepModel: j['deep_model'] as String?,
      quickModel: j['quick_model'] as String?,
      researchDepth: (j['research_depth'] as num?)?.toInt(),
      reportPath: j['report_path'] as String?,
      verdict: v is Map ? Verdict.fromJson(v.cast<String, dynamic>()) : null,
      cost: c is Map ? CostSnapshot.fromJson(c.cast<String, dynamic>()) : null,
      error: j['error'] as String?,
      agentModels: agentModelsFromJson(j['agent_models']),
    );
  }

  /// The BUY/HOLD/SELL-family rating, if the run produced a verdict.
  String? get rating => verdict?.rating;

  bool get isDemo => mode == 'demo';

  /// Map the persisted terminal status onto the view-state phase the Hub / cached review renders.
  RunPhase get phase => switch (status) {
        'done' => RunPhase.done,
        'cancelled' => RunPhase.cancelled,
        'error' => RunPhase.error,
        _ => RunPhase.idle,
      };
}
