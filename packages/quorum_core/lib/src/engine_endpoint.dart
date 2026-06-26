/// The boundary between the UI and a running engine. The ONLY platform-divergent piece of the app:
/// on desktop a [EngineEndpoint] spawns the bundled Python sidecar; a future mobile build swaps in a
/// remote endpoint that points at a hosted engine. Everything downstream (ApiClient, SseTransport,
/// the reducer) is identical.
library;

/// A live engine: its base URL and the per-launch bearer token.
class EngineConnection {
  final Uri baseUri;
  final String token;
  const EngineConnection(this.baseUri, this.token);
}

/// Brings an engine up (or connects to one) and yields a [EngineConnection].
abstract interface class EngineEndpoint {
  Future<EngineConnection> connect();
  Future<void> dispose();
}

class EngineException implements Exception {
  final String message;
  EngineException(this.message);
  @override
  String toString() => 'EngineException: $message';
}
