@echo off
setlocal
title Export ClawLab status report
set "CLAWLAB_SCRIPTS=%~dp0"
if exist "%~dp0..\scripts\Export-ClawLab-Status.ps1" set "CLAWLAB_SCRIPTS=%~dp0..\scripts\"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%CLAWLAB_SCRIPTS%Export-ClawLab-Status.ps1"
set "CLAWLAB_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %CLAWLAB_EXIT%
