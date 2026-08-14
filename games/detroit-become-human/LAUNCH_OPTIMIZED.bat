@echo off
setlocal
title Detroit Intel Arc Stability Fix - Optimized Launch
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Detroit-IntelArc-StabilityFix.ps1" -Action Launch
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if not "%EXIT_CODE%"=="0" echo Optimized launch stopped with error %EXIT_CODE%.
pause
exit /b %EXIT_CODE%
