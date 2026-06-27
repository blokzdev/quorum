import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quorum_core/quorum_core.dart';

import 'catalog_provider.dart'; // engineConnectionProvider
import 'run_controller.dart'; // httpClientProvider

/// The persisted run history (`GET /runs`), fetched lazily on first read and cached. Invalidate it to
/// refresh after a new run completes (the Hub's refresh button + an auto-refresh when a run finishes).
final runHistoryProvider = FutureProvider<List<RunSummary>>((ref) async {
  final conn = await ref.watch(engineConnectionProvider.future);
  // Reuse the shared http client; do NOT close this ApiClient (httpClientProvider owns the client).
  final api = ApiClient(conn, client: ref.read(httpClientProvider));
  return api.listRuns();
});

/// The full canonical report sections for one run (`GET /runs/{id}/reports`) — what the cached review
/// renders. The engine reads them from the in-memory run or, after a restart, from the persisted
/// reports.json, so a cached review works for any historical run.
final runReportsProvider = FutureProvider.family<Map<String, String>, String>((ref, runId) async {
  final conn = await ref.watch(engineConnectionProvider.future);
  final api = ApiClient(conn, client: ref.read(httpClientProvider));
  final body = await api.reports(runId);
  final sections = (body['sections'] as Map?)?.cast<String, dynamic>() ?? const {};
  return sections.map((k, v) => MapEntry(k, '$v'));
});
