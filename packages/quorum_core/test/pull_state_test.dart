// P5.2b — the pull snapshot model + the shared-stream transport's filtering.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:quorum_core/quorum_core.dart';
import 'package:test/test.dart';

void main() {
  group('PullSnapshot.fromJson', () {
    test('parses the full wire shape', () {
      final s = PullSnapshot.fromJson({
        'tag': 'qwen3.5:9b',
        'status': 'pulling',
        'total': 6594462816,
        'completed': 3297231408,
        'catalog_bytes': 6594462816,
        'drift': false,
        'drift_reason': null,
        'error': null,
        'error_kind': null,
      });
      expect(s.tag, 'qwen3.5:9b');
      expect(s.phase, PullPhase.pulling);
      expect(s.isActive, isTrue);
      expect(s.isTerminal, isFalse);
      expect(s.progress, closeTo(0.5, 1e-9));
    });

    test('tolerates an empty map and unknown statuses (forward-compat, never throws)', () {
      final empty = PullSnapshot.fromJson(const {});
      expect(empty.tag, '');
      expect(empty.phase, PullPhase.unknown);
      expect(empty.progress, isNull); // total 0 -> no fabricated progress
      final future = PullSnapshot.fromJson(const {'tag': 't', 'status': 'quantum-syncing'});
      expect(future.phase, PullPhase.unknown);
      expect(future.isTerminal, isFalse);
    });

    test('terminal phases + sticky drift + honest error passthrough', () {
      final err = PullSnapshot.fromJson(const {
        'tag': 't', 'status': 'error',
        'error': 'write /models/blobs: no space left on device',
        'error_kind': 'ollama_error',
      });
      expect(err.isTerminal, isTrue);
      expect(err.error, contains('no space left'));
      final drifted = PullSnapshot.fromJson(const {
        'tag': 't', 'status': 'success', 'drift': true,
        'drift_reason': 'no layer matched catalog bytes',
      });
      expect(drifted.phase, PullPhase.success);
      expect(drifted.drift, isTrue); // drift is orthogonal to phase — a drifted pull completes
    });

    test('progress clamps overshoot and never divides by zero', () {
      expect(
        PullSnapshot.fromJson(const {'tag': 't', 'status': 'pulling', 'total': 10, 'completed': 12})
            .progress,
        1.0,
      );
      expect(
        PullSnapshot.fromJson(const {'tag': 't', 'status': 'pulling', 'completed': 5}).progress,
        isNull,
      );
    });
  });

  group('PullTransport', () {
    test('streams snapshots from the shared SSE stream, skipping heartbeats and noise', () async {
      // Drive the transport through a fake http.Client serving a canned SSE body.
      final body = [
        'event: pull',
        'data: {"tag":"qwen3.5:0.8b","status":"pulling","total":10,"completed":2}',
        '',
        'event: heartbeat',
        'data: {}', // no tag -> skipped
        '',
        'data: not-json', // unparsable -> skipped
        'data: {"tag":"qwen3.5:0.8b","status":"success","total":10,"completed":10}',
        '',
      ].join('\n');
      final client = _FakeSseClient(body);
      final transport = PullTransport(
        EngineConnection(Uri.parse('http://127.0.0.1:1'), 't'),
        client: client,
      );
      final snaps = await transport.events().toList();
      expect(snaps, hasLength(2));
      expect(snaps.first.phase, PullPhase.pulling);
      expect(snaps.last.phase, PullPhase.success);
      expect(client.lastRequest!.url.path, '/pulls/events');
      expect(client.lastRequest!.headers['authorization'], 'Bearer t');
    });

    test('non-200 throws EngineException', () async {
      final transport = PullTransport(
        EngineConnection(Uri.parse('http://127.0.0.1:1'), 't'),
        client: _FakeSseClient('', status: 503),
      );
      expect(transport.events().toList(), throwsA(isA<EngineException>()));
    });
  });
}

class _FakeSseClient extends http.BaseClient {
  final String body;
  final int status;
  http.BaseRequest? lastRequest;
  _FakeSseClient(this.body, {this.status = 200});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    return http.StreamedResponse(Stream.value(utf8.encode(body)), status);
  }
}
