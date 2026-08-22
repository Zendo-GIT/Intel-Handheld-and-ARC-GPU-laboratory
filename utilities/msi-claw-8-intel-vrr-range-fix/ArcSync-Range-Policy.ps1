Set-StrictMode -Version Latest

function Test-ClawLabFrequencyEqual {
    param(
        [Parameter(Mandatory)][float]$Left,
        [Parameter(Mandatory)][float]$Right
    )

    return [Math]::Abs($Left - $Right) -le 0.1
}

function Get-ClawLabArcSyncMonitorRangeState {
    param(
        [Parameter(Mandatory)][string]$PanelKey,
        [Parameter(Mandatory)][float]$MonitorMinimumHz,
        [Parameter(Mandatory)][float]$MonitorMaximumHz,
        [float]$ExpectedMinimumHz = -1.0,
        [float]$ExpectedMaximumHz = -1.0,
        [float]$PhysicalMinimumHz = 48.0,
        [float]$CustomMinimumHz = 30.0,
        [float]$SupportedMaximumHz = 120.0,
        [float]$LegacyRecoveryMaximumHz = 144.0,
        [float[]]$ExperimentalMaximumHz = @(144.0, 165.0, 180.0, 192.0)
    )

    $knownMinimum =
        (Test-ClawLabFrequencyEqual -Left $MonitorMinimumHz -Right $PhysicalMinimumHz) -or
        (Test-ClawLabFrequencyEqual -Left $MonitorMinimumHz -Right $CustomMinimumHz)
    $knownMaximum = Test-ClawLabFrequencyEqual -Left $MonitorMaximumHz -Right $SupportedMaximumHz
    foreach ($candidateMaximum in @($LegacyRecoveryMaximumHz) + @($ExperimentalMaximumHz)) {
        if (Test-ClawLabFrequencyEqual -Left $MonitorMaximumHz -Right $candidateMaximum) {
            $knownMaximum = $true
            break
        }
    }

    if ($knownMinimum -and $knownMaximum) {
        return 'DECLARED_KNOWN_RANGE'
    }

    # On the exact TMA2027 panel used by the Claw A1M and Claw 7 AI+, Intel
    # ControlLib reports a fixed half-physical monitor floor. The EDID remains
    # the pinned physical 48-120 Hz panel data and ctlGetIntelArcSyncProfile
    # independently reports the selected managed profile. This state is
    # telemetry only: 24 Hz is never exposed as an installable profile.
    $halfPhysicalFloor = $PhysicalMinimumHz / 2.0
    if ($PanelKey -eq 'CLAW_A1M_CLAW_7_AI_PLUS' -and
        (Test-ClawLabFrequencyEqual -Left $MonitorMinimumHz -Right $halfPhysicalFloor) -and
        (Test-ClawLabFrequencyEqual -Left $MonitorMaximumHz -Right $SupportedMaximumHz)) {
        return 'INTEL_CONTROL_LIB_HALF_PHYSICAL_FLOOR'
    }

    # Some TMA2027 systems halve the floor of an already loaded 30 Hz ClawLab
    # profile in the monitor-capability query as well. This second anomaly is
    # accepted only when the caller supplies the exact expected managed range.
    # The independently queried active profile must still be verified by the
    # caller, so the telemetry value can never become an installable floor.
    $expectedMinimumIsCustom = Test-ClawLabFrequencyEqual `
        -Left $ExpectedMinimumHz -Right $CustomMinimumHz
    $expectedMaximumKnown = Test-ClawLabFrequencyEqual `
        -Left $ExpectedMaximumHz -Right $SupportedMaximumHz
    foreach ($candidateMaximum in @($LegacyRecoveryMaximumHz) + @($ExperimentalMaximumHz)) {
        if (Test-ClawLabFrequencyEqual -Left $ExpectedMaximumHz -Right $candidateMaximum) {
            $expectedMaximumKnown = $true
            break
        }
    }
    $monitorMaximumMatchesManagedOrPhysical =
        (Test-ClawLabFrequencyEqual -Left $MonitorMaximumHz -Right $ExpectedMaximumHz) -or
        (Test-ClawLabFrequencyEqual -Left $MonitorMaximumHz -Right $SupportedMaximumHz)
    $halfManagedFloor = $CustomMinimumHz / 2.0
    if ($PanelKey -eq 'CLAW_A1M_CLAW_7_AI_PLUS' -and
        $expectedMinimumIsCustom -and $expectedMaximumKnown -and
        $monitorMaximumMatchesManagedOrPhysical -and
        (Test-ClawLabFrequencyEqual -Left $MonitorMinimumHz -Right $halfManagedFloor)) {
        return 'INTEL_CONTROL_LIB_HALF_MANAGED_FLOOR'
    }

    return 'UNSUPPORTED'
}

