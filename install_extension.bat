@echo off
title Install Antigravity Remote IDE Extension
color 0A
cls
echo ======================================================================
echo    Installing Antigravity Remote Companion Extension into IDE...
echo ======================================================================
echo.

set EXT_SRC=%~dp0extension
set EXT_DEST1=%USERPROFILE%\.antigravity\extensions\antigravity-remote-control
set EXT_DEST2=%USERPROFILE%\.gemini\extensions\antigravity-remote-control
set EXT_DEST3=%USERPROFILE%\.vscode\extensions\antigravity-remote-control

echo [*] Copying extension files to Antigravity directories...

mkdir "%EXT_DEST1%" 2>nul
xcopy "%EXT_SRC%" "%EXT_DEST1%" /E /Y /I /Q >nul

mkdir "%EXT_DEST2%" 2>nul
xcopy "%EXT_SRC%" "%EXT_DEST2%" /E /Y /I /Q >nul

mkdir "%EXT_DEST3%" 2>nul
xcopy "%EXT_SRC%" "%EXT_DEST3%" /E /Y /I /Q >nul

echo.
echo [SUCCESS] Antigravity Remote Companion Extension installed successfully!
echo.
echo Features installed:
echo  - Activity Bar Icon: Antigravity Remote panel
echo  - Autostart Checkbox: Launch daemon automatically when IDE starts
echo  - Status Bar Widget: Real-time Online/Offline indicator with IP & Port
echo  - Embedded Console: Live stdout/stderr logs inside IDE
echo.
echo Please restart or reload Antigravity IDE to see the new sidebar panel!
echo.
pause
