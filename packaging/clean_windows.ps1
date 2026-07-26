[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$WindowsRoot = Join-Path $Root "WINDOWS\FindMyFlipperWindows"

@(
    (Join-Path $WindowsRoot "build"),
    (Join-Path $WindowsRoot "obj"),
    (Join-Path $WindowsRoot "FindMyFlipperWindows\Generated Files"),
    (Join-Path $WindowsRoot ".venv-packaging"),
    (Join-Path $WindowsRoot "backend-build"),
    (Join-Path $WindowsRoot "backend-dist"),
    (Join-Path $Root "release")
) | ForEach-Object {
    if (Test-Path $_) { Remove-Item $_ -Recurse -Force }
}

Write-Host "Windows build artifacts removed."
