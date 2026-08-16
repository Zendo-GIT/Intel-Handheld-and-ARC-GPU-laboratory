@echo off
setlocal
title ClawLab UNSTABLE EXPERIMENTAL 48-180 Hz display overclock
set "CLAWLAB_ROOT=%~dp0..\"
set "CLAWLAB_SCRIPTS=%CLAWLAB_ROOT%"
if exist "%CLAWLAB_ROOT%scripts\MSI-Claw-VRR-Fix.ps1" set "CLAWLAB_SCRIPTS=%CLAWLAB_ROOT%scripts\"
echo IMPORTANT VERSION UPGRADE:
echo If ClawLab VRR 2.1.2 or any older release is installed, run its
echo RECOVERY\RESTORE_ORIGINAL_VRR.bat and complete the restart first.
echo Version 2.2.0 refuses to overwrite an older managed installation.
echo.
echo ===============================================================================
echo   UNTESTED DISPLAY OVERCLOCK - OUTSIDE MSI SPECIFICATIONS - EXTREME RISK
echo ===============================================================================
echo Profile: 48-180 Hz - UNSTABLE EXPERIMENTAL - NOT VALIDATED BY CLAWLAB
echo 180 Hz is entirely dependent on the individual panel silicon lottery.
echo This is not an MSI-certified operating mode.
echo.
echo After restart, the guarded test may flicker, show artifacts, or go black.
echo THE TEST AUTOMATICALLY RETURNS TO SAFE 120 HZ AFTER NO MORE THAN 15 SECONDS.
echo If the screen becomes unresponsive, WAIT PATIENTLY. DO NOT POWER OFF OR REBOOT.
echo Windows asks whether 180 Hz was reached only after safe 120 Hz is restored.
echo No, no answer, any failure, or a 30-second timeout restores the original profile.
echo Disconnect every external display before continuing. Only the internal panel may be active.
echo.
echo IMPORTANT: restore any different ClawLab profile first. If CRU was ever used,
echo run reset-all.exe from the current official CRU release and restart Windows.
echo If CRU has never been used on this Windows installation, no CRU reset is needed.
echo.
choice /C YN /N /M "Has CRU never been used, or was reset-all.exe followed by a restart? [Y/N] "
if errorlevel 2 (
  echo Guarded test cancelled safely. Complete the CRU reset and restart first.
  echo Official CRU page: https://www.monitortests.com/forum/Thread-Custom-Resolution-Utility-CRU
  pause
  exit /b 3
)
echo.
echo Disable or remove every other VRR/EDID tool. Only ClawTweaks 3.0 or later,
echo which includes the ClawLab VRR compatibility patch, may remain enabled.
echo ClawTweaks is optional and is not required for the ClawLab VRR fix.
echo.
choice /C YN /N /M "Is every conflicting VRR/EDID tool disabled or removed? [Y/N] "
if errorlevel 2 (
  echo Guarded test cancelled safely. Resolve the VRR ownership conflict first.
  pause
  exit /b 4
)
echo.
echo Please read the complete warning. Confirmation unlocks in 10 seconds...
timeout /t 10 /nobreak >nul
set "CLAWLAB_ACK="
set /p "CLAWLAB_ACK=Type I ACCEPT THE OVERCLOCK RISK to continue: "
if /I not "%CLAWLAB_ACK%"=="I ACCEPT THE OVERCLOCK RISK" (echo Guarded test cancelled safely.& pause& exit /b 2)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%CLAWLAB_SCRIPTS%MSI-Claw-VRR-Fix.ps1" -Action Install48_180
if errorlevel 1 goto :failed
echo The guarded 48-180 Hz trial is scheduled for the next Windows sign-in.
choice /C YN /N /M "Restart the PC now? [Y/N] "
if errorlevel 2 exit /b 0
shutdown.exe /r /t 0
exit /b 0
:failed
echo The experimental profile and guarded trial were not installed. Read the error above.
echo The installer automatically rolls back a failed trial-scheduling transaction.
pause
exit /b 1