function Test-ClawLabArcSyncMonitorRangeCompatible {
    param(
        [Parameter(Mandatory)][string]$PanelKey,
        [Parameter(Mandatory)][float]$MonitorMinimumHz,
        [Parameter(Mandatory)][float]$MonitorMaximumHz,
        [Parameter(Mandatory)][float]$ExpectedMinimumHz,
        [Parameter(Mandatory)][float]$ExpectedMaximumHz,
        [float]$PhysicalMinimumHz = 48.0,
        [float]$CustomMinimumHz = 30.0,
        [float]$SupportedMaximumHz = 120.0,
        [float]$LegacyRecoveryMaximumHz = 144.0,
        [float[]]$ExperimentalMaximumHz = @(144.0, 165.0, 180.0, 192.0)
    )

    $expectedMinimumKnown =
        (Test-ClawLabFrequencyEqual -Left $ExpectedMinimumHz -Right $PhysicalMinimumHz) -or
        (Test-ClawLabFrequencyEqual -Left $ExpectedMinimumHz -Right $CustomMinimumHz)
    $expectedMaximumKnown = Test-ClawLabFrequencyEqual -Left $ExpectedMaximumHz -Right $SupportedMaximumHz
    foreach ($candidateMaximum in @($LegacyRecoveryMaximumHz) + @($ExperimentalMaximumHz)) {
        if (Test-ClawLabFrequencyEqual -Left $ExpectedMaximumHz -Right $candidateMaximum) {
            $expectedMaximumKnown = $true
            break
        }
    }
    if (-not $expectedMinimumKnown -or -not $expectedMaximumKnown) {
        return $false
    }

    $state = Get-ClawLabArcSyncMonitorRangeState -PanelKey $PanelKey `
        -MonitorMinimumHz $MonitorMinimumHz -MonitorMaximumHz $MonitorMaximumHz `
        -ExpectedMinimumHz $ExpectedMinimumHz -ExpectedMaximumHz $ExpectedMaximumHz `
        -PhysicalMinimumHz $PhysicalMinimumHz -CustomMinimumHz $CustomMinimumHz `
        -SupportedMaximumHz $SupportedMaximumHz -LegacyRecoveryMaximumHz $LegacyRecoveryMaximumHz `
        -ExperimentalMaximumHz $ExperimentalMaximumHz
    if ($state -eq 'INTEL_CONTROL_LIB_HALF_PHYSICAL_FLOOR') {
        return $expectedMaximumKnown
    }
    if ($state -eq 'INTEL_CONTROL_LIB_HALF_MANAGED_FLOOR') {
        return $true
    }
    if ($state -ne 'DECLARED_KNOWN_RANGE') {
        return $false
    }

    return (
        (Test-ClawLabFrequencyEqual -Left $MonitorMinimumHz -Right $ExpectedMinimumHz) -and
        (Test-ClawLabFrequencyEqual -Left $MonitorMaximumHz -Right $ExpectedMaximumHz)
    )
}

function Test-ClawLabDirectRangeReady {
    param(
        [Parameter(Mandatory)][string]$PanelKey,
        [Parameter(Mandatory)][int]$DirectMinimumHz,
        [Parameter(Mandatory)][int]$DirectMaximumHz,
        [Parameter(Mandatory)][int]$ExpectedMinimumHz,
        [Parameter(Mandatory)][int]$ExpectedMaximumHz,
        [Parameter(Mandatory)][string]$ReportedEdidSha256,
        [Parameter(Mandatory)][string]$ExpectedEdidSha256,
        [int]$PhysicalMinimumHz = 48,
        [int]$CustomMinimumHz = 30,
        [int]$SupportedMaximumHz = 120,
        [int[]]$ExperimentalMaximumHz = @(144, 165, 180, 192)
    )

    if ($ReportedEdidSha256 -ne $ExpectedEdidSha256 -or
        $ExpectedMinimumHz -notin @($PhysicalMinimumHz, $CustomMinimumHz) -or
        $ExpectedMaximumHz -notin (@($SupportedMaximumHz) + @($ExperimentalMaximumHz))) {
        return $false
    }
    if ($DirectMinimumHz -eq $ExpectedMinimumHz -and $DirectMaximumHz -eq $ExpectedMaximumHz) {
        return $true
    }

    # The direct Intel escape continues to expose the physical EDID floor on
    # TMA2027 while ControlLib exposes the selected active profile separately.
    # Exact EDID matching above prevents a pending or foreign override from
    # being mistaken for a ready managed profile.
    return $PanelKey -eq 'CLAW_A1M_CLAW_7_AI_PLUS' -and
        $DirectMinimumHz -eq $PhysicalMinimumHz -and
        $DirectMaximumHz -eq $SupportedMaximumHz
}

function Test-ClawLabProfileTransitionAllowed {
    param(
        [Parameter(Mandatory)][string]$CurrentMode,
        [Parameter(Mandatory)][string]$CurrentState,
        [Parameter(Mandatory)][string]$DesiredMode
    )

    if ($CurrentMode -eq 'NONE' -and $CurrentState -eq 'CLEAN') {
        return $true
    }

    # Reapplying the exact same fully installed profile is idempotent. Every
    # other transition, including stable-to-experimental and experimental-to-
    # experimental, must pass through the verified original-profile restore.
    return $CurrentMode -eq $DesiredMode -and
        $CurrentState -in @('CONSISTENT', 'LEGACY_MATCHING_OVERRIDE')
}

function Get-ClawLabStableProfileRepairDisposition {
    param(
        [Parameter(Mandatory)][string]$CurrentMode,
        [Parameter(Mandatory)][string]$CurrentState,
        [Parameter(Mandatory)][string]$DesiredMode,
        [Parameter(Mandatory)][string]$CurrentOverrideState,
        [Parameter(Mandatory)][bool]$ManagedIdentityVerified,
        [Parameter(Mandatory)][bool]$VrrOriginalBackupVerified,
        [Parameter(Mandatory)][bool]$LfcOriginalBackupVerified,
        [Parameter(Mandatory)][bool]$TrialArtifactsAbsent,
        [Parameter(Mandatory)][bool]$RecoveryClear
    )

    # Repair is deliberately distinct from the normal transition guard above.
    # The core guard remains strict unless its caller supplies every independent
    # proof required by the transaction coordinator. This prevents a missing
    # task or payload from forcing users through Restore while still refusing
    # cross-profile switches, experimental modes and incomplete recovery.
    $expectedOverride = switch ($DesiredMode) {
        'CLAWLAB_30_120' { 'CLAWLAB_30_120' }
        'OFFICIAL_48_120' { 'NONE' }
        default { $null }
    }
    if ([string]::IsNullOrWhiteSpace($expectedOverride)) {
        return 'RESTORE_REQUIRED'
    }

    $repairableState = $CurrentState -in @('CONSISTENT', 'INCONSISTENT_RESTORE_REQUIRED')
    if ($CurrentMode -eq $DesiredMode -and
        $repairableState -and
        $CurrentOverrideState -eq $expectedOverride -and
        $ManagedIdentityVerified -and
        $VrrOriginalBackupVerified -and
        $LfcOriginalBackupVerified -and
        $TrialArtifactsAbsent -and
        $RecoveryClear) {
        return 'REPAIRABLE_SAME_MODE'
    }

    return 'RESTORE_REQUIRED'
}

function Test-ClawLabFirstInstallProfileSafe {
    param(
        [Parameter(Mandatory)][string]$CurrentMode,
        [Parameter(Mandatory)][string]$CurrentState,
        [Parameter(Mandatory)][int]$ProfileId
    )

    # A first installation must not adopt an unmanaged CUSTOM profile as its
    # restorable baseline. The main installer uses this false result to
    # try Intel RECOMMENDED, fall back to EXCELLENT if the driver silently
    # retains CUSTOM, and verify the chosen standard profile before saving
    # anything. Existing, consistent ClawLab profiles use the idempotent path.
    if ($CurrentMode -eq 'NONE' -and $CurrentState -eq 'CLEAN') {
        return $ProfileId -in @(1, 2)
    }
    return $true
}

function Test-ClawLabKnownTma2027Custom30Profile {
    param(
        [Parameter(Mandatory)][string]$PanelKey,
        [Parameter(Mandatory)][string]$TelemetryState,
        [Parameter(Mandatory)][int]$ProfileId,
        [Parameter(Mandatory)][float]$MinimumHz,
        [Parameter(Mandatory)][float]$MaximumHz,
        [Parameter(Mandatory)][uint32]$MaxIncreaseUs,
        [Parameter(Mandatory)][uint32]$MaxDecreaseUs
    )

    return (
        $TelemetryState -eq 'INTEL_CONTROL_LIB_HALF_PHYSICAL_FLOOR' -and
        (Test-ClawLabExactTma2027Custom30ProfileValues `
            -PanelKey $PanelKey -ProfileId $ProfileId `
            -MinimumHz $MinimumHz -MaximumHz $MaximumHz `
            -MaxIncreaseUs $MaxIncreaseUs -MaxDecreaseUs $MaxDecreaseUs)
    )
}

