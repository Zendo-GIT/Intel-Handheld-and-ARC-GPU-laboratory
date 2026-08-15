@echo off
setlocal
title Emergency removal - MSI Claw custom EDID
set "CLAWLAB_SCRIPTS=%~dp0"
if exist "%~dp0..\scripts\MSI-Claw-VRR-Fix.ps1" set "CLAWLAB_SCRIPTS=%~dp0..\scripts\"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%CLAWLAB_SCRIPTS%MSI-Claw-VRR-Fix.ps1" -Action EmergencyRestoreEdid
set "CLAWLAB_EXIT=%ERRORLEVEL%"
echo.
if not "%CLAWLAB_EXIT%"=="0" (
  echo The emergency removal was not completed. Read the error above.
  pause
  exit /b %CLAWLAB_EXIT%
)
choice /C YN /N /M "Restart the PC now? [Y/N] "
if errorlevel 2 goto :done
shutdown.exe /r /t 0
:done
exit /b %CLAWLAB_EXIT%
