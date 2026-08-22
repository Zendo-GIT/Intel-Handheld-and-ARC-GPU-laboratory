[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path $PSScriptRoot -Parent
$runtimeRoot = if (Test-Path -LiteralPath (Join-Path $projectRoot 'scripts\MSI-Claw-VRR-Fix.ps1') -PathType Leaf) {
    Join-Path $projectRoot 'scripts'
}
else { $projectRoot }
$mainPath = Join-Path $runtimeRoot 'MSI-Claw-VRR-Fix.ps1'
$lfcPath = Join-Path $runtimeRoot 'MSI-Claw-Intel-LFC-Fix.ps1'
$transactionPath = Join-Path $runtimeRoot 'ClawLab-VRR-Transaction.ps1'
$trialPath = Join-Path $runtimeRoot 'Experimental-Overclock-VRR-Trial.ps1'
$vrrLauncherPath = Join-Path $runtimeRoot 'ClawLab-VRR-Startup.vbs'

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
        [Parameter(Mandatory)][string]$StartMarker,
        [Parameter(Mandatory)][string]$EndMarker
    )
    $start = $Text.IndexOf($StartMarker, [StringComparison]::Ordinal)
    if ($start -lt 0) { throw "Missing start marker: $StartMarker" }
    $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length, [StringComparison]::Ordinal)
    if ($end -lt 0) { throw "Missing end marker after ${StartMarker}: $EndMarker" }
    return $Text.Substring($start, $end - $start)
}

foreach ($parsePath in @($mainPath, $lfcPath, $transactionPath, $trialPath)) {
    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($parsePath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -ne 0) {
        throw "$([IO.Path]::GetFileName($parsePath)) has parser errors: $($parseErrors.Message -join ' | ')"
    }
}

$main = [IO.File]::ReadAllText($mainPath).Replace("`r`n", "`n")
$lfc = [IO.File]::ReadAllText($lfcPath).Replace("`r`n", "`n")
$transaction = [IO.File]::ReadAllText($transactionPath).Replace("`r`n", "`n")
$trial = [IO.File]::ReadAllText($trialPath).Replace("`r`n", "`n")
$vrrLauncher = [IO.File]::ReadAllText($vrrLauncherPath).Replace("`r`n", "`n")
$restoreActionMarker = "        { `$_ -in @('Restore', 'RestoreGuardedTrial') } {"
$factory = Get-TextSection -Text $main -StartMarker "        'FactoryReset' {" -EndMarker $restoreActionMarker
$restore = Get-TextSection -Text $main -StartMarker $restoreActionMarker -EndMarker "    }`n}"

$factoryDecision = $factory.IndexOf('$factoryInitialDecision = Get-FactoryResetDecisionForSnapshot', [StringComparison]::Ordinal)
$factorySafeMode = $factory.IndexOf('$safeMode = Set-Safe120DisplayMode', [StringComparison]::Ordinal)
Assert-True -Condition ($factoryDecision -ge 0 -and $factoryDecision -lt $factorySafeMode) `
    -Message 'Factory reset does not fail closed on the initial profile before changing the Windows display mode.'
Assert-True -Condition ($factory.Contains("'PRESERVE_TMA2027_OEM_CUSTOM_30_120'")) `
    -Message 'Factory reset has no exact TMA2027 preservation branch.'
Assert-True -Condition ($factory.Contains('TMA2027_VERIFIED_CUSTOM_30_120_PRESERVED_NO_SETTER')) `
    -Message 'Factory reset does not report the no-setter TMA2027 outcome.'

$preserveFactoryBranch = Get-TextSection -Text $factory `
    -StartMarker "                'PRESERVE_TMA2027_OEM_CUSTOM_30_120' {" `
    -EndMarker "                'SET_INTEL_RECOMMENDED' {"
Assert-True -Condition (-not $preserveFactoryBranch.Contains('Invoke-SetProfile')) `
    -Message 'The TMA2027 factory-preservation branch calls an Intel profile setter.'
