@echo off
setlocal
title Detroit Intel Arc Stability Fix - Status
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Detroit-IntelArc-StabilityFix.ps1" -Action Status
set "EXIT_CODE=%ERRORLEVEL%"
echo.
pause
exit /b %EXIT_CODE%
