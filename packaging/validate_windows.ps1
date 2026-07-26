[CmdletBinding()]
param(
    [string]$PortableZip = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$WindowsRoot = Join-Path $Root "WINDOWS\FindMyFlipperWindows"
$ProjectRoot = Join-Path $WindowsRoot "FindMyFlipperWindows"
$ProjectPath = Join-Path $ProjectRoot "FindMyFlipperWindows.vcxproj"
$SolutionPath = Join-Path $WindowsRoot "FindMyFlipperWindows.sln"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "VALIDATION FAILED: $Message" }
    Write-Host "PASS: $Message"
}

Write-Host "Validating native project and source..."
[xml]$Project = Get-Content $ProjectPath -Raw
Assert-True ($null -ne $Project.Project) "project XML is valid"
Assert-True (Test-Path $SolutionPath) "solution exists"
$SolutionProject = Join-Path $WindowsRoot "FindMyFlipperWindows\FindMyFlipperWindows.vcxproj"
Assert-True (Test-Path $SolutionProject) "solution project path is valid"

$ProjectText = Get-Content $ProjectPath -Raw
Assert-True ($ProjectText.Contains("<UseWinUI>true</UseWinUI>")) "WinUI is enabled"
Assert-True ($ProjectText.Contains("<EnableNativePackageReferenceSupport>true</EnableNativePackageReferenceSupport>")) "native PackageReference support is enabled"
Assert-True ($ProjectText.Contains("<LanguageStandard>stdcpp20</LanguageStandard>")) "C++20 mode is enabled"
Assert-True (-not ($ProjectText -match '(?i)(^|\s)/await(?:\s|$)')) "obsolete /await is absent"
Assert-True ($ProjectText.Contains('<Midl Include="MainWindow.idl">')) "MainWindow.idl is registered with MIDL"
Assert-True ($ProjectText.Contains('<ApplicationIcon>Assets\FindMyFlipper.ico</ApplicationIcon>')) "native executable icon is configured"
Assert-True ((Get-Content (Join-Path $ProjectRoot "MainWindow.idl") -Raw).Contains("runtimeclass MainWindow : Microsoft.UI.Xaml.Window")) "MainWindow runtime class is declared"
Assert-True (-not ((Get-Content (Join-Path $ProjectRoot "App.xaml.cpp") -Raw).Contains('#include "App.xaml.g.cpp"'))) "invalid App.xaml.g.cpp include is absent"

@(
    "Assets\FindMyFlipper.ico",
    "Assets\icon.png",
    "Assets\flipper-zero.png",
    "Map\map.html",
    "Map\leaflet.css",
    "Map\leaflet.js",
    "Map\LEAFLET_LICENSE.txt"
) | ForEach-Object { Assert-True (Test-Path (Join-Path $ProjectRoot $_)) "asset exists: $_" }

$ProfileSource = Get-Content (Join-Path $ProjectRoot "Services\ProfileStore.cpp") -Raw
Assert-True (-not ($ProfileSource -match 'SetNamedValue\([^\r\n]*(private.?key|password|second.?factor)')) "profile serialization does not write secrets"
Assert-True ($ProfileSource.Contains('credentialTarget')) "profile serialization stores only the credential target"
$BluetoothSource = Get-Content (Join-Path $ProjectRoot "Services\BluetoothManager.cpp") -Raw
Assert-True ($BluetoothSource.Contains('lowered.find(L"flipper")')) "BLE Flipper name filtering is present"
Assert-True ($BluetoothSource.Contains('m_devices[record.address] = record')) "BLE advertisements deduplicate by address"
Assert-True ($BluetoothSource.Contains('BluetoothAddressType::Random')) "BLE random addresses are handled"
Assert-True ($BluetoothSource.Contains('args.IsConnectable()')) "BLE connectability is tracked"
Assert-True ($BluetoothSource.Contains('GetDeviceSelectorFromPairingState(true)')) "paired BLE devices are included"
Assert-True ($BluetoothSource.Contains('GattSession::FromDeviceIdAsync')) "BLE GATT session lifetime is maintained"
Assert-True ($BluetoothSource.Contains('HandleUnexpectedDisconnect') -and $BluetoothSource.Contains('m_reconnectScheduled')) "BLE transient disconnects schedule one saved-device reconnect"
Assert-True ($BluetoothSource.Contains('FirmwareRevision') -and $BluetoothSource.Contains('SoftwareRevision')) "BLE firmware revision characteristics are read"
Assert-True (Test-Path (Join-Path $ProjectRoot "Map\map.html")) "local map asset is available"
$MapSource = Get-Content (Join-Path $ProjectRoot "Map\map.html") -Raw
@('data-filter="live"', 'data-filter="1"', 'data-filter="6"', 'data-filter="24"', 'data-filter="168"', 'data-filter="720"') | ForEach-Object {
    Assert-True ($MapSource.Contains($_)) "map timeline includes $_"
}
Assert-True ($MapSource.Contains('customStart') -and $MapSource.Contains('customEnd')) "map supports a custom report timeline"
Assert-True ($MapSource.Contains('data-style="light"') -and $MapSource.Contains('data-style="dark"') -and $MapSource.Contains('data-style="terrain"') -and $MapSource.Contains('data-style="satellite"')) "map includes light, dark, terrain, and satellite modes"
Assert-True ($MapSource.Contains("postMessage('refreshReports')")) "map report menu can request a native refresh"
Assert-True ($MapSource.Contains('#mapTools{position:absolute')) "map tools are anchored over the map"
Assert-True ($MapSource.Contains('id="locate"') -and $MapSource.Contains('id="zoomIn"') -and $MapSource.Contains('id="zoomOut"') -and $MapSource.Contains('id="styles"')) "map control expands to four tools"
Assert-True ($MapSource.Contains('id="openMaps"')) "map can open the latest location externally"

