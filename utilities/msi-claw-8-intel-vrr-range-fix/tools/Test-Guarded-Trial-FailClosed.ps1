[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$runtimeRoot = if (Test-Path -LiteralPath (Join-Path $root 'scripts\Experimental-Overclock-VRR-Trial.ps1') -PathType Leaf) {
    Join-Path $root 'scripts'
}
else { $root }
$trialPath = Join-Path $runtimeRoot 'Experimental-Overclock-VRR-Trial.ps1'
$vrrPath = Join-Path $runtimeRoot 'MSI-Claw-VRR-Fix.ps1'

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $Condition) { throw $Message }
}

function Get-TextSection {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Start,
        [Parameter(Mandatory)][string]$End
    )
    $startIndex = $Text.IndexOf($Start, [StringComparison]::Ordinal)
    if ($startIndex -lt 0) { throw "Missing start marker: $Start" }
    $endIndex = $Text.IndexOf($End, $startIndex + $Start.Length, [StringComparison]::Ordinal)
    if ($endIndex -lt 0) { throw "Missing end marker: $End" }
    return $Text.Substring($startIndex, $endIndex - $startIndex)
}

function Assert-Throws {
    param(
        [Parameter(Mandatory)][scriptblock]$Script,
        [Parameter(Mandatory)][string]$ExpectedText
    )
    try {
        & $Script
        throw "Expected failure containing: $ExpectedText"
    }
    catch {
        if (-not $_.Exception.Message.Contains($ExpectedText)) { throw }
    }
}

foreach ($path in @($trialPath, $vrrPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Source is missing: $path" }
    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $path, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw ("Parse failed for {0}: {1}" -f $path,
            (($parseErrors | ForEach-Object Message) -join ' | '))
    }
}

# Import only production policy functions; -LibraryOnly cannot schedule/run.
. $trialPath -LibraryOnly

