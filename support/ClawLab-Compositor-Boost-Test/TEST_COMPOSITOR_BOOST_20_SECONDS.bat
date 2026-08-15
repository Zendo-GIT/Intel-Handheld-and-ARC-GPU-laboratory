@echo off
setlocal
title ClawLab compositor boost test
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-ClawLab-CompositorBoost.ps1" -CountdownSeconds 5 -BoostSeconds 20
echo.
pause

