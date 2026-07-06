<#
.SYNOPSIS
  Build the Quorum Windows installer (P2.6b): freeze the sidecar, build the Flutter release, assemble
  a self-contained staging tree (runner + bundled sidecar + app-local VC++ CRT), optionally sign, and
  compile a per-user Inno Setup installer.

.NOTES
  Run from anywhere; paths resolve relative to the repo. Production keystore signing is Phase 3 -- the
  -Sign switch here uses a debug self-signed cert to validate the pipeline only.

.EXAMPLE
  # Full clean build:
  powershell -File packaging\build_installer.ps1 -Version 0.2.0 -Sign
  # Fast iteration reusing existing freeze + release:
  powershell -File packaging\build_installer.ps1 -SkipFreeze -SkipFlutter
#>
param(
  [string]$Version = "",   # default: derived from apps/desktop/pubspec.yaml (single source of truth)
  [switch]$SkipFreeze,
  [switch]$SkipFlutter,
  [switch]$Sign
)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$pkg = $PSScriptRoot

if (-not $Version) {
  $pubspec = Get-Content (Join-Path $repo "apps\desktop\pubspec.yaml")
  foreach ($l in $pubspec) { if ($l -match '^version:\s*([0-9]+(\.[0-9]+)*)') { $Version = $Matches[1]; break } }
  if (-not $Version) { throw "could not derive version from pubspec.yaml (pass -Version)" }
}
Write-Host "== Quorum installer build (v$Version) ==" -ForegroundColor Cyan
Write-Host "repo: $repo"

# Prefer the repo .venv (dev machines); fall back to the ambient `python` on CI / clean checkouts where
# there is no .venv (the packaging workflow installs the engine + PyInstaller into the runner's system
# Python via setup-python + pip). Without this the freeze step dies with ".venv\Scripts\python.exe not
# recognized" (P4.3a — surfaced by the first real packaging.yml e2e run).
$venvPy = Join-Path $repo ".venv\Scripts\python.exe"
if (-not (Test-Path $venvPy)) {
  $venvPy = (Get-Command python -ErrorAction SilentlyContinue).Source
  if (-not $venvPy) { throw "no Python found: neither .venv\Scripts\python.exe nor a `python` on PATH" }
  Write-Host "    (no .venv — using ambient python: $venvPy)" -ForegroundColor DarkYellow
}
$staging = Join-Path $pkg "staging"
$distSidecar = Join-Path $pkg "dist\quorum_sidecar"
$release = Join-Path $repo "apps\desktop\build\windows\x64\runner\Release"

# --- 1. Freeze the sidecar (onedir) -----------------------------------------------------------------
if (-not $SkipFreeze) {
  Write-Host "`n[1/5] Freezing sidecar (PyInstaller onedir)..." -ForegroundColor Yellow
  & $venvPy -m PyInstaller (Join-Path $pkg "quorum_sidecar.spec") `
    --distpath (Join-Path $pkg "dist") --workpath (Join-Path $pkg "build") --noconfirm
  if ($LASTEXITCODE -ne 0) { throw "PyInstaller freeze failed ($LASTEXITCODE)" }
} else {
  Write-Host "`n[1/5] Skipping freeze (reusing $distSidecar)" -ForegroundColor DarkYellow
  $ex = Join-Path $distSidecar "quorum_sidecar.exe"
  if (Test-Path $ex) { Write-Warning "reusing sidecar frozen $((Get-Item $ex).LastWriteTime) -- do NOT -SkipFreeze for a release build" }
}
if (-not (Test-Path (Join-Path $distSidecar "quorum_sidecar.exe"))) {
  throw "frozen sidecar missing: $distSidecar\quorum_sidecar.exe"
}

# --- 2. Build the Flutter release -------------------------------------------------------------------
if (-not $SkipFlutter) {
  Write-Host "`n[2/5] Building Flutter release..." -ForegroundColor Yellow
  Push-Location (Join-Path $repo "apps\desktop")
  try { & flutter build windows --release --build-name=$Version; if ($LASTEXITCODE -ne 0) { throw "flutter build failed ($LASTEXITCODE)" } }
  finally { Pop-Location }
} else {
  Write-Host "`n[2/5] Skipping Flutter build (reusing $release)" -ForegroundColor DarkYellow
  if (Test-Path (Join-Path $release "quorum.exe")) { Write-Warning "reusing app built $((Get-Item (Join-Path $release 'quorum.exe')).LastWriteTime) -- do NOT -SkipFlutter for a release build" }
}
if (-not (Test-Path (Join-Path $release "quorum.exe"))) { throw "release runner missing: $release\quorum.exe" }

# --- 3. Assemble the staging tree -------------------------------------------------------------------
Write-Host "`n[3/5] Assembling staging tree..." -ForegroundColor Yellow
if (Test-Path $staging) { Remove-Item -Recurse -Force $staging }
New-Item -ItemType Directory -Force -Path $staging | Out-Null
Copy-Item -Recurse -Force (Join-Path $release "*") $staging
# Bundle the frozen sidecar under sidecar\ (matches SidecarLauncher.resolve()).
New-Item -ItemType Directory -Force -Path (Join-Path $staging "sidecar") | Out-Null
Copy-Item -Recurse -Force (Join-Path $distSidecar "*") (Join-Path $staging "sidecar")

