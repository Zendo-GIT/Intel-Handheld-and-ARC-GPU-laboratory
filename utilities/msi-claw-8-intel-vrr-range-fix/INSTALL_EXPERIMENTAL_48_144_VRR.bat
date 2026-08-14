@echo off
setlocal
title MSI Claw 8 AI+ / 8 EX AI+ Experimental VRR 48-144 Fix
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0MSI-Claw-VRR-Fix.ps1" -Action Install48_144
set "CLAWLAB_EXIT=%ERRORLEVEL%"
echo.
if not "%CLAWLAB_EXIT%"=="0" (
  echo The experimental 144 Hz fix was not installed. Read the error above.
  pause
  exit /b %CLAWLAB_EXIT%
)
choice /C YN /N /M "Restart the PC now? [Y/N] "
if errorlevel 2 goto :done
shutdown.exe /r /t 0
:done
exit /b %CLAWLAB_EXIT%
