// S0 sidecar-spine spike (headless, throwaway): prove the desktop<->sidecar spine on Windows.
//
// Spawns the repo venv sidecar (`python -m services.api`), parses the stdout handshake, health-gates
// on /healthz, drives a cost-free `demo` run over authenticated SSE, then tears down with taskkill
// /T /F /PID (PRIMARY -- Dart's Process.kill does not reap the child tree on Windows). Pure
// dart:io/dart:convert: no packages, no Flutter, no codegen. Run from apps/desktop:
//   <flutter>\bin\dart.bat run tool/spine_spike.dart
// Verifiable via stdout (handshake, SSE event types, PASS/FAIL, orphan check).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<Directory> _findRepoRoot() async {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final py = File([dir.path, '.venv', 'Scripts', 'python.exe'].join(Platform.pathSeparator));
    if (await py.exists()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError('could not locate .venv/Scripts/python.exe upward from ${Directory.current.path}');
}

Future<({int statusCode, String body})> _send(
    HttpClient c, String method, String url, String? token, [Object? json]) async {
  final req = await c.openUrl(method, Uri.parse(url));
  if (token != null) req.headers.set('authorization', 'Bearer $token');
  if (json != null) {
    req.headers.set('content-type', 'application/json');
    req.add(utf8.encode(jsonEncode(json)));
  }
  final resp = await req.close();
  final body = await resp.transform(utf8.decoder).join();
  return (statusCode: resp.statusCode, body: body);
}

Future<void> _teardown(Process proc, String base, String token) async {
  try {
    final c = HttpClient();
    await _send(c, 'POST', '$base/shutdown', token).timeout(const Duration(seconds: 3));
    c.close(force: true);
  } catch (_) {}
  if (Platform.isWindows) {
    Process.runSync('taskkill', ['/T', '/F', '/PID', '${proc.pid}']); // PRIMARY teardown
  } else {
    proc.kill(ProcessSignal.sigterm);
  }
  try {
    await proc.exitCode.timeout(const Duration(seconds: 5));
  } catch (_) {}
}

bool _pidAlive(int pid) {
  if (!Platform.isWindows) return false;
  final r = Process.runSync('tasklist', ['/FI', 'PID eq $pid', '/NH']);
  return (r.stdout as String).contains('$pid');
}

Future<void> main() async {
  final repoRoot = await _findRepoRoot();
  final python = [repoRoot.path, '.venv', 'Scripts', 'python.exe'].join(Platform.pathSeparator);
  stdout.writeln('[spine] repo=${repoRoot.path}');

  final proc = await Process.start(
    python, ['-m', 'services.api'],
    workingDirectory: repoRoot.path,
    environment: {'QUORUM_PARENT_PID': '$pid'},
  );
  stdout.writeln('[spine] sidecar pid=${proc.pid}');

  final handshake = Completer<Map<String, dynamic>>();
  proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    if (line.trim().isEmpty) return;
    try {
      final obj = jsonDecode(line);
      if (obj is Map && obj['quorum_api'] == true && !handshake.isCompleted) {
        handshake.complete(Map<String, dynamic>.from(obj));
        return;
      }
    } catch (_) {/* not the handshake line */}
    stdout.writeln('[py-out] $line');
  });
  proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(
      (line) => stdout.writeln('[py-err] $line'));
  unawaited(proc.exitCode.then((code) {
    if (!handshake.isCompleted) {
      handshake.completeError(StateError('sidecar exited ($code) before handshake'));
    }
  }));

  final Map<String, dynamic> hs;
  try {
    hs = await handshake.future.timeout(const Duration(seconds: 10));
  } catch (e) {
    stderr.writeln('[spine] FAIL: no handshake ($e)');
    await _teardown(proc, 'http://127.0.0.1:0', '');
    exitCode = 2;
    return;
  }
  final base = 'http://${hs['host']}:${hs['port']}';
  final token = hs['token'] as String;
  stdout.writeln('[spine] handshake OK $base contract=${hs['contract_version']}');

  final client = HttpClient();
  // Health gate (/healthz is the only public route).
  var healthy = false;
  final deadline = DateTime.now().add(const Duration(seconds: 25));
  while (DateTime.now().isBefore(deadline)) {
    try {
      final r = await _send(client, 'GET', '$base/healthz', null);
      if (r.statusCode == 200) {
        healthy = true;
        break;
      }
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  if (!healthy) {
    stderr.writeln('[spine] FAIL: /healthz never became ready');
    await _teardown(proc, base, token);
    exitCode = 3;
    return;
  }
  stdout.writeln('[spine] /healthz READY');

  // Kick a cost-free demo run.
  final run = await _send(client, 'POST', '$base/runs', token,
      {'mode': 'demo', 'ticker': 'NVDA', 'step_delay': 0.1});
  final runId = (jsonDecode(run.body) as Map)['run_id'];
  stdout.writeln('[spine] POST /runs -> ${run.statusCode} run_id=$runId');

  // Stream the SSE event types until run_done.
  final types = <String>[];
  final req = await client.getUrl(Uri.parse('$base/runs/$runId/events'));
  req.headers.set('authorization', 'Bearer $token');
  req.headers.set('accept', 'text/event-stream');
  final resp = await req.close();
  final done = Completer<void>();
  final sub = resp.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    if (!line.startsWith('data:')) return;
    try {
      final obj = jsonDecode(line.substring(5).trim()) as Map;
      final type = obj['type'];
      if (type == null) return;
      types.add(type as String);
      final extra = type == 'report_section_done' ? ' (${obj['data']['section']})'
          : type == 'run_done' ? ' rating=${obj['data']['rating']}' : '';
      stdout.writeln('[sse] $type$extra');
      if ((type == 'run_done' || type == 'error') && !done.isCompleted) done.complete();
    } catch (_) {}
  }, onDone: () {
    if (!done.isCompleted) done.complete();
  });
  await done.future.timeout(const Duration(seconds: 60), onTimeout: () {});
  await sub.cancel();
  stdout.writeln('[spine] received ${types.length} events; last=${types.isNotEmpty ? types.last : "none"}');

  await _teardown(proc, base, token);
  client.close(force: true);
  final orphan = _pidAlive(proc.pid);
  stdout.writeln('[spine] python pid ${proc.pid} still alive after teardown: $orphan');

  final ok = types.isNotEmpty && types.last == 'run_done' && !orphan;
  stdout.writeln(ok ? '[spine] PASS' : '[spine] FAIL');
  exitCode = ok ? 0 : 1;
}