# App-local VC++ CRT so the app runs on a clean machine (empirically the only non-UCRT runtime dep;
# ATL is statically linked into the secure-storage plugin). Discover across ANY VS 2022 edition
# (Community/Professional/Enterprise/BuildTools), newest by [version] order (NOT lexical: 14.44 > 14.9).
$vsRoot = "C:\Program Files\Microsoft Visual Studio\2022"
$crtDir = $null
if (Test-Path $vsRoot) {
  $candidates = foreach ($ed in (Get-ChildItem $vsRoot -Directory)) {
    $redist = Join-Path $ed.FullName "VC\Redist\MSVC"
    if (Test-Path $redist) {
      foreach ($ver in (Get-ChildItem $redist -Directory)) {
        $crt = Join-Path $ver.FullName "x64\Microsoft.VC143.CRT"
        if (Test-Path $crt) { [pscustomobject]@{ Ver = [version]$ver.Name; Path = $crt } }
      }
    }
  }
  $crtDir = ($candidates | Sort-Object Ver -Descending | Select-Object -First 1).Path
}
if (-not $crtDir) {
  # CI / no VS redist folder: the same CRT DLLs ship in System32 (installed with the VC++ runtime).
  # Bundling those app-local is standard + works on a clean machine (P4.3a — CI has no VS redist path).
  $sys32 = Join-Path $env:WINDIR "System32"
  $crtDlls = @("msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll")
  $missing = $crtDlls | Where-Object { -not (Test-Path (Join-Path $sys32 $_)) }
  if ($missing.Count -eq 0) {
    $crtDir = $sys32
    Write-Host "    (no VS 2022 redist — bundling CRT from System32)" -ForegroundColor DarkYellow
  } else {
    throw "VC143.CRT not found: no VS 2022 redist under $vsRoot, and System32 lacks $($missing -join ', ')"
  }
}
foreach ($dll in @("msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll")) {
  Copy-Item -Force (Join-Path $crtDir $dll) $staging
}
Write-Host "    staged runner + sidecar\ + CRT from $crtDir"

# --- 4. Sign the app binaries (optional; debug self-signed) -----------------------------------------
function Get-SignTool {
  $st = Get-ChildItem "C:\Program Files (x86)\Windows Kits\10\bin\*\x64\signtool.exe" -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1
  if (-not $st) { throw "signtool.exe not found (Windows SDK)" }
  return $st.FullName
}
$subject = "Quorum Dev (Self-Signed)"
if ($Sign) {
  Write-Host "`n[4/5] Signing (debug self-signed cert)..." -ForegroundColor Yellow
  $cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -eq "CN=$subject" } | Select-Object -First 1
  if (-not $cert) {
    Write-Host "    creating self-signed code-signing cert 'CN=$subject'"
    $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject "CN=$subject" `
      -CertStoreLocation Cert:\CurrentUser\My -KeyUsage DigitalSignature -KeySpec Signature
  }
  $signtool = Get-SignTool
  foreach ($f in @((Join-Path $staging "quorum.exe"), (Join-Path $staging "sidecar\quorum_sidecar.exe"))) {
    & $signtool sign /sha1 $cert.Thumbprint /fd SHA256 $f
    if ($LASTEXITCODE -ne 0) { throw "signtool failed on $f" }
  }
} else { Write-Host "`n[4/5] Skipping signing (no -Sign)" }

# --- 5. Compile the installer -----------------------------------------------------------------------
Write-Host "`n[5/5] Compiling Inno Setup installer..." -ForegroundColor Yellow
$iscc = @(
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
  "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
  "C:\Program Files\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
# Fallbacks if Inno was installed somewhere non-standard (choco/registry): PATH, then the uninstall key.
if (-not $iscc) { $iscc = (Get-Command ISCC.exe -ErrorAction SilentlyContinue).Source }
if (-not $iscc) {
  $reg = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1"
  $loc = (Get-ItemProperty $reg -ErrorAction SilentlyContinue).InstallLocation
  if ($loc) { $cand = Join-Path $loc "ISCC.exe"; if (Test-Path $cand) { $iscc = $cand } }
}
if (-not $iscc) { throw "ISCC.exe not found (Inno Setup 6)" }
New-Item -ItemType Directory -Force -Path (Join-Path $pkg "output") | Out-Null
& $iscc "/DStagingDir=$staging" "/DAppVersion=$Version" (Join-Path $pkg "installer\quorum.iss")
if ($LASTEXITCODE -ne 0) { throw "ISCC failed ($LASTEXITCODE)" }

$setup = Join-Path $pkg "output\Quorum-Setup-$Version.exe"
if ($Sign -and (Test-Path $setup)) {
  $cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -eq "CN=$subject" } | Select-Object -First 1
  & (Get-SignTool) sign /sha1 $cert.Thumbprint /fd SHA256 $setup
}
Write-Host "`n== DONE ==" -ForegroundColor Green
Write-Host "installer: $setup"
