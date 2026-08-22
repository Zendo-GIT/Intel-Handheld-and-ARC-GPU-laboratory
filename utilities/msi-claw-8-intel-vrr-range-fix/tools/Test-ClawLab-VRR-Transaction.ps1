[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$isPackagedLayout = Test-Path -LiteralPath (Join-Path $root 'scripts\ClawLab-VRR-Transaction.ps1') -PathType Leaf
$runtimeRoot = if ($isPackagedLayout) {
    Join-Path $root 'scripts'
}
else { $root }
$coordinatorPath = Join-Path $runtimeRoot 'ClawLab-VRR-Transaction.ps1'
$vrrCorePath = Join-Path $runtimeRoot 'MSI-Claw-VRR-Fix.ps1'
$localizationPath = Join-Path $runtimeRoot 'ClawLab-Localization.ps1'
$catalogPath = Join-Path $runtimeRoot 'locales\messages.json'

function Assert-Test {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) { throw $Message }
}

function Get-TextSection {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$StartMarker,
        [Parameter(Mandatory = $true)][string]$EndMarker
    )
    $start = $Text.IndexOf($StartMarker, [StringComparison]::Ordinal)
    if ($start -lt 0) { throw "Section start not found: $StartMarker" }
    $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length, [StringComparison]::Ordinal)
    if ($end -lt 0) { throw "Section end not found: $EndMarker" }
    return $Text.Substring($start, $end - $start)
}

function Assert-Throws {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Operation,
        [Parameter(Mandatory = $true)][string]$ExpectedMessage
    )
    $threw = $false
    try { & $Operation }
    catch {
        $threw = $true
        Assert-Test -Condition ([string]$_.Exception.Message -eq $ExpectedMessage) `
            -Message "Unexpected exception: $($_.Exception.Message)"
    }
    Assert-Test -Condition $threw -Message "Expected exception was not raised: $ExpectedMessage"
}

foreach ($path in @($coordinatorPath, $vrrCorePath, $localizationPath, $catalogPath)) {
    Assert-Test -Condition (Test-Path -LiteralPath $path -PathType Leaf) `
        -Message "Required test input is missing: $path"
}

$tokens = $null
$parseErrors = $null
[void][Management.Automation.Language.Parser]::ParseFile(
    $coordinatorPath, [ref]$tokens, [ref]$parseErrors)
Assert-Test -Condition ($parseErrors.Count -eq 0) `
    -Message ('Coordinator parse errors: ' + (($parseErrors | ForEach-Object Message) -join ' | '))

$source = [IO.File]::ReadAllText($coordinatorPath, [Text.Encoding]::UTF8)
$vrrCoreSource = [IO.File]::ReadAllText($vrrCorePath, [Text.Encoding]::UTF8)
Assert-Test -Condition ([regex]::Matches($source, '(?i)-Verb\s+RunAs').Count -eq 1) `
    -Message 'The coordinator must contain exactly one UAC elevation boundary.'
Assert-Test -Condition ($source.Contains('if ([bool]$Identity.IsAdministrator)') -and
    $source.Contains('-EncodedCommand $encoded | Out-Host') -and
    $source.Contains('$inheritedTokenExitCode = [int]$LASTEXITCODE') -and
    $source.Contains('return $inheritedTokenExitCode')) `
    -Message 'An already-elevated launcher still attempts a second UAC elevation.'
Assert-Test -Condition ($source.Contains('$script:ElevationLaunchError') -and
    $source.Contains('Write-Host $script:ElevationLaunchError')) `
    -Message 'UAC launch failures are still collapsed into an unexplained administrator error.'

$windowsPowerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$inheritedTokenExitProbe = @(
    & $windowsPowerShellPath -NoLogo -NoProfile -NonInteractive `
        -Command "[Console]::Out.WriteLine('CLAWLAB_ELEVATION_OUTPUT_PROBE'); exit 7" | Out-Host
    [int]$LASTEXITCODE
)
Assert-Test -Condition ($inheritedTokenExitProbe.Count -eq 1 -and
    $inheritedTokenExitProbe[0] -is [int] -and
    [int]$inheritedTokenExitProbe[0] -eq 7) `
    -Message 'Inherited-token child output contaminated the coordinator exit code.'
Assert-Test -Condition ($source -match 'CLAWLAB_CORE_PROCESS_IDENTITY_MISMATCH') `
    -Message 'Core child processes do not fail closed on identity mismatch.'
Assert-Test -Condition ($source -match 'GetCurrentProcess\(\)\.SessionId\s+-ne') `
    -Message 'Core child processes do not verify the caller session.'
Assert-Test -Condition ($source -match 'CLAWLAB_ELEVATED_IDENTITY_MISMATCH') `
    -Message 'The elevated coordinator does not fail closed on identity mismatch.'
Assert-Test -Condition ($source -match 'VRR_AND_LFC_VERIFIED') `
    -Message 'The stable install has no joint VRR/LFC verification checkpoint.'
Assert-Test -Condition ($source -match 'StartupPersistence\s+-ne\s+''INSTALLED_ONE_SHOT_AT_LOGON''') `
    -Message 'The stable install does not verify LFC startup persistence.'
Assert-Test -Condition ($source -match 'StartupReapply') `
    -Message 'The stable install does not verify VRR startup persistence.'
Assert-Test -Condition ($source -match 'AllowLfcFinalizedProvenance:\(\s*\[string\]\$installDisposition\.LfcOriginalStateDisposition') `
    -Message 'Fresh install does not authorize the exact verified post-Restore LFC provenance.'
Assert-Test -Condition ($source -notmatch '(?i)(^|[^0-9])24-120([^0-9]|$)') `
    -Message 'The coordinator must never expose a 24-120 profile.'
Assert-Test -Condition ($source -notmatch '(?i)(^|[^0-9])15-120([^0-9]|$)') `
    -Message 'The coordinator must never expose a 15-120 profile.'

$restoreStart = $source.IndexOf('function Invoke-ClawLabExactRestore', [StringComparison]::Ordinal)
$restoreEnd = $source.IndexOf('function Invoke-ClawLabInstallRollback', [StringComparison]::Ordinal)
Assert-Test -Condition ($restoreStart -ge 0 -and $restoreEnd -gt $restoreStart) `
    -Message 'The restartable exact-restore stage is missing.'
$restoreSegment = $source.Substring($restoreStart, $restoreEnd - $restoreStart)
$vrrRestoreIndex = $restoreSegment.IndexOf('$script:VrrToolPath -CoreAction Restore', [StringComparison]::Ordinal)
$lfcRestoreIndex = $restoreSegment.IndexOf('$script:LfcToolPath -CoreAction PrepareRestore', [StringComparison]::Ordinal)
$lfcCommitIndex = $restoreSegment.IndexOf('$script:LfcToolPath -CoreAction CommitRestore', [StringComparison]::Ordinal)
Assert-Test -Condition ($lfcRestoreIndex -ge 0 -and $vrrRestoreIndex -gt $lfcRestoreIndex) `
    -Message 'TMA2027 recovery requires LFC restoration before VRR cleanup.'
Assert-Test -Condition ($lfcCommitIndex -gt $vrrRestoreIndex) `
    -Message 'The LFC backup must remain retained until VRR restoration succeeds.'
Assert-Test -Condition ($restoreSegment.Contains('Resolve-ClawLabVrrStateWithoutBackup')) `
    -Message 'Exact Restore does not route a missing VRR backup through bounded recovery.'

$boundedRecoveryStart = $source.IndexOf('function Resolve-ClawLabVrrStateWithoutBackup', [StringComparison]::Ordinal)
$boundedRecoveryEnd = $source.IndexOf('function Assert-ClawLabFullyRestoredState', [StringComparison]::Ordinal)
Assert-Test -Condition ($boundedRecoveryStart -ge 0 -and $boundedRecoveryEnd -gt $boundedRecoveryStart) `
    -Message 'The bounded missing-backup recovery stage is missing.'
$boundedRecoverySegment = $source.Substring(
    $boundedRecoveryStart, $boundedRecoveryEnd - $boundedRecoveryStart)
Assert-Test -Condition ($boundedRecoverySegment.Contains('-CoreAction RecoverOrphanedDefaultState')) `
    -Message 'Missing-backup recovery does not invoke the private orphaned-default cleanup action.'
Assert-Test -Condition ([regex]::Matches(
        $boundedRecoverySegment, 'Assert-ClawLabVrrRestoredState').Count -eq 2) `
    -Message 'Bounded recovery does not independently verify both the already-clean and post-cleanup states.'
Assert-Test -Condition ($boundedRecoverySegment.Contains('ORPHANED_DEFAULT_VRR_SHELL_CLEANED')) `
    -Message 'Bounded recovery does not persist its exact recovery phase in the transaction journal.'

$rollbackStart = $source.IndexOf('function Invoke-ClawLabInstallRollback', [StringComparison]::Ordinal)
$rollbackEnd = $source.IndexOf('function Invoke-ClawLabElevatedOperation', [StringComparison]::Ordinal)
Assert-Test -Condition ($rollbackStart -ge 0 -and $rollbackEnd -gt $rollbackStart) `
    -Message 'The install-compensation stage is missing.'
$rollbackSegment = $source.Substring($rollbackStart, $rollbackEnd - $rollbackStart)
$rollbackLfcIndex = $rollbackSegment.IndexOf('$script:LfcToolPath -CoreAction PrepareRestore', [StringComparison]::Ordinal)
$rollbackVrrIndex = $rollbackSegment.IndexOf('$script:VrrToolPath -CoreAction Restore', [StringComparison]::Ordinal)
$rollbackCommitIndex = $rollbackSegment.IndexOf('$script:LfcToolPath -CoreAction CommitRestore', [StringComparison]::Ordinal)
Assert-Test -Condition ($rollbackLfcIndex -ge 0 -and $rollbackVrrIndex -gt $rollbackLfcIndex) `
    -Message 'TMA2027 install compensation requires LFC restoration before VRR cleanup.'
Assert-Test -Condition ($rollbackCommitIndex -gt $rollbackVrrIndex) `
    -Message 'Install compensation consumes the LFC backup before VRR rollback verifies.'
Assert-Test -Condition ($rollbackSegment.Contains('-AllowLfcFinalizedProvenance')) `
    -Message 'Install compensation rejects already-verified post-Restore LFC provenance.'
Assert-Test -Condition ($rollbackSegment.Contains('Resolve-ClawLabVrrStateWithoutBackup')) `
    -Message 'Install compensation bypasses bounded recovery when the original VRR backup is absent.'

$coreRecoverySegment = Get-TextSection -Text $vrrCoreSource `
    -StartMarker "        'RecoverOrphanedDefaultState' {" `
    -EndMarker "        'FactoryReset' {"
Assert-Test -Condition ($coreRecoverySegment.Contains('Assert-OrphanedDefaultVrrShellCleanupAllowed') -and
    $coreRecoverySegment.Contains('Remove-StartupReapply') -and
    $coreRecoverySegment.Contains('Test-ClawLabKnownUnmanagedFactoryProfile')) `
    -Message 'The private orphaned-default action lacks proof, owned-shell cleanup or post-cleanup profile verification.'
foreach ($forbiddenMutation in @(
        'Invoke-SetProfile', 'Set-Safe120DisplayMode', 'Set-EdidOverride',
        'Remove-ItemProperty', 'Set-ItemProperty', 'New-ItemProperty'
    )) {
    Assert-Test -Condition (-not $coreRecoverySegment.Contains($forbiddenMutation)) `
        -Message "The orphaned-default action contains forbidden display mutation '$forbiddenMutation'."
}
$coreRecoveryGuard = Get-TextSection -Text $vrrCoreSource `
    -StartMarker 'function Assert-OrphanedDefaultVrrShellCleanupAllowed {' `
    -EndMarker 'function Get-VerifiedManagedArcSyncSnapshot {'
