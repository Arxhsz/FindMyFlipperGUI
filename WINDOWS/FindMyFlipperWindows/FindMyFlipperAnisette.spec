# -*- mode: python ; coding: utf-8 -*-


a = Analysis(
    ['C:\\Users\\kanaa\\Downloads\\FindMyFlipperWindows-fixed-5-2026-07-14\\fix11-clean\\FindMyFlipperWindows-fixed-10-2026-07-16\\WINDOWS\\FindMyFlipperWindows\\Backend\\anisette_entry.py'],
    pathex=['C:\\Users\\kanaa\\Downloads\\FindMyFlipperWindows-fixed-5-2026-07-14\\fix11-clean\\FindMyFlipperWindows-fixed-10-2026-07-16\\MAC\\FindMyFlipperMac\\Backend', 'C:\\Users\\kanaa\\Downloads\\FindMyFlipperWindows-fixed-5-2026-07-14\\fix11-clean\\FindMyFlipperWindows-fixed-10-2026-07-16\\MAC\\FindMyFlipperMac\\Backend\\findmy_gateway\\vendor'],
    binaries=[],
    datas=[('C:\\Users\\kanaa\\Downloads\\FindMyFlipperWindows-fixed-5-2026-07-14\\fix11-clean\\FindMyFlipperWindows-fixed-10-2026-07-16\\MAC\\FindMyFlipperMac\\Backend\\findmy_gateway\\vendor\\cores', 'findmy_gateway/vendor/cores')],
    hiddenimports=['cores.pypush_gsa_icloud', 'cores.old_key_generation'],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='FindMyFlipperAnisette',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    contents_directory='AnisetteRuntime',
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='FindMyFlipperAnisette',
)
