"""Deterministic source and portable-package checks for FindMyFlipper Windows."""
from __future__ import annotations

import py_compile
import sys
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "WINDOWS/FindMyFlipperWindows/FindMyFlipperWindows"
BACKEND = ROOT / "MAC/FindMyFlipperMac/Backend/findmy_gateway"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> None:
    project_file = PROJECT / "FindMyFlipperWindows.vcxproj"
    xaml_file = PROJECT / "MainWindow.xaml"
    ET.parse(project_file)
    ET.parse(xaml_file)
    ET.parse(PROJECT / "App.xaml")

    project = project_file.read_text(encoding="utf-8")
    xaml = xaml_file.read_text(encoding="utf-8")
    xaml_cpp = (PROJECT / "MainWindow.xaml.cpp").read_text(encoding="utf-8")
    profile_cpp = (PROJECT / "Services/ProfileStore.cpp").read_text(encoding="utf-8")
    bluetooth_cpp = (PROJECT / "Services/BluetoothManager.cpp").read_text(encoding="utf-8")
    server_py = (BACKEND / "server.py").read_text(encoding="utf-8")
    map_html = (PROJECT / "Map/map.html").read_text(encoding="utf-8")

    for marker in (
        "<UseWinUI>true</UseWinUI>",
        "<EnableNativePackageReferenceSupport>true</EnableNativePackageReferenceSupport>",
        "<LanguageStandard>stdcpp20</LanguageStandard>",
        '<Midl Include="MainWindow.idl">',
    ):
        require(marker in project, f"Missing project marker: {marker}")
    require("/await" not in project, "Obsolete /await option is present")
    require("App.xaml.g.cpp" not in xaml_cpp, "Invalid generated App include is present")
    require('HorizontalContentAlignment="Stretch"' in xaml,
            "Onboarding ScrollViewer does not center its constrained content")
    require('x:Name="OnboardingContentColumn"' in xaml and
            'HorizontalAlignment="Center"' in xaml,
            "Onboarding content column is not explicitly centered")
    require("WM_GETMINMAXINFO" in xaml_cpp and
            "AdjustWindowRectExForDpi" in xaml_cpp,
            "Native minimum client-size enforcement is missing")

    for relative in (
        "App.xaml",
        "MainWindow.idl",
        "Assets/icon.png",
        "Assets/FindMyFlipper.ico",
        "Assets/flipper-zero.png",
        "Map/map.html",
        "Map/leaflet.js",
        "Map/leaflet.css",
    ):
        require((PROJECT / relative).is_file(), f"Missing required asset: {relative}")

    require("privateKey" not in profile_cpp, "Profile JSON code references privateKey")
    require("CredentialService::SavePrivateKey" in xaml_cpp,
            "Private-key import is not routed to Credential Manager")
    require("BluetoothLEAdvertisementWatcher" in bluetooth_cpp,
            "Native BLE advertisement watcher is missing")
    require("setMarkerStyle" in map_html and "data-filter=\"24\"" in map_html,
            "Map marker or 24-hour timeline support is missing")
    require("normalizeReport" in map_html and "selectInitialHistoryRange" in map_html,
            "Historical report normalization or automatic range selection is missing")
    require("SendAlert(bool retrying)" in bluetooth_cpp and
            "m_alertRetryCount" not in bluetooth_cpp,
            "Play Alert still uses shared retry state")
    require('host="127.0.0.1"' in server_py,
            "Backend is not explicitly bound to loopback")
    require('/desktop/flipper/keys/import' in server_py,
            "USB Flipper key import endpoint is missing")
    require('/auth/anisette-status' in server_py,
            "Docker/anisette lifecycle endpoint is missing")

    for source in BACKEND.glob("*.py"):
        py_compile.compile(str(source), doraise=True)

    debug_exe = ROOT / "WINDOWS/FindMyFlipperWindows/build/x64/Debug/FindMyFlipperWindows.exe"
    release_exe = ROOT / "WINDOWS/FindMyFlipperWindows/build/x64/Release/FindMyFlipperWindows.exe"
    require(debug_exe.is_file() and debug_exe.stat().st_size > 0,
            "Debug executable is missing or empty")
    require(release_exe.is_file() and release_exe.stat().st_size > 0,
            "Release executable is missing or empty")

    portable = ROOT / "release/FindMyFlipperPortable.zip"
    require(portable.is_file() and portable.stat().st_size > 0,
            "Portable ZIP is missing or empty")
    forbidden = {
        ".pdb", ".obj", ".tlog", ".ilk", ".exp", ".lib", ".vcxproj",
        ".log", ".keys",
    }
    with zipfile.ZipFile(portable) as archive:
        names = archive.namelist()
        require(archive.testzip() is None, "Portable ZIP has a corrupt member")
        for required in (
            "FindMyFlipper.exe",
            "FindMyFlipperBackend.exe",
            "FindMyFlipperAnisette.exe",
            "Map/map.html",
            "Assets/FindMyFlipper.ico",
        ):
            require(required in names, f"Portable ZIP is missing {required}")
        require(not any(Path(name).suffix.lower() in forbidden for name in names),
                "Portable ZIP contains a forbidden build artifact")

    print("FindMyFlipper Windows validation: PASS")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"FindMyFlipper Windows validation: FAIL: {exc}", file=sys.stderr)
        raise
