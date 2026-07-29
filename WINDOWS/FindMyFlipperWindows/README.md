# FindMyFlipper for Windows

Source revision: `windows-native-build-fix-23`

Run the repeatable source/build/package validation after Debug, Release, and
packaging complete:

```powershell
py -3 .\packaging\validate_windows.py
```

The validator checks project/XAML XML, required C++20 and native NuGet
settings, generated-file conventions, assets, backend syntax and loopback
binding, Credential Manager routing, native BLE/map feature markers, both
native executables, and the portable ZIP manifest/integrity.

Revision 13 fixes and verifies the expandable four-button map control, adds an
Open in Maps action, reads firmware from standard BLE Device Information GATT
characteristics, and verifies the active identity against `.keys` files on the
Flipper microSD card without returning private material. It also keeps transient
GATT reconnects from flashing a false disconnected state.

Revision 12 brought the native Leaflet map in line with the Mac app: Live, 1H,
6H, 24H, 7D, 30D, and custom report timelines; a compact Mac-style Flipper
marker; locate and zoom controls; light, dark, terrain, and satellite layers;
and an in-map report refresh/diagnostics menu. It also debounces transient GATT
disconnects and automatically reconnects the saved Windows BLE device.

This revision adds Mac-parity local key generation and USB copy support, keeps
private key material in Windows Credential Manager, stabilizes BLE discovery
order, prioritizes paired devices, hides rotating anonymous advertisements by
default, and connects custom-named Flippers through their stable Windows device
identifier.

This is the native Windows port of the SwiftUI Mac app. The Mac app remains
the product reference for onboarding, navigation, layout, assets, themes, and
state behavior.

## Native stack

- C++20 and C++/WinRT (standard coroutines; no legacy `/await` switch)
- Windows App SDK and WinUI 3
- `BluetoothLEAdvertisementWatcher`, `BluetoothLEDevice`, and native GATT APIs
- Windows Credential Manager for imported private keys
- Win32 `Shell_NotifyIcon` notification-area menu
- WebView2 only for the Leaflet map canvas
- Frozen FastAPI gateway executables for report/auth/decryption services

Qt, Electron, Flutter, and a full-app browser shell are not used.

## Development build

Requirements are documented in [`packaging/README_PACKAGING.md`](../../packaging/README_PACKAGING.md).

```powershell
.\packaging\build_windows.ps1 -Platform x64 -Configuration Debug
```

Open `WINDOWS\FindMyFlipperWindows\FindMyFlipperWindows.sln` in Visual Studio
for normal debugging.

## Release package

```powershell
.\packaging\package_windows.ps1
```

The release includes the self-contained Windows App SDK runtime, frozen local
gateway, anisette/Docker launcher, map assets, native icons, installer when
Inno Setup is present, and required portable ZIP.

## Security model

- A `.keys` private key is never written to profile JSON.
- The profile stores only the Windows Credential Manager target.
- The key is loaded in memory only for a loopback report request.
- Apple passwords and 2FA codes are never persisted.
- The generated Find My MAC and the physical Windows BLE device ID are separate fields.
- The gateway binds to `127.0.0.1`.

## Hardware testing

VMs often cannot access the host Bluetooth adapter. Use a passed-through USB
BLE adapter or a physical Windows PC for final Flipper connection, battery,
firmware, alert, and reconnect validation.
