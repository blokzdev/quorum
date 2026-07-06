# Quorum packaging (P2.6b)

Builds the **self-contained Windows installer**: the Flutter release app + the bundled frozen Python
sidecar + the app-local VC++ CRT, packaged with **Inno Setup** into a per-user installer that runs on
a clean machine with no admin rights and no separate VC++ redist.

> Production code-signing is **deferred to V2** ([ADR 0007](../docs/decisions/0007-defer-code-signing-to-v2.md));
> the 1.0.0 GA (Phase 4) ships **unsigned**, and this pipeline validates with a **debug / self-signed** cert.
> Installer format decision: **Inno Setup** (not MSIX/WiX) — chosen because the app
> spawns a bundled child process and manages it via `taskkill`/`tasklist`, which MSIX's app-container
> virtualization would fight. Sidecar bundling: PyInstaller **onedir**, see
> [ADR 0002](../docs/decisions/0002-sidecar-bundling.md).

## Layout

| File | Role |
| --- | --- |
| `quorum_sidecar.spec` | Production PyInstaller spec — freezes the **full engine** into `quorum_sidecar.exe` (the name `SidecarLauncher.resolve()` spawns). Promoted from the proven P2.0 spike. |
| `sidecar_entry.py` | PyInstaller entry shim (`≈ python -m services.api`). |
| `installer/quorum.iss` | Inno Setup script — per-user install to `%LOCALAPPDATA%\Programs\Quorum`, shortcuts, uninstaller. |
| `build_installer.ps1` | Orchestrator: freeze → flutter release → assemble staging → (sign) → ISCC → (sign Setup). |

The installer lays the sidecar into `<appDir>\sidecar\quorum_sidecar.exe`; the app writes report trees
+ settings to `%LOCALAPPDATA%\Quorum` (separate from the install dir, preserved on uninstall).

## Build

```powershell
# Full clean build (requires: repo .venv, Flutter, VS 2022 C++ toolchain, Inno Setup 6):
powershell -File packaging\build_installer.ps1 -Version 1.0.0 -Sign

# Fast iteration (reuse an existing freeze + release):
powershell -File packaging\build_installer.ps1 -SkipFreeze -SkipFlutter
```

Output: `packaging\output\Quorum-Setup-<version>.exe`. All build artifacts (`staging/`, `dist/`,
`build/`, `output/`) are gitignored.

## App-local runtime deps

`dumpbin /dependents` on the release runner shows the only non-UCRT imports are `MSVCP140.dll`,
`VCRUNTIME140.dll`, `VCRUNTIME140_1.dll` (the `api-ms-win-crt-*` are the Universal CRT, shipped with
Windows 10/11). ATL (used by `flutter_secure_storage_windows`) is statically linked, so no `atls.dll`
is needed. The build copies those three CRT DLLs app-local from the VS `VC143.CRT` redist.
