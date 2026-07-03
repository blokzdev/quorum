import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quorum/engine/sidecar_launch.dart';

/// Hermetic tests for the sidecar launch resolution (P2.6a): env override → bundled exe → dev .venv.
/// All fixtures are real files in per-test temp dirs; nothing touches the machine's actual state.
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('quorum_launch_test_');
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  String join(List<String> parts) => parts.join(Platform.pathSeparator);

  Future<File> touch(List<String> parts) async {
    final f = File(join([tmp.path, ...parts]));
    await f.create(recursive: true);
    return f;
  }

  test('env override wins when the file exists', () async {
    final exe = await touch(['override', 'quorum_sidecar.exe']);
    final work = Directory(join([tmp.path, 'work']));
    final spec = await SidecarLauncher.resolve(
      environment: {'QUORUM_SIDECAR_EXE': exe.path},
      appExecutable: join([tmp.path, 'nowhere', 'app.exe']),
      searchStart: tmp, // no .venv here — override must not need one
      bundledWorkDir: work,
    );
    expect(spec, isNotNull);
    expect(spec!.bundled, isTrue);
    expect(spec.executable, exe.path);
    expect(spec.args, isEmpty);
    expect(spec.imageName, 'quorum_sidecar.exe');
    expect(spec.workingDirectory, work.path);
    expect(await work.exists(), isTrue, reason: 'bundled work dir is created');
  });

  test('a missing env override is skipped (falls through to the next candidate)', () async {
    final appExe = await touch(['app', 'quorum.exe']);
    await touch(['app', 'sidecar', 'quorum_sidecar.exe']);
    final spec = await SidecarLauncher.resolve(
      environment: {'QUORUM_SIDECAR_EXE': join([tmp.path, 'does', 'not', 'exist.exe'])},
      appExecutable: appExe.path,
      searchStart: tmp,
      bundledWorkDir: Directory(join([tmp.path, 'work'])),
    );
    expect(spec, isNotNull);
    expect(spec!.bundled, isTrue);
    expect(spec.executable, join([tmp.path, 'app', 'sidecar', 'quorum_sidecar.exe']));
  });

  test('bundled exe next to the app binary is found (packaged layout)', () async {
    final appExe = await touch(['install', 'quorum.exe']);
    final side = await touch(['install', 'sidecar', 'quorum_sidecar.exe']);
    final spec = await SidecarLauncher.resolve(
      environment: const {},
      appExecutable: appExe.path,
      searchStart: tmp, // no .venv anywhere under tmp
      bundledWorkDir: Directory(join([tmp.path, 'appdata'])),
    );
    expect(spec, isNotNull);
    expect(spec!.bundled, isTrue);
    expect(spec.executable, side.path);
    expect(spec.args, isEmpty);
    expect(spec.lockKey, side.path);
    // The bundled sidecar must NOT run from the (possibly read-only) install dir.
    expect(spec.workingDirectory, isNot(contains('install')));
  });

  test('dev fallback walks up to the repo .venv and runs -m services.api', () async {
    await touch(['repo', '.venv', 'Scripts', 'python.exe']);
    final nested = Directory(join([tmp.path, 'repo', 'apps', 'desktop']));
    await nested.create(recursive: true);
    final spec = await SidecarLauncher.resolve(
      environment: const {},
      appExecutable: join([tmp.path, 'elsewhere', 'app.exe']), // no bundled sidecar
      searchStart: nested,
    );
    expect(spec, isNotNull);
    expect(spec!.bundled, isFalse);
    expect(spec.executable, join([tmp.path, 'repo', '.venv', 'Scripts', 'python.exe']));
    expect(spec.args, ['-m', 'services.api']);
    expect(spec.workingDirectory, join([tmp.path, 'repo']));
    expect(spec.imageName, 'python.exe');
    expect(spec.lockKey, join([tmp.path, 'repo']));
  });

  test('bundled beats the dev .venv when both exist (packaged app on a dev machine)', () async {
    final appExe = await touch(['install', 'quorum.exe']);
    await touch(['install', 'sidecar', 'quorum_sidecar.exe']);
    await touch(['repo', '.venv', 'Scripts', 'python.exe']);
    final spec = await SidecarLauncher.resolve(
      environment: const {},
      appExecutable: appExe.path,
      searchStart: Directory(join([tmp.path, 'repo'])),
      bundledWorkDir: Directory(join([tmp.path, 'appdata'])),
    );
    expect(spec!.bundled, isTrue);
  });

  test('resolves to null when neither a bundled exe nor a .venv exists', () async {
    final spec = await SidecarLauncher.resolve(
      environment: const {},
      appExecutable: join([tmp.path, 'app', 'quorum.exe']),
      searchStart: tmp,
    );
    expect(spec, isNull);
  });
}
