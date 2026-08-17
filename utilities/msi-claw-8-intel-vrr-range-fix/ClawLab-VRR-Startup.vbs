Option Explicit

Dim shell
Dim fileSystem
Dim scriptPath
Dim helperPath
Dim helperCommand
Dim powerShellPath
Dim command
Dim exitCode

Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")
scriptPath = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%\ClawLab\Intel-Arc-Sync-Full-Range\MSI-Claw-VRR-Fix.ps1")
helperPath = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%\ClawLab\Intel-Arc-Sync-Full-Range\ClawLab-Cursor-Refresh-Helper.exe")
powerShellPath = shell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")

' Start the non-elevated desktop helper before PowerShell, WMI and the Intel
' driver finish their slower sign-in initialization. The PowerShell startup
' path still verifies the installed helper and retries it if this best-effort
' launch could not remain active.
If fileSystem.FileExists(helperPath) Then
    helperCommand = Chr(34) & helperPath & Chr(34)
    On Error Resume Next
    shell.Run helperCommand, 0, False
    On Error GoTo 0
End If

command = Chr(34) & powerShellPath & Chr(34) & " -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File " & Chr(34) & scriptPath & Chr(34) & " -Action ApplyStartup"
exitCode = shell.Run(command, 0, True)
WScript.Quit exitCode
