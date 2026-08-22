[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$packageRoot = Split-Path $PSCommandPath -Parent
$vrrTool = Join-Path $packageRoot 'MSI-Claw-VRR-Fix.ps1'
$lfcTool = Join-Path $packageRoot 'MSI-Claw-Intel-LFC-Fix.ps1'
$rangePolicyTool = Join-Path $packageRoot 'ArcSync-Range-Policy.ps1'
$scheduledTaskTool = Join-Path $packageRoot 'Scheduled-Task-Persistence.ps1'
foreach ($requiredTool in @($rangePolicyTool, $scheduledTaskTool)) {
    if (-not (Test-Path -LiteralPath $requiredTool -PathType Leaf)) {
        throw "Required health component is missing: $requiredTool"
    }
}
. $rangePolicyTool
. $scheduledTaskTool
$vrrBackupPath = Join-Path $env:LOCALAPPDATA 'ClawLab\Intel-Arc-Sync-Full-Range\original-profile.json'
$transactionJournalPath = Join-Path $env:LOCALAPPDATA 'ClawLab\VRR-Transaction\transaction.json'
$vrrTaskName = 'ClawLab MSI Claw 8 VRR Range'
$cursorTaskName = 'ClawLab MSI Claw Cursor Refresh Engine'
$lfcTaskName = 'ClawLab MSI Claw Intel LFC Fix'

function Get-ClawLabHealthTaskQuery {
    param([Parameter(Mandatory)][string]$Name)

    try {
        $record = Get-ClawLabScheduledTaskRecord -TaskName $Name
        if ($null -eq $record) {
            return [pscustomobject]@{
                QueryState = 'ABSENT'
                Record = $null
                Error = $null
            }
        }
        return [pscustomobject]@{
            QueryState = 'PRESENT'
            Record = $record
            Error = $null
        }
    }
    catch {
        return [pscustomobject]@{
            QueryState = 'TASK_QUERY_ERROR'
            Record = $null
            Error = $_.Exception.Message
        }
    }
}

$vrrTaskQuery = Get-ClawLabHealthTaskQuery -Name $vrrTaskName
$cursorTaskQuery = Get-ClawLabHealthTaskQuery -Name $cursorTaskName
$lfcTaskQuery = Get-ClawLabHealthTaskQuery -Name $lfcTaskName
$vrrTask = $vrrTaskQuery.Record
$cursorTask = $cursorTaskQuery.Record
$lfcTask = $lfcTaskQuery.Record
$taskQueryFailed = (
    [string]$vrrTaskQuery.QueryState -eq 'TASK_QUERY_ERROR' -or
    [string]$cursorTaskQuery.QueryState -eq 'TASK_QUERY_ERROR' -or
    [string]$lfcTaskQuery.QueryState -eq 'TASK_QUERY_ERROR'
)
$taskQueryErrors = @(
    if ([string]$vrrTaskQuery.QueryState -eq 'TASK_QUERY_ERROR') {
        "${vrrTaskName}: $($vrrTaskQuery.Error)"
    }
    if ([string]$cursorTaskQuery.QueryState -eq 'TASK_QUERY_ERROR') {
        "${cursorTaskName}: $($cursorTaskQuery.Error)"
    }
    if ([string]$lfcTaskQuery.QueryState -eq 'TASK_QUERY_ERROR') {
        "${lfcTaskName}: $($lfcTaskQuery.Error)"
    }
)
$startupInitializing = -not $taskQueryFailed -and (
    ([string]$vrrTaskQuery.QueryState -eq 'PRESENT' -and [string]$vrrTask.State -eq 'Running') -or
    ([string]$lfcTaskQuery.QueryState -eq 'PRESENT' -and [string]$lfcTask.State -eq 'Running')
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
$cursorHelperHealthy = [string]$vrr.CursorRefreshHelper -eq 'RUNNING_NATIVE_DXGI'
$lfcFlagsHealthy = (
    $null -ne $lfc.CurrentState -and
    (-not [bool]$lfc.CurrentState.LowFpsSolutionEnabled) -and
    (-not [bool]$lfc.CurrentState.HighFpsSolutionEnabled)
)
$lfcHealthy = [bool]$lfc.LfcFixActive -and $lfcFlagsHealthy
$coreFixHealthy = $managedProfileHealthy -and $lfcHealthy
$lfcBackupMissing = [string]$lfc.LfcTransition.State -eq 'ORIGINAL_LFC_BACKUP_MISSING_CANNOT_RESTORE'
$lfcFactoryRecoveryPending = [bool]$lfc.FactoryIntentPresent -or
    [string]$lfc.LfcTransition.State -in @(
        'INTEL_VRR_SOLUTIONS_FACTORY_DEFAULTS_PENDING_RESUME',
        'INTEL_VRR_SOLUTIONS_FACTORY_DEFAULTS_FINALIZATION_PENDING'
    )
$transactionJournalPresent = Test-Path -LiteralPath $transactionJournalPath -PathType Leaf
$transactionJournal = $null
$transactionJournalReadError = $null
if ($transactionJournalPresent) {
    try {
        $transactionJournal = [IO.File]::ReadAllText(
            $transactionJournalPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    }
    catch {
        $transactionJournalReadError = $_.Exception.Message
    }
}
$cleanNotInstalled = -not $transactionJournalPresent -and -not $taskQueryFailed -and (Test-ClawLabCleanNotInstalledState `
    -ManagedMode ([string]$vrr.ManagedMode) `
    -ProfileSwitchGuard ([string]$vrr.ProfileSwitchGuard) `
    -OriginalProfileSaved ([bool]$vrr.OriginalProfileSaved) `
    -EdidOverride ([string]$vrr.EdidOverride) `
    -StartupReapply ([string]$vrr.StartupReapply) `
    -CursorRefreshHelper ([string]$vrr.CursorRefreshHelper) `
    -VrrTaskInstalled ($null -ne $vrrTask) `
    -VrrRecoveryRequired ([bool]$vrr.RecoveryRequired) `
    -LfcManagedMode ([string]$lfc.ManagedVrrMode) `
    -LfcBackupPresent ([bool]$lfc.LfcTransition.BackupPresent) `
    -LfcStartupPersistence ([string]$lfc.StartupPersistence) `
    -LfcFixActive ([bool]$lfc.LfcFixActive) `
    -LowFpsSolutionEnabled ($null -ne $lfc.CurrentState -and [bool]$lfc.CurrentState.LowFpsSolutionEnabled) `
    -HighFpsSolutionEnabled ($null -ne $lfc.CurrentState -and [bool]$lfc.CurrentState.HighFpsSolutionEnabled) `
    -LfcTransitionState ([string]$lfc.LfcTransition.State) `
    -LfcRestoreFinalizedPresent ([bool]$lfc.RestoreFinalizedPresent) `
    -LfcRestoreFinalizedVerified ([bool]$lfc.LfcTransition.RestoreFinalizedVerified) `
    -LfcFactoryIntentPresent ([bool]$lfc.FactoryIntentPresent) `
    -LfcFactoryFinalizedPresent ([bool]$lfc.FactoryFinalizedPresent) `
    -LfcFactoryFinalizedVerified ([bool]$lfc.LfcTransition.FactoryFinalizedVerified) `
    -LfcTaskInstalled ([string]$lfcTaskQuery.QueryState -eq 'PRESENT'))

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

$coreHealth = if ($cleanNotInstalled) { 'NOT_INSTALLED' } elseif ($taskQueryFailed) { 'ATTENTION_REQUIRED' } elseif ($coreFixHealthy) { 'HEALTHY' } elseif ($startupInitializing) { 'INITIALIZING' } else { 'ATTENTION_REQUIRED' }
$helperHealth = if ($cleanNotInstalled) { 'NOT_INSTALLED' } elseif ($cursorHelperHealthy) { 'HEALTHY' } elseif ($startupInitializing) { 'INITIALIZING' } else { 'ATTENTION_REQUIRED' }

$overallHealth = if ($cleanNotInstalled) {
    'CLEAN_NOT_INSTALLED'
}
elseif ($taskQueryFailed) {
    'ATTENTION_REQUIRED'
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

$driverVerification = if ($taskQueryFailed) {
    'TASK_PERSISTENCE_NOT_VERIFIED'
}
elseif (-not $driverChanged) {
    'CURRENT_OR_NOT_PREVIOUSLY_RECORDED'
}
elseif ($coreFixHealthy) {
    'DRIVER_CHANGED_AND_CURRENT_FIX_VERIFIED'
}
else {
    'DRIVER_CHANGED_RECHECK_REQUIRED'
}

$cleanTma2027OemCustom = (
    $cleanNotInstalled -and
    [string]$vrr.PanelId -eq 'TMA2027' -and
    [string]$vrr.ArcSyncMonitorTelemetry -eq 'INTEL_CONTROL_LIB_HALF_PHYSICAL_FLOOR' -and
    [string]$vrr.DriverProfile -eq 'CUSTOM' -and
    [string]$vrr.DriverActiveRange -eq '30-120 Hz' -and
    [uint32]$vrr.DriverProfileMaxIncreaseUs -eq 8333 -and
    [uint32]$vrr.DriverProfileMaxDecreaseUs -eq 8333
)

$orphanedDefaultVrrShell = $false
if (-not $taskQueryFailed -and $transactionJournalPresent -and
    $null -ne $transactionJournal -and
    [string]::IsNullOrWhiteSpace($transactionJournalReadError)) {
    $orphanedDefaultVrrShell = Test-ClawLabOrphanedDefaultShellEvidence `
        -Vrr $vrr -Lfc $lfc `
        -VrrTaskQuery ([string]$vrrTaskQuery.QueryState) `
        -CursorTaskQuery ([string]$cursorTaskQuery.QueryState) `
        -LfcTaskQuery ([string]$lfcTaskQuery.QueryState) `
        -TransactionJournal $transactionJournal
}

$recommendedAction = switch ($overallHealth) {
    'CLEAN_NOT_INSTALLED' {
        if ($cleanTma2027OemCustom) {
            'Clean uninstall verified with the exact A1M/Claw 7 AI+ OEM CUSTOM 30-120 baseline. INSTALL_30_120_VRR may preserve this read-only Intel profile without calling the rejected RECOMMENDED/EXCELLENT setters. The 48-120 and display-overclock installers remain blocked while this driver exposes that OEM state. No Restore or Factory Reset is required.'
        }
        elseif ([string]$vrr.DriverProfile -eq 'CUSTOM') {
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
        'The game-facing VRR/LFC correction is healthy. Run UPDATE_CURSOR_REFRESH_ENGINE.bat to repair only the desktop engine without restoring or reinstalling the VRR/LFC profile.'
    }
    default {
        if ($orphanedDefaultVrrShell) {
            'A failed legacy restore left one owned ClawLab startup shell while fresh readback proves the exact Intel factory VRR/LFC state. Run RECOVERY\RESTORE_ORIGINAL_VRR.bat once from this corrected 2.3.0 package, accept UAC, restart Windows, then run CHECK_STATUS.bat. The bounded recovery removes only the stale ClawLab task and payloads; it does not write the display profile or EDID.'
        }
        elseif ($transactionJournalPresent) {
            'An interrupted VRR transaction journal is present. With version 2.3.0, rerun the desired installer: it will remove this journal only after independently verifying a completely clean VRR/LFC, task and protected-runtime state. If the installer still refuses, run Restore Original VRR; do not Factory Reset or delete ClawLab AppData.'
        }
        elseif ($taskQueryFailed) {
            'Task Scheduler could not be queried. Restart Windows once, then run CHECK_STATUS.bat again. Do not Restore, Factory Reset, reinstall, or delete ClawLab AppData until the task query succeeds.'
        }
        elseif ($lfcBackupMissing) {
            'The original Intel LFC backup is missing. Do not reinstall or delete AppData. Use EMERGENCY\SET_INTEL_LFC_FACTORY_DEFAULTS.bat only if restoring Intel factory defaults is intended.'
        }
        elseif ($lfcFactoryRecoveryPending) {
            'An Intel LFC factory-default transaction is incomplete. Rerun EMERGENCY\SET_INTEL_LFC_FACTORY_DEFAULTS.bat to resume the same durable transaction; do not install another profile or delete ClawLab AppData.'
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
            'Run UPDATE_CURSOR_REFRESH_ENGINE.bat. It updates only the desktop engine and preserves the currently verified VRR/LFC profile, including an experimental profile.'
        }
        else {
            'Restore Original VRR, restart Windows, install the desired 30-120 or 48-120 profile, then restart again.'
        }
    }
}

$attentionReason = if ($orphanedDefaultVrrShell) {
    'ORPHANED_DEFAULT_VRR_SHELL_RECOVERABLE'
}
elseif ($transactionJournalPresent) {
    'INTERRUPTED_VRR_TRANSACTION'
}
elseif ($cleanNotInstalled) {
    'NONE'
}
elseif ($startupInitializing) {
    'SIGN_IN_TASKS_RUNNING'
}
elseif ($taskQueryFailed) {
    'TASK_QUERY_ERROR'
}
elseif (-not $managedProfileHealthy) {
    'MANAGED_VRR_PROFILE_NOT_VERIFIED'
}
elseif ($lfcBackupMissing) {
    'ORIGINAL_LFC_BACKUP_MISSING_CANNOT_RESTORE'
}
elseif ($lfcFactoryRecoveryPending) {
    'INTEL_LFC_FACTORY_DEFAULTS_RECOVERY_PENDING'
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
    InstallationState = if ($cleanNotInstalled) { 'NOT_INSTALLED' } elseif ($coreFixHealthy -and -not $taskQueryFailed) { 'INSTALLED' } else { 'INCOMPLETE_OR_UNVERIFIED' }
    StartupInitialization = if ($startupInitializing) { 'IN_PROGRESS' } else { 'COMPLETE_OR_IDLE' }
    StartupTaskQuery = if ($taskQueryFailed) { 'TASK_QUERY_ERROR' } else { 'OK' }
    VrrStartupTaskQuery = [string]$vrrTaskQuery.QueryState
    CursorRefreshTaskQuery = [string]$cursorTaskQuery.QueryState
    IntelLfcStartupTaskQuery = [string]$lfcTaskQuery.QueryState
    TaskQueryError = if ($taskQueryErrors.Count -eq 0) { $null } else { $taskQueryErrors -join ' | ' }
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
    NormalizationCompensation = [string]$vrr.NormalizationCompensation
    IntelLfcTransitionState = [string]$lfc.LfcTransition.State
    IntelLfcFactoryIntentPresent = [bool]$lfc.FactoryIntentPresent
    IntelLfcFactoryFinalizedPresent = [bool]$lfc.FactoryFinalizedPresent
    IntelLfcFactoryFinalizedVerified = [bool]$lfc.LfcTransition.FactoryFinalizedVerified
    TransactionJournalPresent = $transactionJournalPresent
    TransactionJournalAction = if ($null -eq $transactionJournal) { $null } else { [string]$transactionJournal.Action }
    TransactionJournalPhase = if ($null -eq $transactionJournal) { $null } else { [string]$transactionJournal.Phase }
    TransactionJournalReadError = $transactionJournalReadError
    OrphanedDefaultVrrShell = $orphanedDefaultVrrShell
    AttentionReason = $attentionReason
    RecommendedAction = $recommendedAction
}
