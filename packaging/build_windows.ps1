[CmdletBinding()]
param(
    [ValidateSet("x64", "ARM64")]
    [string]$Platform = "x64",
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Solution = Join-Path $Root "WINDOWS\FindMyFlipperWindows\FindMyFlipperWindows.sln"
$ProjectRoot = Join-Path $Root "WINDOWS\FindMyFlipperWindows\FindMyFlipperWindows"
$VsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$SourceRevision = "windows-native-build-fix-24"

$RequiredSourceMarkers = @(
    @{ Path = Join-Path $ProjectRoot "FindMyFlipperWindows.vcxproj"; Marker = "<UseWinUI>true</UseWinUI>" },
    @{ Path = Join-Path $ProjectRoot "FindMyFlipperWindows.vcxproj"; Marker = "<EnableNativePackageReferenceSupport>true</EnableNativePackageReferenceSupport>" },
    @{ Path = Join-Path $ProjectRoot "FindMyFlipperWindows.vcxproj"; Marker = "<LanguageStandard>stdcpp20</LanguageStandard>" },
    @{ Path = Join-Path $ProjectRoot "FindMyFlipperWindows.vcxproj"; Marker = '<Midl Include="MainWindow.idl">' },
    @{ Path = Join-Path $ProjectRoot "MainWindow.idl"; Marker = "runtimeclass MainWindow : Microsoft.UI.Xaml.Window" },
    @{ Path = Join-Path $ProjectRoot "MainWindow.xaml.h"; Marker = "namespace winrt::FindMyFlipperWindows::factory_implementation" },
    @{ Path = Join-Path $ProjectRoot "MainWindow.xaml.cpp"; Marker = '#include "MainWindow.g.cpp"' },
    @{ Path = Join-Path $ProjectRoot "pch.h"; Marker = "Windows.Foundation.Collections.h" },
    @{ Path = Join-Path $ProjectRoot "pch.h"; Marker = "#undef GetCurrentTime" },
    @{ Path = Join-Path $ProjectRoot "Services\BluetoothManager.cpp"; Marker = "using BluetoothDeviceRecord = FindMyFlipper::Models::BluetoothDevice;" }
)

foreach ($Requirement in $RequiredSourceMarkers) {
    if (-not (Test-Path $Requirement.Path)) {
        throw "Windows source is incomplete: $($Requirement.Path) is missing. Extract the latest archive into a new empty folder."
    }
    if (-not (Select-String -Path $Requirement.Path -SimpleMatch $Requirement.Marker -Quiet)) {
        throw "Stale Windows source detected in $($Requirement.Path). Extract the latest archive into a new empty folder."
    }
}

$ProjectText = Get-Content (Join-Path $ProjectRoot "FindMyFlipperWindows.vcxproj") -Raw
if ($ProjectText.Contains("<WinUISDKReferences>false</WinUISDKReferences>")) {
    throw "Stale WinUI project configuration detected. Extract the latest archive into a new empty folder."
}

if ($ProjectText -match '(?i)(^|\s)/await(?:\s|$)') {
    throw "Obsolete /await compiler option detected. This project uses standard C++20 coroutines and must not enable experimental coroutine mode."
}

if (Select-String -Path (Join-Path $ProjectRoot "App.xaml.cpp") -SimpleMatch '#include "App.xaml.g.cpp"' -Quiet) {
    throw "Invalid App.xaml.g.cpp include detected. App generated code is provided by the WinUI build pipeline."
}

Write-Host "FindMyFlipper Windows source revision: $SourceRevision"

if (-not (Test-Path $VsWhere)) {
    throw "Visual Studio 2026 version 18.7 or newer with the C++ WinUI app development tools is required. Install it, then rerun this script."
}

$VsInstallPath = & $VsWhere -latest -products * `
    -requires Microsoft.Component.MSBuild Microsoft.VisualStudio.Component.WindowsAppSdkSupport.Cpp `
    -property installationPath
if (-not $VsInstallPath) {
    throw "No Visual Studio installation with C++ WinUI app development tools was found. Modify Visual Studio and install WinUI application development > C++ WinUI app development tools."
}

$VsVersionText = & $VsWhere -latest -products * `
    -requires Microsoft.Component.MSBuild Microsoft.VisualStudio.Component.WindowsAppSdkSupport.Cpp `
    -property installationVersion
$VsVersion = [Version]$VsVersionText
if ($VsVersion.Major -lt 18 -or ($VsVersion.Major -eq 18 -and $VsVersion.Minor -lt 7)) {
    throw "Visual Studio 2026 version 18.7 or newer is required because this native C++ project uses NuGet PackageReference support."
}
$PlatformToolset = "v145"
$MSBuild = Join-Path $VsInstallPath "MSBuild\Current\Bin\MSBuild.exe"
if (-not (Test-Path $MSBuild)) { throw "MSBuild was not found at $MSBuild." }

Write-Host "Visual Studio: $VsVersionText"
Write-Host "C++ platform toolset: $PlatformToolset"

Write-Host "Restoring Windows App SDK packages..."
& $MSBuild $Solution /t:Restore /m /p:Platform=$Platform /p:Configuration=$Configuration /p:PlatformToolset=$PlatformToolset /p:EnableNativePackageReferenceSupport=true
if ($LASTEXITCODE -ne 0) { throw "NuGet restore failed." }

Write-Host "Building native C++/WinRT WinUI 3 app..."
& $MSBuild $Solution /m /p:Platform=$Platform /p:Configuration=$Configuration /p:PlatformToolset=$PlatformToolset /p:EnableNativePackageReferenceSupport=true /p:WindowsAppSDKSelfContained=true
if ($LASTEXITCODE -ne 0) { throw "Native Windows build failed." }

$Output = Join-Path $Root "WINDOWS\FindMyFlipperWindows\build\$Platform\$Configuration"
if (-not (Test-Path (Join-Path $Output "FindMyFlipperWindows.exe"))) {
    throw "Expected FindMyFlipperWindows.exe was not produced at $Output"
}

Write-Host "Native app output: $Output"
