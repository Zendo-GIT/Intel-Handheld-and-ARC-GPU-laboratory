@echo off
setlocal
title MSI Claw VRR status
set "CLAWLAB_SCRIPTS=%~dp0"
if exist "%~dp0scripts\MSI-Claw-VRR-Fix.ps1" set "CLAWLAB_SCRIPTS=%~dp0scripts\"
echo === ClawLab 2.2.0 overall health ===
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%CLAWLAB_SCRIPTS%ClawLab-Health-Check.ps1"
set "CLAWLAB_EXIT=%ERRORLEVEL%"
echo.
echo === Detailed VRR state ===
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%CLAWLAB_SCRIPTS%MSI-Claw-VRR-Fix.ps1" -Action Status
if not "%ERRORLEVEL%"=="0" set "CLAWLAB_EXIT=%ERRORLEVEL%"
echo.
echo === Detailed Intel LFC state ===
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%CLAWLAB_SCRIPTS%MSI-Claw-Intel-LFC-Fix.ps1" -Action Status
if not "%ERRORLEVEL%"=="0" set "CLAWLAB_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %CLAWLAB_EXIT%
