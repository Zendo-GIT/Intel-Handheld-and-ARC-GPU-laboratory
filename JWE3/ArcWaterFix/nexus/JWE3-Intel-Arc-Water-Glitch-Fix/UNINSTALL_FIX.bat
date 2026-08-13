@echo off
setlocal
title JWE3 Intel Arc Water Fix - Uninstall
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0JWE3-IntelArc-WaterFix.ps1" -Action Uninstall
set "fixExitCode=%ERRORLEVEL%"
echo.
if not "%fixExitCode%"=="0" echo Uninstallation failed. Read the message above before changing any game files manually.
pause
exit /b %fixExitCode%
