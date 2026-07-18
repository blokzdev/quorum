/// The pull-snapshot stream client (P5.2b): `GET /pulls/events` — ONE shared, board-lifetime SSE
/// stream for all pulls. Snapshots are idempotent (latest wins) and the server emits every known
/// pull's current snapshot on connect, so a reconnect needs NO `Last-Event-ID`/replay — connecting
/// IS the bootstrap. Sibling of [SseTransport] over the shared frame parser; the two event layers
/// never touch (plan A1).
library;

import 'package:http/http.dart' as http;

import 'engine_endpoint.dart';
import 'pull_state.dart';
import 'sse_frames.dart';

class PullTransport {
  final EngineConnection conn;
  final http.Client _client;
  final bool _ownsClient;

  PullTransport(this.conn, {http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  /// The shared snapshot stream: the on-connect sweep of every known pull, then live updates.
  /// Heartbeats (`{}` — no `tag`) are skipped. Non-200 → [EngineException].
  Stream<PullSnapshot> events() async* {
    final req = http.Request('GET', conn.baseUri.resolve('/pulls/events'))
      ..headers['authorization'] = 'Bearer ${conn.token}'
      ..headers['accept'] = 'text/event-stream';
    final resp = await _client.send(req);
    if (resp.statusCode != 200) {
      throw EngineException('SSE /pulls/events -> ${resp.statusCode}');
    }
    await for (final frame in sseJsonDataFrames(resp.stream)) {
      final snap = PullSnapshot.fromJson(frame);
      if (snap.tag.isEmpty) continue; // heartbeat or noise
      yield snap;
    }
  }

  /// Closes the HTTP client ONLY when this instance constructed it — an injected (shared) client
  /// is the injector's to close (see [ApiClient.close]; the #52-review defect was this transport
  /// closing the app-wide client on any stream loss).
  void close() {
    if (_ownsClient) _client.close();
  }
}