Assert-Test -Condition ($coreRecoveryGuard.Contains('Test-ClawLabScheduledTaskOwned') -and
    $coreRecoveryGuard.Contains('Test-ClawLabKnownUnmanagedFactoryProfile') -and
    $coreRecoveryGuard.Contains("-notin @('TASK_INVALID', 'TASK_WITHOUT_FILES')")) `
    -Message 'The orphaned-default guard no longer proves task ownership, task state and the exact factory profile.'

$factoryStart = $source.IndexOf("elseif (`$RequestedAction -eq 'FactoryReset')", [StringComparison]::Ordinal)
$factoryEnd = $source.IndexOf("elseif (`$RequestedAction -eq 'RestoreLfcOnly')", [StringComparison]::Ordinal)
Assert-Test -Condition ($factoryStart -ge 0 -and $factoryEnd -gt $factoryStart) `
    -Message 'The coordinated factory-reset stage is missing.'
$factorySegment = $source.Substring($factoryStart, $factoryEnd - $factoryStart)
$factoryLfcIndex = $factorySegment.IndexOf('$script:LfcToolPath -CoreAction PrepareRestore', [StringComparison]::Ordinal)
$factoryVrrIndex = $factorySegment.IndexOf('$script:VrrToolPath -CoreAction FactoryReset', [StringComparison]::Ordinal)
$factoryLfcCommitIndex = $factorySegment.IndexOf('$script:LfcToolPath -CoreAction CommitRestore', [StringComparison]::Ordinal)
Assert-Test -Condition ($factoryLfcIndex -ge 0 -and $factoryVrrIndex -gt $factoryLfcIndex) `
    -Message 'TMA2027 factory reset requires LFC restoration before VRR cleanup.'
Assert-Test -Condition ($factoryLfcCommitIndex -gt $factoryVrrIndex) `
    -Message 'Factory reset consumes the LFC backup before the VRR factory stage verifies.'

. $coordinatorPath -LibraryOnly

$journalSid = 'S-1-5-21-100-200-300-1001'
$recoverableExperimentalJournal = [pscustomobject]@{
    SchemaVersion = 1
    CoordinatorVersion = '2.3.0'
    TransactionId = [Guid]::NewGuid().ToString()
    Action = 'Install48_180'
    CallerSid = $journalSid
    Phase = 'RECOVERY_REQUIRED'
}
Assert-Test -Condition (Test-ClawLabExperimentalRecoveryJournalEligibleForCleanReconciliation `
        -Journal $recoverableExperimentalJournal -CallerSid $journalSid) `
    -Message 'A current experimental false-recovery journal was not eligible for independent clean-state reconciliation.'
foreach ($invalidJournal in @(
        [pscustomobject]@{ Name = 'StableAction'; Value = 'Install30' },
        [pscustomobject]@{ Name = 'WrongPhase'; Value = 'PREFLIGHT_VERIFIED' },
        [pscustomobject]@{ Name = 'WrongVersion'; Value = '2.2.1' },
        [pscustomobject]@{ Name = 'WrongSid'; Value = 'S-1-5-21-100-200-300-1002' }
    )) {
    $candidate = $recoverableExperimentalJournal.PSObject.Copy()
    switch ($invalidJournal.Name) {
        'StableAction' { $candidate.Action = [string]$invalidJournal.Value }
        'WrongPhase' { $candidate.Phase = [string]$invalidJournal.Value }
        'WrongVersion' { $candidate.CoordinatorVersion = [string]$invalidJournal.Value }
        'WrongSid' { $candidate.CallerSid = [string]$invalidJournal.Value }
    }
    Assert-Test -Condition (-not (Test-ClawLabExperimentalRecoveryJournalEligibleForCleanReconciliation `
                -Journal $candidate -CallerSid $journalSid)) `
        -Message "Unsafe experimental journal reconciliation was accepted: $($invalidJournal.Name)."
}

$localizedChoices = @(
    @{ Language = 'en'; Yes = 'Yes'; No = 'No'; YesKey = 'Y'; NoKey = 'N' },
    @{ Language = 'fr'; Yes = 'Oui'; No = 'Non'; YesKey = 'O'; NoKey = 'N' },
    @{ Language = 'sw'; Yes = 'Ndiyo'; No = 'Hapana'; YesKey = 'N'; NoKey = 'H' },
    @{ Language = 'th'; Yes = 'ThaiYes'; No = 'ThaiNo';
        YesKey = ([string][char]0x0E0A); NoKey = ([string][char]0x0E21) }
)
foreach ($choice in $localizedChoices) {
    Assert-Test -Condition (
        (Resolve-CoordinatorYesNoAnswer -Answer $choice.YesKey `
            -YesLabel $choice.Yes -NoLabel $choice.No `
            -YesKey $choice.YesKey -NoKey $choice.NoKey) -eq 'YES'
    ) -Message "Localized Yes shortcut was rejected for '$($choice.Language)'."
    Assert-Test -Condition (
        (Resolve-CoordinatorYesNoAnswer -Answer $choice.NoKey `
            -YesLabel $choice.Yes -NoLabel $choice.No `
            -YesKey $choice.YesKey -NoKey $choice.NoKey) -eq 'NO'
    ) -Message "Localized No shortcut was rejected for '$($choice.Language)'."
    Assert-Test -Condition (
        (Resolve-CoordinatorYesNoAnswer -Answer $choice.Yes `
            -YesLabel $choice.Yes -NoLabel $choice.No `
            -YesKey $choice.YesKey -NoKey $choice.NoKey) -eq 'YES'
    ) -Message "Localized Yes word was rejected for '$($choice.Language)'."
    Assert-Test -Condition (
        (Resolve-CoordinatorYesNoAnswer -Answer $choice.No `
            -YesLabel $choice.Yes -NoLabel $choice.No `
            -YesKey $choice.YesKey -NoKey $choice.NoKey) -eq 'NO'
    ) -Message "Localized No word was rejected for '$($choice.Language)'."
}
Assert-Test -Condition (
    (Resolve-CoordinatorYesNoAnswer -Answer 'Y' -YesLabel 'Oui' -NoLabel 'Non' `
        -YesKey 'O' -NoKey 'N') -eq 'INVALID'
) -Message 'The coordinator still accepts a hidden hard-coded English shortcut in French.'

