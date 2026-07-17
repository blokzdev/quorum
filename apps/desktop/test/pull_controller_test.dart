// P5.2b — PullController: snapshot folding, the success-invalidation seam (P5.2c: a finished pull
// reaches the UI through the REAL discovery path), honest error snapshots on failed starts, and
// the one-active-pull V1 policy bit.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quorum/state/catalog_provider.dart';
import 'package:quorum/state/pull_controller.dart';
import 'package:quorum/state/run_controller.dart' show httpClientProvider;
import 'package:quorum_core/quorum_core.dart';

EdgeModel _entry(String tag) =>
    EdgeModel.fromJson({'ollama_tag': tag, 'bytes': 1000, 'capability': 'analyst'});

/// Answers POST /pulls with a snapshot, streams /pulls/events from a canned body, 200s cancel.
class _FakeApi extends http.BaseClient {
  final Map<String, dynamic> startResponse;
  final String sseBody;
  final requests = <http.BaseRequest>[];
  _FakeApi({required this.startResponse, this.sseBody = ''});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final path = request.url.path;
    if (path == '/pulls/events') {
      return http.StreamedResponse(Stream.value(utf8.encode(sseBody)), 200);
    }
    if (path == '/pulls' && request.method == 'POST') {
      return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode(startResponse))), 202);
    }
    return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
  }
}

ProviderContainer _container(http.Client client) {
  // retry: null -> a failing provider REJECTS instead of hanging .future across Riverpod 3's
  // default exponential-backoff retries (which turned the sidecar-down test into a 30s timeout).
  return ProviderContainer(retry: (_, _) => null, overrides: [
    engineConnectionProvider.overrideWith(
        (ref) async => EngineConnection(Uri.parse('http://127.0.0.1:1'), 't')),
    httpClientProvider.overrideWithValue(client),
  ]);
}

void main() {
  test('start() seeds state from the POST response and the stream keeps folding', () async {
    final api = _FakeApi(
      startResponse: {'tag': 'qwen3.5:2b', 'status': 'pulling', 'total': 1000, 'completed': 0},
      sseBody: 'data: {"tag":"qwen3.5:2b","status":"pulling","total":1000,"completed":500}\n\n'
          'data: {"tag":"qwen3.5:2b","status":"verifying","total":1000,"completed":1000}\n\n',
    );
    final c = _container(api);
    addTearDown(c.dispose);
    final ctrl = c.read(pullControllerProvider.notifier);
    await ctrl.start(_entry('qwen3.5:2b'));
    await Future<void>.delayed(const Duration(milliseconds: 50)); // let the stream fold
    final snap = c.read(pullControllerProvider)['qwen3.5:2b']!;
    expect(snap.phase, PullPhase.verifying); // the LAST snapshot won (idempotent latest-wins)
    expect(snap.completed, 1000);
    expect(ctrl.anyActive, isTrue);
  });

  test('a success snapshot invalidates discovery + the edge catalog (the real P5.2c seam)',
      () async {
    final api = _FakeApi(
      startResponse: {'tag': 'qwen3.5:2b', 'status': 'pulling'},
      sseBody: 'data: {"tag":"qwen3.5:2b","status":"success","total":10,"completed":10}\n\n',
    );
    var localFetches = 0, edgeFetches = 0;
    final c = ProviderContainer(retry: (_, _) => null, overrides: [
      engineConnectionProvider.overrideWith(
          (ref) async => EngineConnection(Uri.parse('http://127.0.0.1:1'), 't')),
      httpClientProvider.overrideWithValue(api),
      localModelsProvider.overrideWith((ref) async {
        localFetches++;
        return const <LocalModel>[];
      }),
      edgeModelCatalogProvider.overrideWith((ref) async {
        edgeFetches++;
        return const EdgeModelCatalog();
      }),
    ]);
    addTearDown(c.dispose);
    // Hold live subscriptions so invalidation actually refetches (the draft_board_test pattern).
    final s1 = c.listen(localModelsProvider, (_, _) {});
    final s2 = c.listen(edgeModelCatalogProvider, (_, _) {});
    addTearDown(s1.close);
    addTearDown(s2.close);
    await c.read(localModelsProvider.future);
    await c.read(edgeModelCatalogProvider.future);
    final before = (localFetches, edgeFetches);

    await c.read(pullControllerProvider.notifier).start(_entry('qwen3.5:2b'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.read(pullControllerProvider)['qwen3.5:2b']!.phase, PullPhase.success);
    expect(localFetches, before.$1 + 1, reason: 'success must refresh discovery');
    expect(edgeFetches, before.$2 + 1, reason: 'success must refresh the board');
  });

  test('a failed start surfaces an honest error snapshot (not a silent no-op)', () async {
    final c = ProviderContainer(retry: (_, _) => null, overrides: [
      engineConnectionProvider.overrideWith((ref) async => throw Exception('sidecar down')),
      httpClientProvider.overrideWithValue(http.Client()),
    ]);
    addTearDown(c.dispose);
    await c.read(pullControllerProvider.notifier).start(_entry('qwen3.5:2b'));
    final snap = c.read(pullControllerProvider)['qwen3.5:2b']!;
    expect(snap.phase, PullPhase.error);
    expect(snap.error, contains('sidecar down'));
  });

  test('cancel posts to /pulls/cancel with the tag in the body', () async {
    final api = _FakeApi(startResponse: const {'tag': 'x', 'status': 'pulling'});
    final c = _container(api);
    addTearDown(c.dispose);
    await c.read(pullControllerProvider.notifier).cancel('openbmb/minicpm5:q4_K_M');
    final cancelReq = api.requests.lastWhere((r) => r.url.path == '/pulls/cancel');
    expect(cancelReq.method, 'POST');
    expect(jsonDecode((cancelReq as http.Request).body)['tag'], 'openbmb/minicpm5:q4_K_M');
  });
}
