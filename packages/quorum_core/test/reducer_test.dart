import 'dart:convert';
import 'dart:io';

import 'package:quorum_core/quorum_core.dart';
import 'package:test/test.dart';

QuorumEvent _ev(Map<String, dynamic> envelope) =>
    QuorumEvent.fromEnvelope(envelope);

void main() {
  group('reduce()', () {
    test('replays the recorded demo run to a Buy verdict with all 5 stages done', () {
      final lines = File('test/fixtures/demo_run.jsonl')
          .readAsLinesSync()
          .where((l) => l.trim().isNotEmpty);

      var s = RunViewState.initial();
      for (final line in lines) {
        s = reduce(s, QuorumEvent.fromEnvelope(jsonDecode(line) as Map<String, dynamic>));
      }

      expect(s.phase, RunPhase.done);
      expect(s.ticker, 'NVDA');
      expect(s.verdict?.rating, 'Buy');
      expect(s.verdict?.priceTarget, 152.0);
      expect(s.verdict?.cancelled, isFalse);

      for (final stage in const [
        Stage.analysts, Stage.researchDebate, Stage.trader, Stage.riskDebate, Stage.portfolio,
      ]) {
        expect(s.stages[stage], NodeStatus.done, reason: '$stage should be done');
      }
      expect(s.agents[AgentId.portfolio], NodeStatus.done);
      expect(s.reports.containsKey('final_trade_decision'), isTrue);
      expect(s.reports['final_trade_decision']!.markdown, startsWith('BUY'));
      // Sequence numbers were monotonic and fully consumed.
      expect(s.lastSeq, greaterThan(0));
    });

    test('accumulates token deltas per agent', () {
      var s = RunViewState.initial();
      s = reduce(s, _ev({'seq': 0, 'run_id': 'r', 'ts': 0, 'type': 'token', 'data': {'agent': 'market', 'delta': 'Hello '}}));
      s = reduce(s, _ev({'seq': 1, 'run_id': 'r', 'ts': 0, 'type': 'token', 'data': {'agent': 'market', 'delta': 'world'}}));
      expect(s.reasoningByAgent['market'], 'Hello world');
    });

    test('debate_turn events fold into an ordered turn thread (P3.3a)', () {
      var s = RunViewState.initial();
      final turns = [
        {'round': 1, 'side': 'bull', 'markdown': 'bull r1'},
        {'round': 1, 'side': 'bear', 'markdown': 'bear r1'},
        {'round': 2, 'side': 'bull', 'markdown': 'bull r2'},
        {'round': 2, 'side': 'bear', 'markdown': 'bear r2'},
      ];
      for (var i = 0; i < turns.length; i++) {
        s = reduce(s, _ev({'seq': i, 'run_id': 'r', 'ts': 0, 'type': 'debate_turn', 'data': turns[i]}));
      }
      expect(s.debateTurns.length, 4);
      expect(s.debateTurns.map((t) => t.side).toList(), ['bull', 'bear', 'bull', 'bear']);
      expect(s.debateTurns.map((t) => t.round).toList(), [1, 1, 2, 2]);
      expect(s.debateTurns.first.markdown, 'bull r1');
      expect(s.debateTurns.last.markdown, 'bear r2'); // arrival order preserved
    });

    test('agent_done no longer carries a (dead) confidence field — parses cleanly without it', () {
      final e = _ev({'seq': 0, 'run_id': 'r', 'ts': 0, 'type': 'agent_done', 'data': {'agent': 'bull'}});
      expect(e, isA<AgentDone>());
      final s = reduce(RunViewState.initial(), e);
      expect(s.agents[AgentId.bull], NodeStatus.done);
    });

    test('is idempotent by seq (a re-delivered event is a no-op)', () {
      final e = _ev({'seq': 0, 'run_id': 'r', 'ts': 0, 'type': 'token', 'data': {'agent': 'bull', 'delta': 'x'}});
      var s = reduce(RunViewState.initial(), e);
      s = reduce(s, e); // same seq again
      expect(s.reasoningByAgent['bull'], 'x'); // not doubled
      expect(s.lastSeq, 0);
    });

    test('run_done with cancelled=true yields the cancelled phase', () {
      final e = _ev({'seq': 9, 'run_id': 'r', 'ts': 0, 'type': 'run_done',
        'data': {'final_decision': 'Run cancelled.', 'rating': null, 'cancelled': true}});
      final s = reduce(RunViewState.initial(), e);
      expect(s.phase, RunPhase.cancelled);
      expect(s.verdict?.rating, isNull);
    });

    test('an error event sets the error phase + message', () {
      final e = _ev({'seq': 3, 'run_id': 'r', 'ts': 0, 'type': 'error',
        'data': {'where': 'graph.stream', 'message': 'boom'}});
      final s = reduce(RunViewState.initial(), e);
      expect(s.phase, RunPhase.error);
      expect(s.error, 'boom');
    });
  });

  group('QuorumEvent.fromEnvelope()', () {
    test('maps an unknown type to UnknownEvent (forward-compatible)', () {
      final e = _ev({'seq': 1, 'run_id': 'r', 'ts': 0, 'type': 'future_event', 'data': {'x': 1}});
      expect(e, isA<UnknownEvent>());
      expect((e as UnknownEvent).type, 'future_event');
    });

    test('parses report_section_done with structured JSON', () {
      final e = _ev({'seq': 2, 'run_id': 'r', 'ts': 0, 'type': 'report_section_done',
        'data': {'section': 'final_trade_decision', 'markdown': 'BUY NVDA', 'structured': {'rating': 'Buy'}}});
      expect(e, isA<ReportSectionDone>());
      final r = e as ReportSectionDone;
      expect(r.section, 'final_trade_decision');
      expect(r.structured?['rating'], 'Buy');
    });

    test('maps wire stage/agent strings to enums', () {
      expect(stageFromWire('research_debate'), Stage.researchDebate);
      expect(stageFromWire('???'), Stage.unknown);
      expect(agentFromWire('research_manager'), AgentId.researchManager);
      expect(agentFromWire('???'), AgentId.unknown);
    });
  });
}
