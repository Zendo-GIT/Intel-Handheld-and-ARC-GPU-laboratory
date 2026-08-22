[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot '..\ArcSync-Range-Policy.ps1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    $modulePath = Join-Path $PSScriptRoot '..\scripts\ArcSync-Range-Policy.ps1'
}
. $modulePath

function Assert-Equal {
    param(
        [Parameter(Mandatory)][object]$Actual,
        [Parameter(Mandatory)][object]$Expected,
        [Parameter(Mandatory)][string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message Expected '$Expected', got '$Actual'."
    }
}

$claw8 = 'CLAW_8_AI_PLUS'
$tmaPanel = 'CLAW_A1M_CLAW_7_AI_PLUS'
$physicalEdid = 'PHYSICAL_EDID'
$customEdid = 'CUSTOM_EDID'

Assert-Equal `
    (Get-ClawLabArcSyncMonitorRangeState -PanelKey $claw8 -MonitorMinimumHz 48 -MonitorMaximumHz 120) `
    'DECLARED_KNOWN_RANGE' 'The Claw 8 physical range was rejected.'
Assert-Equal `
    (Get-ClawLabArcSyncMonitorRangeState -PanelKey $claw8 -MonitorMinimumHz 30 -MonitorMaximumHz 120) `
    'DECLARED_KNOWN_RANGE' 'The Claw 8 custom range was rejected.'
Assert-Equal `
    (Get-ClawLabArcSyncMonitorRangeState -PanelKey $claw8 -MonitorMinimumHz 24 -MonitorMaximumHz 120) `
    'UNSUPPORTED' 'The A1M-only telemetry anomaly leaked into the Claw 8 policy.'
Assert-Equal `
    (Get-ClawLabArcSyncMonitorRangeState -PanelKey $tmaPanel -MonitorMinimumHz 24 -MonitorMaximumHz 120) `
    'INTEL_CONTROL_LIB_HALF_PHYSICAL_FLOOR' 'The collected TMA2027 telemetry anomaly was not recognized.'
Assert-Equal `
    (Get-ClawLabArcSyncMonitorRangeState -PanelKey $tmaPanel -MonitorMinimumHz 25 -MonitorMaximumHz 120) `
    'UNSUPPORTED' 'An uncollected TMA2027 monitor floor was accepted.'
Assert-Equal `
    (Get-ClawLabArcSyncMonitorRangeState -PanelKey $tmaPanel -MonitorMinimumHz 15 -MonitorMaximumHz 120) `
    'UNSUPPORTED' 'The half-managed TMA2027 floor was accepted without a managed-range binding.'
Assert-Equal `
    (Get-ClawLabArcSyncMonitorRangeState -PanelKey $tmaPanel `
        -MonitorMinimumHz 15 -MonitorMaximumHz 120 `
        -ExpectedMinimumHz 30 -ExpectedMaximumHz 120) `
    'INTEL_CONTROL_LIB_HALF_MANAGED_FLOOR' `
    'The collected TMA2027 half-managed-floor telemetry was not recognized.'
Assert-Equal `
    (Get-ClawLabArcSyncMonitorRangeState -PanelKey $claw8 `
        -MonitorMinimumHz 15 -MonitorMaximumHz 120 `
        -ExpectedMinimumHz 30 -ExpectedMaximumHz 120) `
    'UNSUPPORTED' 'The TMA2027 half-managed-floor exception leaked onto Claw 8.'
Assert-Equal `
    (Get-ClawLabArcSyncMonitorRangeState -PanelKey $tmaPanel `
        -MonitorMinimumHz 15 -MonitorMaximumHz 120 `
        -ExpectedMinimumHz 48 -ExpectedMaximumHz 120) `
    'UNSUPPORTED' 'Half-managed telemetry was accepted for the official 48 Hz floor.'

Assert-Equal `
    (Test-ClawLabArcSyncMonitorRangeCompatible -PanelKey $tmaPanel `
        -MonitorMinimumHz 24 -MonitorMaximumHz 120 -ExpectedMinimumHz 30 -ExpectedMaximumHz 120) `
    $true 'TMA2027 did not accept its selected 30-120 profile independently of monitor telemetry.'
Assert-Equal `
    (Test-ClawLabArcSyncMonitorRangeCompatible -PanelKey $tmaPanel `
        -MonitorMinimumHz 24 -MonitorMaximumHz 120 -ExpectedMinimumHz 48 -ExpectedMaximumHz 120) `
    $true 'TMA2027 did not accept its selected 48-120 profile independently of monitor telemetry.'
Assert-Equal `
    (Test-ClawLabArcSyncMonitorRangeCompatible -PanelKey $tmaPanel `
        -MonitorMinimumHz 24 -MonitorMaximumHz 120 -ExpectedMinimumHz 24 -ExpectedMaximumHz 120) `
    $false 'The telemetry-only floor was incorrectly accepted as an installable profile.'
Assert-Equal `
    (Test-ClawLabArcSyncMonitorRangeCompatible -PanelKey $tmaPanel `
        -MonitorMinimumHz 24 -MonitorMaximumHz 120 -ExpectedMinimumHz 30 -ExpectedMaximumHz 144) `
    $true 'The A1M/Claw 7 AI+ telemetry exception rejected the guarded 30-144 profile.'
Assert-Equal `
    (Test-ClawLabArcSyncMonitorRangeCompatible -PanelKey $tmaPanel `
        -MonitorMinimumHz 15 -MonitorMaximumHz 120 -ExpectedMinimumHz 30 -ExpectedMaximumHz 120) `
    $true 'TMA2027 rejected its bound managed 30-120 range when ControlLib reported the halved floor.'
Assert-Equal `
    (Test-ClawLabArcSyncMonitorRangeCompatible -PanelKey $tmaPanel `
        -MonitorMinimumHz 15 -MonitorMaximumHz 120 -ExpectedMinimumHz 48 -ExpectedMaximumHz 120) `
    $false 'The half-managed telemetry floor was accepted for a 48 Hz managed profile.'
Assert-Equal `
    (Test-ClawLabArcSyncMonitorRangeCompatible -PanelKey $claw8 `
        -MonitorMinimumHz 15 -MonitorMaximumHz 120 -ExpectedMinimumHz 30 -ExpectedMaximumHz 120) `
    $false 'The half-managed telemetry floor was accepted on a non-TMA2027 panel.'

foreach ($maximum in @(144, 165, 180, 192)) {
    foreach ($minimum in @(30, 48)) {
        Assert-Equal `
            (Test-ClawLabArcSyncMonitorRangeCompatible -PanelKey $tmaPanel `
                -MonitorMinimumHz 24 -MonitorMaximumHz 120 `
                -ExpectedMinimumHz $minimum -ExpectedMaximumHz $maximum) `
            $true "TMA2027 rejected guarded profile $minimum-$maximum."
    }
    Assert-Equal `
        (Test-ClawLabArcSyncMonitorRangeCompatible -PanelKey $tmaPanel `
            -MonitorMinimumHz 15 -MonitorMaximumHz 120 `
            -ExpectedMinimumHz 30 -ExpectedMaximumHz $maximum) `
        $true "TMA2027 rejected guarded 30-$maximum with half-managed monitor telemetry."
}

Assert-Equal `
    (Test-ClawLabDirectRangeReady -PanelKey $claw8 -DirectMinimumHz 30 -DirectMaximumHz 120 `
        -ExpectedMinimumHz 30 -ExpectedMaximumHz 120 `
        -ReportedEdidSha256 $customEdid -ExpectedEdidSha256 $customEdid) `
    $true 'An exact Claw 8 direct custom range was rejected.'
Assert-Equal `
    (Test-ClawLabDirectRangeReady -PanelKey $claw8 -DirectMinimumHz 48 -DirectMaximumHz 120 `
        -ExpectedMinimumHz 30 -ExpectedMaximumHz 120 `
        -ReportedEdidSha256 $customEdid -ExpectedEdidSha256 $customEdid) `
    $false 'The TMA2027 direct-range exception leaked into the Claw 8 policy.'
Assert-Equal `
    (Test-ClawLabDirectRangeReady -PanelKey $tmaPanel -DirectMinimumHz 48 -DirectMaximumHz 120 `
        -ExpectedMinimumHz 30 -ExpectedMaximumHz 120 `
        -ReportedEdidSha256 $customEdid -ExpectedEdidSha256 $customEdid) `
    $true 'The collected TMA2027 physical direct range was rejected for the loaded custom EDID.'
Assert-Equal `
    (Test-ClawLabDirectRangeReady -PanelKey $tmaPanel -DirectMinimumHz 48 -DirectMaximumHz 120 `
        -ExpectedMinimumHz 30 -ExpectedMaximumHz 120 `
        -ReportedEdidSha256 $physicalEdid -ExpectedEdidSha256 $customEdid) `
    $false 'A pending TMA2027 custom EDID was incorrectly treated as loaded.'
Assert-Equal `
    (Test-ClawLabDirectRangeReady -PanelKey $tmaPanel -DirectMinimumHz 24 -DirectMaximumHz 120 `
        -ExpectedMinimumHz 30 -ExpectedMaximumHz 120 `
        -ReportedEdidSha256 $customEdid -ExpectedEdidSha256 $customEdid) `
    $false 'The telemetry-only floor was incorrectly accepted from the direct Intel interface.'

$profiles = @(
    'OFFICIAL_48_120', 'CLAWLAB_30_120',
    'CLAWLAB_48_144', 'CLAWLAB_48_165', 'CLAWLAB_48_180', 'CLAWLAB_48_192',
    'CLAWLAB_30_144', 'CLAWLAB_30_165', 'CLAWLAB_30_180', 'CLAWLAB_30_192'
)
foreach ($panelKey in @($claw8, $tmaPanel)) {
    foreach ($current in $profiles) {
        foreach ($desired in $profiles) {
            $expected = $current -eq $desired
            Assert-Equal `
                (Test-ClawLabProfileTransitionAllowed -CurrentMode $current `
                    -CurrentState 'CONSISTENT' -DesiredMode $desired) `
                $expected "$panelKey profile-transition guard failed for $current -> $desired."
        }
    }
    foreach ($desired in $profiles) {
        Assert-Equal `
            (Test-ClawLabProfileTransitionAllowed -CurrentMode 'NONE' `
                -CurrentState 'CLEAN' -DesiredMode $desired) `
            $true "$panelKey clean-state install was refused for $desired."
        Assert-Equal `
            (Test-ClawLabProfileTransitionAllowed -CurrentMode 'LEGACY_MANAGED_STATE' `
                -CurrentState 'RESTORE_REQUIRED' -DesiredMode $desired) `
            $false "$panelKey restore-required state allowed $desired."
    }
}

$repairable30 = @{
    CurrentMode = 'CLAWLAB_30_120'
    CurrentState = 'INCONSISTENT_RESTORE_REQUIRED'
    DesiredMode = 'CLAWLAB_30_120'
    CurrentOverrideState = 'CLAWLAB_30_120'
    ManagedIdentityVerified = $true
    VrrOriginalBackupVerified = $true
    LfcOriginalBackupVerified = $true
    TrialArtifactsAbsent = $true
    RecoveryClear = $true
}
Assert-Equal (Get-ClawLabStableProfileRepairDisposition @repairable30) `
    'REPAIRABLE_SAME_MODE' `
    'An exact 30-120 managed identity with missing persistence was not classified as repairable.'
$repairable48 = @{} + $repairable30
$repairable48.CurrentMode = 'OFFICIAL_48_120'
$repairable48.CurrentState = 'CONSISTENT'
$repairable48.DesiredMode = 'OFFICIAL_48_120'
$repairable48.CurrentOverrideState = 'NONE'
Assert-Equal (Get-ClawLabStableProfileRepairDisposition @repairable48) `
    'REPAIRABLE_SAME_MODE' `
    'An exact backed 48-120 same-mode reapplication was not classified as repairable.'

foreach ($invalidRepair in @(
        @{ Name = 'cross-profile'; Property = 'DesiredMode'; Value = 'OFFICIAL_48_120' },
        @{ Name = 'unknown override'; Property = 'CurrentOverrideState'; Value = 'UNKNOWN_OVERRIDE' },
        @{ Name = 'unverified managed identity'; Property = 'ManagedIdentityVerified'; Value = $false },
        @{ Name = 'missing VRR backup'; Property = 'VrrOriginalBackupVerified'; Value = $false },
        @{ Name = 'missing LFC backup'; Property = 'LfcOriginalBackupVerified'; Value = $false },
        @{ Name = 'trial artifacts'; Property = 'TrialArtifactsAbsent'; Value = $false },
        @{ Name = 'recovery pending'; Property = 'RecoveryClear'; Value = $false },
        @{ Name = 'unsupported guard'; Property = 'CurrentState'; Value = 'RESTORE_REQUIRED' }
    )) {
    $arguments = @{} + $repairable30
    $arguments[$invalidRepair.Property] = $invalidRepair.Value
    Assert-Equal (Get-ClawLabStableProfileRepairDisposition @arguments) `
        'RESTORE_REQUIRED' "Unsafe same-mode repair was accepted: $($invalidRepair.Name)."
}
$experimentalRepair = @{} + $repairable30
$experimentalRepair.CurrentMode = 'CLAWLAB_30_144'
$experimentalRepair.DesiredMode = 'CLAWLAB_30_144'
$experimentalRepair.CurrentOverrideState = 'CLAWLAB_30_144'
Assert-Equal (Get-ClawLabStableProfileRepairDisposition @experimentalRepair) `
    'RESTORE_REQUIRED' 'An experimental profile was admitted to the stable repair path.'

Assert-Equal `
    (Test-ClawLabFirstInstallProfileSafe -CurrentMode 'NONE' -CurrentState 'CLEAN' -ProfileId 1) `
    $true 'A clean RECOMMENDED first-install baseline was rejected.'
Assert-Equal `
    (Test-ClawLabFirstInstallProfileSafe -CurrentMode 'NONE' -CurrentState 'CLEAN' -ProfileId 2) `
    $true 'A clean EXCELLENT first-install baseline was rejected.'
Assert-Equal `
    (Test-ClawLabFirstInstallProfileSafe -CurrentMode 'NONE' -CurrentState 'CLEAN' -ProfileId 7) `
    $false 'An unmanaged CUSTOM profile was incorrectly accepted without main-installer standard-profile normalization.'
Assert-Equal `
    (Test-ClawLabFirstInstallProfileSafe -CurrentMode 'CLAWLAB_30_120' -CurrentState 'CONSISTENT' -ProfileId 2) `
    $true 'An existing consistent ClawLab repair was rejected by the first-install guard.'

$exactTmaCustomArguments = @{
    PanelKey = $tmaPanel
    TelemetryState = 'INTEL_CONTROL_LIB_HALF_PHYSICAL_FLOOR'
    ProfileId = 7
    MinimumHz = 30
    MaximumHz = 120
    MaxIncreaseUs = 8333
    MaxDecreaseUs = 8333
}

Assert-Equal `
    (Test-ClawLabKnownTma2027Custom30Profile @exactTmaCustomArguments) `
    $true 'The exact collected TMA2027 CUSTOM 30-120 baseline was not recognized.'

$exactClaw8FactoryArguments = @{
    PanelKey = $claw8
    TelemetryState = 'DECLARED_KNOWN_RANGE'
    ProfileId = 1
    MinimumHz = 60
    MaximumHz = 120
    MaxIncreaseUs = 8333
    MaxDecreaseUs = 8333
}
Assert-Equal `
    (Test-ClawLabKnownUnmanagedFactoryProfile @exactClaw8FactoryArguments) `
    $true 'The exact Claw 8 RECOMMENDED 60-120 Intel factory signature was not recognized.'
Assert-Equal `
    (Test-ClawLabKnownUnmanagedFactoryProfile @exactTmaCustomArguments) `
    $true 'The exact TMA2027 OEM CUSTOM factory signature was not recognized.'

foreach ($variation in @(
        @{ Name = 'CUSTOM profile'; Changes = @{ ProfileId = 7 } },
        @{ Name = '48 Hz floor'; Changes = @{ MinimumHz = 48 } },
        @{ Name = 'wrong ceiling'; Changes = @{ MaximumHz = 119 } },
        @{ Name = 'wrong increase timing'; Changes = @{ MaxIncreaseUs = 8332 } },
        @{ Name = 'wrong decrease timing'; Changes = @{ MaxDecreaseUs = 8334 } },
        @{ Name = 'unsupported telemetry'; Changes = @{ TelemetryState = 'UNSUPPORTED' } }
    )) {
    $arguments = @{} + $exactClaw8FactoryArguments
    foreach ($key in $variation.Changes.Keys) {
        $arguments[$key] = $variation.Changes[$key]
    }
    Assert-Equal `
        (Test-ClawLabKnownUnmanagedFactoryProfile @arguments) `
        $false "The Claw 8 factory-signature proof accepted $($variation.Name)."
}

$orphanedDefaultVrrShell = [pscustomobject]@{
    State = 'DRIVER_PROFILE_CONSTRAINED'
    PanelId = 'CSW0801'
    PhysicalPanelRange = '48-120 Hz'
    ArcSyncMonitorTelemetry = 'DECLARED_KNOWN_RANGE'
    ArcSyncPolicy = 'UNMANAGED'
    ArcSyncVerification = 'NOT_VERIFIED'
    DriverProfile = 'RECOMMENDED'
    DriverActiveRange = '60-120 Hz'
    DriverProfileMaxIncreaseUs = 8333
    DriverProfileMaxDecreaseUs = 8333
    ManagedMode = 'LEGACY_MANAGED_STATE'
    ProfileSwitchGuard = 'RESTORE_REQUIRED'
    OriginalProfileSaved = $false
    StartupReapply = 'TASK_INVALID'
    CursorRefreshHelper = 'NOT_INSTALLED'
    IntelGraphicsStartup = 'INTEL_DEFAULT'
    EdidOverride = 'NONE'
    NormalizationCompensation = 'NONE'
    RecoveryRequired = $false
    RestartRequired = $false
    RegistryModified = $false
    DriverFilesModified = $false
}
$orphanedDefaultLfcShell = [pscustomobject]@{
    ManagedVrrMode = 'UNMANAGED'
    ExpectedRange = 'UNMANAGED'
    StartupPersistence = 'NOT_INSTALLED'
    LfcFixActive = $false
    ThirdPartyEdidOverrideValues = 'NONE'
    RestoreTombstonePresent = $false
    RestoreFinalizedPresent = $false
    FactoryIntentPresent = $false
    FactoryFinalizedPresent = $false
    LfcTransition = [pscustomobject]@{
        State = 'INTEL_VRR_SOLUTIONS_NOT_PATCHED'
        BackupPresent = $false
    }
    CurrentState = [pscustomobject]@{
        Result = 'Success'
        Supported = $true
        VrrEnabled = $true
        MinimumHz = 48
        MaximumHz = 120
        LowFpsSolutionEnabled = $true
        HighFpsSolutionEnabled = $true
    }
}
$failedRestoreJournal = [pscustomobject]@{
    Action = 'Restore'
    Phase = 'RECOVERY_REQUIRED'
}
$orphanEvidenceArguments = @{
    Vrr = $orphanedDefaultVrrShell
    Lfc = $orphanedDefaultLfcShell
    VrrTaskQuery = 'PRESENT'
    CursorTaskQuery = 'ABSENT'
    LfcTaskQuery = 'ABSENT'
    TransactionJournal = $failedRestoreJournal
}
Assert-Equal `
    (Test-ClawLabOrphanedDefaultShellEvidence @orphanEvidenceArguments) `
    $true 'The exact collected Claw 8 orphaned-default shell was not recognized.'

$tmaOrphanedDefaultVrrShell = $orphanedDefaultVrrShell.PSObject.Copy()
$tmaOrphanedDefaultVrrShell.PanelId = 'TMA2027'
$tmaOrphanedDefaultVrrShell.ArcSyncMonitorTelemetry = 'INTEL_CONTROL_LIB_HALF_PHYSICAL_FLOOR'
$tmaOrphanedDefaultVrrShell.DriverProfile = 'CUSTOM'
$tmaOrphanedDefaultVrrShell.DriverActiveRange = '30-120 Hz'
$tmaOrphanEvidenceArguments = @{} + $orphanEvidenceArguments
$tmaOrphanEvidenceArguments.Vrr = $tmaOrphanedDefaultVrrShell
Assert-Equal `
    (Test-ClawLabOrphanedDefaultShellEvidence @tmaOrphanEvidenceArguments) `
    $true 'The exact TMA2027 OEM orphaned-default shell was not recognized.'

foreach ($unsafeOrphan in @(
        @{ Name = 'active EDID'; Target = 'Vrr'; Property = 'EdidOverride'; Value = 'CLAWLAB_30_120' },
        @{ Name = 'profile timing drift'; Target = 'Vrr'; Property = 'DriverProfileMaxIncreaseUs'; Value = 8332 },
        @{ Name = 'unexpected VRR recovery flag'; Target = 'Vrr'; Property = 'RecoveryRequired'; Value = $true },
        @{ Name = 'patched Intel low-FPS flag'; Target = 'LfcCurrent'; Property = 'LowFpsSolutionEnabled'; Value = $false },
        @{ Name = 'wrong journal phase'; Target = 'Journal'; Property = 'Phase'; Value = 'VRR_RESTORED' },
        @{ Name = 'missing stale task'; Target = 'Query'; Property = 'VrrTaskQuery'; Value = 'ABSENT' }
    )) {
    $arguments = @{} + $orphanEvidenceArguments
    $vrrCopy = $orphanedDefaultVrrShell.PSObject.Copy()
    $lfcCopy = $orphanedDefaultLfcShell.PSObject.Copy()
    $lfcCurrentCopy = $orphanedDefaultLfcShell.CurrentState.PSObject.Copy()
    $lfcCopy.CurrentState = $lfcCurrentCopy
    $journalCopy = $failedRestoreJournal.PSObject.Copy()
    $arguments.Vrr = $vrrCopy
    $arguments.Lfc = $lfcCopy
    $arguments.TransactionJournal = $journalCopy
    switch ($unsafeOrphan.Target) {
        'Vrr' { $vrrCopy.($unsafeOrphan.Property) = $unsafeOrphan.Value }
        'LfcCurrent' { $lfcCurrentCopy.($unsafeOrphan.Property) = $unsafeOrphan.Value }
        'Journal' { $journalCopy.($unsafeOrphan.Property) = $unsafeOrphan.Value }
        'Query' { $arguments[$unsafeOrphan.Property] = $unsafeOrphan.Value }
    }
    Assert-Equal `
        (Test-ClawLabOrphanedDefaultShellEvidence @arguments) `
        $false "Unsafe orphaned-default recovery evidence was accepted: $($unsafeOrphan.Name)."
}

Assert-Equal `
    (Get-ClawLabFactoryResetProfileDecision @exactTmaCustomArguments) `
    'PRESERVE_TMA2027_OEM_CUSTOM_30_120' `
    'Factory reset did not preserve the exact TMA2027 OEM CUSTOM baseline.'

$factoryResetUnsafeTmaVariations = @(
    @{ Name = '24 Hz active floor'; Changes = @{ MinimumHz = 24 } },
    @{ Name = 'wrong maximum'; Changes = @{ MaximumHz = 119 } },
    @{ Name = 'wrong increase timing'; Changes = @{ MaxIncreaseUs = 8332 } },
    @{ Name = 'wrong decrease timing'; Changes = @{ MaxDecreaseUs = 8334 } },
    @{ Name = 'wrong telemetry'; Changes = @{ TelemetryState = 'DECLARED_KNOWN_RANGE' } }
)
foreach ($variation in $factoryResetUnsafeTmaVariations) {
    $arguments = @{} + $exactTmaCustomArguments
    foreach ($key in $variation.Changes.Keys) {
        $arguments[$key] = $variation.Changes[$key]
    }
    Assert-Equal `
        (Get-ClawLabFactoryResetProfileDecision @arguments) `
        'REFUSE_UNSAFE_TMA2027_CUSTOM' `
        "Factory reset did not fail closed for the TMA2027 $($variation.Name) variation."
}

foreach ($standardProfile in @(1, 2)) {
    $arguments = @{} + $exactTmaCustomArguments
    $arguments.ProfileId = $standardProfile
    Assert-Equal `
        (Get-ClawLabFactoryResetProfileDecision @arguments) `
        'SET_INTEL_RECOMMENDED' `
        "Factory reset rejected Intel standard profile ID $standardProfile."
}

$factoryWrongPanel = @{} + $exactTmaCustomArguments
$factoryWrongPanel.PanelKey = $claw8
Assert-Equal `
    (Get-ClawLabFactoryResetProfileDecision @factoryWrongPanel) `
    'SET_INTEL_RECOMMENDED' `
    'The TMA2027 factory-preservation exception leaked onto another panel.'

$restorePolicyCases = @(
    @{ Policy = 'INTEL_STANDARD_BASELINE'; Matches = $true; Expected = 'SKIP_ALREADY_MATCHING' },
    @{ Policy = 'INTEL_STANDARD_BASELINE'; Matches = $false; Expected = 'WRITE_SAVED_STANDARD_PROFILE' },
    @{ Policy = 'TMA2027_VERIFIED_CUSTOM_30_120'; Matches = $true; Expected = 'PRESERVE_TMA2027_NO_WRITE' },
    @{ Policy = 'TMA2027_VERIFIED_CUSTOM_30_120'; Matches = $false; Expected = 'REFUSE_TMA2027_DRIFT_NO_WRITE' },
    @{ Policy = 'UNKNOWN_POLICY'; Matches = $true; Expected = 'REFUSE_UNKNOWN_BASELINE_POLICY' }
)
foreach ($case in $restorePolicyCases) {
    Assert-Equal `
        (Get-ClawLabSavedProfileRestoreDecision `
            -BaselinePolicy ([string]$case.Policy) -SnapshotMatches ([bool]$case.Matches)) `
        ([string]$case.Expected) `
        "Saved-profile restore policy failed for $($case.Policy), match=$($case.Matches)."
}

$tmaSignatureVariations = @(
    @{ Name = '24 Hz telemetry floor'; Changes = @{ MinimumHz = 24 } },
    @{ Name = 'wrong maximum'; Changes = @{ MaximumHz = 119 } },
    @{ Name = 'wrong increase timing'; Changes = @{ MaxIncreaseUs = 8332 } },
    @{ Name = 'wrong decrease timing'; Changes = @{ MaxDecreaseUs = 8334 } },
    @{ Name = 'wrong panel'; Changes = @{ PanelKey = $claw8 } },
    @{ Name = 'wrong profile'; Changes = @{ ProfileId = 6 } },
    @{ Name = 'wrong telemetry'; Changes = @{ TelemetryState = 'DECLARED_KNOWN_RANGE' } }
)
foreach ($variation in $tmaSignatureVariations) {
    $arguments = @{} + $exactTmaCustomArguments
    foreach ($key in $variation.Changes.Keys) {
        $arguments[$key] = $variation.Changes[$key]
    }
    Assert-Equal `
        (Test-ClawLabKnownTma2027Custom30Profile @arguments) `
        $false "The TMA2027 exact-signature guard accepted the $($variation.Name) variation."
}

$exactTmaFirstInstallArguments = @{} + $exactTmaCustomArguments
$exactTmaFirstInstallArguments.CurrentMode = 'NONE'
$exactTmaFirstInstallArguments.CurrentState = 'CLEAN'
$exactTmaFirstInstallArguments.OverrideState = 'NONE'
$exactTmaFirstInstallArguments.DesiredMode = 'CLAWLAB_30_120'

Assert-Equal `
    (Get-ClawLabFirstInstallBaselineDecision @exactTmaFirstInstallArguments) `
    'TMA2027_PRESERVE_EXACT_CUSTOM_30_120' `
    'The exact clean TMA2027 fallback did not authorize Install30.'

$refusedTmaModes = @(
    'OFFICIAL_48_120',
    'CLAWLAB_48_144', 'CLAWLAB_48_165', 'CLAWLAB_48_180', 'CLAWLAB_48_192',
    'CLAWLAB_30_144', 'CLAWLAB_30_165', 'CLAWLAB_30_180', 'CLAWLAB_30_192'
)
foreach ($desiredMode in $refusedTmaModes) {
    $arguments = @{} + $exactTmaFirstInstallArguments
    $arguments.DesiredMode = $desiredMode
    Assert-Equal `
        (Get-ClawLabFirstInstallBaselineDecision @arguments) `
        'REFUSE_TMA2027_CUSTOM_FOR_MODE' `
        "The exact TMA2027 fallback incorrectly authorized $desiredMode."
}

$overrideArguments = @{} + $exactTmaFirstInstallArguments
$overrideArguments.OverrideState = 'EXACT_CUSTOM_OVERRIDE'
Assert-Equal `
    (Get-ClawLabFirstInstallBaselineDecision @overrideArguments) `
    'REFUSE_TMA2027_CUSTOM_FOR_MODE' `
    'The TMA2027 fallback accepted an existing EDID override.'

$unsafeTmaDecisionVariations = @(
    @{ Name = '24 Hz profile floor'; Changes = @{ MinimumHz = 24 } },
    @{ Name = 'wrong maximum'; Changes = @{ MaximumHz = 119 } },
    @{ Name = 'wrong increase timing'; Changes = @{ MaxIncreaseUs = 8332 } },
    @{ Name = 'wrong decrease timing'; Changes = @{ MaxDecreaseUs = 8334 } },
    @{ Name = 'wrong telemetry'; Changes = @{ TelemetryState = 'DECLARED_KNOWN_RANGE' } },
    @{ Name = 'managed-only half-floor telemetry without a managed record'; Changes = @{ TelemetryState = 'INTEL_CONTROL_LIB_HALF_MANAGED_FLOOR' } }
)
foreach ($variation in $unsafeTmaDecisionVariations) {
    $arguments = @{} + $exactTmaFirstInstallArguments
    foreach ($key in $variation.Changes.Keys) {
        $arguments[$key] = $variation.Changes[$key]
    }
    Assert-Equal `
        (Get-ClawLabFirstInstallBaselineDecision @arguments) `
        'REFUSE_UNSAFE_TMA2027_CUSTOM' `
        "The first-install policy preserved the unsafe TMA2027 $($variation.Name) variation."
}

$wrongPanelDecision = @{} + $exactTmaFirstInstallArguments
$wrongPanelDecision.PanelKey = $claw8
Assert-Equal `
    (Get-ClawLabFirstInstallBaselineDecision @wrongPanelDecision) `
    'STANDARD_NORMALIZATION_REQUIRED' `
    'The exact TMA2027 exception leaked onto another panel.'

$wrongProfileDecision = @{} + $exactTmaFirstInstallArguments
$wrongProfileDecision.ProfileId = 6
Assert-Equal `
    (Get-ClawLabFirstInstallBaselineDecision @wrongProfileDecision) `
    'STANDARD_NORMALIZATION_REQUIRED' `
    'A non-CUSTOM A1M profile was incorrectly preserved by the exact fallback.'

$managedRepairDecision = @{} + $exactTmaFirstInstallArguments
$managedRepairDecision.CurrentMode = 'CLAWLAB_30_120'
$managedRepairDecision.CurrentState = 'CONSISTENT'
Assert-Equal `
    (Get-ClawLabFirstInstallBaselineDecision @managedRepairDecision) `
    'MANAGED_REPAIR' `
    'A managed repair was incorrectly routed through the first-install fallback.'

$exactTmaManagedArguments = @{
    Policy = 'TMA2027_PRESERVE_EXACT_CUSTOM_30_120'
    PanelKey = $tmaPanel
    Mode = 'CLAWLAB_30_120'
    TelemetryState = 'INTEL_CONTROL_LIB_HALF_PHYSICAL_FLOOR'
    ProfileId = 7
    MinimumHz = 30
    MaximumHz = 120
    MaxIncreaseUs = 8333
    MaxDecreaseUs = 8333
    ExpectedMinimumHz = 30
    ExpectedMaximumHz = 120
}
Assert-Equal `
    (Test-ClawLabManagedArcSyncSnapshot @exactTmaManagedArguments) `
    $true 'The exact managed TMA2027 CUSTOM 30-120 snapshot was rejected.'

$halfManagedTmaArguments = @{} + $exactTmaManagedArguments
$halfManagedTmaArguments.TelemetryState = 'INTEL_CONTROL_LIB_HALF_MANAGED_FLOOR'
Assert-Equal `
    (Test-ClawLabManagedArcSyncSnapshot @halfManagedTmaArguments) `
    $true 'The exact managed TMA2027 CUSTOM snapshot rejected its half-managed-floor telemetry.'

$managedTmaVariations = @(
    @{ Name = 'wrong policy'; Changes = @{ Policy = 'UNKNOWN_POLICY' } },
    @{ Name = 'wrong panel'; Changes = @{ PanelKey = $claw8 } },
    @{ Name = 'wrong mode'; Changes = @{ Mode = 'OFFICIAL_48_120' } },
    @{ Name = 'wrong telemetry'; Changes = @{ TelemetryState = 'DECLARED_KNOWN_RANGE' } },
    @{ Name = 'wrong profile'; Changes = @{ ProfileId = 2 } },
    @{ Name = '24 Hz profile floor'; Changes = @{ MinimumHz = 24 } },
    @{ Name = 'wrong maximum'; Changes = @{ MaximumHz = 119 } },
    @{ Name = 'wrong increase timing'; Changes = @{ MaxIncreaseUs = 8332 } },
    @{ Name = 'wrong decrease timing'; Changes = @{ MaxDecreaseUs = 8334 } },
    @{ Name = 'wrong expected floor'; Changes = @{ ExpectedMinimumHz = 48 } },
    @{ Name = 'wrong expected ceiling'; Changes = @{ ExpectedMaximumHz = 144 } }
)
foreach ($variation in $managedTmaVariations) {
    $arguments = @{} + $exactTmaManagedArguments
    foreach ($key in $variation.Changes.Keys) {
        $arguments[$key] = $variation.Changes[$key]
    }
    Assert-Equal `
        (Test-ClawLabManagedArcSyncSnapshot @arguments) `
        $false "The managed TMA2027 policy accepted the $($variation.Name) variation."
}

$excellentManagedArguments = @{
    Policy = 'INTEL_EXCELLENT_REQUIRED'
    PanelKey = $claw8
    Mode = 'CLAWLAB_30_120'
    TelemetryState = 'DECLARED_KNOWN_RANGE'
    ProfileId = 2
    MinimumHz = 30
    MaximumHz = 120
    MaxIncreaseUs = 0
    MaxDecreaseUs = 0
    ExpectedMinimumHz = 30
    ExpectedMaximumHz = 120
}
Assert-Equal `
    (Test-ClawLabManagedArcSyncSnapshot @excellentManagedArguments) `
    $true 'The exact managed Intel EXCELLENT snapshot was rejected.'
foreach ($variation in @(
    @{ Name = 'wrong profile'; Changes = @{ ProfileId = 1 } },
    @{ Name = 'wrong floor'; Changes = @{ MinimumHz = 48 } },
    @{ Name = 'wrong ceiling'; Changes = @{ MaximumHz = 144 } },
    @{ Name = 'unsupported telemetry'; Changes = @{ TelemetryState = 'UNSUPPORTED' } }
)) {
    $arguments = @{} + $excellentManagedArguments
    foreach ($key in $variation.Changes.Keys) {
        $arguments[$key] = $variation.Changes[$key]
    }
    Assert-Equal `
        (Test-ClawLabManagedArcSyncSnapshot @arguments) `
        $false "The managed Intel EXCELLENT policy accepted the $($variation.Name) variation."
}

Assert-Equal `
    (Test-ClawLabSnapshotMatchesSavedProfile `
        -CurrentProfileId 7 -CurrentMinimumHz 30 -CurrentMaximumHz 120 `
        -CurrentMaxIncreaseUs 8333 -CurrentMaxDecreaseUs 8333 `
        -SavedProfileId 7 -SavedMinimumHz 30 -SavedMaximumHz 120 `
        -SavedMaxIncreaseUs 8333 -SavedMaxDecreaseUs 8333) `
    $true 'The collected A1M already-restored CUSTOM 30-120 profile was not recognized.'
Assert-Equal `
    (Test-ClawLabSnapshotMatchesSavedProfile `
        -CurrentProfileId 7 -CurrentMinimumHz 30 -CurrentMaximumHz 120 `
        -CurrentMaxIncreaseUs 8333 -CurrentMaxDecreaseUs 8333 `
        -SavedProfileId 7 -SavedMinimumHz 30 -SavedMaximumHz 120 `
        -SavedMaxIncreaseUs 10000 -SavedMaxDecreaseUs 8333) `
    $false 'A CUSTOM profile with different transition timing was treated as restored.'
Assert-Equal `
    (Test-ClawLabSnapshotMatchesSavedProfile `
        -CurrentProfileId 1 -CurrentMinimumHz 60 -CurrentMaximumHz 120 `
        -CurrentMaxIncreaseUs 0 -CurrentMaxDecreaseUs 0 `
        -SavedProfileId 1 -SavedMinimumHz 60 -SavedMaximumHz 120 `
        -SavedMaxIncreaseUs 0 -SavedMaxDecreaseUs 0) `
    $true 'An identical non-custom profile was not recognized.'

Assert-Equal `
    (Test-ClawLabCleanNotInstalledState `
        -ManagedMode 'NONE' -ProfileSwitchGuard 'CLEAN' `
        -OriginalProfileSaved $false -EdidOverride 'NONE' `
        -StartupReapply 'NOT_INSTALLED' -CursorRefreshHelper 'NOT_INSTALLED' `
        -VrrTaskInstalled $false -LfcManagedMode 'UNMANAGED' `
        -LfcBackupPresent $false -LfcStartupPersistence 'NOT_INSTALLED' `
        -LfcFixActive $false -LowFpsSolutionEnabled $true `
        -HighFpsSolutionEnabled $true -LfcTaskInstalled $false) `
    $true 'The collected A1M clean-uninstalled state was reported as unhealthy.'
Assert-Equal `
    (Test-ClawLabCleanNotInstalledState `
        -ManagedMode 'NONE' -ProfileSwitchGuard 'CLEAN' `
        -OriginalProfileSaved $false -EdidOverride 'NONE' `
        -StartupReapply 'NOT_INSTALLED' -CursorRefreshHelper 'NOT_INSTALLED' `
        -VrrTaskInstalled $false -LfcManagedMode 'UNMANAGED' `
        -LfcBackupPresent $false -LfcStartupPersistence 'NOT_INSTALLED' `
        -LfcFixActive $false -LowFpsSolutionEnabled $false `
        -HighFpsSolutionEnabled $true -LfcTaskInstalled $false) `
    $false 'A modified Intel LFC flag was accepted as a clean uninstall.'

$cleanHealthArguments = @{
    ManagedMode = 'NONE'; ProfileSwitchGuard = 'CLEAN'
    OriginalProfileSaved = $false; EdidOverride = 'NONE'
    StartupReapply = 'NOT_INSTALLED'; CursorRefreshHelper = 'NOT_INSTALLED'
    VrrTaskInstalled = $false; LfcManagedMode = 'UNMANAGED'
    LfcBackupPresent = $false; LfcStartupPersistence = 'NOT_INSTALLED'
    LfcFixActive = $false; LowFpsSolutionEnabled = $true
    HighFpsSolutionEnabled = $true; LfcTaskInstalled = $false
}
Assert-Equal (Test-ClawLabCleanNotInstalledState @cleanHealthArguments `
        -LfcTransitionState INTEL_VRR_SOLUTIONS_FACTORY_DEFAULTS_FINALIZED `
        -LfcFactoryFinalizedPresent $true -LfcFactoryFinalizedVerified $true) `
    $true 'Verified terminal factory-default provenance was not healthy after uninstall.'
Assert-Equal (Test-ClawLabCleanNotInstalledState @cleanHealthArguments `
        -LfcTransitionState INTEL_VRR_SOLUTIONS_FACTORY_DEFAULTS_PENDING_RESUME `
        -LfcFactoryIntentPresent $true) `
    $false 'A pending LFC factory-default intent was reported as clean.'
Assert-Equal (Test-ClawLabCleanNotInstalledState @cleanHealthArguments `
        -VrrRecoveryRequired $true) `
    $false 'A pending VRR normalization/recovery state was reported as clean.'

[pscustomobject]@{
    Result = 'PASS'
    StableProfiles = '30-120, 48-120'
    GuardedExperimentalProfiles = '30/48 x 144/165/180/192'
    Tma2027TelemetryPolicy = 'HALF_PHYSICAL_FLOOR + MANAGED_30_HALF_FLOOR'
    TelemetryFloorInstallable = $false
    Claw8RegressionGuard = 'PASS'
    PendingEdidGuard = 'PASS'
    ProfileSwitchMatrix = 'PASS'
    FirstInstallCustomProfileGuard = 'PASS'
    Tma2027ExactFallbackSignature = 'PASS'
    Tma2027Install30Only = 'PASS'
    ManagedArcSyncPolicies = 'PASS'
    Tma2027FactoryResetPolicy = 'PASS'
    Tma2027RestoreNoWritePolicy = 'PASS'
    ExactUnmanagedFactoryProfiles = 'PASS'
    OrphanedDefaultShellRecoveryEvidence = 'PASS'
    IdempotentOriginalRestore = 'PASS'
    CleanUninstalledHealthState = 'PASS'
}
