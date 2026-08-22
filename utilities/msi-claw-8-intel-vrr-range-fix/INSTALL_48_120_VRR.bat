@echo off
setlocal
set "CLAWLAB_POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%CLAWLAB_POWERSHELL%" exit /b 1
set "CLAWLAB_SCRIPTS=%~dp0"
if exist "%~dp0scripts\ClawLab-VRR-Transaction.ps1" set "CLAWLAB_SCRIPTS=%~dp0scripts\"
"%CLAWLAB_POWERSHELL%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%CLAWLAB_SCRIPTS%ClawLab-VRR-Transaction.ps1" -Action Install48
exit /b %ERRORLEVEL%