function Test-ClawLabExactTma2027Custom30ProfileValues {
    param(
        [Parameter(Mandatory)][string]$PanelKey,
        [Parameter(Mandatory)][int]$ProfileId,
        [Parameter(Mandatory)][float]$MinimumHz,
        [Parameter(Mandatory)][float]$MaximumHz,
        [Parameter(Mandatory)][uint32]$MaxIncreaseUs,
        [Parameter(Mandatory)][uint32]$MaxDecreaseUs
    )

    return (
        $PanelKey -eq 'CLAW_A1M_CLAW_7_AI_PLUS' -and
        $ProfileId -eq 7 -and
        (Test-ClawLabFrequencyEqual -Left $MinimumHz -Right 30.0) -and
        (Test-ClawLabFrequencyEqual -Left $MaximumHz -Right 120.0) -and
        $MaxIncreaseUs -eq 8333 -and
        $MaxDecreaseUs -eq 8333
    )
}

function Get-ClawLabFirstInstallBaselineDecision {
    param(
        [Parameter(Mandatory)][string]$PanelKey,
        [Parameter(Mandatory)][string]$CurrentMode,
        [Parameter(Mandatory)][string]$CurrentState,
        [Parameter(Mandatory)][string]$OverrideState,
        [Parameter(Mandatory)][string]$DesiredMode,
        [Parameter(Mandatory)][string]$TelemetryState,
        [Parameter(Mandatory)][int]$ProfileId,
        [Parameter(Mandatory)][float]$MinimumHz,
        [Parameter(Mandatory)][float]$MaximumHz,
        [Parameter(Mandatory)][uint32]$MaxIncreaseUs,
        [Parameter(Mandatory)][uint32]$MaxDecreaseUs
    )

    if ($CurrentMode -ne 'NONE' -or $CurrentState -ne 'CLEAN') {
        return 'MANAGED_REPAIR'
    }
    if ($ProfileId -in @(1, 2)) {
        return 'STANDARD_PROFILE'
    }

    $knownTmaCustom = Test-ClawLabKnownTma2027Custom30Profile `
        -PanelKey $PanelKey -TelemetryState $TelemetryState `
        -ProfileId $ProfileId -MinimumHz $MinimumHz -MaximumHz $MaximumHz `
        -MaxIncreaseUs $MaxIncreaseUs -MaxDecreaseUs $MaxDecreaseUs
    if ($knownTmaCustom) {
        if ($OverrideState -eq 'NONE' -and $DesiredMode -eq 'CLAWLAB_30_120') {
            return 'TMA2027_PRESERVE_EXACT_CUSTOM_30_120'
        }
        return 'REFUSE_TMA2027_CUSTOM_FOR_MODE'
    }
    if ($PanelKey -eq 'CLAW_A1M_CLAW_7_AI_PLUS' -and $ProfileId -eq 7) {
        return 'REFUSE_UNSAFE_TMA2027_CUSTOM'
    }
    return 'STANDARD_NORMALIZATION_REQUIRED'
}

function Test-ClawLabManagedArcSyncSnapshot {
    param(
        [Parameter(Mandatory)][string]$Policy,
        [Parameter(Mandatory)][string]$PanelKey,
        [Parameter(Mandatory)][string]$Mode,
        [Parameter(Mandatory)][string]$TelemetryState,
        [Parameter(Mandatory)][int]$ProfileId,
        [Parameter(Mandatory)][float]$MinimumHz,
        [Parameter(Mandatory)][float]$MaximumHz,
        [Parameter(Mandatory)][uint32]$MaxIncreaseUs,
        [Parameter(Mandatory)][uint32]$MaxDecreaseUs,
        [Parameter(Mandatory)][float]$ExpectedMinimumHz,
        [Parameter(Mandatory)][float]$ExpectedMaximumHz
    )

    if ($TelemetryState -notin @(
            'DECLARED_KNOWN_RANGE',
            'INTEL_CONTROL_LIB_HALF_PHYSICAL_FLOOR',
            'INTEL_CONTROL_LIB_HALF_MANAGED_FLOOR'
        )) {
        return $false
    }

    if ($Policy -eq 'INTEL_EXCELLENT_REQUIRED') {
        return (
            $ProfileId -eq 2 -and
            (Test-ClawLabFrequencyEqual -Left $MinimumHz -Right $ExpectedMinimumHz) -and
            (Test-ClawLabFrequencyEqual -Left $MaximumHz -Right $ExpectedMaximumHz)
        )
    }
    if ($Policy -eq 'TMA2027_PRESERVE_EXACT_CUSTOM_30_120') {
        return (
            $TelemetryState -in @(
                'INTEL_CONTROL_LIB_HALF_PHYSICAL_FLOOR',
                'INTEL_CONTROL_LIB_HALF_MANAGED_FLOOR'
            ) -and
            $PanelKey -eq 'CLAW_A1M_CLAW_7_AI_PLUS' -and
            $Mode -eq 'CLAWLAB_30_120' -and
            (Test-ClawLabFrequencyEqual -Left $ExpectedMinimumHz -Right 30.0) -and
            (Test-ClawLabFrequencyEqual -Left $ExpectedMaximumHz -Right 120.0) -and
            (Test-ClawLabExactTma2027Custom30ProfileValues `
                -PanelKey $PanelKey `
                -ProfileId $ProfileId -MinimumHz $MinimumHz -MaximumHz $MaximumHz `
                -MaxIncreaseUs $MaxIncreaseUs -MaxDecreaseUs $MaxDecreaseUs)
        )
    }
    return $false
}

