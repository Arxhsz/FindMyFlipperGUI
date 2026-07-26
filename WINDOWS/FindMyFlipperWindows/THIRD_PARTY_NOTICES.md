# Third-Party Notices

FindMyFlipper for Windows includes compatibility code derived from or designed
to interoperate with [Matthew KuKanich's FindMyFlipper](https://github.com/MatthewKuKanich/FindMyFlipper),
including `.keys` parsing, Apple authentication flow integration, hashed
advertisement-key report requests, SECP224R1/AES-GCM report decryption, and
location report decoding. The upstream project and its license remain
authoritative for the original work.

The map canvas uses Leaflet and OpenStreetMap map tiles. The native shell uses
Microsoft Windows App SDK, WinUI 3, C++/WinRT, and WebView2. The packaged local
gateway uses FastAPI, Uvicorn, Requests, Cryptography, and PyInstaller.

The Windows presentation and application artwork follow Arxhsz's MIT-licensed
FindMyFlipperGUI and its native macOS reference implementation. The pinned
reference revision used for this port is
`bd5a57b34fb049dd2ad855f32724275e960ee26f`. Leaflet 1.9.4 is bundled locally;
its license is included beside the map resources. CARTO and OpenStreetMap tile
attribution remains visible in the map canvas.

No upstream branding implies endorsement. This application is intended only
for tracking a Flipper Zero owned by the user with a `.keys` identity they
control.