Assert-True ((Get-TrialExecutionDisposition -LifecycleState 'SCHEDULED' -AttemptConsumed $false) -eq 'FIRST_ATTEMPT') `
    'A pristine scheduled trial was not accepted exactly once.'
foreach ($state in @('RUNNING', 'ATTEMPT_CONSUMED', 'AWAITING_CONFIRMATION', 'CONFIRMING', 'RECOVERY_REQUIRED')) {
    Assert-True ((Get-TrialExecutionDisposition -LifecycleState $state -AttemptConsumed $true) -eq 'RECOVERY_ONLY') `
        "A consumed/power-loss state could re-enter the OC path: $state"
}
Assert-True ((Get-TrialExecutionDisposition -LifecycleState 'COMMIT_VERIFIED' -AttemptConsumed $true) -eq 'COMMITTED_NO_REAPPLY') `
    'A verified commit was not made idempotent.'

# Fresh No and prompt timeout share the exact safe rollback policy.
foreach ($scenario in @('FRESH_NO', 'FRESH_TIMEOUT', 'CONFIRM_UAC_CANCEL')) {
    Assert-True ((Get-TrialRollbackDisposition -LfcBackupPresent $false `
            -LfcRestoreTombstonePresent $false -LfcRestoreFinalizedPresent $false `
            -LfcFactoryFinalizedPresent $false `
            -FreshLfcProofValid $true) -eq
            'PROVE_FRESH_LFC_THEN_RESTORE_VRR') `
        "$scenario did not use the verified no-backup rollback path."
}
Assert-True ((Get-TrialRollbackDisposition -LfcBackupPresent $true `
        -LfcRestoreTombstonePresent $false -LfcRestoreFinalizedPresent $false `
        -LfcFactoryFinalizedPresent $false `
        -FreshLfcProofValid $false) -eq
        'PREPARE_LFC_THEN_VRR_THEN_COMMIT') `
    'A backup-present trial does not restore LFC before VRR.'
Assert-True ((Get-TrialRollbackDisposition -LfcBackupPresent $false `
        -LfcRestoreTombstonePresent $true -LfcRestoreFinalizedPresent $false `
        -LfcFactoryFinalizedPresent $false `
        -FreshLfcProofValid $false) -eq
        'RESUME_COMMITTED_LFC_THEN_VRR_THEN_FINALIZE') `
    'A committed LFC tombstone cannot resume the interrupted rollback.'
Assert-True ((Get-TrialRollbackDisposition -LfcBackupPresent $false `
        -LfcRestoreTombstonePresent $false -LfcRestoreFinalizedPresent $true `
        -LfcFactoryFinalizedPresent $false `
        -FreshLfcProofValid $false) -eq
        'VERIFY_FINALIZED_LFC_THEN_RESTORE_VRR') `
    'Finalized LFC provenance cannot resume interrupted VRR cleanup.'
Assert-True ((Get-TrialRollbackDisposition -LfcBackupPresent $false `
        -LfcRestoreTombstonePresent $false -LfcRestoreFinalizedPresent $false `
        -LfcFactoryFinalizedPresent $true `
        -FreshLfcProofValid $false) -eq
        'VERIFY_FACTORY_FINALIZED_LFC_THEN_RESTORE_VRR') `
    'Factory-finalized LFC provenance cannot resume interrupted VRR cleanup.'
Assert-True ((Get-TrialRollbackDisposition -LfcBackupPresent $false `
        -LfcRestoreTombstonePresent $false -LfcRestoreFinalizedPresent $false `
        -LfcFactoryFinalizedPresent $false `
        -FreshLfcProofValid $false) -eq
        'FAIL_CLOSED_LFC_DIVERGED') `
    'LFC divergence without a backup was not rejected fail-closed.'

# Direct no-backup proof: exact flags/target/panel pass, any drift fails.
function Get-ClawLabScheduledTaskRecord { param([string]$TaskName) return $null }
$direct = [pscustomobject]@{
    Result = 'Success'; Supported = $true; MinimumHz = 48; MaximumHz = 120
    VrrEnabled = $true; LowFpsSolutionEnabled = $true
    HighFpsSolutionEnabled = $true; TargetId = [uint32]8388688
    DisplayDeviceName = '\\.\DISPLAY1'
}
$status = [pscustomobject]@{
    DriverInterface = 'DIRECT_D3DKMT_INTEL_PRIVATE_ESCAPE'
    IntelGpu = 'Intel Arc test'; IntelDriverVersion = 'test-driver'
    PanelEdidSha256 = ('A' * 64); ManagedVrrMode = 'CLAWLAB_48_144'
    ExpectedRange = '48-144 Hz'; StartupPersistence = 'NOT_INSTALLED'
    LfcFixActive = $false
    LfcTransition = [pscustomobject]@{
        State = 'INTEL_VRR_SOLUTIONS_NOT_PATCHED'; BackupPresent = $false
        RestoreTombstonePresent = $false; RestoreFinalizedPresent = $false
        RestoreFinalizedVerified = $false; FactoryIntentPresent = $false
        FactoryFinalizedPresent = $false; FactoryFinalizedVerified = $false
    }
    CurrentState = $direct
}
$savedBackupPath = $lfcBackupPath
$lfcBackupPath = Join-Path ([IO.Path]::GetTempPath()) ('missing-clawlab-lfc-' + [Guid]::NewGuid().ToString('N'))
$snapshot = New-PreTrialLfcSnapshot -Status $status
$cleanDisposition = Assert-FreshPreTrialLfcState -Snapshot $snapshot -ExpectedManagedMode 'CLAWLAB_48_144' -ExpectedMinimumHz 48 -ExpectedMaximumHz 144
Assert-True ($cleanDisposition -eq 'CLEAN_NO_BACKUP') `
    'A pristine factory-default LFC baseline did not receive the clean disposition.'
$trialProof = [pscustomobject]@{
    PreTrialLfc = $snapshot; PreTrialLfcDisposition = 'CLEAN_NO_BACKUP'
    Mode = 'CLAWLAB_48_144'; MinimumHz = 48; MaximumHz = 144
    PhysicalEdidSha256 = ('A' * 64); ExperimentalEdidSha256 = ('B' * 64)
}
Assert-FreshLfcStillUnchanged -Trial $trialProof -Status $status
$direct.LowFpsSolutionEnabled = $false
Assert-Throws { Assert-FreshLfcStillUnchanged -Trial $trialProof -Status $status } 'Intel LFC changed without a restorable backup'
$direct.LowFpsSolutionEnabled = $true
$direct.TargetId = [uint32]999
Assert-Throws { Assert-FreshLfcStillUnchanged -Trial $trialProof -Status $status } 'Intel LFC changed without a restorable backup'
$direct.TargetId = [uint32]8388688