Assert-True -Condition ($preserveFactoryBranch.Contains('Assert-KnownTma2027CustomBaselineEnvironment')) `
    -Message 'The TMA2027 factory-preservation branch omits direct-state verification.'

$restoreDecision = $restore.IndexOf('$restoreProfileDecision = Get-ClawLabSavedProfileRestoreDecision', [StringComparison]::Ordinal)
$restoreSafeMode = $restore.IndexOf('[void](Set-Safe120DisplayMode)', [StringComparison]::Ordinal)
Assert-True -Condition ($restoreDecision -ge 0 -and $restoreDecision -lt $restoreSafeMode) `
    -Message 'Restore does not reject TMA2027 drift before changing the Windows display mode.'
$preserveRestoreBranch = Get-TextSection -Text $restore `
    -StartMarker "                'PRESERVE_TMA2027_NO_WRITE' {" `
    -EndMarker "                'SKIP_ALREADY_MATCHING' {"
Assert-True -Condition (-not $preserveRestoreBranch.Contains('Restore-SnapshotProfile')) `
    -Message 'The TMA2027 restore-preservation branch writes the saved CUSTOM profile.'
Assert-True -Condition (-not $preserveRestoreBranch.Contains('Invoke-SetProfile')) `
    -Message 'The TMA2027 restore-preservation branch calls an Intel profile setter.'
Assert-True -Condition ($preserveRestoreBranch.Contains('Assert-KnownTma2027CustomBaselineEnvironment')) `
    -Message 'The TMA2027 restore-preservation branch omits direct-state verification.'

$assertEnvironment = Get-TextSection -Text $main `
    -StartMarker 'function Assert-KnownTma2027CustomBaselineEnvironment {' `
    -EndMarker 'function Resolve-FirstInstallProfileBaseline {'
foreach ($requiredInvariant in @(
        'Test-ClawLabKnownTma2027Custom30Profile',
        '$direct.DisplayCount -ne 1',
        '$direct.MinimumHz -ne 48',
        '$direct.MaximumHz -ne 120',
        '$direct.LowFpsSolutionEnabled',
        '$direct.HighFpsSolutionEnabled'
    )) {
    Assert-True -Condition ($assertEnvironment.Contains($requiredInvariant)) `
        -Message "The exact TMA2027 environment proof is missing: $requiredInvariant"
}

$intelUiLaunch = Get-TextSection -Text $main `
    -StartMarker 'function Start-ManagedIntelGraphicsSoftware {' `
    -EndMarker 'function Add-ArcSyncControlType {'
