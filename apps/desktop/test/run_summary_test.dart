import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quorum_core/quorum_core.dart';

void main() {
  test('RunSummary.fromJson parses a manifest (verdict + cost + Track Record fields)', () {
    final s = RunSummary.fromJson({
      'run_id': 'abc123', 'status': 'done', 'mode': 'pro', 'ticker': 'NVDA',
      'trade_date': '2026-05-10', 'asset_type': 'stock',
      'created_at': '2026-05-10T12:00:00', 'finished_at': '2026-05-10T12:03:00',
      'provider': 'anthropic', 'deep_model': 'claude-opus-4-8', 'quick_model': 'claude-sonnet-4-6',
      'research_depth': 2, 'report_path': '/x/NVDA_abc123',
      'verdict': {
        'final_decision': 'BUY NVDA', 'rating': 'Buy', 'confidence': 0.72, 'thesis': 'durable growth',
        'structured': {'entry_price': 124.0, 'price_target': 152.0},
      },
      'cost': {'llm_calls': 14, 'tool_calls': 8, 'tokens_in': 24800, 'tokens_out': 13200, 'est_usd': 0.42},
      'error': null,
    });
    expect(s.runId, 'abc123');
    expect(s.ticker, 'NVDA');
    expect(s.mode, 'pro');
    expect(s.isDemo, false);
    expect(s.phase, RunPhase.done);
    expect(s.tradeDate, '2026-05-10');
    expect(s.rating, 'Buy');
    expect(s.provider, 'anthropic');
    expect(s.deepModel, 'claude-opus-4-8');
    expect(s.researchDepth, 2);
    expect(s.verdict!.confidence, 0.72);
    expect(s.verdict!.entryPrice, 124.0); // Track Record entry-price context
    expect(s.verdict!.priceTarget, 152.0);
    expect(s.cost!.llmCalls, 14);
    expect(s.cost!.estUsd, 0.42);
  });

  test('RunSummary tolerates a minimal/partial manifest', () {
    final s = RunSummary.fromJson(
        {'run_id': 'x', 'ticker': 'AAPL', 'mode': 'demo', 'status': 'cancelled'});
    expect(s.isDemo, true);
    expect(s.phase, RunPhase.cancelled);
    expect(s.verdict, isNull);
    expect(s.cost, isNull);
    expect(s.rating, isNull);
  });

  test('ApiClient.listRuns parses GET /runs into a RunSummary list (order preserved)', () async {
    final client = MockClient((req) async {
      if (req.url.path == '/runs' && req.headers['authorization'] == 'Bearer tok') {
        return http.Response(
            jsonEncode({
              'runs': [
                {'run_id': 'r1', 'ticker': 'NVDA', 'mode': 'pro', 'status': 'done',
                 'verdict': {'final_decision': 'BUY', 'rating': 'Buy'}},
                {'run_id': 'r2', 'ticker': 'TSLA', 'mode': 'demo', 'status': 'done'},
              ]
            }),
            200);
      }
      return http.Response('no', 404);
    });
    final api =
        ApiClient(EngineConnection(Uri.parse('http://127.0.0.1:65000'), 'tok'), client: client);
    final runs = await api.listRuns();
    expect(runs.length, 2);
    expect(runs[0].runId, 'r1');
    expect(runs[0].rating, 'Buy');
    expect(runs[1].ticker, 'TSLA');
    expect(runs[1].isDemo, true);
  });
}
