@echo off
setlocal
title MSI Claw VRR status
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0MSI-Claw-VRR-Fix.ps1" -Action Status
set "CLAWLAB_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %CLAWLAB_EXIT%