foreach ($requiredLaunchGuard in @(
        '$exception -is [System.ComponentModel.Win32Exception]',
        '$exception.NativeErrorCode -eq 1223',
        'if (-not $userCancelled)',
        'throw',
        '$script:intelGraphicsLaunchWarning'
    )) {
    Assert-True -Condition ($intelUiLaunch.Contains($requiredLaunchGuard)) `
        -Message "The Intel UI best-effort launch guard is missing: $requiredLaunchGuard"
}
$applyStartup = Get-TextSection -Text $main `
    -StartMarker "        'ApplyStartup' {" `
    -EndMarker "        { `$_ -in @('Install48', 'Repair48') } {"
$uiStartPosition = $applyStartup.IndexOf('Start-ManagedIntelGraphicsSoftware', [StringComparison]::Ordinal)
$profileVerificationPosition = $applyStartup.IndexOf('$after = Get-VerifiedManagedArcSyncSnapshot', [StringComparison]::Ordinal)
$cursorRestartPosition = $applyStartup.IndexOf('Invoke-CursorRefreshHelperStartupBestEffort -Operation Resync', [StringComparison]::Ordinal)
$successPosition = $applyStartup.IndexOf('Write-StartupResult -Success $true', [StringComparison]::Ordinal)
Assert-True -Condition ($uiStartPosition -ge 0 -and
    $profileVerificationPosition -gt $uiStartPosition -and
    $cursorRestartPosition -gt $profileVerificationPosition -and
    $successPosition -gt $profileVerificationPosition) `
    -Message 'ApplyStartup does not continue from optional Intel UI launch to independent VRR verification and success reporting.'
Assert-True -Condition ($applyStartup.Contains('Intel Graphics Software launch cancelled; VRR verified independently')) `
    -Message 'ApplyStartup does not record the best-effort Intel UI cancellation in its successful status.'
Assert-True -Condition (-not $applyStartup.Contains('catch {')) `
    -Message 'ApplyStartup contains a broad catch that could mask a setter or final VRR readback failure.'

$cursorStrictStart = Get-TextSection -Text $main `
    -StartMarker 'function Start-CursorRefreshHelper {' `
    -EndMarker 'function Sync-CursorRefreshHelper {'
Assert-True -Condition ($cursorStrictStart.Contains('did not publish a verified runtime state after launch')) `
    -Message 'The strict Cursor Refresh Helper start/readback path no longer fails closed.'
$cursorBestEffort = Get-TextSection -Text $main `
    -StartMarker 'function Invoke-CursorRefreshHelperStartupBestEffort {' `
    -EndMarker 'function Remove-CursorRefreshHelper {'
foreach ($requiredCursorGuard in @(
        "[ValidateSet('Start', 'Resync')]",
        '$script:cursorRefreshLaunchWarning = "Cursor Refresh Helper $Operation failed:',
        'Write-Warning $script:cursorRefreshLaunchWarning',
        'return $false'
    )) {
    Assert-True -Condition ($cursorBestEffort.Contains($requiredCursorGuard)) `
        -Message "The ApplyStartup-only Cursor Helper best-effort guard is missing: $requiredCursorGuard"
}
Assert-True -Condition ($main.Contains('[void](Invoke-CursorRefreshHelperStartupBestEffort -Operation Start)')) `
    -Message 'The early ApplyStartup Cursor Helper launch is not routed through the best-effort wrapper.'
$startupInstaller = Get-TextSection -Text $main `
    -StartMarker 'function Install-StartupReapply {' `
    -EndMarker 'function Remove-StartupReapply {'
foreach ($strictInstallMarker in @(
        '$sourceHash -ne $installedHash',
        "throw 'The installed startup files failed their integrity check.'",
        'Install-CursorRefreshHelper',
        'throw'
    )) {
    Assert-True -Condition ($startupInstaller.Contains($strictInstallMarker)) `
        -Message "The Cursor Helper install/integrity path is no longer strict: $strictInstallMarker"
}

$startupResultWriter = Get-TextSection -Text $main `
    -StartMarker 'function Write-StartupResult {' `
    -EndMarker 'function Resolve-IntelGraphicsStartupCommand {'
foreach ($requiredStartupResultField in @(
        'InvocationSource = $StartupSource',
        'IntelGraphicsLaunchWarning = $script:intelGraphicsLaunchWarning',
        'CursorRefreshLaunchWarning = $script:cursorRefreshLaunchWarning'
    )) {
    Assert-True -Condition ($startupResultWriter.Contains($requiredStartupResultField)) `
        -Message "startup-last-run.json is missing: $requiredStartupResultField"
}
Assert-True -Condition ($main.Contains("[ValidateSet('VrrTask', 'LfcTask')]")) `
    -Message 'The VRR startup entry point has no explicit invocation-source allowlist.'
Assert-True -Condition ($vrrLauncher.Contains('-Action ApplyStartup -StartupSource VrrTask')) `
    -Message 'The primary VRR logon launcher does not identify itself as VrrTask.'

# Thin BAT files now route into one elevated transaction coordinator. Verify
# the actual recovery implementation rather than duplicating stale assertions
# about wrapper internals.
$exactRestore = Get-TextSection -Text $transaction `
    -StartMarker 'function Invoke-ClawLabExactRestore {' `
    -EndMarker 'function Invoke-ClawLabInstallRollback {'
$exactLfcRestore = $exactRestore.IndexOf('$script:LfcToolPath -CoreAction PrepareRestore', [StringComparison]::Ordinal)
$exactVrrRestore = $exactRestore.IndexOf('$script:VrrToolPath -CoreAction Restore', [StringComparison]::Ordinal)
Assert-True -Condition ($exactLfcRestore -ge 0 -and $exactVrrRestore -gt $exactLfcRestore) `
    -Message 'The transaction coordinator does not restore LFC before exact VRR recovery.'

$factoryCoordinator = Get-TextSection -Text $transaction `
    -StartMarker "        elseif (`$RequestedAction -eq 'FactoryReset') {" `
    -EndMarker "        elseif (`$RequestedAction -eq 'RestoreLfcOnly') {"
$factoryLfcRestore = $factoryCoordinator.IndexOf('$script:LfcToolPath -CoreAction PrepareRestore', [StringComparison]::Ordinal)
$factoryVrrReset = $factoryCoordinator.IndexOf('$script:VrrToolPath -CoreAction FactoryReset', [StringComparison]::Ordinal)
Assert-True -Condition ($factoryLfcRestore -ge 0 -and $factoryVrrReset -gt $factoryLfcRestore) `
    -Message 'The transaction coordinator does not restore LFC before VRR factory reset.'

# The LFC logon task owns the per-user transaction mutex for its whole flow.
# Its nested VRR ApplyStartup child then takes the startup mutex, establishing
# the global transaction -> startup lock order used by the coordinator.
$lfcTransactionEnter = $lfc.IndexOf(
    "if (`$Action -eq 'ApplyStartup') {`n    Enter-LfcStartupTransactionMutex",
    [StringComparison]::Ordinal
)
$lfcPanelEnumeration = $lfc.IndexOf('$panels = [Collections.Generic.List[object]]::new()', [StringComparison]::Ordinal)
$lfcRangeChild = $lfc.IndexOf('-Action ApplyStartup -StartupSource LfcTask', [StringComparison]::Ordinal)
$lfcTransactionExit = $lfc.LastIndexOf('Exit-LfcStartupTransactionMutex', [StringComparison]::Ordinal)
Assert-True -Condition ($lfcTransactionEnter -ge 0 -and
    $lfcPanelEnumeration -gt $lfcTransactionEnter -and
    $lfcRangeChild -gt $lfcPanelEnumeration -and
    $lfcTransactionExit -gt $lfcRangeChild) `
    -Message 'The LFC startup flow does not hold the transaction mutex across its nested VRR ApplyStartup child.'
foreach ($requiredLfcStartupMarker in @(
        'Global\ClawLab.VRR.DisplayTransaction',
        'catch [Threading.AbandonedMutexException]',
        '-ExecutionTimeLimitMinutes 12'
    )) {
    Assert-True -Condition ($lfc.Contains($requiredLfcStartupMarker)) `
        -Message "The LFC startup transaction contract is missing: $requiredLfcStartupMarker"
}

$mainProtectedPayload = Get-TextSection -Text $main `
    -StartMarker '$protectedRuntimePayloadNames = @(' `
    -EndMarker ")`n`$protectedRuntimeFileNames"
$trialProtectedPayload = Get-TextSection -Text $trial `
    -StartMarker 'function Get-ProtectedRuntimePayload {' `
    -EndMarker 'function Assert-ProtectedRuntimeDirectoryAcl {'
foreach ($localizedPayload in @('ClawLab-Localization.ps1', 'locales\messages.json')) {
    Assert-True -Condition ($mainProtectedPayload.Contains("'$localizedPayload'")) `
        -Message "The VRR protected-runtime verifier omits $localizedPayload."
    Assert-True -Condition ($trialProtectedPayload.Contains("'$localizedPayload'")) `
        -Message "The guarded-trial protected-runtime manifest omits $localizedPayload."
}
$trialStagingDestination = Get-TextSection -Text $trial `
    -StartMarker 'function Get-ProtectedRuntimeStagingDestination {' `
    -EndMarker 'function Assert-ProtectedRuntimeTree {'
Assert-True -Condition ($trialStagingDestination.Contains('[IO.Directory]::CreateDirectory($current)')) `
    -Message 'The guarded-trial copy does not create parent directories for nested localized payloads.'
Assert-True -Condition ($trialStagingDestination.Contains("`$segments = @(`$RelativeFileName -split '[\\/]'")) `
    -Message 'The guarded-trial nested-payload routing does not validate each relative path segment.'

[pscustomobject]@{
    Result = 'PASS'
    FactoryPreserveBranchSetterReferences = 0
    RestorePreserveBranchSetterReferences = 0
    DriftRejectedBeforeDisplayMutation = $true
    DirectVrrAndLfcProofRequired = $true
    CoordinatorLfcRestorePrecedesVrrRecovery = $true
    IntelUiError1223BestEffortOnly = $true
    CursorHelperStartupBestEffortOnly = $true
    StartupInvocationSourceRecorded = $true
    LfcTransactionMutexHeldAcrossStartup = $true
    LocalizedProtectedRuntimeManifest = $true
    VrrSetterAndReadbackRemainFatal = $true
}
