@echo off
setlocal
title MSI Claw Intel VRR 48-120 Fix
set "CLAWLAB_SCRIPTS=%~dp0"
if exist "%~dp0scripts\MSI-Claw-VRR-Fix.ps1" set "CLAWLAB_SCRIPTS=%~dp0scripts\"
echo IMPORTANT CRU preflight:
echo If Custom Resolution Utility ^(CRU^) was ever used on this Windows installation,
echo run reset-all.exe from the current official CRU release and restart Windows first.
echo.
choice /C YN /N /M "Has CRU never been used, or was reset-all.exe followed by a restart? [Y/N] "
if errorlevel 2 (
  echo Installation cancelled safely. Complete the CRU reset and restart, then run this installer again.
  echo Official CRU page: https://www.monitortests.com/forum/Thread-Custom-Resolution-Utility-CRU
  pause
  exit /b 2
)
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%CLAWLAB_SCRIPTS%MSI-Claw-VRR-Fix.ps1" -Action Install48
set "CLAWLAB_EXIT=%ERRORLEVEL%"
echo.
if not "%CLAWLAB_EXIT%"=="0" (
  echo The fix was not installed. Read the error above.
  pause
  exit /b %CLAWLAB_EXIT%
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%CLAWLAB_SCRIPTS%MSI-Claw-Intel-LFC-Fix.ps1" -Action Apply
set "CLAWLAB_EXIT=%ERRORLEVEL%"
echo.
if not "%CLAWLAB_EXIT%"=="0" (
  echo The 48-120 Hz profile was installed, but the Intel LFC fix failed.
  echo Run RECOVERY\RESTORE_ORIGINAL_VRR.bat before trying again.
  pause
  exit /b %CLAWLAB_EXIT%
)
echo The official 48-120 Hz profile and Intel LFC fix were installed and verified.
choice /C YN /N /M "Restart the PC now? [Y/N] "
if errorlevel 2 goto :done
shutdown.exe /r /t 0
:done
exit /b %CLAWLAB_EXIT%
