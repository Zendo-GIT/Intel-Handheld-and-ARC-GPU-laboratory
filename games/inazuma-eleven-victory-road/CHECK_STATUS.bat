@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0IEVR-Offline-Stutter-Fix.ps1" -Action Status
echo.
pause
