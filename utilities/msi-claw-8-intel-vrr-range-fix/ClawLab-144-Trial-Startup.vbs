Option Explicit

Dim shell
Dim fileSystem
Dim scriptDirectory
Dim powerShellPath
Dim toolPath
Dim command

Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")
scriptDirectory = fileSystem.GetParentFolderName(WScript.ScriptFullName)
powerShellPath = shell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")
toolPath = fileSystem.BuildPath(scriptDirectory, "Experimental-144-VRR-Trial.ps1")
command = Chr(34) & powerShellPath & Chr(34) & " -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " & Chr(34) & toolPath & Chr(34) & " -Action Confirm"

shell.Run command, 0, True
