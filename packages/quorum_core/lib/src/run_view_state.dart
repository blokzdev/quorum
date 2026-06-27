/// The single immutable view-state a run reduces to. The UI renders narrow slices of this; the
/// reducer (see reducer.dart) is the only thing that produces new instances.
library;

import 'events.dart';

enum RunPhase { idle, running, done, cancelled, error }

enum NodeStatus { pending, running, done, error }

class ReportSection {
  final String section;
  final String markdown;
  final Map<String, dynamic>? structured;
  const ReportSection(this.section, this.markdown, this.structured);
}

class CostSnapshot {
  final int llmCalls, toolCalls, tokensIn, tokensOut;
  final double? estUsd;
  const CostSnapshot({
    this.llmCalls = 0, this.toolCalls = 0, this.tokensIn = 0, this.tokensOut = 0, this.estUsd,
  });
}

class Verdict {
  final String finalDecision;
  final String? rating, thesis;
  final double? confidence;
  final Map<String, dynamic>? structured;
  final bool cancelled;
  const Verdict({
    required this.finalDecision, this.rating, this.confidence, this.thesis, this.structured,
    this.cancelled = false,
  });

  // Convenience accessors for the verdict rail (present when the PM emitted them).
  double? get priceTarget => (structured?['price_target'] as num?)?.toDouble();
  double? get entryPrice => (structured?['entry_price'] as num?)?.toDouble();
  double? get stopLoss => (structured?['stop_loss'] as num?)?.toDouble();
  String? get timeHorizon => structured?['time_horizon'] as String?;
}

class RunViewState {
  final String? runId;
  final String? ticker;
  final String? tradeDate;
  final RunPhase phase;
  final Map<Stage, NodeStatus> stages;
  final Map<AgentId, NodeStatus> agents;

  /// Accumulated reasoning per agent (keyed by the wire agent id, e.g. "market"). The UI may also
  /// keep an out-of-state token buffer for jank-free streaming; this is the durable accumulation.
  final Map<String, String> reasoningByAgent;

  /// Finished report sections keyed by wire section name (e.g. "final_trade_decision").
  final Map<String, ReportSection> reports;

  final CostSnapshot? cost;
  final Verdict? verdict;
  final String? error;
  final int lastSeq;

  /// Epoch seconds when the run started — seeded optimistically by the client, then overwritten by
  /// the authoritative RunStarted.ts. Drives the header's elapsed timer; null until a run starts.
  final double? startedAtTs;

  const RunViewState({
    this.runId,
    this.ticker,
    this.tradeDate,
    this.phase = RunPhase.idle,
    this.stages = const {},
    this.agents = const {},
    this.reasoningByAgent = const {},
    this.reports = const {},
    this.cost,
    this.verdict,
    this.error,
    this.lastSeq = -1,
    this.startedAtTs,
  });

  factory RunViewState.initial() => const RunViewState();

  bool get isTerminal =>
      phase == RunPhase.done || phase == RunPhase.cancelled || phase == RunPhase.error;

  RunViewState copyWith({
    String? runId,
    String? ticker,
    String? tradeDate,
    RunPhase? phase,
    Map<Stage, NodeStatus>? stages,
    Map<AgentId, NodeStatus>? agents,
    Map<String, String>? reasoningByAgent,
    Map<String, ReportSection>? reports,
    CostSnapshot? cost,
    Verdict? verdict,
    String? error,
    int? lastSeq,
    double? startedAtTs,
  }) {
    return RunViewState(
      runId: runId ?? this.runId,
      ticker: ticker ?? this.ticker,
      tradeDate: tradeDate ?? this.tradeDate,
      phase: phase ?? this.phase,
      stages: stages ?? this.stages,
      agents: agents ?? this.agents,
      reasoningByAgent: reasoningByAgent ?? this.reasoningByAgent,
      reports: reports ?? this.reports,
      cost: cost ?? this.cost,
      verdict: verdict ?? this.verdict,
      error: error ?? this.error,
      lastSeq: lastSeq ?? this.lastSeq,
      startedAtTs: startedAtTs ?? this.startedAtTs,
    );
  }
}
