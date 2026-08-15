@echo off
setlocal
cd /d "%~dp0"
set "CLAWLAB_SCRIPTS=%~dp0"
if exist "%~dp0..\scripts\Collect-Claw-Display-Diagnostics.ps1" set "CLAWLAB_SCRIPTS=%~dp0..\scripts\"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%CLAWLAB_SCRIPTS%Collect-Claw-Display-Diagnostics.ps1"
echo.
pause
endlocal
