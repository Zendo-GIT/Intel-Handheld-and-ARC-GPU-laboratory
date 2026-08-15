@echo off
setlocal
title MSI Claw 8 AI+ / 8 EX AI+ Experimental 48-144 Hz Mode
echo WARNING: 144 Hz is outside MSI specifications and VRR is not guaranteed.
echo After restart, the range will run for 20 seconds and require confirmation.
echo No, closing the prompt, or a 30-second timeout restores the previous profile.
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
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Experimental-144-VRR-Trial.ps1" -Action Schedule -Mode CLAWLAB_48_144
set "CLAWLAB_EXIT=%ERRORLEVEL%"
echo.
if not "%CLAWLAB_EXIT%"=="0" (
  echo The profile was installed, but its confirmation failsafe was not scheduled.
  echo Run RESTORE_ORIGINAL_VRR.bat before trying again.
  pause
  exit /b %CLAWLAB_EXIT%
)
choice /C YN /N /M "Restart the PC now? [Y/N] "
if errorlevel 2 goto :done
shutdown.exe /r /t 0
:done
exit /b %CLAWLAB_EXIT%
