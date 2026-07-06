; Inno Setup script for Quorum (P2.6b) — a per-user, self-contained Windows installer.
;
; Ships the Flutter release runner + the bundled frozen sidecar (staging\sidecar\quorum_sidecar.exe,
; where SidecarLauncher.resolve() finds it) + the app-local VC++ CRT DLLs, so it launches on a clean
; machine with no separate VC++ redist and no admin rights. Production code-signing is deferred to V2
; (ADR 0007); here we validate the pipeline with a debug/self-signed cert (see build_installer.ps1 -Sign).
;
; Compile:  ISCC.exe /DStagingDir=<abs staging path> /DAppVersion=1.0.0 quorum.iss
; (build_installer.ps1 passes these; the defaults below let a maintainer compile standalone.)

#ifndef StagingDir
  #define StagingDir "..\staging"
#endif
#ifndef AppVersion
  ; Fallback for a standalone ISCC compile; build_installer.ps1 always passes /DAppVersion from pubspec.
  #define AppVersion "1.0.0"
#endif
#define AppName "Quorum"
#define AppPublisher "Quorum"
#define AppExe "quorum.exe"

[Setup]
; A stable AppId keeps upgrades/uninstall coherent across versions — do NOT change it.
AppId={{B7E5B0A2-9C4D-4E7A-8F1B-2D6A3C5E9F04}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
; Per-user install: no admin, no UAC. Lands in %LOCALAPPDATA%\Programs\Quorum (writable, so the
; bundled sidecar + report trees have somewhere durable to live).
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#AppExe}
OutputDir=..\output
OutputBaseFilename=Quorum-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"

[Files]
; The entire assembled staging tree (runner + sidecar\ + CRT DLLs), recursively.
Source: "{#StagingDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; The sidecar writes report trees + settings under %LOCALAPPDATA%\Quorum (separate from the install
; dir). Leave user data in place on uninstall (do NOT delete it) — only the install dir is removed.
