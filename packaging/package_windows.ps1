[CmdletBinding()]
param(
    [ValidateSet("x64", "ARM64")]
    [string]$Platform = "x64",
    [switch]$SkipNativeBuild,
    [switch]$SkipBackendBuild,
    [string]$PackagingPython
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$WindowsRoot = Join-Path $Root "WINDOWS\FindMyFlipperWindows"
$BackendRoot = Join-Path $Root "MAC\FindMyFlipperMac\Backend"
$ReleaseRoot = Join-Path $Root "release"
$AppRelease = Join-Path $ReleaseRoot "FindMyFlipper"
$RuntimeRelease = Join-Path $AppRelease "runtime"
$BackendDist = Join-Path $WindowsRoot "backend-dist"
$NativeOutput = Join-Path $WindowsRoot "build\$Platform\Release"
$VersionHeader = Join-Path $PSScriptRoot "version.h"

$VersionParts = @{}
Get-Content $VersionHeader | ForEach-Object {
    if ($_ -match '^#define FINDMYFLIPPER_VERSION_(MAJOR|MINOR|PATCH|BUILD)\s+(\d+)$') {
        $VersionParts[$Matches[1]] = $Matches[2]
    }
}
foreach ($Part in "MAJOR", "MINOR", "PATCH", "BUILD") {
    if (-not $VersionParts.ContainsKey($Part)) { throw "Missing FINDMYFLIPPER_VERSION_$Part in version.h" }
}
$Version = "$($VersionParts.MAJOR).$($VersionParts.MINOR).$($VersionParts.PATCH).$($VersionParts.BUILD)"

if (-not $SkipNativeBuild) {
    & (Join-Path $PSScriptRoot "clean_windows.ps1")
    & (Join-Path $PSScriptRoot "build_windows.ps1") -Platform $Platform -Configuration Release
} elseif (-not (Test-Path (Join-Path $NativeOutput "FindMyFlipperWindows.exe"))) {
    throw "-SkipNativeBuild requires an existing Release executable at $NativeOutput"
}

New-Item -ItemType Directory -Force -Path $AppRelease, $RuntimeRelease, $BackendDist | Out-Null

if (-not $SkipBackendBuild) {
Write-Host "Building self-contained backend executables..."
$PreviousErrorActionPreference = $ErrorActionPreference
if ($PackagingPython) {
    $VenvPython = (Resolve-Path $PackagingPython).Path
    & $VenvPython -c "import PyInstaller, fastapi, uvicorn, cryptography, serial"
    if ($LASTEXITCODE -ne 0) { throw "The supplied packaging Python is missing backend dependencies." }
} else {
    $Python = Get-Command py -ErrorAction SilentlyContinue
    if (-not $Python) { $Python = Get-Command python -ErrorAction SilentlyContinue }
    if (-not $Python) { throw "Python 3.11+ is required only to create the release package. End users do not need Python." }

    $Venv = Join-Path $WindowsRoot ".venv-packaging"
    & $Python.Source -3 -m venv $Venv 2>$null
    if ($LASTEXITCODE -ne 0) { & $Python.Source -m venv $Venv }
    $VenvPython = Join-Path $Venv "Scripts\python.exe"
    $ErrorActionPreference = "Continue"
    & $VenvPython -m pip install --disable-pip-version-check --upgrade pip pyinstaller
    if ($LASTEXITCODE -ne 0) {
        $ErrorActionPreference = $PreviousErrorActionPreference
        throw "PyInstaller installation failed."
    }
    & $VenvPython -m pip install --disable-pip-version-check -r (Join-Path $BackendRoot "requirements.txt")
    if ($LASTEXITCODE -ne 0) {
        $ErrorActionPreference = $PreviousErrorActionPreference
        throw "Backend dependency installation failed."
    }
}

$BackendEntry = Join-Path $WindowsRoot "Backend\backend_entry.py"
$AnisetteEntry = Join-Path $WindowsRoot "Backend\anisette_entry.py"
$VendorCores = Join-Path $BackendRoot "findmy_gateway\vendor\cores"
$VendorRoot = Split-Path -Parent $VendorCores
$Separator = [IO.Path]::PathSeparator

Push-Location $WindowsRoot
try {
    # PyInstaller reports normal progress on stderr. PowerShell must not turn
    # those informational lines into terminating NativeCommandError records;
    # the explicit exit-code checks below remain authoritative.
    $ErrorActionPreference = "Continue"
    # Use PyInstaller's one-directory layout.  The one-file bootloader must
    # unpack the complete cryptography/BLE stack on every launch and can be
    # delayed indefinitely by Windows real-time scanning.  Onedir remains
    # Python-independent, starts deterministically, and lets both helpers
    # share the same private runtime directory in the portable package.
    # Use the console bootloader for reliable Python 3.14 startup. The native
    # process manager always launches helpers with CREATE_NO_WINDOW, so no
    # console is presented to end users.
    & $VenvPython -m PyInstaller --noconfirm --clean --onedir --noconsole `
        --contents-directory BackendRuntime `
        --name FindMyFlipperBackend `
        --distpath $BackendDist --workpath (Join-Path $WindowsRoot "backend-build\gateway") `
        --paths $BackendRoot `
        --paths $VendorRoot `
        --add-data "$VendorCores${Separator}findmy_gateway/vendor/cores" `
        --hidden-import cores.pypush_gsa_icloud `
        --hidden-import cores.old_key_generation `
        $BackendEntry
    if ($LASTEXITCODE -ne 0) { throw "Backend executable build failed." }

    & $VenvPython -m PyInstaller --noconfirm --clean --onedir --noconsole `
        --contents-directory AnisetteRuntime `
        --name FindMyFlipperAnisette `
        --distpath $BackendDist --workpath (Join-Path $WindowsRoot "backend-build\anisette") `
        --paths $BackendRoot `
        --paths $VendorRoot `
        --add-data "$VendorCores${Separator}findmy_gateway/vendor/cores" `
        --hidden-import cores.pypush_gsa_icloud `
        --hidden-import cores.old_key_generation `
        $AnisetteEntry
    if ($LASTEXITCODE -ne 0) { throw "Anisette launcher build failed." }
}
finally {
    $ErrorActionPreference = $PreviousErrorActionPreference
    Pop-Location
}
}
else {
    Write-Host "Reusing previously built self-contained backend executables..."
    $GatewayBundleCheck = Join-Path $BackendDist "FindMyFlipperBackend"
    $AnisetteBundleCheck = Join-Path $BackendDist "FindMyFlipperAnisette"
    if (-not (Test-Path (Join-Path $GatewayBundleCheck "FindMyFlipperBackend.exe")) -or
        -not (Test-Path (Join-Path $GatewayBundleCheck "BackendRuntime")) -or
        -not (Test-Path (Join-Path $AnisetteBundleCheck "FindMyFlipperAnisette.exe")) -or
        -not (Test-Path (Join-Path $AnisetteBundleCheck "AnisetteRuntime"))) {
        throw "-SkipBackendBuild requires complete PyInstaller bundles under $BackendDist"
    }
}

Write-Host "Assembling portable application..."
Copy-Item (Join-Path $NativeOutput "*") $AppRelease -Recurse -Force
$GatewayBundle = Join-Path $BackendDist "FindMyFlipperBackend"
$AnisetteBundle = Join-Path $BackendDist "FindMyFlipperAnisette"
Copy-Item (Join-Path $GatewayBundle "FindMyFlipperBackend.exe") $AppRelease -Force
Copy-Item (Join-Path $AnisetteBundle "FindMyFlipperAnisette.exe") $AppRelease -Force
Copy-Item (Join-Path $GatewayBundle "BackendRuntime") $AppRelease -Recurse -Force
Copy-Item (Join-Path $AnisetteBundle "AnisetteRuntime") $AppRelease -Recurse -Force
Copy-Item $VersionHeader $RuntimeRelease -Force
Copy-Item (Join-Path $WindowsRoot "THIRD_PARTY_NOTICES.md") $AppRelease -Force
Copy-Item (Join-Path $PSScriptRoot "README_PACKAGING.md") $AppRelease -Force

# PyInstaller compiles the bundled modules itself. Source-tree bytecode caches can
# otherwise be carried through --add-data and are neither required nor suitable
# for the portable release payload.
Get-ChildItem -LiteralPath $AppRelease -Recurse -Directory -Filter "__pycache__" |
    Remove-Item -Recurse -Force
Get-ChildItem -LiteralPath $AppRelease -Recurse -File -Filter "*.pyc" |
    Remove-Item -Force

# Symbols, maps, logs, browser profiles, and link intermediates are retained in
# development locations, never shipped in the portable end-user package.
Get-ChildItem $AppRelease -Recurse -File | Where-Object {
    $_.Extension -in @(".pdb", ".map", ".log", ".obj", ".tlog", ".ilk", ".exp", ".lib")
} | Remove-Item -Force
Get-ChildItem $AppRelease -Recurse -Directory | Where-Object {
    $_.Name -like "*.WebView2" -or $_.Name -eq "EBWebView"
} | Sort-Object FullName -Descending | Remove-Item -Recurse -Force

$NativeExe = Join-Path $AppRelease "FindMyFlipperWindows.exe"
$FinalExe = Join-Path $AppRelease "FindMyFlipper.exe"
if (Test-Path $NativeExe) { Move-Item $NativeExe $FinalExe -Force }
if (-not (Test-Path $FinalExe)) { throw "Release executable is missing: $FinalExe" }

# C++ __FILE__ strings and linker debug records can silently disclose the
# packager's profile or checkout path even when no PDB is shipped.
$FinalExeText = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($FinalExe))
@($Root, $env:USERPROFILE) | Where-Object { $_ } | ForEach-Object {
    if ($FinalExeText.IndexOf($_, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "Release executable contains a private local build path. Enable Release path mapping and rebuild."
    }
}

# Unpackaged WinUI resolves the default PRI resource map from the executable
# base name. Keep the PRI name aligned when the release executable is renamed.
$NativePri = Join-Path $AppRelease "FindMyFlipperWindows.pri"
$FinalPri = Join-Path $AppRelease "FindMyFlipper.pri"
if (Test-Path $NativePri) { Move-Item $NativePri $FinalPri -Force }

$ForbiddenReleaseFiles = Get-ChildItem $AppRelease -Recurse -File | Where-Object {
    $_.Extension -in @(".keys", ".pdb", ".map", ".log", ".obj", ".tlog", ".ilk", ".exp", ".lib")
}
if ($ForbiddenReleaseFiles) {
    throw "Release assembly contains forbidden private or development files: $($ForbiddenReleaseFiles.FullName -join ', ')"
}
$ForbiddenReleaseDirectories = Get-ChildItem $AppRelease -Recurse -Directory | Where-Object {
    $_.Name -like "*.WebView2" -or $_.Name -eq "EBWebView" -or $_.Name -eq "__pycache__"
}
if ($ForbiddenReleaseDirectories) {
    throw "Release assembly contains forbidden runtime or cache directories: $($ForbiddenReleaseDirectories.FullName -join ', ')"
}

$Zip = Join-Path $ReleaseRoot "FindMyFlipperPortable.zip"
Compress-Archive -Path (Join-Path $AppRelease "*") -DestinationPath $Zip -CompressionLevel Optimal -Force

$InnoCandidates = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
)
$ISCC = $InnoCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($ISCC) {
    & $ISCC (Join-Path $PSScriptRoot "installer_config.iss") "/DRoot=$Root" "/DAppVersion=$Version"
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed." }
} else {
    Write-Warning "Inno Setup 6 was not found. Portable ZIP was created; installer creation was skipped."
}

Write-Host ""
Write-Host "FindMyFlipper Windows package complete:"
Write-Host "  Version: $Version"
Write-Host "  App folder: $AppRelease"
Write-Host "  Portable ZIP: $Zip"
$Installer = Join-Path $ReleaseRoot "FindMyFlipperSetup.exe"
if (Test-Path $Installer) { Write-Host "  Installer: $Installer" }
