@echo off
title Google Antigravity Remote Host Daemon
color 0A
cls
echo ======================================================================
echo          Google Antigravity 2.0 - Remote Host Daemon (agy-daemon)
echo ======================================================================
echo.

:: Ensure dependencies
echo [*] Checking Python environment...
py -m pip install websockets --quiet >nul 2>&1

:: Run Host Daemon
echo [*] Launching Daemon on Port 7800 (Auto-Discovery Port 7801)...
echo.
py server\host_daemon.py

echo.
echo Daemon process stopped.
pause
