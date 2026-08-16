Option Explicit

Dim shell
Dim fileSystem
Dim scriptDirectory
Dim scriptPath
Dim powerShellPath
Dim command

Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")
scriptDirectory = fileSystem.GetParentFolderName(WScript.ScriptFullName)
scriptPath = fileSystem.BuildPath(scriptDirectory, "Experimental-Overclock-VRR-Trial.ps1")
powerShellPath = shell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")
command = Chr(34) & powerShellPath & Chr(34) & " -NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File " & Chr(34) & scriptPath & Chr(34) & " -Action Run"
shell.Run command, 0, False
