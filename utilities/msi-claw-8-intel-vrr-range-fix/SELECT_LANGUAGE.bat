@echo off
setlocal
set "CLAWLAB_POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%CLAWLAB_POWERSHELL%" exit /b 1
chcp 65001 >nul
title ClawLab language

set "CLAWLAB_SELECTOR=%~dp0tools\Select-ClawLab-Language.ps1"
if exist "%~dp0scripts\Select-ClawLab-Language.ps1" set "CLAWLAB_SELECTOR=%~dp0scripts\Select-ClawLab-Language.ps1"
"%CLAWLAB_POWERSHELL%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%CLAWLAB_SELECTOR%"
set "CLAWLAB_EXIT=%ERRORLEVEL%"

if not "%CLAWLAB_EXIT%"=="0" (
    echo.
    echo ClawLab language selection failed with exit code %CLAWLAB_EXIT%.
    pause
)

exit /b %CLAWLAB_EXIT%
