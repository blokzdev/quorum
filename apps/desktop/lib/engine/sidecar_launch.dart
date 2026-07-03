import 'dart:io';

/// How to launch the engine sidecar: the resolved executable + args + cwd, plus the metadata the
/// endpoint's lifecycle hardening needs (which image name to stale-reap, what key to lock on).
///
/// Resolution order (first hit wins) — see [SidecarLauncher.resolve]:
/// 1. `QUORUM_SIDECAR_EXE` env var pointing at an existing file — the dev/test escape hatch (lets a
///    dev-built app drive the frozen exe, and makes this resolution unit-testable).
/// 2. The **bundled** frozen sidecar next to the app: `<appDir>/sidecar/quorum_sidecar.exe`
///    (the PyInstaller onedir output, shipped by the installer).
/// 3. The **dev** fallback: walk up from the working directory to the repo `.venv` and run
///    `python.exe -m services.api` (unchanged Phase-1 behavior).
class SidecarLaunchSpec {
  final String executable;
  final List<String> args;

  /// The sidecar's working directory. Dev mode: the repo root (so `-m services.api` resolves).
  /// Bundled mode: a per-user writable dir — the install dir may be read-only (Program Files) and
  /// the engine writes report trees relative to cwd.
  final String workingDirectory;

  /// The process image name (`python.exe` / `quorum_sidecar.exe`) the stale-reap must filter on —
  /// reaping by PID alone risks killing a stranger after PID reuse.
  final String imageName;

  /// Stable identity for the single-instance lockfile (dev: the repo root; bundled: the exe path).
  final String lockKey;

  final bool bundled;

  const SidecarLaunchSpec({
    required this.executable,
    required this.args,
    required this.workingDirectory,
    required this.imageName,
    required this.lockKey,
    required this.bundled,
  });
}

class SidecarLauncher {
  /// Resolve where the sidecar lives. Returns null when neither a bundled exe nor a dev `.venv`
  /// exists (the endpoint surfaces that as an [Exception] with a setup hint).
  ///
  /// All inputs are injectable for hermetic tests; production callers pass nothing.
  static Future<SidecarLaunchSpec?> resolve({
    Map<String, String>? environment,
    String? appExecutable,
    Directory? searchStart,
    Directory? bundledWorkDir,
  }) async {
    final env = environment ?? Platform.environment;
    final appExe = appExecutable ?? Platform.resolvedExecutable;

    // 1. Explicit override (dev/test escape hatch).
    final override = env['QUORUM_SIDECAR_EXE'];
    if (override != null && override.trim().isNotEmpty && await File(override).exists()) {
      return _bundledSpec(File(override), bundledWorkDir);
    }

    // 2. Bundled exe shipped next to the app binary.
    final appDir = File(appExe).parent.path;
    final bundledExe = File(_join([appDir, 'sidecar', 'quorum_sidecar.exe']));
    if (await bundledExe.exists()) {
      return _bundledSpec(bundledExe, bundledWorkDir);
    }

    // 3. Dev fallback: the repo .venv, walking upward like Phase 1 always has.
    final repoRoot = await _findRepoRoot(searchStart ?? Directory.current);
    if (repoRoot != null) {
      return SidecarLaunchSpec(
        executable: _join([repoRoot, '.venv', 'Scripts', 'python.exe']),
        args: const ['-m', 'services.api'],
        workingDirectory: repoRoot,
        imageName: 'python.exe',
        lockKey: repoRoot,
        bundled: false,
      );
    }
    return null;
  }

  static Future<SidecarLaunchSpec> _bundledSpec(File exe, Directory? workDirOverride) async {
    // The engine writes report trees relative to cwd, and the install dir may be read-only — use a
    // per-user app-data dir (creating it) rather than the exe's own directory.
    final workDir = workDirOverride ??
        Directory(_join([
          Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path,
          'Quorum',
        ]));
    if (!await workDir.exists()) {
      await workDir.create(recursive: true);
    }
    return SidecarLaunchSpec(
      executable: exe.path,
      args: const [],
      workingDirectory: workDir.path,
      imageName: exe.uri.pathSegments.last,
      lockKey: exe.path,
      bundled: true,
    );
  }

  static String _join(List<String> parts) => parts.join(Platform.pathSeparator);

  static Future<String?> _findRepoRoot(Directory start) async {
    var dir = start;
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
