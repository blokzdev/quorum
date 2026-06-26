import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:quorum_core/quorum_core.dart';

/// Desktop [EngineEndpoint]: spawns the bundled Python sidecar (in dev, the repo's `.venv`) and
/// yields a connection once it has handshaked and passed `/healthz`. Promotes the proven
/// `tool/spine_spike.dart` into a reusable service.
///
/// Lifecycle hardening (from the S2 adversarial pre-mortem):
/// - **Single-instance:** [connect] reaps any stale sidecar recorded in a per-repo lockfile (verified
///   to still be a live `python.exe` by PID) — this kills hot-restart zombie accumulation during dev.
/// - **Teardown:** [dispose] POSTs `/shutdown` then `taskkill /T /F`s the tree (`Process.kill` does
///   NOT reap children on Windows). The sidecar's `QUORUM_PARENT_PID` watchdog is the final backstop.
///
/// The only platform-divergent part of the app lives here; a future mobile build swaps in a
/// `RemoteEndpoint` and everything downstream (ApiClient/SseTransport/reduce) is unchanged.
class DesktopSidecarEndpoint implements EngineEndpoint {
  final void Function(String line)? onLog;

  Process? _proc;
  EngineConnection? _conn;
  String? _repoRoot;

  DesktopSidecarEndpoint({this.onLog});

  bool get isConnected => _conn != null;

  @override
  Future<EngineConnection> connect() async {
    if (_conn != null) return _conn!;

    final repoRoot = await _findRepoRoot();
    if (repoRoot == null) {
      throw EngineException(
          'could not locate the repo .venv (dev mode) upward from ${Directory.current.path}');
    }
    _repoRoot = repoRoot;
    _reapStale(repoRoot); // kill a sidecar leaked by a prior hot-restart, if any

    final python = _join([repoRoot, '.venv', 'Scripts', 'python.exe']);
    _log('spawning sidecar: $python -m services.api (cwd=$repoRoot)');

    final proc = await Process.start(
      python,
      ['-m', 'services.api'],
      workingDirectory: repoRoot,
      environment: {'QUORUM_PARENT_PID': '$pid'},
    );
    _proc = proc; // stored synchronously so a stop() during connect() can still kill it

    final handshake = Completer<Map<String, dynamic>>();
    proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      if (line.trim().isEmpty) return;
      try {
        final obj = jsonDecode(line);
        if (obj is Map && obj['quorum_api'] == true && !handshake.isCompleted) {
          handshake.complete(obj.cast<String, dynamic>());
          return;
        }
      } catch (_) {/* not the handshake line */}
      _log('[py] $line');
    });
    proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((l) => _log('[py-err] $l'));
    unawaited(proc.exitCode.then((code) {
      if (!handshake.isCompleted) {
        handshake.completeError(EngineException('sidecar exited ($code) before handshake'));
      }
    }));

    final hs = await handshake.future.timeout(const Duration(seconds: 12),
        onTimeout: () => throw EngineException('sidecar handshake timed out'));
    final base = Uri.parse('http://${hs['host']}:${hs['port']}');
    final token = hs['token'] as String;
    _log('handshake ok: $base (contract ${hs['contract_version']})');

    await _healthGate(base);
    _writeLock(repoRoot, proc.pid, base.port);
    _conn = EngineConnection(base, token);
    return _conn!;
  }

  Future<void> _healthGate(Uri base) async {
    final client = HttpClient();
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    try {
      while (DateTime.now().isBefore(deadline)) {
        try {
          final resp = await (await client.getUrl(base.resolve('/healthz'))).close();
          await resp.drain<void>();
          if (resp.statusCode == 200) {
            _log('/healthz ready');
            return;
          }
        } catch (_) {/* not up yet */}
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    } finally {
      client.close(force: true);
    }
    await dispose();
    throw EngineException('sidecar /healthz never became ready');
  }

  @override
  Future<void> dispose() async {
    final conn = _conn;
    final proc = _proc;
    final repoRoot = _repoRoot;
    _conn = null;
    _proc = null;
    if (conn != null) {
      final api = ApiClient(conn);
      try {
        await api.shutdown().timeout(const Duration(seconds: 2));
      } catch (_) {/* best effort; taskkill below is the real teardown */}
      api.close();
    }
    if (proc != null) {
      if (Platform.isWindows) {
        try {
          Process.runSync('taskkill', ['/T', '/F', '/PID', '${proc.pid}']);
        } catch (_) {/* already gone */}
      } else {
        proc.kill(ProcessSignal.sigterm);
      }
    }
    if (repoRoot != null) {
      try {
        final lock = _lockFile(repoRoot);
        if (lock.existsSync()) lock.deleteSync();
      } catch (_) {}
    }
  }

  // --- single-instance lockfile (per repo) to reap hot-restart zombies ---

  File _lockFile(String repoRoot) =>
      File('${Directory.systemTemp.path}${Platform.pathSeparator}quorum_sidecar_${repoRoot.hashCode}.lock');

  void _writeLock(String repoRoot, int pid, int port) {
    try {
      _lockFile(repoRoot).writeAsStringSync(jsonEncode({'pid': pid, 'port': port}));
    } catch (_) {}
  }

  void _reapStale(String repoRoot) {
    try {
      final lock = _lockFile(repoRoot);
      if (!lock.existsSync()) return;
      final data = jsonDecode(lock.readAsStringSync()) as Map<String, dynamic>;
      final stalePid = data['pid'] as int?;
      if (stalePid != null && _isLivePython(stalePid)) {
        _log('reaping stale sidecar pid=$stalePid');
        Process.runSync('taskkill', ['/T', '/F', '/PID', '$stalePid']);
      }
      lock.deleteSync();
    } catch (_) {/* lock unreadable / already gone */}
  }

  bool _isLivePython(int pid) {
    if (!Platform.isWindows) return false;
    // Verify it's actually a python.exe with this PID (guards against PID reuse killing a stranger).
    final r = Process.runSync(
        'tasklist', ['/FI', 'PID eq $pid', '/FI', 'IMAGENAME eq python.exe', '/NH']);
    return (r.stdout as String).contains('$pid');
  }

  void _log(String line) => onLog?.call(line);

  static String _join(List<String> parts) => parts.join(Platform.pathSeparator);

  static Future<String?> _findRepoRoot() async {
    var dir = Directory.current;
    for (var i = 0; i < 12; i++) {
      final py = File(_join([dir.path, '.venv', 'Scripts', 'python.exe']));
      if (await py.exists()) return dir.path;
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }
}
