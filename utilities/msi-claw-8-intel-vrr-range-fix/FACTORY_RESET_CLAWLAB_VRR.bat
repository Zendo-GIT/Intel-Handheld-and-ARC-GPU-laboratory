@echo off
setlocal
cd /d "%~dp0"
title MSI Claw Intel ClawLab VRR Factory Reset
echo This recovery removes every exact ClawLab VRR override and managed task.
echo It restores the detected panel's native resolution at 120 Hz and Intel RECOMMENDED mode.
echo Unknown third-party EDID overrides are refused and will not be removed.
echo.
choice /C YN /N /M "Continue with the ClawLab VRR factory reset? [Y/N] "
if errorlevel 2 exit /b 0
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0MSI-Claw-Intel-LFC-Fix.ps1" -Action Restore
set "CLAWLAB_EXIT=%ERRORLEVEL%"
echo.
if not "%CLAWLAB_EXIT%"=="0" (
  echo The saved Intel LFC state could not be restored. Factory reset stopped safely.
  echo Read the error above and do not delete this package.
  pause
  exit /b %CLAWLAB_EXIT%
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0MSI-Claw-VRR-Fix.ps1" -Action FactoryReset
set "CLAWLAB_EXIT=%ERRORLEVEL%"
echo.
if not "%CLAWLAB_EXIT%"=="0" (
  echo Factory reset was not completed. Read the error above.
  pause
  exit /b %CLAWLAB_EXIT%
)
choice /C YN /N /M "Restart the PC now to reload the physical EDID? [Y/N] "
if errorlevel 2 goto :done
shutdown.exe /r /t 0
:done
exit /b %CLAWLAB_EXIT%
