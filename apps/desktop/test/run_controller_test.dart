import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quorum/state/run_controller.dart';
import 'package:quorum_core/quorum_core.dart';

/// A fake endpoint that "connects" without spawning a process (tests the controller, not the sidecar).
class _FakeEndpoint implements EngineEndpoint {
  bool disposed = false;
  @override
  Future<EngineConnection> connect() async =>
      EngineConnection(Uri.parse('http://127.0.0.1:65000'), 'tok');
  @override
  Future<void> dispose() async => disposed = true;
}

String _frame(Map<String, dynamic> env) => 'data: ${jsonEncode(env)}\n\n';

void main() {
  final demoFrames = [
    _frame({'type': 'run_started', 'seq': 0, 'run_id': 'demo', 'ts': 0, 'data': {'ticker': 'NVDA'}}),
    _frame({'type': 'stage_started', 'seq': 1, 'run_id': 'demo', 'ts': 0, 'data': {'stage': 'analysts'}}),
    _frame({'type': 'agent_started', 'seq': 2, 'run_id': 'demo', 'ts': 0, 'data': {'agent': 'market'}}),
    _frame({'type': 'report_section_done', 'seq': 3, 'run_id': 'demo', 'ts': 0, 'data': {'section': 'market_report', 'markdown': 'MKT'}}),
    _frame({'type': 'agent_done', 'seq': 4, 'run_id': 'demo', 'ts': 0, 'data': {'agent': 'market'}}),
    _frame({'type': 'stage_done', 'seq': 5, 'run_id': 'demo', 'ts': 0, 'data': {'stage': 'analysts'}}),
    _frame({'type': 'run_done', 'seq': 6, 'run_id': 'demo', 'ts': 0, 'data': {'final_decision': 'BUY NVDA', 'rating': 'Buy', 'cancelled': false}}),
  ].join();

  http.Client demoClient() => MockClient.streaming((req, body) async {
        if (req.method == 'POST' && req.url.path == '/runs') {
          return http.StreamedResponse(
              Stream.value(utf8.encode('{"run_id":"demo","status":"queued"}')), 202);
        }
        if (req.url.path == '/runs/demo/events') {
          return http.StreamedResponse(Stream.value(utf8.encode(demoFrames)), 200);
        }
        return http.StreamedResponse(Stream<List<int>>.empty(), 404);
      });

  ProviderContainer container(http.Client client, EngineEndpoint endpoint) {
    final c = ProviderContainer(overrides: [
      engineEndpointProvider.overrideWithValue(endpoint),
      httpClientProvider.overrideWithValue(client),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  Future<void> waitTerminal(ProviderContainer c, {Duration timeout = const Duration(seconds: 2)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (c.read(runControllerProvider).isTerminal) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('start() drives a run to a Buy verdict with stages reduced', () async {
    final c = container(demoClient(), _FakeEndpoint());
    await c.read(runControllerProvider.notifier)
        .start(config: const RunConfig(mode: 'demo', ticker: 'NVDA', stepDelay: 0.2));
    await waitTerminal(c);

    final s = c.read(runControllerProvider);
    expect(s.phase, RunPhase.done);
    expect(s.ticker, 'NVDA');
    expect(s.verdict?.rating, 'Buy');
    expect(s.stages[Stage.analysts], NodeStatus.done);
    expect(s.reports.containsKey('market_report'), isTrue);
  });

  test('double start() is a no-op while one is in flight', () async {
    final c = container(demoClient(), _FakeEndpoint());
    final ctrl = c.read(runControllerProvider.notifier);
    await Future.wait([ctrl.start(), ctrl.start()]); // second is ignored
    await waitTerminal(c);
    expect(c.read(runControllerProvider).phase, RunPhase.done);
  });

  test('a failing engine surfaces an error phase (no spinner hang)', () async {
    final failing = MockClient.streaming(
        (req, body) async => http.StreamedResponse(Stream.value(utf8.encode('nope')), 500));
    final c = container(failing, _FakeEndpoint());
    await c.read(runControllerProvider.notifier).start();
    await waitTerminal(c);
    expect(c.read(runControllerProvider).phase, RunPhase.error);
    expect(c.read(runControllerProvider).error, isNotNull);
  });

  test('shutdown() disposes the endpoint', () async {
    final endpoint = _FakeEndpoint();
    final c = container(demoClient(), endpoint);
    await c.read(runControllerProvider.notifier).shutdown();
    expect(endpoint.disposed, isTrue);
  });
}