# A normal verified Restore is also a clean original baseline. Original Intel
# solution flags may legitimately be either value, so only exact durable
# provenance -- not guessed factory defaults -- authorizes the trial.
$status.LfcTransition.State = 'ORIGINAL_LFC_RESTORE_FINALIZED'
$status.LfcTransition.RestoreFinalizedPresent = $true
$status.LfcTransition.RestoreFinalizedVerified = $true
$direct.LowFpsSolutionEnabled = $false
$direct.HighFpsSolutionEnabled = $false
$restoredSnapshot = New-PreTrialLfcSnapshot -Status $status
$restoredDisposition = Assert-FreshPreTrialLfcState -Snapshot $restoredSnapshot `
    -ExpectedManagedMode 'CLAWLAB_48_144' -ExpectedMinimumHz 48 -ExpectedMaximumHz 144
Assert-True ($restoredDisposition -eq 'VERIFIED_RESTORE_FINALIZED_NO_BACKUP') `
    'Verified restore-finalized provenance was rejected by guarded scheduling.'
$status.LfcTransition.RestoreFinalizedVerified = $false
Assert-Throws {
    Assert-FreshPreTrialLfcState -Snapshot (New-PreTrialLfcSnapshot -Status $status) `
        -ExpectedManagedMode 'CLAWLAB_48_144' -ExpectedMinimumHz 48 -ExpectedMaximumHz 144
} 'no verified clean or finalized-original provenance'

$status.LfcTransition.State = 'INTEL_VRR_SOLUTIONS_FACTORY_DEFAULTS_FINALIZED'
$status.LfcTransition.RestoreFinalizedPresent = $false
$status.LfcTransition.RestoreFinalizedVerified = $false
$status.LfcTransition.FactoryFinalizedPresent = $true
$status.LfcTransition.FactoryFinalizedVerified = $true
$direct.LowFpsSolutionEnabled = $true
$direct.HighFpsSolutionEnabled = $true
$factorySnapshot = New-PreTrialLfcSnapshot -Status $status
$factoryDisposition = Assert-FreshPreTrialLfcState -Snapshot $factorySnapshot `
    -ExpectedManagedMode 'CLAWLAB_48_144' -ExpectedMinimumHz 48 -ExpectedMaximumHz 144
Assert-True ($factoryDisposition -eq 'VERIFIED_FACTORY_FINALIZED_NO_BACKUP') `
    'Verified factory-finalized provenance was rejected by guarded scheduling.'
$lfcBackupPath = $savedBackupPath

# Fresh protected-runtime staging never follows a pre-created destination,
# traversal or unexpected tree entry.
$stagingPolicyRoot = Join-Path ([IO.Path]::GetTempPath()) `
    ('clawlab-trial-staging-test-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($stagingPolicyRoot) | Out-Null
try {
    $nestedDestination = Get-ProtectedRuntimeStagingDestination `
        -StagingRoot $stagingPolicyRoot -RelativeFileName 'locales\messages.json'
    Assert-True ($nestedDestination.EndsWith('locales\messages.json',
            [StringComparison]::OrdinalIgnoreCase)) `
        'A safe nested protected-runtime destination was not resolved inside staging.'
    [IO.File]::WriteAllText($nestedDestination, '{}')
    [IO.File]::WriteAllText((Join-Path $stagingPolicyRoot 'core.ps1'), '# test')
    [IO.File]::WriteAllText((Join-Path $stagingPolicyRoot 'protected-runtime.json'), '{}')
    Assert-ProtectedRuntimeTree -RuntimeRoot $stagingPolicyRoot `
        -FileNames @('core.ps1', 'locales\messages.json')
    Assert-Throws {
        Get-ProtectedRuntimeStagingDestination -StagingRoot $stagingPolicyRoot `
            -RelativeFileName 'locales\messages.json'
    } 'unsafe or already exists'
    Assert-Throws {
        Get-ProtectedRuntimeStagingDestination -StagingRoot $stagingPolicyRoot `
            -RelativeFileName '..\escape.ps1'
    } 'unsafe'
    [IO.File]::WriteAllText((Join-Path $stagingPolicyRoot 'unexpected.bin'), 'x')
    Assert-Throws {
        Assert-ProtectedRuntimeTree -RuntimeRoot $stagingPolicyRoot `
            -FileNames @('core.ps1', 'locales\messages.json')
    } 'unexpected file'
}
finally {
    if (Test-Path -LiteralPath $stagingPolicyRoot) {
        [IO.Directory]::Delete($stagingPolicyRoot, $true)
    }
}

$trialSource = [IO.File]::ReadAllText($trialPath, [Text.Encoding]::UTF8).Replace("`r`n", "`n")
$vrrSource = [IO.File]::ReadAllText($vrrPath, [Text.Encoding]::UTF8).Replace("`r`n", "`n")
$schedule = Get-TextSection -Text $trialSource -Start "if (`$Action -eq 'Schedule') {" -End 'function Invoke-GuardedTrialRun {'
$scheduleElevation = Get-TextSection -Text $trialSource -Start 'function Confirm-AdministratorOrRelaunch {' -End 'function Get-TrialTaskSpec {'
$run = Get-TextSection -Text $trialSource -Start 'function Invoke-GuardedTrialRun {' -End '$trialExitCode = 1'
$consume = Get-TextSection -Text $trialSource -Start 'function Consume-TrialAttemptAndTask {' -End 'function Set-TrialRecoveryRequired {'
$locks = Get-TextSection -Text $trialSource -Start 'function Enter-TrialTransactionLocks {' -End 'function Exit-TrialTransactionLocks {'
$confirmBootstrap = Get-TextSection -Text $trialSource -Start 'function Invoke-BoundElevatedTrialConfirmation {' -End 'function Get-LfcStatusObject {'
$rollbackBootstrap = Get-TextSection -Text $trialSource -Start 'function Invoke-BoundElevatedTrialRollback {' -End 'function Get-LfcStatusObject {'
$applyTrialCore = Get-TextSection -Text $vrrSource -Start "        'ApplyExperimentalTrial' {" -End "        'SetSafe120ForTrial' {"
$confirmCore = Get-TextSection -Text $vrrSource -Start "        'ConfirmExperimentalTrial' {" -End "        'ApplyStartup' {"
$commitCleanup = Get-TextSection -Text $vrrSource -Start 'function Complete-ExperimentalOverclockTrialCommit {' -End 'function Get-CursorRefreshHelperProcesses {'
$startupInstall = Get-TextSection -Text $vrrSource -Start 'function Install-StartupReapply {' -End 'function Remove-StartupReapply {'
$guardedRestore = Get-TextSection -Text $vrrSource -Start "        { `$_ -in @('Restore', 'RestoreGuardedTrial') } {" -End "`n}`ncatch {"

$consumeState = $consume.IndexOf("-LifecycleState 'RUNNING'", [StringComparison]::Ordinal)
$consumeVerify = $consume.IndexOf('Get-ClawLabScheduledTaskRecord -TaskName $trialTaskName', [StringComparison]::Ordinal)
$consumeFinal = $consume.IndexOf("-LifecycleState 'ATTEMPT_CONSUMED'", [StringComparison]::Ordinal)
$readyPrompt = $run.IndexOf('$readyAnswer = Show-Message', [StringComparison]::Ordinal)
$applyOc = $run.IndexOf("-ToolAction 'ApplyExperimentalTrial'", [StringComparison]::Ordinal)
$visibleObservation = $run.IndexOf('Invoke-ExperimentalObservationUi -Trial $trial', [StringComparison]::Ordinal)
$verifyObservation = $run.IndexOf("-ToolAction 'VerifyExperimentalTrial'", [StringComparison]::Ordinal)
$safe120 = $run.IndexOf("-ToolAction 'SetSafe120ForTrial'", [StringComparison]::Ordinal)
Assert-True ($consumeState -ge 0 -and $consumeVerify -gt $consumeState -and
    $consumeFinal -gt $consumeVerify -and $readyPrompt -ge 0 -and
    $applyOc -gt $readyPrompt) `
    'The one-time task is not atomically consumed and verified before OC application.'
Assert-True ($visibleObservation -gt $applyOc -and $verifyObservation -gt $visibleObservation -and
    $safe120 -gt $verifyObservation) `
    'The guarded OC is not ordered as apply -> visible observation -> end verification -> automatic safe 120.'

$transactionLock = $locks.IndexOf("'Global\ClawLab.VRR.DisplayTransaction'", [StringComparison]::Ordinal)
$startupLock = $locks.IndexOf("'Global\ClawLab.MSIClaw.VrrApplyStartup'", [StringComparison]::Ordinal)
Assert-True ($transactionLock -ge 0 -and $startupLock -gt $transactionLock) `
    'Trial mutex order is not global transaction then global startup.'
Assert-True ($trialSource.Contains("try {`n    `$trialExitCode = Invoke-GuardedTrialRun`n}`nfinally {`n    Exit-TrialTransactionLocks")) `
    'Trial mutexes are not held through the complete commit/rollback call.'

