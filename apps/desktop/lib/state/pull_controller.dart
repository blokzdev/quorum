// P5.2b — the pull controller: owns the ONE shared pull-snapshot subscription and the start/cancel
// actions. State = {tag -> latest PullSnapshot} (snapshots are idempotent; latest wins — no reducer).
//
// SCOPE WALL: start() takes the TYPED catalog entry — no String-tag parameter exists on this seam,
// so no user-typed text can ever reach the pull wire (and the sidecar re-validates against the
// curated catalog anyway, 422). POLICY (not schema): ONE active pull at a time in V1 — the map
// supports N, but the UI disables other Pull buttons while one is in flight (bandwidth/disk sanity;
// the A1 exit criterion is pull∥run, not pull∥pull).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quorum_core/quorum_core.dart';

import 'catalog_provider.dart';
import 'run_controller.dart' show httpClientProvider;

final pullControllerProvider =
    NotifierProvider<PullController, Map<String, PullSnapshot>>(PullController.new);

class PullController extends Notifier<Map<String, PullSnapshot>> {
  StreamSubscription<PullSnapshot>? _sub;
  PullTransport? _transport;
  bool _disposed = false;

  @override
  Map<String, PullSnapshot> build() {
    ref.onDispose(_teardown);
    return const {};
  }

  bool get anyActive => state.values.any((s) => s.isActive);

  /// Start (or resume — same wire call; Ollama resumes server-side) a curated pull. The POST
  /// response body is the pull's first snapshot, so the row updates immediately; the shared stream
  /// keeps it fresh from there.
  Future<void> start(EdgeModel entry) async {
    if (entry.ollamaTag.isEmpty) return;
    try {
      // Riverpod 3 auto-retries a failing provider with backoff, leaving `.future` PENDING across
      // attempts — without a timeout, a dead sidecar makes this await hang and the tap silently do
      // nothing. Bound it so the row shows an honest error instead.
      final conn = await ref
          .read(engineConnectionProvider.future)
          .timeout(const Duration(seconds: 8));
      final api = ApiClient(conn, client: ref.read(httpClientProvider));
      // Seed from the POST response FIRST, then subscribe: the stream's on-connect sweep delivers
      // the current state of every pull, so subscribing later loses nothing — while the reverse
      // order lets a fast terminal snapshot get clobbered by the stale POST seed (caught by test).
      final snap = await api.startPull(entry.ollamaTag);
      _fold(snap);
      await _ensureSubscribed();
    } catch (e) {
      // Surface the failure as an honest error snapshot (e.g. sidecar down, 422) — the row shows
      // the message + Retry rather than silently doing nothing.
      _fold(PullSnapshot.fromJson({
        'tag': entry.ollamaTag,
        'status': 'error',
        'error': '$e',
        'error_kind': 'ollama_unreachable',
      }));
    }
  }

  Future<void> cancel(String tag) async {
    try {
      final conn =
          await ref.read(engineConnectionProvider.future).timeout(const Duration(seconds: 8));
      final api = ApiClient(conn, client: ref.read(httpClientProvider));
      await api.cancelPull(tag); // 404 (already finished) is swallowed by the client — benign race
    } catch (_) {
      // Cancel is best-effort: if the sidecar is unreachable the pull died with it anyway.
    }
  }

  /// Subscribe to the shared snapshot stream (idempotent). Connecting IS the bootstrap: the server
  /// sweeps every known pull's snapshot on connect, so an app that restarts mid-session recovers
  /// terminal states without a separate GET. On stream loss the subscription self-clears; the next
  /// start() reattaches (snapshots are idempotent — a gap costs staleness, never correctness).
  Future<void> _ensureSubscribed() async {
    if (_sub != null) return;
    try {
      final conn =
          await ref.read(engineConnectionProvider.future).timeout(const Duration(seconds: 8));
      final transport = PullTransport(conn, client: ref.read(httpClientProvider));
      _transport = transport;
      _sub = transport.events().listen(
        _fold,
        onError: (_) => _clearSub(),
        onDone: _clearSub,
        cancelOnError: true,
      );
    } catch (_) {
      _clearSub(); // sidecar not up — the start() call will surface the actual error
    }
  }

  void _fold(PullSnapshot snap) {
    if (_disposed) return; // a late stream event after teardown must not touch dead state
    final existing = state[snap.tag];
    // Anti-clobber: never let a stale echo of the SAME pull (same or older started_at) demote a
    // terminal snapshot back to active. A genuine re-pull carries a LATER started_at and folds.
    if (existing != null &&
        existing.isTerminal &&
        !snap.isTerminal &&
        snap.startedAt <= existing.startedAt) {
      return;
    }
    state = {...state, snap.tag: snap};
    if (snap.phase == PullPhase.success) {
      // P5.2c: a completed pull folds into the EXISTING discovery + capability gate without an app
      // restart — the Installed chip and role-assignability come from the real /catalog paths,
      // never a synthetic client-side flag.
      ref.invalidate(localModelsProvider);
      ref.invalidate(edgeModelCatalogProvider);
    }
  }

  void _clearSub() {
    _sub?.cancel();
    _sub = null;
    _transport?.close();
    _transport = null;
  }

  void _teardown() {
    _disposed = true;
    _clearSub();
  }
}
