@echo off
setlocal
title Emergency Intel LFC factory defaults
set "CLAWLAB_SCRIPTS=%~dp0"
if exist "%~dp0..\scripts\MSI-Claw-Intel-LFC-Fix.ps1" set "CLAWLAB_SCRIPTS=%~dp0..\scripts\"
echo EMERGENCY ONLY: this sets both Intel low- and high-FPS VRR solutions to ON.
echo Use this only when the original ClawLab LFC backup was already lost and
echo CHECK_STATUS reports ORIGINAL_LFC_BACKUP_MISSING_CANNOT_RESTORE.
echo If a backup still exists, this operation is refused; use RECOVERY instead.
echo.
choice /C YN /N /M "Set Intel LFC factory defaults now? [Y/N] "
if errorlevel 2 exit /b 0
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%CLAWLAB_SCRIPTS%MSI-Claw-Intel-LFC-Fix.ps1" -Action FactoryDefaults
set "CLAWLAB_EXIT=%ERRORLEVEL%"
echo.
if not "%CLAWLAB_EXIT%"=="0" echo Factory defaults were not applied. Read the error above.
pause
exit /b %CLAWLAB_EXIT%