$boundRollbackCall = $run.IndexOf('Invoke-BoundElevatedTrialRollback -Trial $trial', [StringComparison]::Ordinal)
$lfcPrepare = $rollbackBootstrap.IndexOf('-Action PrepareRestore', [StringComparison]::Ordinal)
$vrrRestore = $rollbackBootstrap.IndexOf('-Action RestoreGuardedTrial', $lfcPrepare + 1, [StringComparison]::Ordinal)
$verifiedEdidRemoval = $guardedRestore.IndexOf("throw 'The ClawLab custom EDID override could not be removed completely.'", [StringComparison]::Ordinal)
$lfcCommit = $guardedRestore.IndexOf('-Action CommitRestore', [StringComparison]::Ordinal)
$lfcFinalize = $guardedRestore.IndexOf('-Action FinalizeRestore', $lfcCommit + 1, [StringComparison]::Ordinal)
$finalizedProof = $guardedRestore.IndexOf('RestoreFinalizedPresent', $lfcFinalize + 1, [StringComparison]::Ordinal)
$runtimeCleanup = $guardedRestore.IndexOf('Remove-StartupReapply', [StringComparison]::Ordinal)
Assert-True ($boundRollbackCall -ge 0 -and $lfcPrepare -ge 0 -and $vrrRestore -gt $lfcPrepare -and
    $verifiedEdidRemoval -ge 0 -and $lfcCommit -gt $verifiedEdidRemoval -and
    $lfcFinalize -gt $lfcCommit -and $finalizedProof -gt $lfcFinalize -and
    $runtimeCleanup -gt $finalizedProof) `
    'Backup-present rollback is not ordered PrepareRestore -> VRR Restore -> CommitRestore -> FinalizeRestore -> cleanup.'
Assert-True (-not $run.Contains("-ToolAction 'PrepareRestore'") -and
    -not $run.Contains("-ToolAction 'CommitRestore'") -and
    -not $run.Contains('-ToolAction $vrrRestoreAction')) `
    'Rollback still launches detached generic elevation children instead of one bound transaction.'
