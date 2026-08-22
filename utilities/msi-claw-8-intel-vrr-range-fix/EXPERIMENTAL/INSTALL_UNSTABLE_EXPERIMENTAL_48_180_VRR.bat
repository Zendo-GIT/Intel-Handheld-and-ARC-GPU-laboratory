@echo off
setlocal
set "CLAWLAB_POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%CLAWLAB_POWERSHELL%" exit /b 1
set "CLAWLAB_ROOT=%~dp0..\"
set "CLAWLAB_SCRIPTS=%CLAWLAB_ROOT%"
if exist "%CLAWLAB_ROOT%scripts\ClawLab-VRR-Transaction.ps1" set "CLAWLAB_SCRIPTS=%CLAWLAB_ROOT%scripts\"
"%CLAWLAB_POWERSHELL%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%CLAWLAB_SCRIPTS%ClawLab-VRR-Transaction.ps1" -Action Install48_180
exit /b %ERRORLEVEL%
