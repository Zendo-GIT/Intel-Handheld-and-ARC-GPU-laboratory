[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$packageRoot = Split-Path $PSCommandPath -Parent
$vrrTool = Join-Path $packageRoot 'MSI-Claw-VRR-Fix.ps1'
$lfcTool = Join-Path $packageRoot 'MSI-Claw-Intel-LFC-Fix.ps1'
$vrrBackupPath = Join-Path $env:LOCALAPPDATA 'ClawLab\Intel-Arc-Sync-Full-Range\original-profile.json'
$vrrTaskName = 'ClawLab MSI Claw 8 VRR Range'
$lfcTaskName = 'ClawLab MSI Claw Intel LFC Fix'

$vrrTask = Get-ScheduledTask -TaskName $vrrTaskName -ErrorAction SilentlyContinue
$lfcTask = Get-ScheduledTask -TaskName $lfcTaskName -ErrorAction SilentlyContinue
$startupInitializing = (
    ($null -ne $vrrTask -and [string]$vrrTask.State -eq 'Running') -or
    ($null -ne $lfcTask -and [string]$lfcTask.State -eq 'Running')
)

try {
    $vrr = & $vrrTool -Action Status
    $lfc = & $lfcTool -Action Status
}
catch {
    if ($startupInitializing) {
        [pscustomobject]@{
            OverallHealth = 'INITIALIZING'
            StartupInitialization = 'IN_PROGRESS'
            DriverVerification = 'PENDING_DRIVER_AVAILABILITY'
            CurrentIntelDriver = 'PENDING'
            DriverRecordedAtFirstInstall = 'PENDING'
            ManagedProfileHealthy = 'PENDING'
            CursorRefreshHelperHealthy = 'PENDING'
            IntelLfcCorrectionHealthy = 'PENDING'
            RecommendedAction = 'Wait up to two minutes for sign-in initialization to finish, then run CHECK_STATUS.bat again.'
        }
        exit 0
    }
    throw
}

$managedProfileHealthy = (
    [string]$vrr.State -in @('CLAWLAB_30_120_ACTIVE', 'OFFICIAL_48_120_ACTIVE') -and
    [string]$vrr.ProfileSwitchGuard -eq 'CONSISTENT'
)
$cursorHelperHealthy = [string]$vrr.CursorRefreshHelper -eq 'RUNNING_EVENT_DRIVEN'
$lfcFlagsHealthy = (
    $null -ne $lfc.CurrentState -and
    (-not [bool]$lfc.CurrentState.LowFpsSolutionEnabled) -and
    (-not [bool]$lfc.CurrentState.HighFpsSolutionEnabled)
)
$lfcHealthy = [bool]$lfc.LfcFixActive -and $lfcFlagsHealthy

$savedDriver = $null
if (Test-Path -LiteralPath $vrrBackupPath -PathType Leaf) {
    try {
        $backup = [IO.File]::ReadAllText($vrrBackupPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        if ('IntelDriverVersion' -in $backup.PSObject.Properties.Name) {
            $savedDriver = [string]$backup.IntelDriverVersion
        }
    }
    catch {
        $savedDriver = $null
    }
}

$driverChanged = (
    -not [string]::IsNullOrWhiteSpace($savedDriver) -and
    $savedDriver -ne [string]$vrr.IntelDriver
)

$overallHealth = if ($managedProfileHealthy -and $cursorHelperHealthy -and $lfcHealthy) {
    'HEALTHY'
}
elseif ($startupInitializing) {
    'INITIALIZING'
}
else {
    'ATTENTION_REQUIRED'
}

$driverVerification = if (-not $driverChanged) {
    'CURRENT_OR_NOT_PREVIOUSLY_RECORDED'
}
elseif ($overallHealth -eq 'HEALTHY') {
    'DRIVER_CHANGED_AND_CURRENT_FIX_VERIFIED'
}
else {
    'DRIVER_CHANGED_RECHECK_REQUIRED'
}

$recommendedAction = switch ($overallHealth) {
    'HEALTHY' {
        if ($driverChanged) {
            'No repair is required: the new Intel driver is already verified. Keep this result for reference.'
        }
        else {
            'None.'
        }
    }
    'INITIALIZING' {
        'Wait up to two minutes for sign-in initialization to finish, then run CHECK_STATUS.bat again.'
    }
    default {
        if ($managedProfileHealthy -and -not $cursorHelperHealthy) {
            'Restart Windows once. If the helper is still not running, reinstall the currently selected 30-120 or 48-120 profile.'
        }
        elseif ($managedProfileHealthy -and -not $lfcHealthy) {
            'Restart Windows once. If LfcFixActive remains False, reinstall the currently selected 30-120 or 48-120 profile.'
        }
        else {
            'Restore Original VRR, restart Windows, install the desired 30-120 or 48-120 profile, then restart again.'
        }
    }
}

[pscustomobject]@{
    OverallHealth = $overallHealth
    StartupInitialization = if ($startupInitializing) { 'IN_PROGRESS' } else { 'COMPLETE_OR_IDLE' }
    DriverVerification = $driverVerification
    CurrentIntelDriver = [string]$vrr.IntelDriver
    DriverRecordedAtFirstInstall = if ($null -eq $savedDriver) { 'NOT_RECORDED' } else { $savedDriver }
    ManagedProfileHealthy = $managedProfileHealthy
    CursorRefreshHelperHealthy = $cursorHelperHealthy
    IntelLfcCorrectionHealthy = $lfcHealthy
    RecommendedAction = $recommendedAction
}
