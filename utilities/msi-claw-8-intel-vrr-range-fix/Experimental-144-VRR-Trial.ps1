[CmdletBinding()]
param(
    [ValidateSet('Schedule', 'Confirm', 'Status', 'Remove')]
    [string]$Action = 'Status',

    [ValidateSet('CLAWLAB_48_144', 'CLAWLAB_30_144')]
    [string]$Mode = 'CLAWLAB_48_144'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$toolVersion = '2.0.1'
$stateRoot = Join-Path $env:LOCALAPPDATA 'ClawLab\Intel-Arc-Sync-Full-Range'
$managedModePath = Join-Path $stateRoot 'managed-mode.json'
$experimentalStatePath = Join-Path $stateRoot 'experimental-edid.json'
$trialStatePath = Join-Path $stateRoot 'experimental-144-trial.json'
$installedTrialPath = Join-Path $stateRoot 'Experimental-144-VRR-Trial.ps1'
$installedLauncherPath = Join-Path $stateRoot 'ClawLab-144-Trial-Startup.vbs'
$installedDriverInterfacePath = Join-Path $stateRoot 'Intel-VRR-144-Trial-Driver-Interface.ps1'
$installedMainToolPath = Join-Path $stateRoot 'MSI-Claw-VRR-Fix.ps1'
$installedLfcToolPath = Join-Path $env:LOCALAPPDATA 'ClawLab\Intel-LFC-Fix\MSI-Claw-Intel-LFC-Fix.ps1'
$taskName = 'ClawLab MSI Claw 144 Hz Trial Confirmation'
$observationSeconds = 20
$confirmationTimeoutSeconds = 30

function Confirm-AdministratorOrRelaunch {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        return
    }
    $arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Action $Action -Mode $Mode"
    $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments -Wait -PassThru
    exit $process.ExitCode
}

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required trial state is missing: $Path"
    }
    return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json
}

function Get-TrialTaskState {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($null -eq $task) { return 'NOT_INSTALLED' }
    return [string]$task.State
}

function Remove-TrialArtifacts {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($null -ne $task) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
    }
    [IO.File]::Delete($trialStatePath)
    [IO.File]::Delete($installedLauncherPath)
    [IO.File]::Delete($installedDriverInterfacePath)
    [IO.File]::Delete($installedTrialPath)
}

function Show-TrialPopup {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Title,
        [int]$Seconds = 0,
        [int]$Type = 48
    )

    $shell = New-Object -ComObject WScript.Shell
    return $shell.Popup($Text, $Seconds, $Title, $Type)
}

function Restore-ExperimentalProfile {
    param([Parameter(Mandatory)][string]$Reason)

    if (-not (Test-Path -LiteralPath $installedMainToolPath -PathType Leaf)) {
        throw 'The installed ClawLab VRR restore tool is missing. Run RESTORE_ORIGINAL_VRR.bat from the release package.'
    }
    if (-not (Test-Path -LiteralPath $installedLfcToolPath -PathType Leaf)) {
        throw 'The installed Intel LFC restore tool is missing. Run RESTORE_ORIGINAL_VRR.bat from the release package.'
    }
    $lfcArguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$installedLfcToolPath`" -Action Restore"
    $lfcProcess = Start-Process -FilePath 'powershell.exe' -ArgumentList $lfcArguments -WindowStyle Hidden -Wait -PassThru
    if ($lfcProcess.ExitCode -ne 0) {
        throw "Automatic Intel LFC rollback failed with exit code $($lfcProcess.ExitCode). Run RESTORE_ORIGINAL_VRR.bat from the release package."
    }
    $arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$installedMainToolPath`" -Action Restore"
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "Automatic experimental-profile rollback failed with exit code $($process.ExitCode). Run RESTORE_ORIGINAL_VRR.bat from the release package."
    }

    Remove-TrialArtifacts
    $message = "The experimental 144 Hz profile was restored because: $Reason`r`n`r`nWindows will restart in 15 seconds to reload the physical panel EDID."
    [void](Show-TrialPopup -Text $message -Title 'ClawLab experimental VRR rollback' -Seconds 12 -Type 48)
    Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\shutdown.exe') `
        -ArgumentList '/r /t 15 /c "ClawLab experimental VRR rollback"' -WindowStyle Hidden | Out-Null
}

