@echo off
setlocal
title Restore original Intel LFC state
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0MSI-Claw-30-120-LFC-Fix.ps1" -Action Restore
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
