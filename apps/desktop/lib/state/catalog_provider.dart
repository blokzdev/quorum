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

/// The data-vendor catalog (`GET /catalog/vendors`, P3.1) — the per-category vendor picker for Model
/// Studio's Data sources section. Fetched lazily + cached on the same shared connection as [catalogProvider].
final vendorCatalogProvider = FutureProvider<VendorCatalog>((ref) async {
  final conn = await ref.watch(engineConnectionProvider.future);
  final api = ApiClient(conn, client: ref.read(httpClientProvider));
  return VendorCatalog.fromJson(await api.vendors());
});

/// The device's installed Ollama models (`GET /catalog/local-models`, P3.2) — folded into the Ollama
/// model picker so real local models (Gemma/Qwen/GLM/…) are discovered rather than hand-typed, each with
/// its real tool-capability for the gate. Degrades to an EMPTY list on any error (Ollama down, or no
/// sidecar yet) so the picker cleanly falls back to its static option + custom-id path — a local-model
/// discovery failure must never break Model Studio.
final localModelsProvider = FutureProvider<List<LocalModel>>((ref) async {
  try {
    final conn = await ref.watch(engineConnectionProvider.future);
    final api = ApiClient(conn, client: ref.read(httpClientProvider));
    return LocalModel.listFromJson(await api.localModels());
  } catch (_) {
    return const <LocalModel>[];
  }
});

/// The curated Edge Model Draft Board (`GET /catalog/edge-models`, P5.1a) — tiers + per-model exact
/// bytes/KV params/verification + the detected Ollama version (null = Ollama absent, the P5.3c
/// onboarding discriminator). Degrades to an EMPTY catalog on any error (sidecar unreachable) so the
/// Draft Board renders a clean empty/absent state — a catalog failure must never break Settings.
final edgeModelCatalogProvider = FutureProvider<EdgeModelCatalog>((ref) async {
  try {
    final conn = await ref.watch(engineConnectionProvider.future);
    final api = ApiClient(conn, client: ref.read(httpClientProvider));
    return EdgeModelCatalog.fromJson(await api.edgeModels());
  } catch (_) {
    return const EdgeModelCatalog();
  }
});
