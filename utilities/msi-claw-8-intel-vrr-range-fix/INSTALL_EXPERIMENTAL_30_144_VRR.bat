@echo off
setlocal
title MSI Claw 8 AI+ / 8 EX AI+ Experimental 30-144 Hz Trial
echo WARNING: 30-144 Hz is outside MSI specifications.
echo This exact range caused visible flicker on the reference panel.
echo It is provided only as an informed, reversible hardware trial.
echo.
echo After restart, the verified range will run for 20 seconds and ask whether
echo you want to keep it. No, closing the prompt, or no answer within 30 seconds
echo restores the previous profile and restarts Windows automatically.
echo.
choice /C YN /N /M "Start the guarded experimental 30-144 Hz trial? [Y/N] "
if errorlevel 2 exit /b 0
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0MSI-Claw-VRR-Fix.ps1" -Action Install30_144
set "CLAWLAB_EXIT=%ERRORLEVEL%"
echo.
if not "%CLAWLAB_EXIT%"=="0" (
  echo The experimental 30-144 Hz profile was not installed. Read the error above.
  pause
  exit /b %CLAWLAB_EXIT%
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0MSI-Claw-Intel-LFC-Fix.ps1" -Action Apply
set "CLAWLAB_EXIT=%ERRORLEVEL%"
echo.
if not "%CLAWLAB_EXIT%"=="0" (
  echo The 30-144 Hz profile was installed, but the Intel LFC fix failed.
  echo Run RESTORE_ORIGINAL_VRR.bat before trying again.
  pause
  exit /b %CLAWLAB_EXIT%
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Experimental-144-VRR-Trial.ps1" -Action Schedule -Mode CLAWLAB_30_144
set "CLAWLAB_EXIT=%ERRORLEVEL%"
echo.
if not "%CLAWLAB_EXIT%"=="0" (
  echo The profile was installed, but its confirmation failsafe was not scheduled.
  echo Run RESTORE_ORIGINAL_VRR.bat before trying again.
  pause
  exit /b %CLAWLAB_EXIT%
)
choice /C YN /N /M "Restart the PC now to begin the guarded trial? [Y/N] "
if errorlevel 2 goto :done
shutdown.exe /r /t 0
:done
exit /b %CLAWLAB_EXIT%
