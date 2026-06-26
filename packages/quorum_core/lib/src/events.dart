/// The Quorum streaming event contract in Dart — a sealed union mirroring the Python
/// `tradingagents/runtime/events.py` (contract_version 1).
///
/// Hand-written (no codegen) so the reducer gets Dart 3 exhaustive switches with zero build_runner
/// toolchain. `QuorumEvent.fromEnvelope` parses the wire shape `{seq, run_id, ts, type, data}` and
/// is forward-compatible: an unrecognized `type` becomes [UnknownEvent] rather than throwing.
library;

const int contractVersion = 1;

/// The five pipeline phases, in order. [Stage.unknown] guards forward-compat.
enum Stage { analysts, researchDebate, trader, riskDebate, portfolio, unknown }

/// Stable agent identifiers. [AgentId.unknown] guards forward-compat.
enum AgentId {
  market, social, news, fundamentals,
  bull, bear, researchManager, trader,
  aggressive, neutral, conservative, portfolio,
  unknown,
}

Stage stageFromWire(String? s) => switch (s) {
      'analysts' => Stage.analysts,
      'research_debate' => Stage.researchDebate,
      'trader' => Stage.trader,
      'risk_debate' => Stage.riskDebate,
      'portfolio' => Stage.portfolio,
      _ => Stage.unknown,
    };

AgentId agentFromWire(String? s) => switch (s) {
      'market' => AgentId.market,
      'social' => AgentId.social,
      'news' => AgentId.news,
      'fundamentals' => AgentId.fundamentals,
      'bull' => AgentId.bull,
      'bear' => AgentId.bear,
      'research_manager' => AgentId.researchManager,
      'trader' => AgentId.trader,
      'aggressive' => AgentId.aggressive,
      'neutral' => AgentId.neutral,
      'conservative' => AgentId.conservative,
      'portfolio' => AgentId.portfolio,
      _ => AgentId.unknown,
    };

sealed class QuorumEvent {
  final int seq;
  final String? runId;
  final double ts;
  const QuorumEvent({required this.seq, required this.runId, required this.ts});

  /// Parse a wire envelope `{seq, run_id, ts, type, data}` into a typed event.
  static QuorumEvent fromEnvelope(Map<String, dynamic> env) {
    final seq = (env['seq'] as num?)?.toInt() ?? -1;
    final runId = env['run_id'] as String?;
    final ts = (env['ts'] as num?)?.toDouble() ?? 0;
    final data = ((env['data'] as Map?) ?? const {}).cast<String, dynamic>();
    switch (env['type'] as String?) {
      case 'run_started':
        return RunStarted(seq: seq, runId: runId, ts: ts,
            ticker: data['ticker'] as String? ?? '',
            tradeDate: data['trade_date'] as String? ?? '',
            assetType: data['asset_type'] as String? ?? 'stock');
      case 'stage_started':
        return StageStarted(seq: seq, runId: runId, ts: ts, stage: stageFromWire(data['stage'] as String?));
      case 'stage_done':
        return StageDone(seq: seq, runId: runId, ts: ts, stage: stageFromWire(data['stage'] as String?));
      case 'agent_started':
        return AgentStarted(seq: seq, runId: runId, ts: ts, agent: agentFromWire(data['agent'] as String?));
      case 'agent_done':
        return AgentDone(seq: seq, runId: runId, ts: ts,
            agent: agentFromWire(data['agent'] as String?),
            confidence: (data['confidence'] as num?)?.toDouble());
      case 'token':
        return TokenDelta(seq: seq, runId: runId, ts: ts,
            agent: data['agent'] as String? ?? 'system', delta: data['delta'] as String? ?? '');
      case 'tool_call':
        return ToolCall(seq: seq, runId: runId, ts: ts,
            agent: data['agent'] as String? ?? 'system',
            tool: data['tool'] as String? ?? '',
            argsSummary: data['args_summary'] as String? ?? '',
            status: data['status'] as String? ?? '');
      case 'report_section_done':
        return ReportSectionDone(seq: seq, runId: runId, ts: ts,
            section: data['section'] as String? ?? '',
            markdown: data['markdown'] as String? ?? '',
            structured: (data['structured'] as Map?)?.cast<String, dynamic>());
      case 'cost':
        return CostEvent(seq: seq, runId: runId, ts: ts,
            llmCalls: (data['llm_calls'] as num?)?.toInt() ?? 0,
            toolCalls: (data['tool_calls'] as num?)?.toInt() ?? 0,
            tokensIn: (data['tokens_in'] as num?)?.toInt() ?? 0,
            tokensOut: (data['tokens_out'] as num?)?.toInt() ?? 0,
            estUsd: (data['est_usd'] as num?)?.toDouble());
      case 'run_done':
        return RunDone(seq: seq, runId: runId, ts: ts,
            finalDecision: data['final_decision'] as String? ?? '',
            rating: data['rating'] as String?,
            confidence: (data['confidence'] as num?)?.toDouble(),
            thesis: data['thesis'] as String?,
            structured: (data['structured'] as Map?)?.cast<String, dynamic>(),
            cancelled: data['cancelled'] as bool? ?? false);
      case 'error':
        return ErrorEvent(seq: seq, runId: runId, ts: ts,
            where: data['where'] as String? ?? '',
            message: data['message'] as String? ?? '',
            recoverable: data['recoverable'] as bool? ?? false);
      case 'heartbeat':
        return Heartbeat(seq: seq, runId: runId, ts: ts);
      case final t:
        return UnknownEvent(seq: seq, runId: runId, ts: ts, type: t ?? 'unknown', data: data);
    }
  }
}

