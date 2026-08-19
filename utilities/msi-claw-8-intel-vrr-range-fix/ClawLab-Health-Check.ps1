[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$packageRoot = Split-Path $PSCommandPath -Parent
$vrrTool = Join-Path $packageRoot 'MSI-Claw-VRR-Fix.ps1'
$lfcTool = Join-Path $packageRoot 'MSI-Claw-Intel-LFC-Fix.ps1'
$rangePolicyTool = Join-Path $packageRoot 'ArcSync-Range-Policy.ps1'
if (-not (Test-Path -LiteralPath $rangePolicyTool -PathType Leaf)) {
    throw "Required health policy is missing: $rangePolicyTool"
}
. $rangePolicyTool
$vrrBackupPath = Join-Path $env:LOCALAPPDATA 'ClawLab\Intel-Arc-Sync-Full-Range\original-profile.json'
$vrrTaskName = 'ClawLab MSI Claw 8 VRR Range'
$lfcTaskName = 'ClawLab MSI Claw Intel LFC Fix'

$vrrTask = Get-ScheduledTask -TaskName $vrrTaskName -ErrorAction SilentlyContinue
$lfcTask = Get-ScheduledTask -TaskName $lfcTaskName -ErrorAction SilentlyContinue
$startupInitializing = (
    ($null -ne $vrrTask -and [string]$vrrTask.State -eq 'Running') -or
    ($null -ne $lfcTask -and [string]$lfcTask.State -eq 'Running')
)

function Invoke-RequiredStatusQuery {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Operation
    )

    $result = @(& $Operation)
    $operationSucceeded = $?
    if (-not $operationSucceeded -or $result.Count -ne 1 -or $null -eq $result[0]) {
        throw "$Name status did not return exactly one valid state object."
    }
    return $result[0]
}

try {
    $vrr = Invoke-RequiredStatusQuery -Name 'VRR' -Operation { & $vrrTool -Action Status }
    $lfc = Invoke-RequiredStatusQuery -Name 'Intel LFC' -Operation { & $lfcTool -Action Status }
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
            CoreVrrAndLfcHealth = 'INITIALIZING'
            DesktopHelperHealth = 'INITIALIZING'
            CoreFixOperational = $false
            DesktopHelperOperational = $false
            AttentionReason = 'SIGN_IN_TASKS_RUNNING'
            RecommendedAction = 'Wait up to two minutes for sign-in initialization to finish, then run CHECK_STATUS.bat again.'
        }
        return
    }
    [pscustomobject]@{
        OverallHealth = 'ATTENTION_REQUIRED'
        StartupInitialization = 'COMPLETE_OR_IDLE'
        DriverVerification = 'STATUS_QUERY_FAILED'
        CurrentIntelDriver = 'UNKNOWN'
        DriverRecordedAtFirstInstall = 'UNKNOWN'
        ManagedProfileHealthy = $false
        CursorRefreshHelperHealthy = $false
        IntelLfcCorrectionHealthy = $false
        CoreVrrAndLfcHealth = 'ATTENTION_REQUIRED'
        DesktopHelperHealth = 'UNKNOWN'
        CoreFixOperational = $false
        DesktopHelperOperational = $false
        AttentionReason = 'STATUS_QUERY_FAILED'
        StatusQueryError = $_.Exception.Message
        RecommendedAction = 'Run CHECK_STATUS.bat and read the detailed VRR/LFC error. Do not Factory Reset or delete ClawLab AppData.'
    }
    return
}