function Get-ClawLabFactoryResetProfileDecision {
    param(
        [Parameter(Mandatory)][string]$PanelKey,
        [Parameter(Mandatory)][string]$TelemetryState,
        [Parameter(Mandatory)][int]$ProfileId,
        [Parameter(Mandatory)][float]$MinimumHz,
        [Parameter(Mandatory)][float]$MaximumHz,
        [Parameter(Mandatory)][uint32]$MaxIncreaseUs,
        [Parameter(Mandatory)][uint32]$MaxDecreaseUs
    )

    # The collected TMA2027 OEM state is already the only profile that these
    # drivers accept reliably. Factory reset must therefore preserve that exact
    # signature instead of calling the rejected RECOMMENDED setter. A near
    # match is never adopted: fail closed and collect diagnostics instead.
    if (Test-ClawLabKnownTma2027Custom30Profile `
            -PanelKey $PanelKey -TelemetryState $TelemetryState `
            -ProfileId $ProfileId -MinimumHz $MinimumHz -MaximumHz $MaximumHz `
            -MaxIncreaseUs $MaxIncreaseUs -MaxDecreaseUs $MaxDecreaseUs) {
        return 'PRESERVE_TMA2027_OEM_CUSTOM_30_120'
    }
    if ($PanelKey -eq 'CLAW_A1M_CLAW_7_AI_PLUS' -and $ProfileId -eq 7) {
        return 'REFUSE_UNSAFE_TMA2027_CUSTOM'
    }
    return 'SET_INTEL_RECOMMENDED'
}

function Test-ClawLabKnownUnmanagedFactoryProfile {
    param(
        [Parameter(Mandatory)][string]$PanelKey,
        [Parameter(Mandatory)][string]$TelemetryState,
        [Parameter(Mandatory)][int]$ProfileId,
        [Parameter(Mandatory)][float]$MinimumHz,
        [Parameter(Mandatory)][float]$MaximumHz,
        [Parameter(Mandatory)][uint32]$MaxIncreaseUs,
        [Parameter(Mandatory)][uint32]$MaxDecreaseUs
    )

    # The Claw 8 AI+ / 8 EX AI+ Intel factory profile is RECOMMENDED with the
    # driver-constrained 60-120 Hz range. The exact 8,333 us frame-time values
    # are part of the proof: a merely similar CUSTOM state must never be adopted
    # as an original profile when its backup is absent.
    if ($PanelKey -eq 'CLAW_8_AI_PLUS') {
        return (
            $TelemetryState -eq 'DECLARED_KNOWN_RANGE' -and
            $ProfileId -eq 1 -and
            (Test-ClawLabFrequencyEqual -Left $MinimumHz -Right 60.0) -and
            (Test-ClawLabFrequencyEqual -Left $MaximumHz -Right 120.0) -and
            $MaxIncreaseUs -eq 8333 -and
            $MaxDecreaseUs -eq 8333
        )
    }

    # A1M / Claw 7 AI+ drivers can expose only the collected OEM CUSTOM
    # 30-120 profile. Reuse the same pinned signature as factory reset; no
    # RECOMMENDED or EXCELLENT setter is inferred from telemetry alone.
    return Test-ClawLabKnownTma2027Custom30Profile `
        -PanelKey $PanelKey -TelemetryState $TelemetryState `
        -ProfileId $ProfileId -MinimumHz $MinimumHz -MaximumHz $MaximumHz `
        -MaxIncreaseUs $MaxIncreaseUs -MaxDecreaseUs $MaxDecreaseUs
}

function Test-ClawLabOrphanedDefaultShellEvidence {
    param(
        [Parameter(Mandatory)][object]$Vrr,
        [Parameter(Mandatory)][object]$Lfc,
        [Parameter(Mandatory)][string]$VrrTaskQuery,
        [Parameter(Mandatory)][string]$CursorTaskQuery,
        [Parameter(Mandatory)][string]$LfcTaskQuery,
        [Parameter(Mandatory)][object]$TransactionJournal
    )

    try {
        $panelKey = switch ([string]$Vrr.PanelId) {
            'CSW0801' { 'CLAW_8_AI_PLUS' }
            'TMA2027' { 'CLAW_A1M_CLAW_7_AI_PLUS' }
            default { return $false }
        }
        $profileId = switch ([string]$Vrr.DriverProfile) {
            'RECOMMENDED' { 1 }
            'CUSTOM' { 7 }
            default { return $false }
        }
        $rangeMatch = [regex]::Match(
            [string]$Vrr.DriverActiveRange,
            '^\s*(\d+(?:\.\d+)?)\s*-\s*(\d+(?:\.\d+)?)\s+Hz\s*$')
        if (-not $rangeMatch.Success) { return $false }

        $knownFactoryProfile = Test-ClawLabKnownUnmanagedFactoryProfile `
            -PanelKey $panelKey -TelemetryState ([string]$Vrr.ArcSyncMonitorTelemetry) `
            -ProfileId $profileId `
            -MinimumHz ([float]::Parse($rangeMatch.Groups[1].Value,
                    [Globalization.CultureInfo]::InvariantCulture)) `
            -MaximumHz ([float]::Parse($rangeMatch.Groups[2].Value,
                    [Globalization.CultureInfo]::InvariantCulture)) `
            -MaxIncreaseUs ([uint32]$Vrr.DriverProfileMaxIncreaseUs) `
            -MaxDecreaseUs ([uint32]$Vrr.DriverProfileMaxDecreaseUs)
        if (-not $knownFactoryProfile) { return $false }

        return (
            [string]$TransactionJournal.Action -eq 'Restore' -and
            [string]$TransactionJournal.Phase -eq 'RECOVERY_REQUIRED' -and
            [string]$Vrr.State -eq 'DRIVER_PROFILE_CONSTRAINED' -and
            [string]$Vrr.PhysicalPanelRange -eq '48-120 Hz' -and
            [string]$Vrr.ArcSyncPolicy -eq 'UNMANAGED' -and
            [string]$Vrr.ArcSyncVerification -eq 'NOT_VERIFIED' -and
            [string]$Vrr.ManagedMode -eq 'LEGACY_MANAGED_STATE' -and
            [string]$Vrr.ProfileSwitchGuard -eq 'RESTORE_REQUIRED' -and
            -not [bool]$Vrr.OriginalProfileSaved -and
            [string]$Vrr.StartupReapply -in @('TASK_INVALID', 'TASK_WITHOUT_FILES') -and
            [string]$Vrr.CursorRefreshHelper -eq 'NOT_INSTALLED' -and
            [string]$Vrr.IntelGraphicsStartup -in @('INTEL_DEFAULT', 'MISSING_WITHOUT_BACKUP') -and
            [string]$Vrr.EdidOverride -eq 'NONE' -and
            [string]$Vrr.NormalizationCompensation -eq 'NONE' -and
            -not [bool]$Vrr.RecoveryRequired -and
            -not [bool]$Vrr.RestartRequired -and
            -not [bool]$Vrr.RegistryModified -and
            -not [bool]$Vrr.DriverFilesModified -and
            $VrrTaskQuery -eq 'PRESENT' -and
            $CursorTaskQuery -eq 'ABSENT' -and
            $LfcTaskQuery -eq 'ABSENT' -and
            [string]$Lfc.ManagedVrrMode -eq 'UNMANAGED' -and
            [string]$Lfc.ExpectedRange -eq 'UNMANAGED' -and
            [string]$Lfc.StartupPersistence -eq 'NOT_INSTALLED' -and
            -not [bool]$Lfc.LfcFixActive -and
            [string]$Lfc.ThirdPartyEdidOverrideValues -eq 'NONE' -and
            [string]$Lfc.LfcTransition.State -eq 'INTEL_VRR_SOLUTIONS_NOT_PATCHED' -and
            -not [bool]$Lfc.LfcTransition.BackupPresent -and
            -not [bool]$Lfc.RestoreTombstonePresent -and
            -not [bool]$Lfc.RestoreFinalizedPresent -and
            -not [bool]$Lfc.FactoryIntentPresent -and
            -not [bool]$Lfc.FactoryFinalizedPresent -and
            $null -ne $Lfc.CurrentState -and
            [string]$Lfc.CurrentState.Result -eq 'Success' -and
            [bool]$Lfc.CurrentState.Supported -and
            [bool]$Lfc.CurrentState.VrrEnabled -and
            [int]$Lfc.CurrentState.MinimumHz -eq 48 -and
            [int]$Lfc.CurrentState.MaximumHz -eq 120 -and
            [bool]$Lfc.CurrentState.LowFpsSolutionEnabled -and
            [bool]$Lfc.CurrentState.HighFpsSolutionEnabled
        )
    }
    catch {
        return $false
    }
}

function Get-ClawLabSavedProfileRestoreDecision {
    param(
        [Parameter(Mandatory)][string]$BaselinePolicy,
        [Parameter(Mandatory)][bool]$SnapshotMatches
    )

    # Standard Intel baselines can be written back. The verified TMA2027 OEM
    # CUSTOM baseline is intentionally read-only: restoration either proves
    # that it is still exact or refuses without calling a profile setter.
    switch ($BaselinePolicy) {
        'INTEL_STANDARD_BASELINE' {
            if ($SnapshotMatches) { return 'SKIP_ALREADY_MATCHING' }
            return 'WRITE_SAVED_STANDARD_PROFILE'
        }
        'TMA2027_VERIFIED_CUSTOM_30_120' {
            if ($SnapshotMatches) { return 'PRESERVE_TMA2027_NO_WRITE' }
            return 'REFUSE_TMA2027_DRIFT_NO_WRITE'
        }
        default { return 'REFUSE_UNKNOWN_BASELINE_POLICY' }
    }
}

function Test-ClawLabSnapshotMatchesSavedProfile {
    param(
        [Parameter(Mandatory)][int]$CurrentProfileId,
        [Parameter(Mandatory)][float]$CurrentMinimumHz,
        [Parameter(Mandatory)][float]$CurrentMaximumHz,
        [Parameter(Mandatory)][uint32]$CurrentMaxIncreaseUs,
        [Parameter(Mandatory)][uint32]$CurrentMaxDecreaseUs,
        [Parameter(Mandatory)][int]$SavedProfileId,
        [Parameter(Mandatory)][float]$SavedMinimumHz,
        [Parameter(Mandatory)][float]$SavedMaximumHz,
        [Parameter(Mandatory)][uint32]$SavedMaxIncreaseUs,
        [Parameter(Mandatory)][uint32]$SavedMaxDecreaseUs,
        [int]$CustomProfileId = 7
    )

    if ($CurrentProfileId -ne $SavedProfileId) {
        return $false
    }
    if ($SavedProfileId -ne $CustomProfileId) {
        return $true
    }

    return (
        (Test-ClawLabFrequencyEqual -Left $CurrentMinimumHz -Right $SavedMinimumHz) -and
        (Test-ClawLabFrequencyEqual -Left $CurrentMaximumHz -Right $SavedMaximumHz) -and
        $CurrentMaxIncreaseUs -eq $SavedMaxIncreaseUs -and
        $CurrentMaxDecreaseUs -eq $SavedMaxDecreaseUs
    )
}

function Test-ClawLabCleanNotInstalledState {
    param(
        [Parameter(Mandatory)][string]$ManagedMode,
        [Parameter(Mandatory)][string]$ProfileSwitchGuard,
        [Parameter(Mandatory)][bool]$OriginalProfileSaved,
        [Parameter(Mandatory)][string]$EdidOverride,
        [Parameter(Mandatory)][string]$StartupReapply,
        [Parameter(Mandatory)][string]$CursorRefreshHelper,
        [Parameter(Mandatory)][bool]$VrrTaskInstalled,
        [Parameter(Mandatory)][string]$LfcManagedMode,
        [Parameter(Mandatory)][bool]$LfcBackupPresent,
        [Parameter(Mandatory)][string]$LfcStartupPersistence,
        [Parameter(Mandatory)][bool]$LfcFixActive,
        [Parameter(Mandatory)][bool]$LowFpsSolutionEnabled,
        [Parameter(Mandatory)][bool]$HighFpsSolutionEnabled,
        [Parameter(Mandatory)][bool]$LfcTaskInstalled,
        [bool]$VrrRecoveryRequired = $false,
        [string]$LfcTransitionState = 'INTEL_VRR_SOLUTIONS_NOT_PATCHED',
        [bool]$LfcRestoreFinalizedPresent = $false,
        [bool]$LfcRestoreFinalizedVerified = $false,
        [bool]$LfcFactoryIntentPresent = $false,
        [bool]$LfcFactoryFinalizedPresent = $false,
        [bool]$LfcFactoryFinalizedVerified = $false
    )

    $verifiedOriginalProvenance =
        ($LfcTransitionState -eq 'INTEL_VRR_SOLUTIONS_NOT_PATCHED' -and
            -not $LfcRestoreFinalizedPresent -and
            -not $LfcFactoryFinalizedPresent -and
            $LowFpsSolutionEnabled -and $HighFpsSolutionEnabled) -or
        ($LfcTransitionState -eq 'ORIGINAL_LFC_RESTORE_FINALIZED' -and
            $LfcRestoreFinalizedPresent -and $LfcRestoreFinalizedVerified -and
            -not $LfcFactoryFinalizedPresent) -or
        ($LfcTransitionState -eq 'INTEL_VRR_SOLUTIONS_FACTORY_DEFAULTS_FINALIZED' -and
            -not $LfcRestoreFinalizedPresent -and
            $LfcFactoryFinalizedPresent -and $LfcFactoryFinalizedVerified -and
            $LowFpsSolutionEnabled -and $HighFpsSolutionEnabled)

    return (
        $ManagedMode -eq 'NONE' -and
        $ProfileSwitchGuard -eq 'CLEAN' -and
        -not $OriginalProfileSaved -and
        $EdidOverride -eq 'NONE' -and
        $StartupReapply -eq 'NOT_INSTALLED' -and
        $CursorRefreshHelper -eq 'NOT_INSTALLED' -and
        -not $VrrTaskInstalled -and
        -not $VrrRecoveryRequired -and
        $LfcManagedMode -eq 'UNMANAGED' -and
        -not $LfcBackupPresent -and
        $LfcStartupPersistence -eq 'NOT_INSTALLED' -and
        -not $LfcFixActive -and
        -not $LfcFactoryIntentPresent -and
        $verifiedOriginalProvenance -and
        -not $LfcTaskInstalled
    )
}
