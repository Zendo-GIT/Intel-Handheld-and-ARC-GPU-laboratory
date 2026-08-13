@echo off
setlocal
title JWE3 Intel Arc Water Fix - Status
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0JWE3-IntelArc-WaterFix.ps1" -Action Status
set "fixExitCode=%ERRORLEVEL%"
echo.
pause
exit /b %fixExitCode%