Assert-True ($run.Contains('Assert-FreshLfcStillUnchanged -Trial $trial -Status $lfcStatus')) `
    'Fresh no-backup rollback has no exact direct LFC proof.'
Assert-True ($run.Contains('return 1') -and $run.Contains('Set-TrialRecoveryRequired -Trial $trial')) `
    'Failed rollback does not preserve evidence and return without success.'

foreach ($identityMarker in @(
        'OwnerSid', 'OwnerLocalAppData', 'RunSessionId',
        '$actualSession -ne __SESSION__', '$actualSid.Equals($expectedSid',
        '$actualLocal.Equals($canonicalExpectedLocal',
        'if (-not (Test-Path -LiteralPath $toolPath -PathType Leaf)) { exit 32 }'
    )) {
    Assert-True ($trialSource.Contains($identityMarker)) "Bound UAC identity marker is missing: $identityMarker"
}
$loadCore = $confirmBootstrap.IndexOf('& $toolPath -Action ConfirmExperimentalTrial', [StringComparison]::Ordinal)
$identityGate = $confirmBootstrap.IndexOf('$actualSession -ne __SESSION__', [StringComparison]::Ordinal)
Assert-True ($identityGate -ge 0 -and $loadCore -gt $identityGate) `
    'The protected confirmation core can load before OTS identity validation.'
Assert-True ($run.Contains('Invoke-BoundElevatedTrialConfirmation -Trial $trial')) `
    'The Run path does not use the bound confirmation elevation.'
