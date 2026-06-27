import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quorum_core/quorum_core.dart';

import 'run_controller.dart'; // engineEndpointProvider, httpClientProvider

/// The engine connection — spawns + handshakes the sidecar on first read; the endpoint memoizes it,
/// so this shares the same connection the run controller uses.
final engineConnectionProvider = FutureProvider<EngineConnection>((ref) async {
  return ref.read(engineEndpointProvider).connect();
});

/// The provider/model catalog (`GET /catalog/providers`), fetched lazily on first read and cached.
/// Model Studio (P2.3) is the first consumer, so there is no boot-time fetch and first-screen latency
/// is unchanged.
///
/// A run that errors usually means the sidecar died, and the endpoint memoizes its connection — so on
/// the error edge we drop both [engineConnectionProvider] and ourselves, and the next read reconnects
/// and refetches a live catalog instead of serving one bound to a dead sidecar.
final catalogProvider = FutureProvider<Catalog>((ref) async {
  ref.listen(runControllerProvider, (prev, next) {
    if (next.phase == RunPhase.error && prev?.phase != RunPhase.error) {
      ref.invalidate(engineConnectionProvider);
      ref.invalidateSelf();
    }
  });
  final conn = await ref.watch(engineConnectionProvider.future);
  // Reuse the shared http client; do NOT close this ApiClient (that would close the shared client,
  // which httpClientProvider owns and disposes).
  final api = ApiClient(conn, client: ref.read(httpClientProvider));
  return Catalog.fromJson(await api.catalog());
});
