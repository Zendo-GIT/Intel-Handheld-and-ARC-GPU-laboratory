@echo off
setlocal
cd /d "%~dp0"
title ClawLab A1M read-only Arc Sync diagnostics
echo This tool only reads the A1M panel EDID and the two Intel VRR interfaces.
echo It does not install a VRR profile or change any display setting.
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Collect-A1M-ArcSync-Diagnostics.ps1"
set "CLAWLAB_EXIT=%ERRORLEVEL%"
echo.
if not "%CLAWLAB_EXIT%"=="0" echo Collection failed. Send a photo of the complete error.
pause
exit /b %CLAWLAB_EXIT%