$activeManagedStates = @(
    'CLAWLAB_30_120_ACTIVE',
    'OFFICIAL_48_120_ACTIVE',
    'EXPERIMENTAL_48_144_ACTIVE',
    'EXPERIMENTAL_48_165_ACTIVE',
    'EXPERIMENTAL_48_180_ACTIVE',
    'EXPERIMENTAL_48_192_ACTIVE',
    'EXPERIMENTAL_30_144_ACTIVE',
    'EXPERIMENTAL_30_165_ACTIVE',
    'EXPERIMENTAL_30_180_ACTIVE',
    'EXPERIMENTAL_30_192_ACTIVE'
)
$managedProfileHealthy = (
    [string]$vrr.State -in $activeManagedStates -and
    [string]$vrr.ProfileSwitchGuard -eq 'CONSISTENT'
)
$cursorHelperHealthy = [string]$vrr.CursorRefreshHelper -eq 'RUNNING_EVENT_DRIVEN'
$lfcFlagsHealthy = (
    $null -ne $lfc.CurrentState -and
    (-not [bool]$lfc.CurrentState.LowFpsSolutionEnabled) -and
    (-not [bool]$lfc.CurrentState.HighFpsSolutionEnabled)
)
$lfcHealthy = [bool]$lfc.LfcFixActive -and $lfcFlagsHealthy
$coreFixHealthy = $managedProfileHealthy -and $lfcHealthy
$lfcBackupMissing = [string]$lfc.LfcTransition.State -eq 'ORIGINAL_LFC_BACKUP_MISSING_CANNOT_RESTORE'
$cleanNotInstalled = Test-ClawLabCleanNotInstalledState `
    -ManagedMode ([string]$vrr.ManagedMode) `
    -ProfileSwitchGuard ([string]$vrr.ProfileSwitchGuard) `
    -OriginalProfileSaved ([bool]$vrr.OriginalProfileSaved) `
    -EdidOverride ([string]$vrr.EdidOverride) `
    -StartupReapply ([string]$vrr.StartupReapply) `
    -CursorRefreshHelper ([string]$vrr.CursorRefreshHelper) `
    -VrrTaskInstalled ($null -ne $vrrTask) `
    -LfcManagedMode ([string]$lfc.ManagedVrrMode) `
    -LfcBackupPresent ([bool]$lfc.LfcTransition.BackupPresent) `
    -LfcStartupPersistence ([string]$lfc.StartupPersistence) `
    -LfcFixActive ([bool]$lfc.LfcFixActive) `
    -LowFpsSolutionEnabled ($null -ne $lfc.CurrentState -and [bool]$lfc.CurrentState.LowFpsSolutionEnabled) `
    -HighFpsSolutionEnabled ($null -ne $lfc.CurrentState -and [bool]$lfc.CurrentState.HighFpsSolutionEnabled) `
    -LfcTaskInstalled ($null -ne $lfcTask)

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
$experimentalProfileActive = [string]$vrr.ManagedMode -in @(
    'CLAWLAB_48_144', 'CLAWLAB_48_165', 'CLAWLAB_48_180', 'CLAWLAB_48_192',
    'CLAWLAB_30_144', 'CLAWLAB_30_165', 'CLAWLAB_30_180', 'CLAWLAB_30_192'
)

$coreHealth = if ($cleanNotInstalled) { 'NOT_INSTALLED' } elseif ($coreFixHealthy) { 'HEALTHY' } elseif ($startupInitializing) { 'INITIALIZING' } else { 'ATTENTION_REQUIRED' }
$helperHealth = if ($cleanNotInstalled) { 'NOT_INSTALLED' } elseif ($cursorHelperHealthy) { 'HEALTHY' } elseif ($startupInitializing) { 'INITIALIZING' } else { 'ATTENTION_REQUIRED' }

$overallHealth = if ($cleanNotInstalled) {
    'CLEAN_NOT_INSTALLED'
}
elseif ($coreFixHealthy -and $cursorHelperHealthy) {
    'HEALTHY'
}
elseif ($startupInitializing) {
    'INITIALIZING'
}
elseif ($coreFixHealthy) {
    'CORE_HEALTHY_HELPER_ATTENTION'
}
else {
    'ATTENTION_REQUIRED'
}

$driverVerification = if (-not $driverChanged) {
    'CURRENT_OR_NOT_PREVIOUSLY_RECORDED'
}
elseif ($coreFixHealthy) {
    'DRIVER_CHANGED_AND_CURRENT_FIX_VERIFIED'
}
else {
    'DRIVER_CHANGED_RECHECK_REQUIRED'
}

