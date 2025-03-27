@echo off
setlocal

rem Define variables – adjust these if needed
set "SHORTCUT_PATH=%USERPROFILE%\Desktop\FindMyFlipper.lnk"
set "TARGET_BAT=%~dp0start_app.bat"
set "WORKING_DIR=%~dp0"
set "ICON_PATH=%~dp0icons\icon.ico"

echo Checking if shortcut exists on Desktop...
if exist "%SHORTCUT_PATH%" (
    echo Shortcut already exists.
) else (
    echo Creating shortcut on Desktop...
    rem Use PowerShell with -NoProfile to quickly create the shortcut.
    powershell -NoProfile -Command "$s = New-Object -ComObject WScript.Shell; $sc = $s.CreateShortcut('%SHORTCUT_PATH%'); $sc.TargetPath = '%TARGET_BAT%'; $sc.WorkingDirectory = '%WORKING_DIR%'; $sc.IconLocation = '%ICON_PATH%'; $sc.Save()"
)

echo Launching application...
call "%TARGET_BAT%"

endlocal
exit