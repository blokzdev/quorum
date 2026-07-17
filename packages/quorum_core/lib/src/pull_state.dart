/// The pull-lane client model (P5.2b): a tolerant typed view of the sidecar's pull SNAPSHOTS.
///
/// The wire is deliberately simpler than the run stream: the sidecar's `/pulls` lane emits
/// state-carrying, idempotent snapshots (latest wins) — not deltas — so the client needs no
/// reducer, no seq cursors, and no `Last-Event-ID`: parse a snapshot, store it by tag, done. Drift
/// is computed SERVER-side against the curated catalog's exact bytes and rides the snapshot.
/// This union never touches the run event contract (plan A1 — no `CONTRACT_VERSION` coupling).
library;

/// The sidecar's pull statuses, plus [unknown] for forward-compat (an unrecognized status string
/// degrades to a safe rendering, never a throw).
enum PullPhase { pulling, verifying, success, error, cancelled, unknown }

/// One tag's pull snapshot, exactly as served by `POST /pulls` / `GET /pulls` /
/// `GET /pulls/events`. Immutable; tolerant of missing keys.
class PullSnapshot {
  final String tag;
  final PullPhase phase;
  final String statusRaw;
  final int completed;
  final int total; // 0 = not yet known → indeterminate presentation

  /// The curated entry's exact bytes the server compared against (0 when unserved).
  final int catalogBytes;

  /// STICKY server-side drift flag: the pulled bytes don't match the curated catalog (a repointed
  /// tag). Orthogonal to phase — a drifted pull still completes; the warning persists.
  final bool drift;
  final String? driftReason;
  final String? error;
  final String? errorKind; // 'ollama_unreachable' | 'ollama_error' (raw; forward-tolerant)

  const PullSnapshot({
    required this.tag,
    this.phase = PullPhase.unknown,
    this.statusRaw = '',
    this.completed = 0,
    this.total = 0,
    this.catalogBytes = 0,
    this.drift = false,
    this.driftReason,
    this.error,
    this.errorKind,
  });

  factory PullSnapshot.fromJson(Map<String, dynamic> j) {
    final status = j['status'] as String? ?? '';
    return PullSnapshot(
      tag: j['tag'] as String? ?? '',
      phase: switch (status) {
        'pulling' => PullPhase.pulling,
        'verifying' => PullPhase.verifying,
        'success' => PullPhase.success,
        'error' => PullPhase.error,
        'cancelled' => PullPhase.cancelled,
        _ => PullPhase.unknown,
      },
      statusRaw: status,
      completed: (j['completed'] as num?)?.toInt() ?? 0,
      total: (j['total'] as num?)?.toInt() ?? 0,
      catalogBytes: (j['catalog_bytes'] as num?)?.toInt() ?? 0,
      drift: j['drift'] as bool? ?? false,
      driftReason: j['drift_reason'] as String?,
      error: j['error'] as String?,
      errorKind: j['error_kind'] as String?,
    );
  }

  bool get isTerminal =>
      phase == PullPhase.success || phase == PullPhase.error || phase == PullPhase.cancelled;
  bool get isActive => phase == PullPhase.pulling || phase == PullPhase.verifying;

  /// 0..1 when the total is known, else null (the UI renders a static zero bar + the status text —
  /// never a fake indeterminate animation).
  double? get progress =>
      total > 0 ? (completed / total).clamp(0.0, 1.0) : null;
}
