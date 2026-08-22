[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Test {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$root = Split-Path $PSScriptRoot -Parent
$runtimeRoot = if (Test-Path -LiteralPath (Join-Path $root 'scripts\MSI-Claw-VRR-Fix.ps1') -PathType Leaf) {
    Join-Path $root 'scripts'
}
else { $root }
$corePath = Join-Path $runtimeRoot 'MSI-Claw-VRR-Fix.ps1'
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    $corePath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    throw "VRR core parser failure: $($parseErrors[0].Message)"
}

foreach ($functionName in @(
        'Test-NormalizationTargetIdentity',
        'Test-NormalizationProfileExact',
        'Get-NormalizationCompensationRecord',
        'Assert-NormalizationCompensationIdentity',
        'Set-NormalizationCompensationPhase',
        'New-NormalizationCompensationRecord',
        'Remove-NormalizationCompensationRecord',
        'Invoke-NormalizationCompensationRestore',
        'Complete-NormalizationCompensationAfterBackup',
        'Resolve-PendingNormalizationCompensation'
    )) {
    $matches = @($ast.FindAll({
                param($node)
                $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq $functionName
            }, $true))
    if ($matches.Count -ne 1) {
        throw "Expected one core function named ${functionName}; found $($matches.Count)."
    }
    Invoke-Expression $matches[0].Extent.Text
}

function Test-ClawLabFrequencyEqual {
    param([float]$Left, [float]$Right)
    return [Math]::Abs($Left - $Right) -le 0.1
}

function Remove-FileIfPresent {
    param([string]$LiteralPath)
    if (Test-Path -LiteralPath $LiteralPath -PathType Leaf) {
        [IO.File]::Delete($LiteralPath)
    }
}

function Write-ClawLabJsonAtomically {
    param([string]$LiteralPath, [object]$Value)
    $directory = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($LiteralPath))
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $temporary = Join-Path $directory ('.normalization-test-' + [Guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText(
            $temporary, ($Value | ConvertTo-Json -Depth 8),
            [Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $LiteralPath -PathType Leaf) {
            [IO.File]::Delete($LiteralPath)
        }
        [IO.File]::Move($temporary, $LiteralPath)
    }
    finally {
        Remove-FileIfPresent -LiteralPath $temporary
    }
}

function Start-Sleep {
    param([int]$Milliseconds, [int]$Seconds)
}

function Copy-TestSnapshot {
    param([Parameter(Mandatory)][object]$Snapshot)
    return [pscustomobject]@{
        AdapterIndex = [int]$Snapshot.AdapterIndex
        DisplayIndex = [int]$Snapshot.DisplayIndex
        MonitorMinimumHz = [float]$Snapshot.MonitorMinimumHz
        MonitorMaximumHz = [float]$Snapshot.MonitorMaximumHz
        MonitorMaxIncreaseUs = [uint32]$Snapshot.MonitorMaxIncreaseUs
        MonitorMaxDecreaseUs = [uint32]$Snapshot.MonitorMaxDecreaseUs
        ProfileId = [int]$Snapshot.ProfileId
        ProfileName = [string]$Snapshot.ProfileName
        ActiveMinimumHz = [float]$Snapshot.ActiveMinimumHz
        ActiveMaximumHz = [float]$Snapshot.ActiveMaximumHz
        ActiveMaxIncreaseUs = [uint32]$Snapshot.ActiveMaxIncreaseUs
        ActiveMaxDecreaseUs = [uint32]$Snapshot.ActiveMaxDecreaseUs
    }
}

function Set-TestSnapshotProfile {
    param([Parameter(Mandatory)][object]$Profile)
    $next = Copy-TestSnapshot -Snapshot $script:testCurrentSnapshot
    $next.ProfileId = [int]$Profile.ProfileId
    $next.ProfileName = [string]$Profile.ProfileName
    $next.ActiveMinimumHz = [float]$Profile.MinRefreshRateInHz
    $next.ActiveMaximumHz = [float]$Profile.MaxRefreshRateInHz
    $next.ActiveMaxIncreaseUs = [uint32]$Profile.MaxFrameTimeIncreaseInUs
    $next.ActiveMaxDecreaseUs = [uint32]$Profile.MaxFrameTimeDecreaseInUs
    $script:testCurrentSnapshot = $next
}

function Restore-SnapshotProfile {
    param([object]$Target, [object]$Profile)
    $script:restoreCallCount++
    if ($script:restoreShouldFail) { throw 'SIMULATED_SETTER_FAILURE' }
    Set-TestSnapshotProfile -Profile $Profile
}

function Get-TargetSnapshot {
    param([int]$Attempts)
    return Copy-TestSnapshot -Snapshot $script:testCurrentSnapshot
}

function Get-OriginalProfile {
    return $script:testOriginalBackup
}

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'ClawLab-Normalization-Test-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temporaryRoot) | Out-Null
try {
    $fixVersion = '2.3.0'
    $normalizationCompensationPath = Join-Path $temporaryRoot 'normalization-compensation.json'
    $backupPath = Join-Path $temporaryRoot 'original-profile.json'
    $script:normalizationCompensationContext = $null
    $script:restoreShouldFail = $false
    $script:restoreCallCount = 0
    $script:testOriginalBackup = $null

    $panel = [pscustomobject]@{
        Manufacturer = 'CSW'
        ProductCode = '0801'
        Name = 'PN8007QB1-2'
        InstanceName = 'DISPLAY\CSW0801\4&TEST&0&UID1_0'
        Definition = [pscustomobject]@{
            Key = 'CLAW_8_AI_PLUS'
            PhysicalEdidSha256 = 'E49BC570225510B7C889ED292570F1345CAA07F5840DB57EA6998A403DB5CEF0'
        }
    }
    $gpu = [pscustomobject]@{
        Name = 'Intel(R) Arc(TM) 140V GPU'
        PNPDeviceID = 'PCI\VEN_8086&DEV_TEST'
        DriverVersion = '32.0.101.8974'
    }
    $originalSnapshot = [pscustomobject]@{
        AdapterIndex = 0
        DisplayIndex = 0
        MonitorMinimumHz = 48.0
        MonitorMaximumHz = 120.0
        MonitorMaxIncreaseUs = 8333
        MonitorMaxDecreaseUs = 8333
        ProfileId = 7
        ProfileName = 'CUSTOM'
        ActiveMinimumHz = 47.5
        ActiveMaximumHz = 120.0
        ActiveMaxIncreaseUs = 9123
        ActiveMaxDecreaseUs = 8456
    }
    $recommendedSnapshot = Copy-TestSnapshot -Snapshot $originalSnapshot
    $recommendedSnapshot.ProfileId = 1
    $recommendedSnapshot.ProfileName = 'RECOMMENDED'
    $recommendedSnapshot.ActiveMinimumHz = 60
    $recommendedSnapshot.ActiveMaximumHz = 120
    $recommendedSnapshot.ActiveMaxIncreaseUs = 0
    $recommendedSnapshot.ActiveMaxDecreaseUs = 0

    # Power loss immediately after PREPARED: current state is still exact, so
    # recovery removes the WAL without issuing any setter.
    $script:testCurrentSnapshot = Copy-TestSnapshot -Snapshot $originalSnapshot
    [void](New-NormalizationCompensationRecord -Panel $panel -Gpu $gpu `
            -Snapshot $script:testCurrentSnapshot)
    [void](Invoke-NormalizationCompensationRestore -Panel $panel -Gpu $gpu `
            -CurrentTarget $script:testCurrentSnapshot)
    Assert-Test -Condition (-not (Test-Path -LiteralPath $normalizationCompensationPath)) `
        -Message 'PREPARED power-loss recovery retained the WAL after exact no-write verification.'
    Assert-Test -Condition ($script:restoreCallCount -eq 0) `
        -Message 'PREPARED power-loss recovery issued an unnecessary profile setter.'

    # Power loss after a candidate write: restore the exact custom values and
    # remove the WAL only after direct readback matches every saved field.
    $script:testCurrentSnapshot = Copy-TestSnapshot -Snapshot $originalSnapshot
    $record = New-NormalizationCompensationRecord -Panel $panel -Gpu $gpu `
        -Snapshot $script:testCurrentSnapshot
    [void](Set-NormalizationCompensationPhase -Record $record `
        -Phase MUTATION_ATTEMPTED -CandidateName RECOMMENDED)
    $script:testCurrentSnapshot = Copy-TestSnapshot -Snapshot $recommendedSnapshot
    [void](Invoke-NormalizationCompensationRestore -Panel $panel -Gpu $gpu `
            -CurrentTarget $script:testCurrentSnapshot)
    Assert-Test -Condition (Test-NormalizationProfileExact `
            -Snapshot $script:testCurrentSnapshot `
            -SavedProfile ([pscustomobject]@{
                ProfileId = 7; ProfileName = 'CUSTOM'
                MinRefreshRateInHz = 47.5; MaxRefreshRateInHz = 120
                MaxFrameTimeIncreaseInUs = 9123; MaxFrameTimeDecreaseInUs = 8456
            })) -Message 'MUTATION_ATTEMPTED recovery did not restore the exact original snapshot.'
    Assert-Test -Condition (-not (Test-Path -LiteralPath $normalizationCompensationPath)) `
        -Message 'Verified candidate-write recovery did not remove the WAL.'

    # A failed restore is fail-closed: the WAL survives for the next explicit
    # recovery attempt and no clean state can be reported.
    $script:testCurrentSnapshot = Copy-TestSnapshot -Snapshot $originalSnapshot
    $record = New-NormalizationCompensationRecord -Panel $panel -Gpu $gpu `
        -Snapshot $script:testCurrentSnapshot
    [void](Set-NormalizationCompensationPhase -Record $record `
        -Phase MUTATION_ATTEMPTED -CandidateName EXCELLENT)
    $script:testCurrentSnapshot = Copy-TestSnapshot -Snapshot $recommendedSnapshot
    $script:restoreShouldFail = $true
    $failedClosed = $false
    try {
        [void](Invoke-NormalizationCompensationRestore -Panel $panel -Gpu $gpu `
                -CurrentTarget $script:testCurrentSnapshot)
    }
    catch { $failedClosed = $_.Exception.Message -like '*SIMULATED_SETTER_FAILURE*' }
    finally { $script:restoreShouldFail = $false }
    Assert-Test -Condition ($failedClosed -and
        (Test-Path -LiteralPath $normalizationCompensationPath -PathType Leaf)) `
        -Message 'A failed compensation restore did not retain its durable WAL.'
    Remove-FileIfPresent -LiteralPath $normalizationCompensationPath

    # Power loss after original-profile backup creation but before WAL cleanup:
    # the exact validated standard backup commits the normalization and the
    # unknown pre-normalization snapshot is no longer replayed.
    $script:testCurrentSnapshot = Copy-TestSnapshot -Snapshot $originalSnapshot
    $record = New-NormalizationCompensationRecord -Panel $panel -Gpu $gpu `
        -Snapshot $script:testCurrentSnapshot
    $record = Set-NormalizationCompensationPhase -Record $record `
        -Phase MUTATION_ATTEMPTED -CandidateName RECOMMENDED
    $script:testCurrentSnapshot = Copy-TestSnapshot -Snapshot $recommendedSnapshot
    [void](Set-NormalizationCompensationPhase -Record $record `
        -Phase NORMALIZED_VERIFIED -CandidateName RECOMMENDED)
    [IO.File]::WriteAllText($backupPath, '{}')
    $script:testOriginalBackup = [pscustomobject]@{
        BaselinePolicy = 'INTEL_STANDARD_BASELINE'
        ProfileId = 1; ProfileName = 'RECOMMENDED'
        MinRefreshRateInHz = 60; MaxRefreshRateInHz = 120
        MaxFrameTimeIncreaseInUs = 0; MaxFrameTimeDecreaseInUs = 0
    }
    Complete-NormalizationCompensationAfterBackup -Panel $panel -Gpu $gpu `
        -CurrentTarget $script:testCurrentSnapshot
    Assert-Test -Condition (-not (Test-Path -LiteralPath $normalizationCompensationPath)) `
        -Message 'A validated original-profile backup did not finalize the WAL.'

    # Identity drift never replays a user-writable WAL onto another driver.
    Remove-FileIfPresent -LiteralPath $backupPath
    $script:testOriginalBackup = $null
    $script:testCurrentSnapshot = Copy-TestSnapshot -Snapshot $originalSnapshot
    [void](New-NormalizationCompensationRecord -Panel $panel -Gpu $gpu `
            -Snapshot $script:testCurrentSnapshot)
    $differentDriver = $gpu.PSObject.Copy()
    $differentDriver.DriverVersion = '99.0.0.0'
    $identityRejected = $false
    try {
        [void](Invoke-NormalizationCompensationRestore -Panel $panel `
                -Gpu $differentDriver -CurrentTarget $script:testCurrentSnapshot)
    }
    catch { $identityRejected = $_.Exception.Message -like '*does not match the exact active*' }
    Assert-Test -Condition ($identityRejected -and
        (Test-Path -LiteralPath $normalizationCompensationPath -PathType Leaf)) `
        -Message 'A normalization WAL crossed an Intel driver identity boundary.'

    $source = [IO.File]::ReadAllText($corePath).Replace("`r`n", "`n")
    $normalizationStart = $source.IndexOf(
        '$normalizationRecord = New-NormalizationCompensationRecord',
        [StringComparison]::Ordinal)
    $candidateWrite = $source.IndexOf(
        'Invoke-SetProfile -Target $normalized', $normalizationStart,
        [StringComparison]::Ordinal)
    Assert-Test -Condition ($normalizationStart -ge 0 -and
        $candidateWrite -gt $normalizationStart) `
        -Message 'A normalization candidate setter can run before the durable WAL is created.'
    $saveStart = $source.IndexOf('function Save-OriginalProfile {', [StringComparison]::Ordinal)
    $saveEnd = $source.IndexOf('function Invoke-SetProfile {', $saveStart, [StringComparison]::Ordinal)
    $saveSection = $source.Substring($saveStart, $saveEnd - $saveStart)
    Assert-Test -Condition ($saveSection.IndexOf(
            'Complete-NormalizationCompensationAfterBackup',
            [StringComparison]::Ordinal) -gt $saveSection.IndexOf(
            'Get-OriginalProfile', [StringComparison]::Ordinal)) `
        -Message 'Save-OriginalProfile clears compensation before validating its true backup.'
    foreach ($requiredSafetyMarker in @(
            'NormalizationCompensation = Test-Path -LiteralPath $normalizationCompensationPath',
            'RecoveryRequired = Test-Path -LiteralPath $normalizationCompensationPath',
            'Resolve-PendingNormalizationCompensation',
            'RECOVERY\RESTORE_ORIGINAL_VRR.bat'
        )) {
        Assert-Test -Condition ($source.Contains($requiredSafetyMarker)) `
            -Message "Missing normalization recovery/clean-proof marker: $requiredSafetyMarker"
    }

    [pscustomobject]@{
        Result = 'PASS'
        PreparedPowerLoss = 'NO_WRITE_VERIFIED'
        CandidateWritePowerLoss = 'EXACT_SNAPSHOT_RESTORED'
        FailedRestore = 'WAL_RETAINED'
        BackupCommitPowerLoss = 'WAL_FINALIZED_AFTER_BACKUP_PROOF'
        DriverIdentityDrift = 'REFUSED'
    }
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot -PathType Container) {
        [IO.Directory]::Delete($temporaryRoot, $true)
    }
}