Assert-Test -Condition (Test-ClawLabOverclockConsentValue -Value 'I ACCEPT THE OVERCLOCK RISK') `
    -Message 'The exact invariant overclock-consent phrase was rejected.'
foreach ($invalidConsent in @(
        '', 'Y', 'YES', 'I accept the overclock risk',
        'I ACCEPT THE OVERCLOCK RISK ', 'I ACCEPT THE RISK'
    )) {
    Assert-Test -Condition (-not (Test-ClawLabOverclockConsentValue -Value $invalidConsent)) `
        -Message "An invalid overclock-consent value was accepted: '$invalidConsent'"
}
$yesNoSection = Get-TextSection -Text $source `
    -StartMarker 'function Read-CoordinatorYesNo {' `
    -EndMarker 'function Wait-CoordinatorEnter {'
Assert-Test -Condition ($yesNoSection.Contains('[Console]::ReadKey($true)') -and
    $yesNoSection.Contains('Write-Host $prompt -NoNewline')) `
    -Message 'Localized Yes/No confirmations are no longer immediate one-key choices.'
$riskReadingSection = Get-TextSection -Text $source `
    -StartMarker 'function Show-ClawLabOverclockRiskReadingPeriod {' `
    -EndMarker 'function Get-ClawLabIdentityContext {'
Assert-Test -Condition ($riskReadingSection.Contains('$readingSeconds = 10') -and
    $riskReadingSection.Contains("Write-CoordinatorText -Key 'experimental_schedule_details'") -and
    $riskReadingSection.Contains('Start-Sleep -Seconds 1')) `
    -Message 'The experimental risks are not shown throughout a visible ten-second reading period.'
$consentSection = Get-TextSection -Text $source `
    -StartMarker 'function Read-ClawLabOverclockConsent {' `
    -EndMarker 'function Show-ClawLabOverclockRiskReadingPeriod {'
Assert-Test -Condition (([regex]::Matches(
            $consentSection, [regex]::Escape('I ACCEPT THE OVERCLOCK RISK'))).Count -eq 1) `
    -Message 'The exact typed overclock consent phrase is no longer presented exactly once.'
$bootstrapIdentityIndex = $source.IndexOf('$actualIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()', [StringComparison]::Ordinal)
$bootstrapLoadIndex = $source.IndexOf('& $scriptPath -Action $requestedAction', [StringComparison]::Ordinal)
Assert-Test -Condition ($bootstrapIdentityIndex -ge 0 -and $bootstrapLoadIndex -gt $bootstrapIdentityIndex) `
    -Message 'The elevated bootstrap loads a user-writable coordinator before validating SID/session identity.'
Assert-Test -Condition ($source -match '\$actualSession\s+-ne\s+__SESSION__' -and
    $source -match '\$actualLocal\.Equals\(\$expectedLocal') `
    -Message 'The elevated bootstrap does not validate the caller session and LocalAppData before loading files.'

function New-TestInstallState {
    param(
        [string]$FixVersion = '2.3.0',
        [string]$LfcToolVersion = '2.0.7',
        [string]$Guard = 'CLEAN',
        [string]$ManagedMode = 'NONE',
        [string]$VrrState = 'DRIVER_PROFILE_CONSTRAINED',
        [string]$DriverProfile = 'RECOMMENDED',
        [string]$EdidOverride = 'NONE',
        [string]$DriverActiveRange = '48-120 Hz',
        [string]$ArcSyncPolicy = 'UNMANAGED',
        [string]$ArcSyncVerification = 'NOT_VERIFIED',
        [bool]$VrrBackupPresent = $false,
        [string]$VrrBackupPath = '',
        [bool]$VrrRecoveryRequired = $false,
        [bool]$VrrRestartRequired = $false,
        [string]$LfcManagedMode = 'UNMANAGED',
        [string]$LfcExpectedRange = 'UNMANAGED',
        [bool]$LfcBackupPresent = $false,
        [bool]$LfcIdentityAccepted = $true,
        [string]$LfcIdentityState = 'NO_BACKUP',
        [string]$LfcTransitionState = 'INTEL_VRR_SOLUTIONS_NOT_PATCHED',
        [string]$LfcStartupPersistence = 'NOT_INSTALLED',
        [bool]$LfcFixActive = $false,
        [bool]$LfcSupported = $true,
        [bool]$LfcVrrEnabled = $true,
        [float]$LfcMinimumHz = 48,
        [float]$LfcMaximumHz = 120,
        [bool]$LowFpsSolutionEnabled = $true,
        [bool]$HighFpsSolutionEnabled = $true,
        [string]$VrrStartupReapply = 'NOT_INSTALLED',
        [string]$CursorRefreshHelper = 'NOT_INSTALLED',
        [string]$IntelGraphicsStartup = 'INTEL_DEFAULT',
        [string]$ThirdPartyEdidOverrideValues = 'NONE',
        [string]$PanelEdidSha256 = ('A' * 64),
        [bool]$LfcRestoreTombstonePresent = $false,
        [bool]$LfcRestoreFinalizedPresent = $false,
        [bool]$LfcRestoreFinalizedVerified = $false,
        [bool]$LfcFactoryIntentPresent = $false,
        [bool]$LfcFactoryFinalizedPresent = $false,
        [bool]$LfcFactoryFinalizedVerified = $false
    )

    return [pscustomobject]@{
        Vrr = [pscustomobject]@{
            FixVersion = $FixVersion
            State = $VrrState
            DriverProfile = $DriverProfile
            ProfileSwitchGuard = $Guard
            ManagedMode = $ManagedMode
            OriginalProfileSaved = $VrrBackupPresent
            BackupPath = $VrrBackupPath
            EdidOverride = $EdidOverride
            DriverActiveRange = $DriverActiveRange
            ArcSyncPolicy = $ArcSyncPolicy
            ArcSyncVerification = $ArcSyncVerification
            StartupReapply = $VrrStartupReapply
            CursorRefreshHelper = $CursorRefreshHelper
            IntelGraphicsStartup = $IntelGraphicsStartup
            RecoveryRequired = $VrrRecoveryRequired
            RestartRequired = $VrrRestartRequired
            RegistryModified = $false
        }
        Lfc = [pscustomobject]@{
            ToolVersion = $LfcToolVersion
            DriverInterface = 'DIRECT_D3DKMT_INTEL_PRIVATE_ESCAPE'
            ManagedVrrMode = $LfcManagedMode
            ExpectedRange = $LfcExpectedRange
            ThirdPartyEdidOverrideValues = $ThirdPartyEdidOverrideValues
            PanelEdidSha256 = $PanelEdidSha256
            StartupPersistence = $LfcStartupPersistence
            LfcFixActive = $LfcFixActive
            RestoreTombstonePresent = $LfcRestoreTombstonePresent
            RestoreFinalizedPresent = $LfcRestoreFinalizedPresent
            FactoryIntentPresent = $LfcFactoryIntentPresent
            FactoryFinalizedPresent = $LfcFactoryFinalizedPresent
            CurrentState = [pscustomobject]@{
                Supported = $LfcSupported
                VrrEnabled = $LfcVrrEnabled
                MinimumHz = $LfcMinimumHz
                MaximumHz = $LfcMaximumHz
                LowFpsSolutionEnabled = $LowFpsSolutionEnabled
                HighFpsSolutionEnabled = $HighFpsSolutionEnabled
            }
            LfcBackupIdentity = [pscustomobject]@{
                Accepted = $LfcIdentityAccepted
                State = $LfcIdentityState
            }
            LfcTransition = [pscustomobject]@{
                BackupPresent = $LfcBackupPresent
                State = $LfcTransitionState
                RestoreTombstonePresent = $LfcRestoreTombstonePresent
                RestoreFinalizedPresent = $LfcRestoreFinalizedPresent
                RestoreFinalizedVerified = $LfcRestoreFinalizedVerified
                FactoryIntentPresent = $LfcFactoryIntentPresent
                FactoryFinalizedPresent = $LfcFactoryFinalizedPresent
                FactoryFinalizedVerified = $LfcFactoryFinalizedVerified
            }
        }
    }
}

$freshState = New-TestInstallState
$freshDisposition = Get-ClawLabInstallDispositionFromState -RequestedAction Install30 `
    -Vrr $freshState.Vrr -Lfc $freshState.Lfc `
    -TrialArtifactsAbsent $true -RecoveryClear $true
Assert-Test -Condition ([string]$freshDisposition.Disposition -eq 'FRESH_INSTALL') `
    -Message 'A clean first installation was not classified as fresh.'
