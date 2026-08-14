@echo off
setlocal
title Detroit Intel Arc Stability Fix - Uninstall
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Detroit-IntelArc-StabilityFix.ps1" -Action Uninstall
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if not "%EXIT_CODE%"=="0" echo Uninstall stopped with error %EXIT_CODE%.
pause
exit /b %EXIT_CODE%
