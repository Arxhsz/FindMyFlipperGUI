# Release notes

## Native Windows and macOS desktop release

### Windows

- Replaced the legacy Electron Windows client with a native C++20, C++/WinRT, WinUI 3 application.
- Added secure `.keys` import/generation and Credential Manager secret storage.
- Added native BLE discovery, stable filtering, reconnect, battery, RSSI, firmware, physical Bluetooth MAC display, and repeatable alert playback.
- Added USB Flipper import/copy and confirmation-protected firmware/microSD key inspection.
- Added a local Leaflet map with live and historical timelines, custom ranges, marker focus, zoom, and four map modes.
- Added dashboard, reports, profiles, diagnostics, themes, tray integration, loopback-only backend management, and clean child-process shutdown.
- Added self-contained Windows App SDK output, standalone Python backends, portable ZIP validation, and an Inno Setup installer.

### macOS

- Native SwiftUI app with MapKit, CoreBluetooth, Keychain, menu-bar integration, profiles, diagnostics, themes, and a bundled local backend.

### Security

- Private keys are never serialized into profile JSON.
- Apple credentials and 2FA codes are not persisted.
- Native local services listen only on loopback.
- Generated Find My MAC addresses remain distinct from physical Bluetooth identifiers.

### Credits

FindMyFlipperGUI builds on [FindMyFlipper](https://github.com/MatthewKuKanich/FindMyFlipper) by Matthew KuKanich. See the platform-specific third-party notices for dependency credits and licenses.