Assert-Test -Condition ([string]$freshDisposition.LfcOriginalStateDisposition -eq 'FACTORY_DEFAULTS') `
    -Message 'The clean Intel default LFC baseline was not identified exactly.'

foreach ($originalFlags in @(
        [pscustomobject]@{ Low = $true; High = $true },
        [pscustomobject]@{ Low = $true; High = $false },
        [pscustomobject]@{ Low = $false; High = $true },
        [pscustomobject]@{ Low = $false; High = $false }
    )) {
    $restoredState = New-TestInstallState `
        -LfcTransitionState ORIGINAL_LFC_RESTORE_FINALIZED `
        -LfcRestoreFinalizedPresent $true -LfcRestoreFinalizedVerified $true `
        -LowFpsSolutionEnabled $originalFlags.Low `
        -HighFpsSolutionEnabled $originalFlags.High
    $restoredDisposition = Get-ClawLabInstallDispositionFromState `
        -RequestedAction Install30 -Vrr $restoredState.Vrr -Lfc $restoredState.Lfc `
        -TrialArtifactsAbsent $true -RecoveryClear $true
    Assert-Test -Condition ([string]$restoredDisposition.Disposition -eq 'FRESH_INSTALL' -and
        [string]$restoredDisposition.LfcOriginalStateDisposition -eq
        'VERIFIED_FINALIZED_PROVENANCE') `
        -Message ("A verified restored LFC original state was rejected: Low={0}, High={1}." -f
            $originalFlags.Low, $originalFlags.High)
}

$factoryFinalizedState = New-TestInstallState `
    -LfcTransitionState INTEL_VRR_SOLUTIONS_FACTORY_DEFAULTS_FINALIZED `
    -LfcFactoryFinalizedPresent $true -LfcFactoryFinalizedVerified $true
$factoryFinalizedDisposition = Get-ClawLabInstallDispositionFromState `
    -RequestedAction Install30 -Vrr $factoryFinalizedState.Vrr `
    -Lfc $factoryFinalizedState.Lfc -TrialArtifactsAbsent $true -RecoveryClear $true
Assert-Test -Condition ([string]$factoryFinalizedDisposition.Disposition -eq 'FRESH_INSTALL' -and
    [string]$factoryFinalizedDisposition.LfcOriginalStateDisposition -eq
    'VERIFIED_FACTORY_FINALIZED_PROVENANCE') `
    -Message 'A verified terminal factory-default provenance was not reusable by Apply.'

foreach ($unsafeFactoryState in @(
        (New-TestInstallState `
            -LfcTransitionState INTEL_VRR_SOLUTIONS_FACTORY_DEFAULTS_PENDING_RESUME `
            -LfcFactoryIntentPresent $true),
        (New-TestInstallState `
            -LfcTransitionState INTEL_VRR_SOLUTIONS_FACTORY_DEFAULTS_FINALIZATION_PENDING `
            -LfcFactoryIntentPresent $true -LfcFactoryFinalizedPresent $true `
            -LfcFactoryFinalizedVerified $true),
        (New-TestInstallState `
            -LfcTransitionState INTEL_VRR_SOLUTIONS_FACTORY_DEFAULTS_FINALIZED `
            -LfcFactoryFinalizedPresent $true -LfcFactoryFinalizedVerified $false)
    )) {
    Assert-Throws -Operation {
        [void](Get-ClawLabInstallDispositionFromState -RequestedAction Install30 `
                -Vrr $unsafeFactoryState.Vrr -Lfc $unsafeFactoryState.Lfc `
                -TrialArtifactsAbsent $true -RecoveryClear $true)
    } -ExpectedMessage 'CLAWLAB_RESTORE_REQUIRED_BEFORE_INSTALL'
}

$normalizationRecoveryState = New-TestInstallState -VrrRecoveryRequired $true
Assert-Throws -Operation {
    [void](Get-ClawLabInstallDispositionFromState -RequestedAction Install30 `
            -Vrr $normalizationRecoveryState.Vrr -Lfc $normalizationRecoveryState.Lfc `
            -TrialArtifactsAbsent $true -RecoveryClear $false)
} -ExpectedMessage 'CLAWLAB_RESTORE_REQUIRED_BEFORE_INSTALL'

$unprovenOriginalFlags = New-TestInstallState `
    -LowFpsSolutionEnabled $false -HighFpsSolutionEnabled $true
Assert-Throws -Operation {
    [void](Get-ClawLabInstallDispositionFromState -RequestedAction Install30 `
            -Vrr $unprovenOriginalFlags.Vrr -Lfc $unprovenOriginalFlags.Lfc `
            -TrialArtifactsAbsent $true -RecoveryClear $true)
} -ExpectedMessage 'CLAWLAB_RESTORE_REQUIRED_BEFORE_INSTALL'
foreach ($missingFinalizedProof in @('TopLevelMarker', 'TransitionMarker', 'Verification')) {
    $state = New-TestInstallState `
        -LfcTransitionState ORIGINAL_LFC_RESTORE_FINALIZED `
        -LfcRestoreFinalizedPresent $true -LfcRestoreFinalizedVerified $true `
        -LowFpsSolutionEnabled $false -HighFpsSolutionEnabled $false
    if ($missingFinalizedProof -eq 'TopLevelMarker') {
        $state.Lfc.RestoreFinalizedPresent = $false
    }
    elseif ($missingFinalizedProof -eq 'TransitionMarker') {
        $state.Lfc.LfcTransition.RestoreFinalizedPresent = $false
    }
    else {
        $state.Lfc.LfcTransition.RestoreFinalizedVerified = $false
    }
    Assert-Throws -Operation {
        [void](Get-ClawLabInstallDispositionFromState -RequestedAction Install30 `
                -Vrr $state.Vrr -Lfc $state.Lfc `
                -TrialArtifactsAbsent $true -RecoveryClear $true)
    } -ExpectedMessage 'CLAWLAB_RESTORE_REQUIRED_BEFORE_INSTALL'
}
foreach ($unsafeFreshState in @(
        (New-TestInstallState -VrrStartupReapply Ready),
        (New-TestInstallState -LfcStartupPersistence ORPHANED_PAYLOAD),
        (New-TestInstallState -LfcFixActive $true),
        (New-TestInstallState -LowFpsSolutionEnabled $false),
        (New-TestInstallState -HighFpsSolutionEnabled $false),
        (New-TestInstallState -LfcToolVersion 2.0.6)
    )) {
    Assert-Throws -Operation {
        [void](Get-ClawLabInstallDispositionFromState -RequestedAction Install30 `
                -Vrr $unsafeFreshState.Vrr -Lfc $unsafeFreshState.Lfc `
                -TrialArtifactsAbsent $true -RecoveryClear $true)
    } -ExpectedMessage 'CLAWLAB_RESTORE_REQUIRED_BEFORE_INSTALL'
}

function New-TestRepairState {
    param(
        [ValidateSet('Install30', 'Install48')][string]$Action,
        [string]$Guard = 'INCONSISTENT_RESTORE_REQUIRED',
        [string]$VrrStartupReapply = 'NOT_INSTALLED',
        [string]$LfcStartupPersistence = 'NOT_INSTALLED'
    )

    if ($Action -eq 'Install30') {
        return New-TestInstallState -Guard $Guard -ManagedMode CLAWLAB_30_120 `
            -VrrState CLAWLAB_30_120_ACTIVE -EdidOverride CLAWLAB_30_120 `
            -DriverProfile EXCELLENT `
            -DriverActiveRange '30-120 Hz' -ArcSyncPolicy INTEL_EXCELLENT_REQUIRED `
            -ArcSyncVerification EXCELLENT_EXACT -VrrBackupPresent $true `
            -LfcManagedMode CLAWLAB_30_120 -LfcExpectedRange '30-120 Hz' `
            -LfcBackupPresent $true -LfcIdentityState STABLE_IDENTITY_VERIFIED `
            -LfcTransitionState CLAWLAB_LFC_FIX_ACTIVE -LfcMinimumHz 30 `
            -LfcMaximumHz 120 -LowFpsSolutionEnabled $false `
            -HighFpsSolutionEnabled $false -VrrStartupReapply $VrrStartupReapply `
            -LfcStartupPersistence $LfcStartupPersistence
    }

    return New-TestInstallState -Guard $Guard -ManagedMode OFFICIAL_48_120 `
        -VrrState OFFICIAL_48_120_ACTIVE -EdidOverride NONE `
        -DriverProfile EXCELLENT `
        -DriverActiveRange '48-120 Hz' -ArcSyncPolicy INTEL_EXCELLENT_REQUIRED `
        -ArcSyncVerification EXCELLENT_EXACT -VrrBackupPresent $true `
        -LfcManagedMode OFFICIAL_48_120 -LfcExpectedRange '48-120 Hz' `
        -LfcBackupPresent $true -LfcIdentityState STABLE_IDENTITY_VERIFIED `
        -LfcTransitionState CLAWLAB_LFC_FIX_ACTIVE -LfcMinimumHz 48 `
        -LfcMaximumHz 120 -LowFpsSolutionEnabled $false `
        -HighFpsSolutionEnabled $false -VrrStartupReapply $VrrStartupReapply `
        -LfcStartupPersistence $LfcStartupPersistence
}

