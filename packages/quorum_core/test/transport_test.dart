import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quorum_core/quorum_core.dart';
import 'package:test/test.dart';

void main() {
  final conn = EngineConnection(Uri.parse('http://127.0.0.1:9999'), 'tok');

  group('ApiClient', () {
    test('createRun posts JSON with bearer and returns run_id', () async {
      final mock = MockClient((req) async {
        expect(req.method, 'POST');
        expect(req.url.path, '/runs');
        expect(req.headers['authorization'], 'Bearer tok');
        expect((jsonDecode(req.body) as Map)['mode'], 'demo');
        return http.Response('{"run_id":"abc123","status":"queued"}', 202);
      });
      final api = ApiClient(conn, client: mock);
      expect(await api.createRun({'mode': 'demo', 'ticker': 'NVDA'}), 'abc123');
    });

    test('createRun throws EngineException on non-202', () async {
      final mock = MockClient((req) async => http.Response('bad', 500));
      expect(() => ApiClient(conn, client: mock).createRun({}), throwsA(isA<EngineException>()));
    });

    test('health() hits the public route without an auth header', () async {
      final mock = MockClient((req) async {
        expect(req.headers.containsKey('authorization'), isFalse);
        return http.Response('{"status":"ok","contract_version":1}', 200);
      });
      expect((await ApiClient(conn, client: mock).health())['status'], 'ok');
    });
  });

  group('SseTransport', () {
    test('parses data frames into typed events and skips heartbeats', () async {
      final frames = [
        'event: run_started',
        'id: 0',
        'data: ${jsonEncode({'type': 'run_started', 'seq': 0, 'run_id': 'r', 'ts': 0, 'data': {'ticker': 'NVDA'}})}',
        '',
        'event: heartbeat',
        'data: {}',
        '',
        'data: ${jsonEncode({'type': 'run_done', 'seq': 1, 'run_id': 'r', 'ts': 0, 'data': {'rating': 'Buy', 'final_decision': 'BUY'}})}',
        '',
      ].join('\n');
      final mock = MockClient.streaming((req, body) async {
        expect(req.headers['authorization'], 'Bearer tok');
        return http.StreamedResponse(Stream.value(utf8.encode(frames)), 200);
      });
      final events = await SseTransport(conn, client: mock).events('r').toList();
      expect(events, hasLength(2));
      expect(events.first, isA<RunStarted>());
      expect(events.last, isA<RunDone>());
      expect((events.last as RunDone).rating, 'Buy');
    });

    test('sends Last-Event-ID when resuming from a seq', () async {
      final mock = MockClient.streaming((req, body) async {
        expect(req.headers['last-event-id'], '5');
        return http.StreamedResponse(Stream<List<int>>.empty(), 200);
      });
      await SseTransport(conn, client: mock).events('r', fromSeq: 5).toList();
    });
  });
}