try {
    switch ($Action) {
        'Schedule' {
            Confirm-AdministratorOrRelaunch
            $managed = Read-JsonFile -Path $managedModePath
            $experimental = Read-JsonFile -Path $experimentalStatePath
            if ([string]$managed.Mode -ne $Mode -or [string]$experimental.Mode -ne $Mode) {
                throw "The managed and EDID states do not both match the requested trial mode $Mode."
            }

            $sourceLauncherPath = Join-Path $PSScriptRoot 'ClawLab-144-Trial-Startup.vbs'
            $sourceDriverInterfacePath = Join-Path $PSScriptRoot 'Intel-VRR-LFC-Driver-Interface.ps1'
            foreach ($path in @($sourceLauncherPath, $sourceDriverInterfacePath, $installedMainToolPath, $installedLfcToolPath)) {
                if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                    throw "Required trial file is missing: $path"
                }
            }

            [IO.Directory]::CreateDirectory($stateRoot) | Out-Null
            [IO.File]::Copy($PSCommandPath, $installedTrialPath, $true)
            [IO.File]::Copy($sourceLauncherPath, $installedLauncherPath, $true)
            [IO.File]::Copy($sourceDriverInterfacePath, $installedDriverInterfacePath, $true)
            foreach ($pair in @(
                @($PSCommandPath, $installedTrialPath),
                @($sourceLauncherPath, $installedLauncherPath),
                @($sourceDriverInterfacePath, $installedDriverInterfacePath)
            )) {
                if ((Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash -ne
                    (Get-FileHash -LiteralPath $pair[1] -Algorithm SHA256).Hash) {
                    throw "Trial-file verification failed: $($pair[1])"
                }
            }

            $trialState = [ordered]@{
                SchemaVersion = 1
                ToolVersion = $toolVersion
                Mode = $Mode
                ScheduledAt = (Get-Date).ToString('o')
                ObservationSeconds = $observationSeconds
                ConfirmationTimeoutSeconds = $confirmationTimeoutSeconds
            }
            [IO.File]::WriteAllText(
                $trialStatePath,
                ($trialState | ConvertTo-Json),
                [Text.UTF8Encoding]::new($false)
            )

            $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $wscriptPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
            $taskAction = New-ScheduledTaskAction -Execute $wscriptPath -Argument "//B //Nologo `"$installedLauncherPath`""
            $trigger = New-ScheduledTaskTrigger -AtLogOn -User $identity.Name
            $principal = New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Highest
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 6)
            $task = New-ScheduledTask -Action $taskAction -Trigger $trigger -Principal $principal `
                -Settings $settings -Description 'Validates an experimental MSI Claw 144 Hz profile, waits 20 seconds, then requires confirmation or rolls back.'
            Register-ScheduledTask -TaskName $taskName -InputObject $task -Force | Out-Null
            if ((Get-TrialTaskState) -eq 'NOT_INSTALLED') {
                throw 'The experimental confirmation task could not be verified.'
            }
            Write-Host "Experimental $($Mode.Replace('CLAWLAB_', '').Replace('_', '-')) Hz trial is scheduled for the next sign-in." -ForegroundColor Yellow
            Write-Host 'After the verified profile has run for 20 seconds, choose Yes to keep it or No to restore it.' -ForegroundColor Yellow
            Write-Host 'No answer within 30 seconds is treated as No and triggers automatic rollback plus restart.' -ForegroundColor Yellow
        }

        'Confirm' {
            $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $principal = [Security.Principal.WindowsPrincipal]::new($identity)
            if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                throw 'The experimental confirmation task is not running with its registered highest privileges.'
            }
            $trial = Read-JsonFile -Path $trialStatePath
            $Mode = [string]$trial.Mode
            if ($Mode -notin @('CLAWLAB_48_144', 'CLAWLAB_30_144')) {
                throw "Invalid experimental trial mode: $Mode"
            }
            $expectedMinimumHz = if ($Mode -eq 'CLAWLAB_30_144') { 30 } else { 48 }
            $verified = $false
            for ($attempt = 1; $attempt -le 90; $attempt++) {
                try {
                    $driverState = & $installedDriverInterfacePath -Action Status
                    if ($driverState.Supported -and $driverState.Enabled -and
                        [int]$driverState.MinimumHz -eq $expectedMinimumHz -and
                        [int]$driverState.MaximumHz -eq 144 -and
                        -not [bool]$driverState.LowFpsSolutionEnabled -and
                        -not [bool]$driverState.HighFpsSolutionEnabled) {
                        $verified = $true
                        break
                    }
                }
                catch {}
                Start-Sleep -Seconds 2
            }
            if (-not $verified) {
                Restore-ExperimentalProfile -Reason 'the driver did not verify both the requested range and the shared LFC x2 correction after sign-in'
                break
            }

            Start-Sleep -Seconds $observationSeconds
            $rangeText = "$expectedMinimumHz-144 Hz"
            $message = "The experimental $rangeText profile and shared LFC x2 correction have been active and verified for 20 seconds.`r`n`r`nKeep this custom VRR range?`r`n`r`nYES: keep it and remove the trial task.`r`nNO or no answer: restore the previous profile and restart Windows.`r`n`r`nThe test will default to NO after 30 seconds."
            $choice = Show-TrialPopup -Text $message -Title "ClawLab experimental $rangeText confirmation" `
                -Seconds $confirmationTimeoutSeconds -Type (4 + 48 + 4096)
            if ($choice -eq 6) {
                Remove-TrialArtifacts
                [void](Show-TrialPopup -Text "The experimental $rangeText profile was kept. You can restore it later with RESTORE_ORIGINAL_VRR.bat." `
                    -Title 'ClawLab experimental VRR profile kept' -Seconds 12 -Type 64)
            }
            else {
                $reason = if ($choice -eq 7) { 'you selected No' } else { 'the confirmation timed out or was closed' }
                Restore-ExperimentalProfile -Reason $reason
            }
        }

        'Status' {
            $trial = if (Test-Path -LiteralPath $trialStatePath -PathType Leaf) { Read-JsonFile -Path $trialStatePath } else { $null }
            [pscustomobject]@{
                ToolVersion = $toolVersion
                TrialState = if ($null -eq $trial) { 'NOT_SCHEDULED' } else { 'AWAITING_CONFIRMATION' }
                Mode = if ($null -eq $trial) { $null } else { [string]$trial.Mode }
                TaskState = Get-TrialTaskState
                ObservationSeconds = $observationSeconds
                ConfirmationTimeoutSeconds = $confirmationTimeoutSeconds
            }
        }

        'Remove' {
            Confirm-AdministratorOrRelaunch
            Remove-TrialArtifacts
            Write-Host 'The experimental 144 Hz confirmation task was removed. The active VRR profile was not changed.' -ForegroundColor Green
        }
    }
}
catch {
    try {
        if ($Action -eq 'Confirm') {
            [void](Show-TrialPopup -Text ("Automatic trial handling failed:`r`n`r`n" + $_.Exception.Message + "`r`n`r`nRun RESTORE_ORIGINAL_VRR.bat from the release package.") `
                -Title 'ClawLab experimental VRR error' -Seconds 0 -Type (16 + 4096))
        }
    }
    catch {}
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
