@echo off
setlocal
title Detroit Intel Arc Stability Fix - Install
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Detroit-IntelArc-StabilityFix.ps1" -Action Install
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if not "%EXIT_CODE%"=="0" echo Installation stopped with error %EXIT_CODE%.
pause
exit /b %EXIT_CODE%
