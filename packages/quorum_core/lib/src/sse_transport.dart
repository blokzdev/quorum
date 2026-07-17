/// Hand-rolled Server-Sent Events client over package:http. The run's typed events as a Dart Stream,
/// with the bearer header and Last-Event-ID resume. Hand-rolled (not a pub.dev SSE wrapper) so the
/// custom auth header + resume semantics stay exact and portable to mobile.
library;

import 'package:http/http.dart' as http;

import 'engine_endpoint.dart';
import 'events.dart';
import 'sse_frames.dart';

class SseTransport {
  final EngineConnection conn;
  final http.Client _client;

  SseTransport(this.conn, {http.Client? client}) : _client = client ?? http.Client();

  /// Streams typed events for [runId]. [fromSeq] >= 0 resumes after that seq (Last-Event-ID);
  /// -1 replays from the beginning. Heartbeats and unparsable frames are skipped.
  Stream<QuorumEvent> events(String runId, {int fromSeq = -1}) async* {
    final req = http.Request('GET', conn.baseUri.resolve('/runs/$runId/events'))
      ..headers['authorization'] = 'Bearer ${conn.token}'
      ..headers['accept'] = 'text/event-stream';
    if (fromSeq >= 0) {
      req.headers['last-event-id'] = '$fromSeq';
    }
    final resp = await _client.send(req);
    if (resp.statusCode != 200) {
      throw EngineException('SSE /runs/$runId/events -> ${resp.statusCode}');
    }
    await for (final env in sseJsonDataFrames(resp.stream)) {
      if (env['type'] == null) continue; // heartbeat frame ({}) or noise
      yield QuorumEvent.fromEnvelope(env);
    }
  }

  void close() => _client.close();
}
