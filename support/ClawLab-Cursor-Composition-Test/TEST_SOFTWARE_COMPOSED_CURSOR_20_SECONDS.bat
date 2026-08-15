@echo off
setlocal
title ClawLab software-composed cursor test
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-ClawLabSoftwareCursor.ps1" -CountdownSeconds 5 -TestSeconds 20
echo.
pause

