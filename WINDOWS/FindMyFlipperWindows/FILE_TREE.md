# Windows File Tree

```text
WINDOWS/FindMyFlipperWindows/
|-- Backend/
|   |-- anisette_entry.py
|   `-- backend_entry.py
|-- FindMyFlipperWindows.sln
|-- FindMyFlipperWindows/
|   |-- App.xaml
|   |-- App.xaml.cpp
|   |-- App.xaml.h
|   |-- Assets/
|   |   |-- FindMyFlipper.ico
|   |   |-- flipper-zero.png
|   |   `-- icon.png
|   |-- FindMyFlipperWindows.vcxproj
|   |-- MainWindow.xaml
|   |-- MainWindow.xaml.cpp
|   |-- MainWindow.xaml.h
|   |-- MainWindow.idl
|   |-- Map/
|   |   `-- map.html
|   |-- Models/
|   |   `-- AppModels.h
|   |-- Services/
|   |   |-- BackendManager.cpp
|   |   |-- BackendManager.h
|   |   |-- BluetoothManager.cpp
|   |   |-- BluetoothManager.h
|   |   |-- CredentialService.cpp
|   |   |-- CredentialService.h
|   |   |-- ProfileStore.cpp
|   |   |-- ProfileStore.h
|   |   |-- TrayIconService.cpp
|   |   `-- TrayIconService.h
|   |-- Version.rc
|   |-- pch.cpp
|   `-- pch.h
|-- README.md
|-- THIRD_PARTY_NOTICES.md
`-- WINDOWS_TESTING.md

packaging/
|-- README_PACKAGING.md
|-- build_windows.ps1
|-- clean_windows.ps1
|-- installer_config.iss
|-- package_windows.ps1
|-- validate_windows.ps1
`-- version.h
```

The frozen gateway uses the shared source at
`MAC/FindMyFlipperMac/Backend/findmy_gateway/` so the Mac and Windows clients
cannot drift into different `.keys`, Apple authentication, report, or
decryption implementations.
