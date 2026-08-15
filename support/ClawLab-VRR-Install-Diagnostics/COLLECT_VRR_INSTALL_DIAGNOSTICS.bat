@echo off
setlocal
cd /d "%~dp0"
title ClawLab VRR read-only install diagnostics
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\Collect-ClawLab-VRR-Install-Diagnostics.ps1" -PackageDirectory "%~dp0."
echo.
pause
endlocal
