@echo off
setlocal
title MSI Claw VRR status
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0MSI-Claw-VRR-Fix.ps1" -Action Status
set "CLAWLAB_EXIT=%ERRORLEVEL%"
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0MSI-Claw-30-120-LFC-Fix.ps1" -Action Status
if not "%ERRORLEVEL%"=="0" set "CLAWLAB_EXIT=%ERRORLEVEL%"
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Experimental-144-VRR-Trial.ps1" -Action Status
if not "%ERRORLEVEL%"=="0" set "CLAWLAB_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %CLAWLAB_EXIT%
