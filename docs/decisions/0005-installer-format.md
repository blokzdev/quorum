# ADR 0005 — Windows installer format: Inno Setup

- **Status:** Accepted (2026-07-04) — P2.6b
- **Context:** Phase 2 P2.6b ([phase-2-plan.md](../phase-2-plan.md#p26--installer-packaging--flutter-ci-depends-on-p20-build-the-distributable)); the app must ship as a self-contained Windows installer.
- **Deciders:** ganesh (founder) chose from a recommended shortlist; desktop track validated on the real machine.
- **Validation:** built + installed + launched + real-run + uninstalled on the dev machine (see the P2.6b close-out in the plan).

## Context

The Quorum desktop app is a Flutter runner that **spawns a bundled frozen Python sidecar as a child
process** and manages that child's lifecycle directly: it reaps hot-restart zombies via `tasklist`
(filtered by image name) + `taskkill /T /F`, and the sidecar self-exits through a `QUORUM_PARENT_PID`
watchdog. It also writes report trees + settings to `%LOCALAPPDATA%\Quorum`. The installer must be
per-user (no admin/UAC), self-contained (the release runner links MSVCP140 / VCRUNTIME140 / VCRUNTIME140_1
— empirically the only non-UCRT deps; ATL is statically linked in `flutter_secure_storage_windows`), and
must not interfere with the child-process + process-management model.

## Decision

Package with **Inno Setup 6** (per-user install to `%LOCALAPPDATA%\Programs\Quorum`,
`PrivilegesRequired=lowest`). Bundle the frozen sidecar at `<appDir>\sidecar\quorum_sidecar.exe` (where
`SidecarLauncher.resolve()` looks) and the three VC++ CRT DLLs app-local. Validate the pipeline with a
**debug self-signed cert**; production keystore code-signing is **Phase 3**.

## Consequences

- **+** Full Win32 execution — no app-container virtualization to fight the child-process spawn,
  `taskkill`/`tasklist` reaping, or `%LOCALAPPDATA%` writes. Simplest path to a working self-contained,
  no-admin installer. Battle-tested, free, scriptable (`packaging/build_installer.ps1`).
- **−** No built-in auto-update channel (deferred to Phase 3 anyway) and not Microsoft-Store-ready.
- The frozen sidecar must bundle the provider LLM stack explicitly (they are lazily imported, so
  PyInstaller's static analysis misses them) — see `packaging/quorum_sidecar.spec`.

## Alternatives considered

- **MSIX** — modern, Store-ready, clean update channel. **Rejected for P2.6b:** its app-container
  virtualization (virtualized filesystem/registry, restricted process ops) can interfere with spawning
  a bundled child and with the `taskkill`/`tasklist` model we rely on, and it adds signing friction even
  for sideloading. Revisit for Store distribution in a later phase.
- **WiX / MSI** — powerful, enterprise/Group-Policy deployment. **Rejected:** heavy XML authoring,
  overkill for a debug/self-signed validation build.
