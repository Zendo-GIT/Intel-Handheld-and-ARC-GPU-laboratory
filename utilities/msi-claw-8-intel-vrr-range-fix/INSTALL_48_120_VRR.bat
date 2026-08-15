@echo off
setlocal
title MSI Claw 8 AI+ / 8 EX AI+ VRR 48-120 Fix
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0MSI-Claw-VRR-Fix.ps1" -Action Install48
set "CLAWLAB_EXIT=%ERRORLEVEL%"
echo.
if not "%CLAWLAB_EXIT%"=="0" (
  echo The fix was not installed. Read the error above.
  pause
  exit /b %CLAWLAB_EXIT%
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0MSI-Claw-Intel-LFC-Fix.ps1" -Action Apply
set "CLAWLAB_EXIT=%ERRORLEVEL%"
echo.
if not "%CLAWLAB_EXIT%"=="0" (
  echo The 48-120 Hz profile was installed, but the Intel LFC fix failed.
  echo Run RESTORE_ORIGINAL_VRR.bat before trying again.
  pause
  exit /b %CLAWLAB_EXIT%
)
echo The official 48-120 Hz profile and Intel LFC fix were installed and verified.
choice /C YN /N /M "Restart the PC now? [Y/N] "
if errorlevel 2 goto :done
shutdown.exe /r /t 0
:done
exit /b %CLAWLAB_EXIT%
