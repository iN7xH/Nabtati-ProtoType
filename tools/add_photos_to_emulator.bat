@echo off
REM Copy photos from the PC into the running Android emulator's gallery.
REM Usage: in Windows Explorer, select photos (or a folder) and DRAG them onto this file.
REM The emulator must be running.

set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"

if "%~1"=="" (
    echo Drag one or more photos ^(or a folder^) from Explorer onto this file.
    pause
    exit /b
)

:loop
if "%~1"=="" goto scan
echo Copying %~nx1 ...
"%ADB%" push "%~1" /sdcard/Pictures/ >nul
shift
goto loop

:scan
REM Tell Android to register the new photos so the gallery shows them.
"%ADB%" shell content call --method scan_volume --uri content://media --arg external_primary >nul
echo.
echo Done! Open the app and tap the gallery button.
pause
