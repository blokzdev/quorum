import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:quorum_core/quorum_core.dart';

import '../engine/desktop_sidecar_endpoint.dart';

/// The engine endpoint (desktop = spawns the sidecar). Overridable in tests with a fake.
final engineEndpointProvider = Provider<EngineEndpoint>((ref) {
  final endpoint = DesktopSidecarEndpoint(
    onLog: (line) => ref.read(sidecarLogProvider.notifier).add(line),
  );
  ref.onDispose(endpoint.dispose);
  return endpoint;
});

/// One shared HTTP client for the control plane + SSE. Overridable in tests with a MockClient.
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// A small rolling buffer of sidecar stdout/stderr for the debug screen.
final sidecarLogProvider = NotifierProvider<SidecarLog, List<String>>(SidecarLog.new);

class SidecarLog extends Notifier<List<String>> {
  @override
  List<String> build() => const [];
  void add(String line) {
    final next = [...state, line];
    state = next.length > 200 ? next.sublist(next.length - 200) : next;
  }
}

/// Owns a run end to end: connect -> createRun -> SSE -> reduce -> [RunViewState]. KeepAlive (survives
/// UI rebuilds); native cleanup is owned explicitly via [shutdown], NOT left to provider GC.
final runControllerProvider =
    NotifierProvider<RunController, RunViewState>(RunController.new);

class RunController extends Notifier<RunViewState> {
  StreamSubscription<QuorumEvent>? _sub;
  ApiClient? _api;
  String? _runId;
  bool _connecting = false;
  bool _disposed = false;

  @override
  RunViewState build() {
    ref.onDispose(_teardown); // belt-and-suspenders (a keepAlive provider may not fire this)
    return RunViewState.initial();
  }

  bool get _busy => _connecting || state.phase == RunPhase.running;

  /// Start a run. No-op if one is already in flight (single in-flight guard).
  Future<void> start({String mode = 'demo', String ticker = 'NVDA', double stepDelay = 0.2}) async {
    if (_busy) return;
    _connecting = true;
    _runId = null;
    await _sub?.cancel();
    _sub = null;
    state = RunViewState.initial().copyWith(phase: RunPhase.running, ticker: ticker);
    try {
      final conn = await ref.read(engineEndpointProvider).connect();
      if (_disposed) return;
      final client = ref.read(httpClientProvider);
      _api = ApiClient(conn, client: client);
      final runId = await _api!.createRun({'mode': mode, 'ticker': ticker, 'step_delay': stepDelay});
      _runId = runId;
      if (_disposed) {
        await _api!.cancel(runId); // don't leave a headless run on the server
        return;
      }
      _sub = SseTransport(conn, client: client).events(runId).listen(
        (event) {
          if (!_disposed) state = reduce(state, event);
        },
        onError: (Object e) {
          if (!_disposed) state = state.copyWith(phase: RunPhase.error, error: '$e');
        },
        onDone: () {
          if (!_disposed && !state.isTerminal) {
            state = state.copyWith(phase: RunPhase.error, error: 'event stream ended before run_done');
          }
        },
        cancelOnError: true,
      );
    } catch (e) {
      if (!_disposed) state = state.copyWith(phase: RunPhase.error, error: '$e');
      final id = _runId, api = _api;
      if (id != null && api != null) {
        try {
          await api.cancel(id); // createRun may have succeeded before SSE failed
        } catch (_) {}
      }
    } finally {
      _connecting = false;
    }
  }

  /// Cooperatively cancel the in-flight run (server emits run_done(cancelled) over SSE).
  Future<void> cancel() async {
    final id = _runId, api = _api;
    if (id != null && api != null) {
      try {
        await api.cancel(id);
      } catch (_) {}
    }
  }

  Future<void> _teardown() async {
    _disposed = true;
    await _sub?.cancel();
    _sub = null;
    _api?.close();
    _api = null;
  }

  /// Explicit shutdown from the app's exit path (close button / detached): tear down the stream and
  /// kill the sidecar. Safe to call multiple times.
  Future<void> shutdown() async {
    await _teardown();
    try {
      await ref.read(engineEndpointProvider).dispose();
    } catch (_) {}
  }
}
