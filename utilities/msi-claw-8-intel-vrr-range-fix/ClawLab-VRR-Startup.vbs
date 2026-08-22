Option Explicit

Dim shell
Dim scriptPath
Dim powerShellPath
Dim command
Dim exitCode

Set shell = CreateObject("WScript.Shell")
scriptPath = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%\ClawLab\Intel-Arc-Sync-Full-Range\MSI-Claw-VRR-Fix.ps1")
powerShellPath = shell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")

command = Chr(34) & powerShellPath & Chr(34) & " -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File " & Chr(34) & scriptPath & Chr(34) & " -Action ApplyStartup -StartupSource VrrTask"
exitCode = shell.Run(command, 0, True)
WScript.Quit exitCode
