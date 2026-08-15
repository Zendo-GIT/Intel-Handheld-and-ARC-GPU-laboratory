@echo off
setlocal
title Restore original Intel LFC state
set "CLAWLAB_SCRIPTS=%~dp0"
if exist "%~dp0..\scripts\MSI-Claw-VRR-Fix.ps1" set "CLAWLAB_SCRIPTS=%~dp0..\scripts\"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%CLAWLAB_SCRIPTS%MSI-Claw-Intel-LFC-Fix.ps1" -Action Restore
set "CLAWLAB_EXIT=%ERRORLEVEL%"
echo.
if not "%CLAWLAB_EXIT%"=="0" (
  echo The saved Intel LFC state was not restored. Read the error above.
  pause
  exit /b %CLAWLAB_EXIT%
)
echo The original Intel low- and high-FPS VRR solution flags were restored.
echo The selected ClawLab VRR range was not changed.
pause
exit /b 0
