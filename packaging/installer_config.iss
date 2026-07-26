#ifndef Root
  #define Root ".."
#endif
#ifndef AppVersion
  #define AppVersion "1.0.0.1"
#endif

#define AppName "FindMyFlipper"

[Setup]
AppId={{5C503B2E-11DE-4C92-862B-E815735CD63B}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=FindMyFlipper
DefaultDirName={autopf}\FindMyFlipper
DefaultGroupName=FindMyFlipper
OutputDir={#Root}\release
OutputBaseFilename=FindMyFlipperSetup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible arm64
ArchitecturesInstallIn64BitMode=x64compatible arm64
WizardStyle=modern
SetupIconFile={#Root}\WINDOWS\FindMyFlipperWindows\FindMyFlipperWindows\Assets\FindMyFlipper.ico
UninstallDisplayIcon={app}\FindMyFlipper.exe

[Files]
Source: "{#Root}\release\FindMyFlipper\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\FindMyFlipper"; Filename: "{app}\FindMyFlipper.exe"
Name: "{autodesktop}\FindMyFlipper"; Filename: "{app}\FindMyFlipper.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"

[Run]
Filename: "{app}\FindMyFlipper.exe"; Description: "Launch FindMyFlipper"; Flags: nowait postinstall skipifsilent