foreach ($diagnosticMarker in @(
        'experimental-confirmation-last-error.txt',
        "Replace('__ERROR64__', `$error64)",
        '[IO.File]::WriteAllText($confirmationErrorPath, $details',
        '[IO.File]::ReadAllText($confirmationErrorPath',
        'The protected confirmation core returned exit code $LASTEXITCODE.'
    )) {
    Assert-True ($trialSource.Contains($diagnosticMarker)) `
        "Bound confirmation diagnostics are not durably preserved: $diagnosticMarker"
}
Assert-True (-not $applyTrialCore.Contains('Install-StartupReapply') -and
    -not $applyTrialCore.Contains('Install-CursorRefreshHelper') -and
    -not $applyTrialCore.Contains("-Action Apply")) `
    'The 30-second overclock observation writes persistent VRR/LFC/helper state before confirmation.'
$rollbackIdentityGate = $rollbackBootstrap.IndexOf('$actualSession -ne __SESSION__', [StringComparison]::Ordinal)
$rollbackPrepare = $rollbackBootstrap.IndexOf('& $lfcToolPath -Action PrepareRestore', [StringComparison]::Ordinal)
$rollbackVrr = $rollbackBootstrap.IndexOf('& $vrrToolPath -Action RestoreGuardedTrial', [StringComparison]::Ordinal)
Assert-True ($rollbackIdentityGate -ge 0 -and $rollbackPrepare -gt $rollbackIdentityGate -and
    $rollbackVrr -gt $rollbackPrepare) `
    'The bound rollback loads a protected core before identity validation or splits the transaction.'
Assert-True (([regex]::Matches($rollbackBootstrap, [regex]::Escape('-Verb RunAs')).Count) -eq 1) `
    'The bound rollback does not use exactly one UAC elevation.'
Assert-True ($trialSource.Contains("`$windowsPowerShellPath = Join-Path `$env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'") -and
    -not $trialSource.Contains("Start-Process -FilePath 'powershell.exe'")) `
    'A guarded-trial child process can still resolve PowerShell through PATH/current-directory search.'
$scheduleIdentityGate = $scheduleElevation.IndexOf('$actualSession -ne __SESSION__', [StringComparison]::Ordinal)
$scheduleLoad = $scheduleElevation.IndexOf('& $scriptPath -Action Schedule -Mode $mode', [StringComparison]::Ordinal)
Assert-True ($scheduleIdentityGate -ge 0 -and $scheduleLoad -gt $scheduleIdentityGate -and
    $scheduleElevation.Contains("'-EncodedCommand', `$encoded")) `
    'Schedule elevation is not bound to the initiating SID/session/LOCALAPPDATA before script load.'

$commitMarker = $commitCleanup.IndexOf("'COMMIT_VERIFIED'", [StringComparison]::Ordinal)
$taskRemoval = $commitCleanup.IndexOf('Remove-ClawLabScheduledTask', [StringComparison]::Ordinal)
$taskProof = $commitCleanup.IndexOf('Get-ClawLabScheduledTaskRecord', [StringComparison]::Ordinal)
$runtimeRemoval = $commitCleanup.IndexOf('Remove-ProtectedExperimentalRuntime', [StringComparison]::Ordinal)
Assert-True ($commitMarker -ge 0 -and $taskRemoval -gt $commitMarker -and $taskProof -gt $taskRemoval -and $runtimeRemoval -gt $taskProof) `
    'Protected runtime cleanup occurs before durable commit and consumed-task proof.'
Assert-True (-not $confirmCore.Contains('try { Remove-ProtectedExperimentalRuntime }')) `
    'ConfirmExperimentalTrial still performs the old premature runtime cleanup.'
Assert-True ($confirmCore.Contains('Complete-ExperimentalOverclockTrialCommit -Trial $context.Trial')) `
    'Confirmed profiles do not use the verified dedicated final cleanup.'
$confirmedManagedRecord = $confirmCore.IndexOf('Set-ManagedModeRecord -Mode ([string]$context.Trial.Mode)', [StringComparison]::Ordinal)
$confirmedVrrPersistence = $confirmCore.IndexOf('Install-StartupReapply -PreserveExperimentalRecovery', [StringComparison]::Ordinal)
$confirmedLfcApply = $confirmCore.IndexOf('& $protectedLfcToolPath -Action Apply', [StringComparison]::Ordinal)
$confirmedLfcVerify = $confirmCore.IndexOf('[string]$lfcResult.StartupPersistence -ne ''INSTALLED_ONE_SHOT_AT_LOGON''', [StringComparison]::Ordinal)
$confirmedVrrVerify = $confirmCore.IndexOf('$vrrStartupState = Get-StartupReapplyState', [StringComparison]::Ordinal)
$persistenceApplied = $confirmCore.IndexOf("-NotePropertyValue 'PERSISTENCE_APPLIED'", [StringComparison]::Ordinal)
$persistenceStateWrite = $confirmCore.IndexOf('Write-ClawLabJsonAtomically -LiteralPath $experimentalTrialStatePath', [StringComparison]::Ordinal)
$pendingTransitionProof = $confirmCore.IndexOf("[string]`$confirmedManaged.State -ne 'EXPERIMENTAL_TRIAL_PENDING'", [StringComparison]::Ordinal)
$confirmedCommit = $confirmCore.IndexOf('Complete-ExperimentalOverclockTrialCommit -Trial $context.Trial', [StringComparison]::Ordinal)
Assert-True ($confirmedManagedRecord -ge 0 -and
    $confirmedVrrPersistence -gt $confirmedManagedRecord -and
    $confirmedLfcApply -gt $confirmedVrrPersistence -and
    $confirmedLfcVerify -gt $confirmedLfcApply -and
    $confirmedVrrVerify -gt $confirmedLfcVerify -and
    $persistenceApplied -gt $confirmedVrrVerify -and
    $persistenceStateWrite -gt $persistenceApplied -and
    $pendingTransitionProof -gt $persistenceStateWrite -and
    $confirmedCommit -gt $pendingTransitionProof) `
    'Confirmed experimental profiles do not atomically install and verify VRR, LFC and helper persistence before commit.'
Assert-True (-not $confirmCore.Contains("[string]`$confirmedManaged.State -ne 'CONSISTENT'")) `
    'Confirmation still requires post-commit consistency before the guarded trial task can be consumed.'
Assert-True ($startupInstall.Contains('Install-CursorRefreshHelper')) `
    'Confirmed experimental VRR startup persistence no longer installs the Cursor Refresh Helper.'
Assert-True ($vrrSource.Contains("`$localesRoot = Join-Path `$runtimeRoot 'locales'")) `
    'Protected runtime cleanup does not handle the known nested locales directory.'
Assert-True ($trialSource.Contains("('.staging-' + [Guid]::NewGuid().ToString('N'))") -and
    $trialSource.Contains('[IO.Directory]::Move(') -and
    $trialSource.Contains('The final protected runtime already exists and is not empty') -and
    $trialSource.Contains('Assert-ProtectedRuntimeTree -RuntimeRoot $StagingRoot')) `
    'Protected runtime publication is not a fresh verified staging-to-final atomic rename.'
$schedulePreflight = $schedule.IndexOf('Get-LfcStatusObject -ToolPath $sourceLfcToolPath', [StringComparison]::Ordinal)
$scheduleStaging = $schedule.IndexOf('$stagingRoot = Initialize-ProtectedRuntimeDirectory', [StringComparison]::Ordinal)
$scheduleState = $schedule.IndexOf('Write-TrialStateAtomic -Trial $trial', $scheduleStaging + 1, [StringComparison]::Ordinal)
$schedulePublish = $schedule.IndexOf('Publish-ProtectedRuntimeStaging', $scheduleState + 1, [StringComparison]::Ordinal)
$scheduleTask = $schedule.IndexOf('Install-ClawLabScheduledTask', $schedulePublish + 1, [StringComparison]::Ordinal)
Assert-True ($schedulePreflight -ge 0 -and $scheduleStaging -gt $schedulePreflight -and
    $scheduleState -gt $scheduleStaging -and $schedulePublish -gt $scheduleState -and
    $scheduleTask -gt $schedulePublish) `
    'Schedule is not ordered preflight -> fresh staging -> durable state -> atomic publish -> task registration last.'

[pscustomobject]@{
    Result = 'PASS'
    FreshNoAndTimeout = 'PROOF_THEN_VRR_RESTORE'
    ConfirmUacCancel = 'ROLLBACK'
    BackupPresentOrder = 'LFC_PREPARE_VRR_RESTORE_LFC_COMMIT_FINALIZE'
    TombstoneRetry = 'RESUME_THEN_FINALIZE'
    FinalizedRetry = 'VERIFY_THEN_FINISH_VRR_CLEANUP'
    DivergenceNoBackup = 'FAIL_CLOSED'
    PowerLossSecondLogon = 'RECOVERY_ONLY'
    MutexOrder = 'GLOBAL_TRANSACTION_THEN_GLOBAL_STARTUP'
    BoundUacIdentity = $true
    RuntimeCleanupAfterCommitProof = $true
    RuntimePublication = 'FRESH_STAGING_ATOMIC_RENAME'
    ObservationPersistence = 'NONE_UNTIL_CONFIRMATION'
    ConfirmedPersistence = 'VRR_LFC_CURSOR'
}