$recommendedAction = switch ($overallHealth) {
    'CLEAN_NOT_INSTALLED' {
        if ([string]$vrr.DriverProfile -eq 'CUSTOM') {
            'Clean uninstall verified. Run the desired installer when ready; it will automatically try Intel RECOMMENDED, fall back to EXCELLENT when the driver silently retains CUSTOM, and save only the first standard profile verified by fresh readback. No Restore or Factory Reset is required.'
        }
        else {
            'Clean uninstall verified. Install one desired 30-120 or 48-120 profile when ready; no Restore or Factory Reset is required.'
        }
    }
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
    'CORE_HEALTHY_HELPER_ATTENTION' {
        'The game-facing VRR/LFC correction is healthy. Restart Windows once to repair only the optional desktop Cursor Refresh Helper; do not Factory Reset or delete ClawLab AppData.'
    }
    default {
        if ($lfcBackupMissing) {
            'The original Intel LFC backup is missing. Do not reinstall or delete AppData. Use EMERGENCY\SET_INTEL_LFC_FACTORY_DEFAULTS.bat only if restoring Intel factory defaults is intended.'
        }
        elseif ($managedProfileHealthy -and -not $lfcHealthy) {
            if ($experimentalProfileActive) {
                'Restart Windows once. If LfcFixActive remains False, restore the original VRR profile, restart, then rerun the desired guarded experimental installer.'
            }
            else {
                'Restart Windows once. If LfcFixActive remains False, reinstall the currently selected 30-120 or 48-120 profile.'
            }
        }
        elseif ($managedProfileHealthy -and -not $cursorHelperHealthy) {
            if ($experimentalProfileActive) {
                'Restart Windows once. The core VRR/LFC fix remains independent of the optional desktop helper; do not rerun a display-overclock trial only for a helper issue.'
            }
            else {
                'Restart Windows once. If the helper is still not running, reinstall the currently selected 30-120 or 48-120 profile.'
            }
        }
        else {
            'Restore Original VRR, restart Windows, install the desired 30-120 or 48-120 profile, then restart again.'
        }
    }
}

$attentionReason = if ($cleanNotInstalled) {
    'NONE'
}
elseif ($startupInitializing) {
    'SIGN_IN_TASKS_RUNNING'
}
elseif (-not $managedProfileHealthy) {
    'MANAGED_VRR_PROFILE_NOT_VERIFIED'
}
elseif ($lfcBackupMissing) {
    'ORIGINAL_LFC_BACKUP_MISSING_CANNOT_RESTORE'
}
elseif (-not $lfcHealthy) {
    'INTEL_LFC_CORRECTION_NOT_VERIFIED'
}
elseif (-not $cursorHelperHealthy) {
    'OPTIONAL_DESKTOP_HELPER_NOT_RUNNING'
}
else {
    'NONE'
}

[pscustomobject]@{
    OverallHealth = $overallHealth
    InstallationState = if ($cleanNotInstalled) { 'NOT_INSTALLED' } elseif ($coreFixHealthy) { 'INSTALLED' } else { 'INCOMPLETE_OR_UNVERIFIED' }
    StartupInitialization = if ($startupInitializing) { 'IN_PROGRESS' } else { 'COMPLETE_OR_IDLE' }
    DriverVerification = $driverVerification
    CurrentIntelDriver = [string]$vrr.IntelDriver
    DriverRecordedAtFirstInstall = if ($null -eq $savedDriver) { 'NOT_RECORDED' } else { $savedDriver }
    ManagedProfileHealthy = $managedProfileHealthy
    CursorRefreshHelperHealthy = $cursorHelperHealthy
    IntelLfcCorrectionHealthy = $lfcHealthy
    CoreVrrAndLfcHealth = $coreHealth
    DesktopHelperHealth = $helperHealth
    CoreFixOperational = $coreFixHealthy
    DesktopHelperOperational = $cursorHelperHealthy
    AttentionReason = $attentionReason
    RecommendedAction = $recommendedAction
}
