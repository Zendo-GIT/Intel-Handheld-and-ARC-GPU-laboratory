@echo off
setlocal
cd /d "%~dp0"
echo The Isle must be completely closed before installation.
echo This profile targets Evrima 0.21.784 / Steam build 24664737.
echo Select 1920x1200 in the game before running this installer.
echo It locks Engine.ini and GameUserSettings.ini read-only to preserve the profile.
echo Uninstall before changing graphics or input settings.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0The-Isle-Evrima-Claw-Fix.ps1" -Action Install
echo.
pause
