# Windows Test Matrix

## Required Windows environment

- Windows 11 x64 or ARM64
- Windows Bluetooth adapter, or a USB BLE adapter passed through to the VM
- Visual Studio 2026 version 18.7+ with C++ WinUI development tools
- Python 3.11+ and Inno Setup 6 on the packaging host
- Docker Desktop for the current anisette-v3 service

## VM procedure

On Apple silicon, create a Windows 11 ARM64 VM in VMware Fusion 13.6+ or UTM
4.6+. Allocate 8 GB RAM, four CPU cores, and 80 GB storage. Install the native
ARM64 Visual Studio tools, attach a USB Bluetooth adapter when host Bluetooth
is not exposed, clone the repository, then run:

```powershell
.\packaging\package_windows.ps1 -Platform ARM64
```

## Acceptance checks

1. Launch `release\FindMyFlipper\FindMyFlipper.exe`.
2. Complete the welcome and `.keys` import screens with a test-only identity.
3. Verify `profile.json` contains only the credential target, not the private key.
4. Confirm the backend starts automatically and `/health` responds.
5. Confirm anisette is detected or Docker Desktop is started automatically.
6. Complete Apple sign-in and the in-app 2FA continuation.
7. Open native BLE scan; verify adapter-off and VM-unavailable recovery text.
8. Select a real Flipper, restart the app, and verify saved-device reconnect.
9. Confirm the map, no-reports, dashboard, reports, Flipper, profiles, and settings views.
10. Verify the notification-area icon and its commands.
11. Extract `FindMyFlipperPortable.zip` into a clean folder and launch it.
12. Install and uninstall `FindMyFlipperSetup.exe`.

## Results for windows-native-build-fix-24

- Historical map input is normalized for legacy millisecond timestamps and
  invalid coordinates. When a freshly loaded identity only has older reports,
  the main map automatically selects the smallest 24H, 7D, or 30D range that
  exposes those historical markers.
- Every Play Alert click now begins an independent attempt. A reconnect retry
  is bounded to one attempt and cannot suppress a later user click; GATT writes
  honor the characteristic's with-response or without-response capability.
- Buttons now use an app-owned WinUI visual-state template. Pointer exit always
  restores the active theme brush instead of retaining the stock white hover
  state.

- Backend readiness is now independent of Docker/anisette startup. Local key
  generation, USB access, diagnostics, report controls, and backend restart no
  longer queue behind Docker Desktop.
- Blocking report, authentication, and anisette operations run in FastAPI's
  worker pool so the loopback health endpoint and other requests remain
  responsive.
- Native background operations return to WinUI through the window dispatcher;
  backend authentication status is fetched off the UI thread. This removes the
  reproduced `0x8001010D` COM reentrancy/marshaling crash.
- A clean Debug build and an interactive onboarding key-generation test passed;
  the generated identity was returned in seconds and the app remained
  responsive.

- The map control button is anchored at the lower-right and expands to current
  marker, zoom in, zoom out, and map-style controls.
- Live BLE firmware read passed on the connected test Flipper and returned a
  valid firmware revision string.
- Live USB microSD verification found one `.keys` file and matched the active
  test identity without exposing its filename or content.
- A transient BLE disconnect automatically reconnected; the UI now retains a
  reconnecting state until a retry actually fails.

- Verify the map defaults to Live and does not draw the historical trail.
- Verify 1H, 6H, 24H, 7D, 30D, and custom ranges update markers and bounds.
- Expand map controls and verify locate, zoom, Light, Dark, 3D Terrain, and
  Satellite modes.
- Use the map action menu to refresh reports and open diagnostics.
- Leave the saved Flipper connected long enough to exercise automatic GATT
  reconnection after a transient disconnect.

Validated on Windows 11 x64 with Visual Studio 18.7.11911.148, MSBuild 18.7.8,
the v145 toolset, and Windows SDK 10.0.26100.0:

- Clean Debug and Release builds: passed with zero errors.
- Native startup and WinUI/XAML rendering: passed.
- Native title-bar icon and embedded executable icon: passed.
- Onboarding Continue/Back navigation and clean close/reopen: passed.
- Project/source/backend/portable automated validation: passed.
- Test `.keys` import passed; profile JSON retained only the Credential Manager
  target and contained no private key material.
- Apple auth status and loopback routing passed. A live credential submission
  was not repeated for this revision because Windows blocked UI automation for
  the unsigned local executable; no credentials were placed in scripts/logs.
- Portable ZIP clean extraction and source-independent startup: passed.
- Frozen backend startup, `/health`, `/keys/generate`, auth status, and Flipper
  USB status passed from the freshly extracted ZIP. The portable runtime needs
  no installed Python and the listener is restricted to `127.0.0.1`.
- The supplied test `.keys` parsed with all required fields. Validation output
  contained booleans only and did not expose private key content.
- Release helpers use separate PyInstaller one-directory runtimes and the
  Windows GUI bootloader. This avoids one-file extraction stalls and prevents
  console windows from appearing.
- Frozen anisette executable was produced; Docker-backed anisette availability
  remains host-dependent.
- Backend child processes are assigned to a kill-on-close Windows Job Object.
- Reproduced the unnamed-device crash and traced it to the missing
  `SurfaceAltBrush` resource. The resource is now defined and render failures
  are reported in the Bluetooth status area instead of terminating WinUI.
- Live BLE advertisement scanning passed with unnamed devices enabled. Four
  anonymous devices were rendered with address, RSSI, and connection status;
  the window remained responsive throughout the scan.
- BLE UI refreshes are throttled and coalesced, anonymous address history is
  bounded, selection tags are parsed without throwing, and callbacks use weak
  window lifetimes during shutdown.
- The executable, title bar, taskbar, and tray icon now use a multi-resolution
  ICO generated from the exact Mac `FlipperZero.imageset/flipper-zero.png`.
- Fixed a delayed `0xc0000005` crash caused by attempting to resume background
  operations through a null Windows dispatcher. Each operation now captures
  and returns through its originating C++/WinRT apartment context.
- WebView2 full and compact maps rendered in both the Debug output and a clean
  extraction of the portable ZIP.
- The default Live map was tested with a valid report aged 48 hours. It
  rendered exactly one current Flipper marker, centered on its coordinates,
  and selected zoom level 16 instead of hiding the marker behind a one-hour
  cutoff.
- Apple-auth vendor output is captured when running under the windowed
  PyInstaller bootloader, preventing closed-pipe `WinError 233` failures.
- Backend health, report-refresh failure handling, Docker/anisette status,
  clean child-process shutdown, and the Flipper USB no-device state passed.
- Backend tests: 31 passed. Both native x64 configurations built with zero
  errors. Portable ZIP and Inno Setup installer were produced and validated.

Not represented as passing for fix-24: a new live Apple credential/2FA
submission, real Find My report retrieval, or physical Flipper USB/BLE/GATT
operations. Those require the account and hardware to be available during the
final clean test and are not inferred from simulated data.
