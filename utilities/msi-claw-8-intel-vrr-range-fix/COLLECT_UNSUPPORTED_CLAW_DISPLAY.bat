@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\Collect-Claw-Display-Diagnostics.ps1"
echo.
pause
endlocal
