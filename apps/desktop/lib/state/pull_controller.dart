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

/// Consecutive stream losses (with no snapshot in between) before active pulls are declared dead.
const int _kMaxLossStreak = 3;

class PullController extends Notifier<Map<String, PullSnapshot>> {
  /// The reconnect backoff. Static so tests can shrink it (the provider constructs this notifier —
  /// there is no constructor seam); production never mutates it.
  static Duration retryDelay = const Duration(seconds: 3);

  StreamSubscription<PullSnapshot>? _sub;
  PullTransport? _transport;
  Future<void>? _subscribing;
  Timer? _retry;
  int _lossStreak = 0;
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

  /// Subscribe to the shared snapshot stream (idempotent; concurrent callers share ONE in-flight
  /// attempt — the awaits inside made the bare `_sub != null` check a check-then-act race where two
  /// quick start()s opened two sockets and leaked the first, #52 review). Connecting IS the
  /// bootstrap: the server sweeps every known pull's snapshot on connect, so an app that restarts
  /// mid-session recovers terminal states without a separate GET.
  Future<void> _ensureSubscribed() {
    if (_sub != null) return Future.value();
    return _subscribing ??= _subscribe().whenComplete(() => _subscribing = null);
  }

  Future<void> _subscribe() async {
    try {
      final conn =
          await ref.read(engineConnectionProvider.future).timeout(const Duration(seconds: 8));
      if (_disposed) return;
      final transport = PullTransport(conn, client: ref.read(httpClientProvider));
      _transport = transport;
      _sub = transport.events().listen(
        _fold,
        onError: (_) => _onStreamLoss(),
        onDone: _onStreamLoss,
        cancelOnError: true,
      );
    } catch (_) {
      _onStreamLoss(); // sidecar not up — the start() call will surface the actual error
    }
  }

  /// Stream loss ≠ pull loss: the pull keeps running server-side, so a dropped board stream must
  /// reattach or the rows freeze mid-progress and a finishing pull never folds into discovery
  /// (#52 review). Retry on a short timer while any pull is active — the on-connect sweep makes
  /// recovery complete regardless of what was missed. With nothing active, the next start()
  /// reattaches (snapshots are idempotent — a gap costs staleness, never correctness).
  ///
  /// But a DEAD sidecar can never send a terminal snapshot, so an unbounded silent retry loop
  /// would leave live-looking frozen rows blocking every Pull button all session (#53 review):
  /// after [_kMaxLossStreak] straight losses with no snapshot in between, the active pulls are
  /// declared dead honestly — the sidecar drives the pull (Ollama aborts when its socket closes),
  /// so no sidecar means no download either.
  void _onStreamLoss() {
    _clearSub();
    if (_disposed || !anyActive) return;
    _lossStreak++;
    if (_lossStreak >= _kMaxLossStreak) {
      _failActivePulls();
      return;
    }
    _retry ??= Timer(retryDelay, () {
      _retry = null;
      if (!_disposed && anyActive) _ensureSubscribed();
    });
  }

  void _failActivePulls() {
    for (final s in state.values.where((s) => s.isActive).toList()) {
      _fold(PullSnapshot.fromJson({
        'tag': s.tag,
        'status': 'error',
        'error': 'Lost contact with the engine — the pull stopped. Pull again to resume.',
        'error_kind': 'ollama_unreachable',
        'started_at': s.startedAt,
      }));
    }
  }

  void _fold(PullSnapshot snap) {
    if (_disposed) return; // a late stream event after teardown must not touch dead state
    _lossStreak = 0; // a snapshot arriving proves the pipe is alive — reset the dead-sidecar count
    final existing = state[snap.tag];
    // Anti-clobber: never let a stale echo of the SAME pull (same or older started_at) demote a
    // terminal snapshot back to active. A genuine re-pull carries a LATER started_at and folds.
    if (existing != null &&
        existing.isTerminal &&
        !snap.isTerminal &&
        snap.startedAt <= existing.startedAt) {
      return;
    }
    final wasSuccess = existing != null && existing.phase == PullPhase.success;
    state = {...state, snap.tag: snap};
    if (snap.phase == PullPhase.success && !wasSuccess) {
      // P5.2c: a completed pull folds into the EXISTING discovery + capability gate without an app
      // restart — the Installed chip and role-assignability come from the real /catalog paths,
      // never a synthetic client-side flag. Transition-gated: reconnect sweeps redeliver terminal
      // snapshots, and each redelivery must not refetch the catalogs again (#52 review).
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
    _retry?.cancel();
    _retry = null;
    _clearSub();
  }
}
