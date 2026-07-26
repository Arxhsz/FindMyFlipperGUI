# FindMyFlipper Windows Packaging

The Windows client is a native C++/C++/WinRT WinUI 3 application. Qt,
Electron, Flutter, and a full-app web shell are not used. WebView2 is limited
to the interactive map canvas.

## Build host

- Windows 11 x64 or ARM64
- Visual Studio 2026 version 18.7 or newer with **Desktop development with C++** and **C++ WinUI app development tools**
- Windows 10/11 SDK 10.0.19041 or newer
- Python 3.11 or newer (packaging host only)
- Optional: Inno Setup 6 for `FindMyFlipperSetup.exe`

The native project uses NuGet `<PackageReference>`. Visual Studio 18.7 requires
`EnableNativePackageReferenceSupport=true`; the project and build script both
set that property so restore and build use the same native dependency graph.

The project uses standard C++20 coroutines. Do not add the legacy `/await`
compiler option: MSVC 14.51 rejects experimental coroutine mode with STL1011.

End users do not need Python. PyInstaller freezes the gateway and anisette
launcher into executables copied beside the native app.

## One command

From the repository root in PowerShell:

```powershell
.\packaging\package_windows.ps1
```

Use `-Platform ARM64` on a Windows on ARM build host. The script cleans old
artifacts, restores NuGet packages, builds the native app, freezes both local
services, assembles `release/FindMyFlipper`, creates the portable ZIP, and
creates the installer when Inno Setup is installed.

Run source/backend validation independently with:

```powershell
.\packaging\validate_windows.ps1
```

## Outputs

```text
release/
|-- FindMyFlipperSetup.exe       # when Inno Setup 6 is installed
|-- FindMyFlipperPortable.zip
`-- FindMyFlipper/
    |-- FindMyFlipper.exe
    |-- FindMyFlipperBackend.exe
    |-- FindMyFlipperAnisette.exe
    |-- Assets/
    |-- Map/
    `-- runtime/
```

## VM test setup on Apple silicon

1. Install VMware Fusion 13.6+ or UTM 4.6+.
2. Create a Windows 11 ARM64 VM with 8 GB RAM, 4 CPU cores, and 80 GB disk.
3. Enable Bluetooth sharing or attach a supported USB Bluetooth adapter to the VM.
4. Install Visual Studio and the workloads listed above.
5. Clone the repository in the VM and run the one-command package script.
6. Test both the extracted portable ZIP and the Inno installer.

Hypervisors often do not expose the Mac Bluetooth controller as a Windows BLE
radio. The app detects that state and keeps the native BLE path available for a
physical Windows machine or a passed-through USB adapter.
