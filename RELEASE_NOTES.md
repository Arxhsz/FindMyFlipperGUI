# Release Notes

## Native macOS Preview

This release adds the native macOS FindMyFlipper app while keeping the existing Electron and Windows files in place.

### Added

- Native SwiftUI macOS app in `MAC/FindMyFlipperMac`.
- Bundled local FastAPI backend with original-compatible FindMyFlipper logic.
- `.keys` import, validation, Keychain-only private key storage, and local profile persistence.
- Apple access onboarding through the local backend.
- CoreBluetooth scanning, selection, reconnect state, battery display, and alert command support.
- MapKit map screen, dashboard, reports, profiles, settings, diagnostics, and menu bar status.
- Flipper microSD folder support for `/ext/apps_data/findmy`.
- Generated key replacement flow that removes older copies after a verified replacement.
- Seven visual themes with orange/white as the default.
- Sanitized screenshots and updated setup documentation.

### Notes

- Windows users can keep using the existing Electron app. A refreshed Windows update is coming soon.
- The Mac app is intended only for tracking your own Flipper Zero with `.keys` files you generated or imported yourself.
- Private keys are stored in macOS Keychain by the native Mac app.
- The generated Find My MAC and the CoreBluetooth identifier are intentionally modeled as separate identities.

### Credits

FindMyFlipperGUI builds on the original [FindMyFlipper](https://github.com/MatthewKuKanich/FindMyFlipper) project by Matthew KuKanich.
