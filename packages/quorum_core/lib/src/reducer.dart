/// The pure, synchronous reducer: `reduce(state, event) -> state`.
///
/// Idempotent by `seq` (a re-delivered event is a no-op) as belt-and-suspenders; the server's SSE
/// resume is already exclusive (`start_seq = last_event_id + 1`). Exhaustive over the sealed
/// [QuorumEvent] union, so adding an event type is a compile error until handled here.
library;

import 'events.dart';
import 'run_view_state.dart';

RunViewState reduce(RunViewState s, QuorumEvent e) {
  if (e.seq >= 0 && e.seq <= s.lastSeq) return s; // already applied
  final base = e.seq >= 0 ? s.copyWith(lastSeq: e.seq) : s;

  switch (e) {
    case RunStarted():
      return base.copyWith(
        runId: e.runId, ticker: e.ticker, tradeDate: e.tradeDate, phase: RunPhase.running);
    case StageStarted():
      return base.copyWith(stages: {...s.stages, e.stage: NodeStatus.running});
    case StageDone():
      return base.copyWith(stages: {...s.stages, e.stage: NodeStatus.done});
    case AgentStarted():
      return base.copyWith(agents: {...s.agents, e.agent: NodeStatus.running});
    case AgentDone():
      return base.copyWith(agents: {...s.agents, e.agent: NodeStatus.done});
    case TokenDelta():
      return base.copyWith(reasoningByAgent: {
        ...s.reasoningByAgent,
        e.agent: (s.reasoningByAgent[e.agent] ?? '') + e.delta,
      });
    case ToolCall():
      return base; // tool calls are streamed to the UI live; not part of durable state yet
    case ReportSectionDone():
      return base.copyWith(reports: {
        ...s.reports,
        e.section: ReportSection(e.section, e.markdown, e.structured),
      });
    case CostEvent():
      return base.copyWith(cost: CostSnapshot(
        llmCalls: e.llmCalls, toolCalls: e.toolCalls,
        tokensIn: e.tokensIn, tokensOut: e.tokensOut, estUsd: e.estUsd));
    case RunDone():
      return base.copyWith(
        phase: e.cancelled ? RunPhase.cancelled : RunPhase.done,
        verdict: Verdict(
          finalDecision: e.finalDecision, rating: e.rating, confidence: e.confidence,
          thesis: e.thesis, structured: e.structured, cancelled: e.cancelled),
      );
    case ErrorEvent():
      return base.copyWith(phase: RunPhase.error, error: e.message);
    case Heartbeat():
      return base;
    case UnknownEvent():
      return base; // forward-compatible: ignore unrecognized event types
  }
}
