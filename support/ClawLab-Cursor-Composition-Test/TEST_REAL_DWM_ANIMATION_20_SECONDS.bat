@echo off
setlocal
title ClawLab real DWM animation test
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Test-ClawLabDwmAnimation.ps1" -CountdownSeconds 5 -TestSeconds 20
echo.
pause

