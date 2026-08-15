@echo off
setlocal
title MSI Claw 8 AI+ / 8 EX AI+ Experimental 48-144 Hz Mode
echo WARNING: Fixed 144 Hz was stable on tested panels, but VRR at 144 Hz is not guaranteed.
echo Do not use this installer if you require verified variable-refresh behavior.
echo.
choice /C YN /N /M "Install the experimental 48-144 Hz profile anyway? [Y/N] "
if errorlevel 2 exit /b 0
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0MSI-Claw-VRR-Fix.ps1" -Action Install48_144
set "CLAWLAB_EXIT=%ERRORLEVEL%"
echo.
if not "%CLAWLAB_EXIT%"=="0" (
  echo The experimental 144 Hz profile was not installed. Read the error above.
  pause
  exit /b %CLAWLAB_EXIT%
)
choice /C YN /N /M "Restart the PC now? [Y/N] "
if errorlevel 2 goto :done
shutdown.exe /r /t 0
:done
exit /b %CLAWLAB_EXIT%