final class RunStarted extends QuorumEvent {
  final String ticker, tradeDate, assetType;
  const RunStarted({required super.seq, required super.runId, required super.ts,
      required this.ticker, required this.tradeDate, required this.assetType});
}

final class StageStarted extends QuorumEvent {
  final Stage stage;
  const StageStarted({required super.seq, required super.runId, required super.ts, required this.stage});
}

final class StageDone extends QuorumEvent {
  final Stage stage;
  const StageDone({required super.seq, required super.runId, required super.ts, required this.stage});
}

final class AgentStarted extends QuorumEvent {
  final AgentId agent;
  const AgentStarted({required super.seq, required super.runId, required super.ts, required this.agent});
}

final class AgentDone extends QuorumEvent {
  final AgentId agent;
  final double? confidence;
  const AgentDone({required super.seq, required super.runId, required super.ts, required this.agent, this.confidence});
}

final class TokenDelta extends QuorumEvent {
  final String agent;
  final String delta;
  const TokenDelta({required super.seq, required super.runId, required super.ts, required this.agent, required this.delta});
}

final class ToolCall extends QuorumEvent {
  final String agent, tool, argsSummary, status;
  const ToolCall({required super.seq, required super.runId, required super.ts,
      required this.agent, required this.tool, required this.argsSummary, required this.status});
}

final class ReportSectionDone extends QuorumEvent {
  final String section, markdown;
  final Map<String, dynamic>? structured;
  const ReportSectionDone({required super.seq, required super.runId, required super.ts,
      required this.section, required this.markdown, this.structured});
}

final class CostEvent extends QuorumEvent {
  final int llmCalls, toolCalls, tokensIn, tokensOut;
  final double? estUsd;
  const CostEvent({required super.seq, required super.runId, required super.ts,
      required this.llmCalls, required this.toolCalls, required this.tokensIn, required this.tokensOut, this.estUsd});
}

final class RunDone extends QuorumEvent {
  final String finalDecision;
  final String? rating, thesis;
  final double? confidence;
  final Map<String, dynamic>? structured;
  final bool cancelled;
  const RunDone({required super.seq, required super.runId, required super.ts,
      required this.finalDecision, this.rating, this.confidence, this.thesis, this.structured, this.cancelled = false});
}

final class ErrorEvent extends QuorumEvent {
  final String where, message;
  final bool recoverable;
  const ErrorEvent({required super.seq, required super.runId, required super.ts,
      required this.where, required this.message, this.recoverable = false});
}

final class Heartbeat extends QuorumEvent {
  const Heartbeat({required super.seq, required super.runId, required super.ts});
}

final class UnknownEvent extends QuorumEvent {
  final String type;
  final Map<String, dynamic> data;
  const UnknownEvent({required super.seq, required super.runId, required super.ts, required this.type, required this.data});
}
