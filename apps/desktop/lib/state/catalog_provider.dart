import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quorum_core/quorum_core.dart';

import 'run_controller.dart'; // engineEndpointProvider, httpClientProvider

/// The engine connection — spawns + handshakes the sidecar on first read; the endpoint memoizes it,
/// so this shares the same connection the run controller uses.
final engineConnectionProvider = FutureProvider<EngineConnection>((ref) async {
  return ref.read(engineEndpointProvider).connect();
});

/// The provider/model catalog (`GET /catalog/providers`), fetched lazily on first read and cached.
/// Nothing watches it in P2.1 — Model Studio (P2.3) is the first consumer, so there is no boot-time
/// fetch and first-screen latency is unchanged.
///
// TODO(P2.3): invalidate engineConnectionProvider + catalogProvider on sidecar crash / RunPhase.error
// (the endpoint memoizes the connection) before Settings relies on a live connection.
final catalogProvider = FutureProvider<Catalog>((ref) async {
  final conn = await ref.watch(engineConnectionProvider.future);
  // Reuse the shared http client; do NOT close this ApiClient (that would close the shared client,
  // which httpClientProvider owns and disposes).
  final api = ApiClient(conn, client: ref.read(httpClientProvider));
  return Catalog.fromJson(await api.catalog());
});
