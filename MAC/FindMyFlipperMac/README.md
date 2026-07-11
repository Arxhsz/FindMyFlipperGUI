# FindMyFlipper for Mac

Track your Flipper Zero using Apple's Find My network — entirely locally on your Mac.

## Overview

FindMyFlipper Mac is a native macOS application (macOS 14+) that lets you track your Flipper Zero device using the Apple Find My network. All cryptographic operations happen locally; no data leaves your Mac except to the Apple Find My API.

**Built on the shoulders of giants:**
- [FindMyFlipper](https://github.com/MatthewKuKanich/FindMyFlipper) by Matthew KuKanich (Apache 2.0)
- [pypush](https://github.com/beeper/pypush) for Apple GSA/iCloud authentication

---

## Prerequisites

- macOS 14 Sonoma or later
- Xcode 15+ (for building from source)
- Python 3.11+ (for the local backend)
- Homebrew (optional, used by the app to install OrbStack automatically if Docker is missing)
- OrbStack or Docker Desktop (for the local anisette service used by Apple access)
- Flipper Zero with FindMy firmware

---

## Backend Setup

```bash
# 1. Create a Python virtual environment
cd Backend
python3 -m venv venv
source venv/bin/activate

# 2. Install dependencies
pip install -r requirements.txt

# 3. Verify the bundled original-compatible auth core is present
test -f findmy_gateway/vendor/cores/pypush_gsa_icloud.py

# 4. Start the backend server (the macOS app starts the bundled backend automatically)
python -m findmy_gateway.server
```

When you build with `./build_and_run.sh`, the generated `.app` includes the Python backend under
`Contents/Resources/Backend`, including the minimal Matthew-compatible auth core under
`findmy_gateway/vendor/cores`. Onboarding can import an existing FindMyFlipper `.keys` file or
generate a new compatible identity in-app, then stores the private key in Keychain. During Apple access setup the app first reuses any running anisette
service, then starts the Docker container. If Docker is missing and Homebrew is installed, the app
can install and launch OrbStack from the setup flow. Apple ID credentials are submitted only to the
local backend so it can obtain the original-compatible DSID/searchParty token pair; the password is
not stored. If Apple requires two-factor authentication, the local backend keeps the sign-in attempt
alive in memory until the user enters the code in the app. If Apple access is already cached,
onboarding shows the connected account and lets the user continue or choose **Sign In Again** to
run sign-in and 2FA again.

USB onboarding detects the Flipper serial port and creates this directory directly on its microSD
card:

```text
/ext/apps_data/findmy
```

Imported and generated `.keys` files can be copied there during onboarding. Quit qFlipper before
transferring because only one application can own the Flipper serial connection. Generated key
files are transient on the Mac; persisted private keys remain in Keychain. Bluetooth scanning starts
only after the user clicks the scan button, so macOS Bluetooth permission is not requested on screen
load. Selecting a nearby device stores its macOS CoreBluetooth peripheral identifier, immediately
connects, discovers available services, and automatically reconnects on later launches. Battery,
firmware, RSSI, and alert support are shown only when the device actually exposes them.

For the FindMyFlipper application service, Play Alert uses the same write/read
characteristics and `03 B2 02 00` command as the existing GUI integration; standard
Bluetooth Immediate Alert remains available as a fallback.

The Flipper detail screen identifies the active `.keys` filename and import time and marks
the newest app record. **Replace Keys and Delete Old Copies** performs guarded rotation:
it generates and validates a replacement, saves its private key in Keychain, copies the
bundle to the Flipper, relinks the profile, and only then removes older `.keys` files from
`/ext/apps_data/findmy` and unreferenced Mac Keychain records. The operation requires a
connected USB Flipper and explicit confirmation. Profile names can be changed with the
pencil button beside the profile title.
For older imports whose Mac and Flipper filenames differ, the app reads the Flipper files
over USB and matches only their hashed advertisement identity; it does not log or persist
private material read during this verification. Profile cancellation and deletion also
clean up unreferenced Keychain records, reports, and key metadata.

Report refresh resolves the profile's `FindMyKeyRecord` first and then loads the private key through
that record's separate `keychainKeyID`; private key material is never read using the public record ID.
Backend `ok: false` responses retain their readable server detail instead of being reported as the
synthetic and unactionable `HTTP error: 0`.
Expired Apple report tokens, including non-JSON 401 responses, are cleared and
routed to an in-app reconnect flow instead of being displayed as a raw endpoint error.
The local Python process is health-checked and restarted if it exits even when the
previous Swift state still said it was running.

---

## Building & Running

```bash
# Build using Swift Package Manager
swift build

# Run tests
swift test

# Build for Release
swift build -c release

# Or open in Xcode
open Package.swift
```

---

## Project Structure

```
FindMyFlipper/
├── Sources/FindMyFlipperMac/        # Swift app source
│   ├── App/                         # AppState, AppRouter, AppTheme, Constants, MenuBarController
│   ├── Models/                      # FlipperProfile, LocationReport, AppSettings, etc.
│   ├── Services/
│   │   ├── BLE/                     # BLEManager, BLEScanner, BLEDeviceScorer
│   │   ├── Backend/                 # BackendClient, BackendManager, ReportRefreshService
│   │   ├── Keys/                    # KeychainService, KeysFileParser, KeyImportService
│   │   ├── Storage/                 # ProfileStore, ReportsStore, SettingsStore
│   │   ├── Diagnostics/             # SetupDiagnosticsService
│   │   ├── Permissions/             # PermissionService
│   │   └── Notifications/           # NotificationService
│   └── Views/                       # SwiftUI views organized by feature
├── Tests/FindMyFlipperMacTests/      # XCTest unit tests
├── Backend/                          # Python FastAPI backend
│   ├── findmy_gateway/               # Python package
│   └── requirements.txt
└── THIRD_PARTY_NOTICES.md             # Third-party attribution
```

---

## Privacy

- Private keys are stored in macOS Keychain and never logged or transmitted
- The backend binds to `127.0.0.1` only — no external exposure
- All Find My location data is end-to-end encrypted by Apple
- No telemetry, analytics, or external accounts required

---

## License

MIT License. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for third-party attributions.
