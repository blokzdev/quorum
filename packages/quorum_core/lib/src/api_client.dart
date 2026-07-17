/// The control-plane HTTP client for the Quorum engine API. Bearer-injecting, JSON in/out. Portable
/// (uses package:http), so the desktop app and a future mobile client share it.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'engine_endpoint.dart';
import 'pull_state.dart';
import 'run_summary.dart';

class ApiClient {
  final EngineConnection conn;
  final http.Client _client;

  ApiClient(this.conn, {http.Client? client}) : _client = client ?? http.Client();

  Map<String, String> get _auth => {'authorization': 'Bearer ${conn.token}'};

  Future<Map<String, dynamic>> health() => _getJson('/healthz', auth: false);

  Future<Map<String, dynamic>> catalog() => _getJson('/catalog/providers');

  /// GET /catalog/vendors -> the per-category data-vendor catalog (P3.1).
  Future<Map<String, dynamic>> vendors() => _getJson('/catalog/vendors');

  /// GET /catalog/local-models -> the device's installed Ollama models + tool-capability (P3.2).
  Future<Map<String, dynamic>> localModels() => _getJson('/catalog/local-models');

  /// The curated Edge Model Draft Board + detected Ollama version (P5.1a).
  Future<Map<String, dynamic>> edgeModels() => _getJson('/catalog/edge-models');

  /// Host-only: provider keys read from the sidecar host's `.env`, for a one-time import into the
  /// desktop's OS keystore. Returns `{provider: key}`; values are never logged.
  Future<Map<String, dynamic>> envKeys() => _getJson('/env-keys');

  /// POST /runs -> 202 {run_id}. [body] is the run request (mode/ticker/provider/...).
  Future<String> createRun(Map<String, dynamic> body) async {
    final r = await _client.post(
      conn.baseUri.resolve('/runs'),
      headers: {..._auth, 'content-type': 'application/json'},
      body: jsonEncode(body),
    );
    if (r.statusCode != 202) {
      throw EngineException('createRun failed: ${r.statusCode} ${r.body}');
    }
    return (jsonDecode(r.body) as Map<String, dynamic>)['run_id'] as String;
  }

  Future<Map<String, dynamic>> getRun(String runId) => _getJson('/runs/$runId');

  /// GET /runs -> the persisted run history (newest first), as typed [RunSummary]s.
  Future<List<RunSummary>> listRuns() async {
    final body = await _getJson('/runs');
    final runs = (body['runs'] as List?) ?? const [];
    return runs
        .map((e) => RunSummary.fromJson((e as Map).cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> reports(String runId) => _getJson('/runs/$runId/reports');

  Future<void> cancel(String runId) async {
    await _client.post(conn.baseUri.resolve('/runs/$runId/cancel'), headers: _auth);
  }

  /// Best-effort graceful shutdown; failures are swallowed (the caller force-kills as backstop).
  Future<void> shutdown() async {
    try {
      await _client.post(conn.baseUri.resolve('/shutdown'), headers: _auth);
    } catch (_) {/* ignore */}
  }

  /// POST /pulls -> start (202) or idempotently join (200) a curated-model pull; the response body
  /// is the pull's current snapshot either way. The tag must be a curated `ollama_tag` — the
  /// sidecar re-validates against the catalog (422 otherwise; the server-side scope wall).
  Future<PullSnapshot> startPull(String tag) async {
    final r = await _client.post(
      conn.baseUri.resolve('/pulls'),
      headers: {..._auth, 'content-type': 'application/json'},
      body: jsonEncode({'tag': tag}),
    );
    if (r.statusCode != 202 && r.statusCode != 200) {
      throw EngineException('startPull failed: ${r.statusCode} ${r.body}');
    }
    return PullSnapshot.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  /// GET /pulls -> every known pull's snapshot (active + terminal) — the reconnect bootstrap.
  Future<List<PullSnapshot>> listPulls() async {
    final body = await _getJson('/pulls');
    return ((body['pulls'] as List?) ?? const [])
        .map((e) => PullSnapshot.fromJson((e as Map).cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// POST /pulls/cancel — aborts an active pull (Ollama keeps partial layers; re-pull resumes).
  /// 404 (no active pull) is swallowed: cancel-after-finish is a benign race, not an error.
  Future<void> cancelPull(String tag) async {
    final r = await _client.post(
      conn.baseUri.resolve('/pulls/cancel'),
      headers: {..._auth, 'content-type': 'application/json'},
      body: jsonEncode({'tag': tag}),
    );
    if (r.statusCode != 200 && r.statusCode != 404) {
      throw EngineException('cancelPull failed: ${r.statusCode} ${r.body}');
    }
  }

  Future<Map<String, dynamic>> _getJson(String path, {bool auth = true}) async {
    final r = await _client.get(conn.baseUri.resolve(path), headers: auth ? _auth : null);
    if (r.statusCode != 200) {
      throw EngineException('GET $path -> ${r.statusCode}');
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  void close() => _client.close();
}