$ResourceSource = Get-Content (Join-Path $ProjectRoot "Version.rc") -Raw
Assert-True ($ResourceSource.Contains('IDI_FINDMYFLIPPER ICON')) "window and taskbar icon resource is embedded"
$AuthSource = Get-Content (Join-Path $Root "MAC\FindMyFlipperMac\Backend\findmy_gateway\auth.py") -Raw
Assert-True ($AuthSource.Contains('redirect_stdout') -and $AuthSource.Contains('redirect_stderr')) "Apple auth tolerates closed GUI pipes"
$FlipperBridge = Get-Content (Join-Path $Root "MAC\FindMyFlipperMac\Backend\findmy_gateway\platform_bridge.py") -Raw
$BackendServer = Get-Content (Join-Path $Root "MAC\FindMyFlipperMac\Backend\findmy_gateway\server.py") -Raw
Assert-True ($FlipperBridge.Contains('verify_hashed_adv_key') -and $BackendServer.Contains('/desktop/flipper/keys/verify')) "microSD active identity verification is implemented"

Write-Host "Validating Python backend..."
$Python = Get-Command py -ErrorAction SilentlyContinue
if (-not $Python) { $Python = Get-Command python -ErrorAction SilentlyContinue }
Assert-True ($null -ne $Python) "Python is available for validation"
$PythonFiles = Get-ChildItem (Join-Path $WindowsRoot "Backend"), (Join-Path $Root "MAC\FindMyFlipperMac\Backend\findmy_gateway") -Filter *.py -File -Recurse | Select-Object -ExpandProperty FullName
if ($Python.Name -eq "py.exe") { & $Python.Source -3 -m py_compile @PythonFiles } else { & $Python.Source -m py_compile @PythonFiles }
Assert-True ($LASTEXITCODE -eq 0) "backend Python syntax is valid"
$BackendRoot = Join-Path $Root "MAC\FindMyFlipperMac\Backend"
$ImportCode = "import sys; sys.path.insert(0, r'$BackendRoot'); import findmy_gateway; from findmy_gateway.server import app; assert app"
if ($Python.Name -eq "py.exe") { & $Python.Source -3 -c $ImportCode } else { & $Python.Source -c $ImportCode }
Assert-True ($LASTEXITCODE -eq 0) "findmy_gateway imports successfully"

if ($PortableZip) {
    Write-Host "Validating portable package..."
    Assert-True (Test-Path $PortableZip) "portable ZIP exists"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $Archive = [IO.Compression.ZipFile]::OpenRead((Resolve-Path $PortableZip))
    try {
        $Entries = @($Archive.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
        @("FindMyFlipper.exe", "FindMyFlipper.pri", "FindMyFlipperBackend.exe", "FindMyFlipperAnisette.exe", "Map/map.html", "Map/leaflet.css", "Map/leaflet.js", "Map/LEAFLET_LICENSE.txt", "Assets/FindMyFlipper.ico") | ForEach-Object {
            Assert-True ($Entries -contains $_) "portable ZIP contains $_"
        }
        $Forbidden = @($Entries | Where-Object { $_ -match '(?i)\.(pdb|obj|tlog|ilk|exp|lib|vcxproj)$|(^|/)(obj|Generated Files|\.venv-packaging|backend-build)/' })
        Assert-True ($Forbidden.Count -eq 0) "portable ZIP excludes development artifacts"
    }
    finally { $Archive.Dispose() }
}

Write-Host "ALL WINDOWS VALIDATIONS PASSED"
