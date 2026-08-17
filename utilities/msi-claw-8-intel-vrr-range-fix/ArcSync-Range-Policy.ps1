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
        [float]$PhysicalMinimumHz = 48.0,
        [float]$CustomMinimumHz = 30.0,
        [float]$SupportedMaximumHz = 120.0,
        [float]$LegacyRecoveryMaximumHz = 144.0,
        [float[]]$ExperimentalMaximumHz = @(144.0, 165.0, 180.0)
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
        [float[]]$ExperimentalMaximumHz = @(144.0, 165.0, 180.0)
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
        -PhysicalMinimumHz $PhysicalMinimumHz -CustomMinimumHz $CustomMinimumHz `
        -SupportedMaximumHz $SupportedMaximumHz -LegacyRecoveryMaximumHz $LegacyRecoveryMaximumHz `
        -ExperimentalMaximumHz $ExperimentalMaximumHz
    if ($state -eq 'INTEL_CONTROL_LIB_HALF_PHYSICAL_FLOOR') {
        return $expectedMaximumKnown
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
        [int[]]$ExperimentalMaximumHz = @(144, 165, 180)
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

function Test-ClawLabFirstInstallProfileSafe {
    param(
        [Parameter(Mandatory)][string]$CurrentMode,
        [Parameter(Mandatory)][string]$CurrentState,
        [Parameter(Mandatory)][int]$ProfileId
    )

    # A first installation must not adopt an unmanaged CUSTOM profile as its
    # restorable baseline. The main installer uses this false result to
    # normalize the clean, unowned state to Intel RECOMMENDED and verifies it
    # before saving anything. Existing, consistent ClawLab profiles are handled
    # by the normal idempotent path.
    if ($CurrentMode -eq 'NONE' -and $CurrentState -eq 'CLEAN') {
        return $ProfileId -in @(1, 2)
    }
    return $true
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
        [Parameter(Mandatory)][bool]$LfcTaskInstalled
    )

    return (
        $ManagedMode -eq 'NONE' -and
        $ProfileSwitchGuard -eq 'CLEAN' -and
        -not $OriginalProfileSaved -and
        $EdidOverride -eq 'NONE' -and
        $StartupReapply -eq 'NOT_INSTALLED' -and
        $CursorRefreshHelper -eq 'NOT_INSTALLED' -and
        -not $VrrTaskInstalled -and
        $LfcManagedMode -eq 'UNMANAGED' -and
        -not $LfcBackupPresent -and
        $LfcStartupPersistence -eq 'NOT_INSTALLED' -and
        -not $LfcFixActive -and
        $LowFpsSolutionEnabled -and
        $HighFpsSolutionEnabled -and
        -not $LfcTaskInstalled
    )
}