foreach ($repairCase in @(
        [pscustomobject]@{ Action = 'Install30'; Mode = 'CLAWLAB_30_120' },
        [pscustomobject]@{ Action = 'Install48'; Mode = 'OFFICIAL_48_120' }
    )) {
    $state = New-TestRepairState -Action $repairCase.Action
    $disposition = Get-ClawLabInstallDispositionFromState -RequestedAction $repairCase.Action `
        -Vrr $state.Vrr -Lfc $state.Lfc -VrrOriginalBackupVerified $true `
        -TrialArtifactsAbsent $true -RecoveryClear $true
    Assert-Test -Condition ([string]$disposition.Disposition -eq 'REPAIRABLE_SAME_MODE') `
        -Message "Exact same stable profile repair was refused: $($repairCase.Action)"
}

$missingPersistence30 = New-TestRepairState -Action Install30 `
    -VrrStartupReapply TASK_WITHOUT_FILES -LfcStartupPersistence ORPHANED_PAYLOAD
$missingPersistenceDisposition = Get-ClawLabInstallDispositionFromState `
    -RequestedAction Install30 -Vrr $missingPersistence30.Vrr -Lfc $missingPersistence30.Lfc `
    -VrrOriginalBackupVerified $true -TrialArtifactsAbsent $true -RecoveryClear $true
Assert-Test -Condition ([string]$missingPersistenceDisposition.Disposition -eq 'REPAIRABLE_SAME_MODE') `
    -Message 'Missing stable task/payload persistence incorrectly forced an original-state restore.'

foreach ($driverResetCase in @(
        [pscustomobject]@{
            Action = 'Install30'; State = 'CLAWLAB_30_120_PENDING_RESTART'
            Range = '60-120 Hz'; MinimumHz = 48.0
        },
        [pscustomobject]@{
            Action = 'Install48'; State = 'DRIVER_PROFILE_CONSTRAINED'
            Range = '60-120 Hz'; MinimumHz = 48.0
        }
    )) {
    $driverReset = New-TestRepairState -Action $driverResetCase.Action
    $driverReset.Vrr.State = $driverResetCase.State
    $driverReset.Vrr.DriverProfile = 'RECOMMENDED'
    $driverReset.Vrr.DriverActiveRange = $driverResetCase.Range
    $driverReset.Vrr.ArcSyncVerification = 'NOT_VERIFIED'
    $driverReset.Vrr.RestartRequired = $true
    $driverReset.Lfc.CurrentState.MinimumHz = $driverResetCase.MinimumHz
    $driverReset.Lfc.CurrentState.LowFpsSolutionEnabled = $true
    $driverReset.Lfc.CurrentState.HighFpsSolutionEnabled = $true
    $driverReset.Lfc.LfcFixActive = $false
    $driverResetDisposition = Get-ClawLabInstallDispositionFromState `
        -RequestedAction $driverResetCase.Action -Vrr $driverReset.Vrr `
        -Lfc $driverReset.Lfc -VrrOriginalBackupVerified $true `
        -TrialArtifactsAbsent $true -RecoveryClear $true
    Assert-Test -Condition ([string]$driverResetDisposition.Disposition -eq `
        'REPAIRABLE_SAME_MODE') `
        -Message "A known Intel post-driver reset was not repairable: $($driverResetCase.Action)."
}

$customDriverDrift = New-TestRepairState -Action Install30
$customDriverDrift.Vrr.State = 'CLAWLAB_30_120_PENDING_RESTART'
$customDriverDrift.Vrr.DriverProfile = 'CUSTOM'
$customDriverDrift.Vrr.DriverActiveRange = '60-120 Hz'
$customDriverDrift.Vrr.ArcSyncVerification = 'NOT_VERIFIED'
$customDriverDrift.Lfc.CurrentState.MinimumHz = 48
Assert-Throws -Operation {
    [void](Get-ClawLabInstallDispositionFromState -RequestedAction Install30 `
            -Vrr $customDriverDrift.Vrr -Lfc $customDriverDrift.Lfc `
            -VrrOriginalBackupVerified $true -TrialArtifactsAbsent $true `
            -RecoveryClear $true)
} -ExpectedMessage 'CLAWLAB_RESTORE_REQUIRED_BEFORE_INSTALL'

$unknownRangeDrift = New-TestRepairState -Action Install30
$unknownRangeDrift.Vrr.State = 'CLAWLAB_30_120_PENDING_RESTART'
$unknownRangeDrift.Vrr.DriverProfile = 'RECOMMENDED'
$unknownRangeDrift.Vrr.DriverActiveRange = '24-120 Hz'
$unknownRangeDrift.Vrr.ArcSyncVerification = 'NOT_VERIFIED'
$unknownRangeDrift.Lfc.CurrentState.MinimumHz = 24
Assert-Throws -Operation {
    [void](Get-ClawLabInstallDispositionFromState -RequestedAction Install30 `
            -Vrr $unknownRangeDrift.Vrr -Lfc $unknownRangeDrift.Lfc `
            -VrrOriginalBackupVerified $true -TrialArtifactsAbsent $true `
            -RecoveryClear $true)
} -ExpectedMessage 'CLAWLAB_RESTORE_REQUIRED_BEFORE_INSTALL'

$same30 = New-TestRepairState -Action Install30
foreach ($unsafeRepairAction in @(
        'Install48', 'Install30_144', 'Install30_165', 'Install30_180', 'Install30_192'
    )) {
    Assert-Throws -Operation {
        [void](Get-ClawLabInstallDispositionFromState -RequestedAction $unsafeRepairAction `
                -Vrr $same30.Vrr -Lfc $same30.Lfc -VrrOriginalBackupVerified $true `
                -TrialArtifactsAbsent $true -RecoveryClear $true)
    } -ExpectedMessage 'CLAWLAB_RESTORE_REQUIRED_BEFORE_INSTALL'
}
$invalidRepairStates = [Collections.Generic.List[object]]::new()
$oldCore = New-TestRepairState -Action Install30
$oldCore.Vrr.FixVersion = '2.2.1'
$invalidRepairStates.Add($oldCore)
$oldLfc = New-TestRepairState -Action Install30
$oldLfc.Lfc.ToolVersion = '2.0.6'
$invalidRepairStates.Add($oldLfc)
$missingLfcBackup = New-TestRepairState -Action Install30
$missingLfcBackup.Lfc.LfcTransition.BackupPresent = $false
$invalidRepairStates.Add($missingLfcBackup)
$invalidLfcIdentity = New-TestRepairState -Action Install30
$invalidLfcIdentity.Lfc.LfcBackupIdentity.Accepted = $false
$invalidRepairStates.Add($invalidLfcIdentity)
$wrongActiveState = New-TestRepairState -Action Install30
$wrongActiveState.Vrr.State = 'CLAWLAB_30_120_PENDING_RESTART'
$invalidRepairStates.Add($wrongActiveState)
$wrongDriverRange = New-TestRepairState -Action Install30
$wrongDriverRange.Vrr.DriverActiveRange = '48-120 Hz'
$invalidRepairStates.Add($wrongDriverRange)
$unknownOverride = New-TestRepairState -Action Install30
$unknownOverride.Vrr.EdidOverride = 'UNKNOWN_OVERRIDE'
$invalidRepairStates.Add($unknownOverride)
$recoveryPending = New-TestRepairState -Action Install30
$recoveryPending.Vrr.RecoveryRequired = $true
$invalidRepairStates.Add($recoveryPending)
$restartPending = New-TestRepairState -Action Install30
$restartPending.Vrr.RestartRequired = $true
$restartPendingDisposition = Get-ClawLabInstallDispositionFromState `
    -RequestedAction Install30 -Vrr $restartPending.Vrr -Lfc $restartPending.Lfc `
    -VrrOriginalBackupVerified $true -TrialArtifactsAbsent $true -RecoveryClear $true
Assert-Test -Condition ([string]$restartPendingDisposition.Disposition -eq `
        'REPAIRABLE_SAME_MODE') `
    -Message 'RestartRequired is output health and incorrectly invalidated exact managed ownership.'
$wrongLfcRange = New-TestRepairState -Action Install30
$wrongLfcRange.Lfc.CurrentState.MinimumHz = 48
$invalidRepairStates.Add($wrongLfcRange)
$thirdPartyOverride = New-TestRepairState -Action Install30
$thirdPartyOverride.Lfc.ThirdPartyEdidOverrideValues = 'CRU_OVERRIDE'
$invalidRepairStates.Add($thirdPartyOverride)

foreach ($invalidRepairState in $invalidRepairStates) {
    Assert-Throws -Operation {
        [void](Get-ClawLabInstallDispositionFromState -RequestedAction Install30 `
                -Vrr $invalidRepairState.Vrr -Lfc $invalidRepairState.Lfc `
                -VrrOriginalBackupVerified $true -TrialArtifactsAbsent $true `
                -RecoveryClear $true)
    } -ExpectedMessage 'CLAWLAB_RESTORE_REQUIRED_BEFORE_INSTALL'
}

foreach ($missingProof in @('VrrBackup', 'TrialAbsence', 'RecoveryClear')) {
    Assert-Throws -Operation {
        [void](Get-ClawLabInstallDispositionFromState -RequestedAction Install30 `
                -Vrr $same30.Vrr -Lfc $same30.Lfc `
                -VrrOriginalBackupVerified ($missingProof -ne 'VrrBackup') `
                -TrialArtifactsAbsent ($missingProof -ne 'TrialAbsence') `
                -RecoveryClear ($missingProof -ne 'RecoveryClear'))
    } -ExpectedMessage 'CLAWLAB_RESTORE_REQUIRED_BEFORE_INSTALL'
}

$repairCatchMarker = "if ([string]`$installDisposition.Disposition -eq 'REPAIRABLE_SAME_MODE')"
$repairCatchIndex = $source.IndexOf($repairCatchMarker, [StringComparison]::Ordinal)
$rollbackPhaseIndex = $source.IndexOf("Set-ClawLabTransactionPhase -Journal `$journal -Phase 'ROLLBACK_STARTED'", `
    $repairCatchIndex, [StringComparison]::Ordinal)
Assert-Test -Condition ($repairCatchIndex -ge 0 -and $rollbackPhaseIndex -gt $repairCatchIndex) `
    -Message 'The same-profile repair preservation branch is missing.'
$repairSegment = $source.Substring($repairCatchIndex, $rollbackPhaseIndex - $repairCatchIndex)
Assert-Test -Condition ($repairSegment -notmatch 'Invoke-ClawLabInstallRollback') `
    -Message 'A same-profile repair failure must not consume pre-existing original backups.'

function New-TestStablePair {
    param(
        [string]$VrrState = 'CLAWLAB_30_120_ACTIVE',
        [string]$LfcState = 'CLAWLAB_LFC_FIX_ACTIVE',
        [string]$ArcSyncPolicy = 'INTEL_EXCELLENT_REQUIRED',
        [string]$ArcSyncVerification = 'EXCELLENT_EXACT',
        [string]$ManagedMode = 'CLAWLAB_30_120',
        [string]$LfcManagedMode = 'CLAWLAB_30_120'
    )
    return [pscustomobject]@{
        Vrr = [pscustomobject]@{
            State = $VrrState
            ArcSyncPolicy = $ArcSyncPolicy
            ArcSyncVerification = $ArcSyncVerification
            ManagedMode = $ManagedMode
        }
        Lfc = [pscustomobject]@{
            ManagedVrrMode = $LfcManagedMode
            LfcTransition = [pscustomobject]@{ State = $LfcState }
        }
    }
}

$activePair = New-TestStablePair
$activeDecision = Get-ClawLabStableStatePairDecision -RequestedAction Install30 `
    -Vrr $activePair.Vrr -Lfc $activePair.Lfc
Assert-Test -Condition (-not [bool]$activeDecision.RestartVerificationPending) `
    -Message 'A fully active standard 30-120 pair was not accepted.'

$pendingPair = New-TestStablePair -VrrState CLAWLAB_30_120_PENDING_RESTART `
    -LfcState CLAWLAB_LFC_FIX_PENDING_RESTART
$pendingDecision = Get-ClawLabStableStatePairDecision -RequestedAction Install30 `
    -Vrr $pendingPair.Vrr -Lfc $pendingPair.Lfc
Assert-Test -Condition ([bool]$pendingDecision.RestartVerificationPending) `
    -Message 'A matching standard pending-restart pair was not accepted.'

$tmaPair = New-TestStablePair -LfcState CLAWLAB_LFC_FIX_PENDING_RESTART `
    -ArcSyncPolicy TMA2027_PRESERVE_EXACT_CUSTOM_30_120 `
    -ArcSyncVerification TMA2027_CUSTOM_EXACT
$tmaDecision = Get-ClawLabStableStatePairDecision -RequestedAction Install30 `
    -Vrr $tmaPair.Vrr -Lfc $tmaPair.Lfc
Assert-Test -Condition ([bool]$tmaDecision.RestartVerificationPending -and
    [bool]$tmaDecision.Tma2027Exception) `
    -Message 'The exact TMA2027 active-VRR/pending-LFC pair was not accepted.'

foreach ($invalidTmaPair in @(
        (New-TestStablePair -LfcState CLAWLAB_LFC_FIX_PENDING_RESTART `
            -ArcSyncPolicy INTEL_EXCELLENT_REQUIRED -ArcSyncVerification TMA2027_CUSTOM_EXACT),
        (New-TestStablePair -LfcState CLAWLAB_LFC_FIX_PENDING_RESTART `
            -ArcSyncPolicy TMA2027_PRESERVE_EXACT_CUSTOM_30_120 -ArcSyncVerification NOT_VERIFIED),
        (New-TestStablePair -LfcState CLAWLAB_LFC_FIX_PENDING_RESTART `
            -ArcSyncPolicy TMA2027_PRESERVE_EXACT_CUSTOM_30_120 `
            -ArcSyncVerification TMA2027_CUSTOM_EXACT -LfcManagedMode UNMANAGED)
    )) {
    Assert-Throws -Operation {
        [void](Get-ClawLabStableStatePairDecision -RequestedAction Install30 `
                -Vrr $invalidTmaPair.Vrr -Lfc $invalidTmaPair.Lfc)
    } -ExpectedMessage 'The active VRR profile was verified, but Intel LFC is not active: CLAWLAB_LFC_FIX_PENDING_RESTART'
}

$officialPair = New-TestStablePair -VrrState OFFICIAL_48_120_ACTIVE `
    -ManagedMode OFFICIAL_48_120 -LfcManagedMode OFFICIAL_48_120
[void](Get-ClawLabStableStatePairDecision -RequestedAction Install48 `
        -Vrr $officialPair.Vrr -Lfc $officialPair.Lfc)
$officialPendingLfc = New-TestStablePair -VrrState OFFICIAL_48_120_ACTIVE `
    -LfcState CLAWLAB_LFC_FIX_PENDING_RESTART -ManagedMode OFFICIAL_48_120 `
    -LfcManagedMode OFFICIAL_48_120
Assert-Throws -Operation {
    [void](Get-ClawLabStableStatePairDecision -RequestedAction Install48 `
            -Vrr $officialPendingLfc.Vrr -Lfc $officialPendingLfc.Lfc)
} -ExpectedMessage 'The active VRR profile was verified, but Intel LFC is not active: CLAWLAB_LFC_FIX_PENDING_RESTART'

$identity = [pscustomobject]@{
    Sid = 'S-1-5-21-100-200-300-1001'
    SessionId = 7
    LocalAppData = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) 'ClawLabIdentity'))
    IsAdministrator = $true
}
Assert-Test -Condition (Assert-ClawLabElevatedIdentity -Actual $identity `
        -CallerSid $identity.Sid -CallerSessionId $identity.SessionId `
        -CallerLocalAppData $identity.LocalAppData) `
    -Message 'Matching caller/elevated identity was rejected.'

$wrongSid = $identity.PSObject.Copy()
$wrongSid.Sid = 'S-1-5-21-100-200-300-1002'
Assert-Throws -Operation {
    [void](Assert-ClawLabElevatedIdentity -Actual $wrongSid -CallerSid $identity.Sid `
            -CallerSessionId $identity.SessionId -CallerLocalAppData $identity.LocalAppData)
} -ExpectedMessage 'CLAWLAB_ELEVATED_IDENTITY_MISMATCH'

$wrongSession = $identity.PSObject.Copy()
$wrongSession.SessionId = 8
Assert-Throws -Operation {
    [void](Assert-ClawLabElevatedIdentity -Actual $wrongSession -CallerSid $identity.Sid `
            -CallerSessionId $identity.SessionId -CallerLocalAppData $identity.LocalAppData)
} -ExpectedMessage 'CLAWLAB_ELEVATED_IDENTITY_MISMATCH'

$wrongProfile = $identity.PSObject.Copy()
$wrongProfile.LocalAppData = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) 'OtherIdentity'))
Assert-Throws -Operation {
    [void](Assert-ClawLabElevatedIdentity -Actual $wrongProfile -CallerSid $identity.Sid `
            -CallerSessionId $identity.SessionId -CallerLocalAppData $identity.LocalAppData)
} -ExpectedMessage 'CLAWLAB_ELEVATED_IDENTITY_MISMATCH'

$notAdmin = $identity.PSObject.Copy()
$notAdmin.IsAdministrator = $false
Assert-Throws -Operation {
    [void](Assert-ClawLabElevatedIdentity -Actual $notAdmin -CallerSid $identity.Sid `
            -CallerSessionId $identity.SessionId -CallerLocalAppData $identity.LocalAppData)
} -ExpectedMessage 'CLAWLAB_ELEVATED_IDENTITY_MISMATCH'

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('ClawLab-Transaction-Test-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temporaryRoot) | Out-Null
try {
    $paths = New-ClawLabTransactionPaths -LocalAppData $temporaryRoot
    [IO.Directory]::CreateDirectory($paths.VrrStateRoot) | Out-Null
    [IO.Directory]::CreateDirectory($paths.LfcStateRoot) | Out-Null
    $backupHash = 'E49BC570225510B7C889ED292570F1345CAA07F5840DB57EA6998A403DB5CEF0'
    $stableCustom30Hash = '14CDDC390CF69367C4B6821A46728518200446A33F708A1A87CA673B68B66918'
    $verifiedVrrBackup = [pscustomobject][ordered]@{
        SchemaVersion = 2
        FixVersion = '2.3.0'
        BaselinePolicy = 'INTEL_STANDARD_BASELINE'
        PanelKey = 'CLAW_8_AI_PLUS'
        PhysicalEdidSha256 = $backupHash
        EdidOverrideStateAtSave = 'NONE'
        ProfileId = 2
        ProfileName = 'EXCELLENT'
        MinRefreshRateInHz = 48
        MaxRefreshRateInHz = 120
        MaxFrameTimeIncreaseInUs = 8333
        MaxFrameTimeDecreaseInUs = 8333
    }
    Write-ClawLabJsonAtomic -LiteralPath $paths.VrrBackup -Value $verifiedVrrBackup
    $backupVrrStatus = [pscustomobject]@{
        OriginalProfileSaved = $true
        BackupPath = $paths.VrrBackup
        PanelId = 'CSW0801'
    }
    # A stable 30-120 repair reports the active custom EDID here, while the
    # original VRR backup is intentionally bound to the pinned physical EDID.
    $backupLfcStatus = [pscustomobject]@{ PanelEdidSha256 = $stableCustom30Hash }
    Assert-Test -Condition (Test-ClawLabVrrOriginalBackupVerified -Paths $paths `
            -Vrr $backupVrrStatus -Lfc $backupLfcStatus) `
        -Message 'A physical VRR backup was not accepted with the exact stable custom 30-120 active EDID.'
    $verifiedVrrBackup.FixVersion = '2.2.1'
    Write-ClawLabJsonAtomic -LiteralPath $paths.VrrBackup -Value $verifiedVrrBackup
    Assert-Test -Condition (-not (Test-ClawLabVrrOriginalBackupVerified -Paths $paths `
                -Vrr $backupVrrStatus -Lfc $backupLfcStatus)) `
        -Message 'A VRR original backup from another release identity was accepted for repair.'
    $verifiedVrrBackup.FixVersion = '2.3.0'
    $verifiedVrrBackup.PhysicalEdidSha256 = '3518AB4456669D12A7B8D254F63005EAE143C784DCE02EC56C3753C41A664CA1'
    Write-ClawLabJsonAtomic -LiteralPath $paths.VrrBackup -Value $verifiedVrrBackup
    Assert-Test -Condition (-not (Test-ClawLabVrrOriginalBackupVerified -Paths $paths `
                -Vrr $backupVrrStatus -Lfc $backupLfcStatus)) `
        -Message 'A VRR original backup bound to another physical EDID was accepted for repair.'
    $verifiedVrrBackup.PhysicalEdidSha256 = $backupHash
    Write-ClawLabJsonAtomic -LiteralPath $paths.VrrBackup -Value $verifiedVrrBackup
    $backupVrrStatus.PanelId = 'TMA2027'
    Assert-Test -Condition (-not (Test-ClawLabVrrOriginalBackupVerified -Paths $paths `
                -Vrr $backupVrrStatus -Lfc $backupLfcStatus)) `
        -Message 'A VRR original backup was accepted for another active panel identity.'
    $backupVrrStatus.PanelId = 'CSW0801'
    $backupLfcStatus.PanelEdidSha256 = 'A' * 64
    Assert-Test -Condition (-not (Test-ClawLabVrrOriginalBackupVerified -Paths $paths `
                -Vrr $backupVrrStatus -Lfc $backupLfcStatus)) `
        -Message 'A VRR original backup was accepted with an unknown active EDID.'
    [IO.File]::Delete($paths.VrrBackup)

    $journal = New-ClawLabTransactionJournal -RequestedAction Install30 -Identity $identity `
        -Id ([Guid]::NewGuid().ToString('D')) -Previous $null
    Write-ClawLabJsonAtomic -LiteralPath $paths.Journal -Value $journal
    $readBack = Read-ClawLabJsonFile -LiteralPath $paths.Journal
    Assert-Test -Condition ([string]$readBack.Phase -eq 'STARTED') `
        -Message 'Atomic journal round trip failed.'
    Set-ClawLabTransactionPhase -Journal $journal -Phase 'TEST_PHASE' `
        -JournalPath $paths.Journal -Detail 'test'
    $readBack = Read-ClawLabJsonFile -LiteralPath $paths.Journal
    Assert-Test -Condition ([string]$readBack.Phase -eq 'TEST_PHASE') `
        -Message 'Atomic transaction phase update failed.'
    $cleanVrr = [pscustomobject]@{
        ManagedMode = 'NONE'; ProfileSwitchGuard = 'CLEAN'; OriginalProfileSaved = $false
        EdidOverride = 'NONE'; StartupReapply = 'NOT_INSTALLED'
        CursorRefreshHelper = 'NOT_INSTALLED'; IntelGraphicsStartup = 'INTEL_DEFAULT'
        RegistryModified = $false; RecoveryRequired = $false
    }
    $cleanLfc = [pscustomobject]@{
        ManagedVrrMode = 'UNMANAGED'; ExpectedRange = 'UNMANAGED'
        StartupPersistence = 'NOT_INSTALLED'; LfcFixActive = $false
        RestoreFinalizedPresent = $false; FactoryIntentPresent = $false
        FactoryFinalizedPresent = $false
        CurrentState = [pscustomobject]@{
            LowFpsSolutionEnabled = $true; HighFpsSolutionEnabled = $true
        }
        LfcTransition = [pscustomobject]@{
            State = 'INTEL_VRR_SOLUTIONS_NOT_PATCHED'; BackupPresent = $false
            RestoreTombstonePresent = $false; RestoreFinalizedVerified = $false
            FactoryIntentPresent = $false; FactoryFinalizedPresent = $false
            FactoryFinalizedVerified = $false
        }
    }
    $cleanDecision = Get-ClawLabRecoveryCleanDecision -Vrr $cleanVrr -Lfc $cleanLfc `
        -PresentTasks @() -RemainingArtifacts @()
    Assert-Test -Condition $cleanDecision.Clean `
        -Message 'A fully clean recovery state was not recognized as clean.'

    $factoryTerminal = (New-TestInstallState `
        -LfcTransitionState INTEL_VRR_SOLUTIONS_FACTORY_DEFAULTS_FINALIZED `
        -LfcFactoryFinalizedPresent $true -LfcFactoryFinalizedVerified $true).Lfc
    $factoryTerminalDecision = Get-ClawLabRecoveryCleanDecision -Vrr $cleanVrr `
        -Lfc $factoryTerminal -PresentTasks @() -RemainingArtifacts @() `
        -AllowLfcFactoryFinalizedProvenance
    Assert-Test -Condition $factoryTerminalDecision.Clean `
        -Message 'Verified terminal factory-default provenance was not accepted explicitly.'
    $factoryTerminalRefused = Get-ClawLabRecoveryCleanDecision -Vrr $cleanVrr `
        -Lfc $factoryTerminal -PresentTasks @() -RemainingArtifacts @()
    Assert-Test -Condition (-not $factoryTerminalRefused.Clean) `
        -Message 'Factory-default provenance was accepted without the explicit proof allowance.'

    foreach ($dirtyCase in @(
        [pscustomobject]@{ Tasks = @($paths.VrrTaskName); Artifacts = @() },
        [pscustomobject]@{ Tasks = @(); Artifacts = @($paths.VrrManaged) }
    )) {
        $dirtyDecision = Get-ClawLabRecoveryCleanDecision -Vrr $cleanVrr -Lfc $cleanLfc `
            -PresentTasks $dirtyCase.Tasks -RemainingArtifacts $dirtyCase.Artifacts
        Assert-Test -Condition (-not $dirtyDecision.Clean) `
            -Message 'An orphaned task or payload was incorrectly accepted as fully restored.'
    }

    $paths.ProtectedRuntimeBaseRoot = Join-Path $temporaryRoot 'ProtectedRuntimeBase'
    $paths.ProtectedRuntimeRoot = Join-Path $paths.ProtectedRuntimeBaseRoot '2.3.0'
    Assert-Test -Condition (@(Get-ClawLabRemainingManagedArtifacts -Paths $paths).Count -eq 0) `
        -Message 'An empty temporary state unexpectedly reported managed artifacts.'
    [IO.Directory]::CreateDirectory((Split-Path -Parent $paths.VrrManaged)) | Out-Null
    [IO.File]::WriteAllText($paths.VrrManaged, '{}', [Text.UTF8Encoding]::new($false))
    Assert-Test -Condition ((Get-ClawLabRemainingManagedArtifacts -Paths $paths) -contains $paths.VrrManaged) `
        -Message 'A partial managed state artifact was not detected.'
    [IO.File]::Delete($paths.VrrManaged)
    [IO.File]::WriteAllText($paths.VrrNormalizationCompensation, '{}', [Text.UTF8Encoding]::new($false))
    Assert-Test -Condition ((Get-ClawLabRemainingManagedArtifacts -Paths $paths) -contains `
            $paths.VrrNormalizationCompensation) `
        -Message 'A pending normalization compensation WAL was not detected as managed recovery state.'
    [IO.File]::Delete($paths.VrrNormalizationCompensation)
    [IO.File]::WriteAllText($paths.LfcFactoryIntent, '{}', [Text.UTF8Encoding]::new($false))
    Assert-Test -Condition ((Get-ClawLabRemainingManagedArtifacts -Paths $paths) -contains `
            $paths.LfcFactoryIntent) `
        -Message 'A pending LFC factory-default intent was not detected as managed recovery state.'

    $readOnlyProbe = Join-Path $temporaryRoot 'read-only-probe.ps1'
    [IO.File]::WriteAllText($readOnlyProbe, @'
Write-Host 'This user-facing child text must be suppressed.'
[pscustomobject]@{ Result = 'PASS'; Value = ('caf' + [char]0x00E9) }
'@, [Text.UTF8Encoding]::new($false))
    $readOnlyEnvelope = Invoke-ClawLabReadOnlyObject -ScriptPath $readOnlyProbe
    Assert-Test -Condition ([string]$readOnlyEnvelope.Result.Value -eq ('caf' + [char]0x00E9)) `
        -Message 'The ASCII/Base64 child envelope did not preserve Unicode data.'
}
finally {
    $resolvedTemporary = [IO.Path]::GetFullPath($temporaryRoot)
    $resolvedTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    Assert-Test -Condition $resolvedTemporary.StartsWith($resolvedTempRoot, [StringComparison]::OrdinalIgnoreCase) `
        -Message 'Refusing to clean a test directory outside the system temporary directory.'
    if ([IO.Directory]::Exists($resolvedTemporary)) {
        [IO.Directory]::Delete($resolvedTemporary, $true)
    }
}

. $localizationPath
[void](Initialize-ClawLabLocalization -Language en -CatalogPath $catalogPath)
$keyMatches = [regex]::Matches($source, '(?:-Key|-QuestionKey)\s+''([^'']+)''')
$usedKeys = @($keyMatches | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$catalog = [IO.File]::ReadAllText($catalogPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
$languages = @(Get-ClawLabSupportedLanguages)
Assert-Test -Condition ($languages.Count -eq 34) -Message 'The localization catalog must expose 34 languages.'
foreach ($language in $languages) {
    $localeProperty = $catalog.locales.PSObject.Properties[$language]
    Assert-Test -Condition ($null -ne $localeProperty) -Message "Missing locale: $language"
    foreach ($key in $usedKeys) {
        Assert-Test -Condition ($null -ne $localeProperty.Value.PSObject.Properties[$key]) `
            -Message "Locale '$language' is missing coordinator key '$key'."
    }
}

$batActions = [ordered]@{
    'CHECK_STATUS.bat' = 'CheckStatus'
    'UPDATE_CURSOR_REFRESH_ENGINE.bat' = 'UpdateCursorHelper'
    'COLLECT_UNSUPPORTED_CLAW_DISPLAY.bat' = 'CollectDiagnostics'
    'EXPORT_STATUS_REPORT.bat' = 'ExportStatus'
    'INSTALL_30_120_VRR.bat' = 'Install30'
    'INSTALL_48_120_VRR.bat' = 'Install48'
    'RESTORE_ORIGINAL_VRR.bat' = 'Restore'
    'RESTORE_INTEL_LFC_DEFAULTS.bat' = 'RestoreLfcOnly'
    'FACTORY_RESET_CLAWLAB_VRR.bat' = 'FactoryReset'
    'EMERGENCY_REMOVE_CLAWLAB_EDID.bat' = 'EmergencyRestoreEdid'
    'SET_INTEL_LFC_FACTORY_DEFAULTS.bat' = 'FactoryLfcDefaults'
    'EXPERIMENTAL\INSTALL_STABLE_EXPERIMENTAL_48_144_VRR.bat' = 'Install48_144'
    'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_30_144_VRR.bat' = 'Install30_144'
    'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_30_165_VRR.bat' = 'Install30_165'
    'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_30_180_VRR.bat' = 'Install30_180'
    'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_30_192_VRR.bat' = 'Install30_192'
    'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_48_165_VRR.bat' = 'Install48_165'
    'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_48_180_VRR.bat' = 'Install48_180'
    'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_48_192_VRR.bat' = 'Install48_192'
}
$packagedLauncherDirectories = @{
    'COLLECT_UNSUPPORTED_CLAW_DISPLAY.bat' = 'DIAGNOSTICS'
    'EXPORT_STATUS_REPORT.bat' = 'DIAGNOSTICS'
    'RESTORE_ORIGINAL_VRR.bat' = 'RECOVERY'
    'RESTORE_INTEL_LFC_DEFAULTS.bat' = 'RECOVERY'
    'FACTORY_RESET_CLAWLAB_VRR.bat' = 'EMERGENCY'
    'EMERGENCY_REMOVE_CLAWLAB_EDID.bat' = 'EMERGENCY'
    'SET_INTEL_LFC_FACTORY_DEFAULTS.bat' = 'EMERGENCY'
}

foreach ($entry in $batActions.GetEnumerator()) {
    $relativeBatPath = [string]$entry.Key
    if ($isPackagedLayout -and $packagedLauncherDirectories.ContainsKey($relativeBatPath)) {
        $relativeBatPath = Join-Path $packagedLauncherDirectories[$relativeBatPath] $relativeBatPath
    }
    $batPath = Join-Path $root $relativeBatPath
    Assert-Test -Condition (Test-Path -LiteralPath $batPath -PathType Leaf) `
        -Message "Public launcher is missing: $relativeBatPath"
    $bat = [IO.File]::ReadAllText($batPath, [Text.Encoding]::Default)
    Assert-Test -Condition ([regex]::Matches($bat,
            '(?im)^set "CLAWLAB_POWERSHELL=%SystemRoot%\\System32\\WindowsPowerShell\\v1\.0\\powershell\.exe"\s*$').Count -eq 1) `
        -Message "Public launcher does not pin Windows PowerShell by absolute System32 path: $($entry.Key)"
    Assert-Test -Condition ([regex]::Matches($bat,
            '(?im)^if not exist "%CLAWLAB_POWERSHELL%" exit /b 1\s*$').Count -eq 1) `
        -Message "Public launcher does not fail closed when Windows PowerShell is absent: $($entry.Key)"
    Assert-Test -Condition ([regex]::Matches($bat,
            '(?im)^"%CLAWLAB_POWERSHELL%"\s').Count -eq 1) `
        -Message "Public launcher must start the pinned Windows PowerShell exactly once: $($entry.Key)"
    Assert-Test -Condition ($bat -notmatch '(?im)^\s*powershell(?:\.exe)?\s') `
        -Message "Public launcher still resolves PowerShell through PATH: $($entry.Key)"
    Assert-Test -Condition ($bat -match ('(?i)-Action\s+' + [regex]::Escape([string]$entry.Value) + '(\s|$)')) `
        -Message "Public launcher has the wrong coordinator action: $($entry.Key)"
    Assert-Test -Condition ($bat -match 'ClawLab-VRR-Transaction\.ps1') `
        -Message "Public launcher bypasses the coordinator: $($entry.Key)"
    Assert-Test -Condition ($bat -notmatch '(?i)MSI-Claw-(?:VRR|Intel-LFC)-Fix\.ps1') `
        -Message "Public launcher invokes a core mutator directly: $($entry.Key)"
    Assert-Test -Condition ($bat -notmatch '(?im)^\s*(?:choice|set\s+/p|pause|timeout|shutdown(?:\.exe)?)\b') `
        -Message "Public launcher still contains an unlocalized prompt or restart side effect: $($entry.Key)"
    Assert-Test -Condition ($bat -notmatch '(?im)^\s*echo\s+[^.]') `
        -Message "Public launcher still contains user-facing English text: $($entry.Key)"
}

Write-Host ("ClawLab VRR transaction tests passed on PowerShell {0}." -f $PSVersionTable.PSVersion) -ForegroundColor Green
