@echo off
setlocal
title JWE3 Intel Arc Water Fix - Install
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0JWE3-IntelArc-WaterFix.ps1" -Action Install
set "fixExitCode=%ERRORLEVEL%"
echo.
if not "%fixExitCode%"=="0" echo Installation failed. Read the message above; no unsupported version was modified.
pause
exit /b %fixExitCode%
