@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0The-Isle-Evrima-Claw-Fix.ps1" -Action Status
echo.
pause
