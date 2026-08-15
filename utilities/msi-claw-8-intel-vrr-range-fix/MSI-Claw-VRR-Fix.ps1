[CmdletBinding()]
param(
    [ValidateSet('Status', 'Install48', 'Install30', 'Restore', 'FactoryReset', 'EmergencyRestoreEdid', 'ApplyStartup')]
    [string]$Action = 'Status'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$fixVersion = '2.0.2'
$targetManufacturer = 'CSW'
$targetProductCode = '0801'
$targetPanelName = 'PN8007QB1-2'
$targetMinimumHz = 48.0
$experimentalMinimumHz = 30.0
$targetMaximumHz = 120.0
$experimentalMaximumHz = 144.0
$profileRecommended = 1
$profileExcellent = 2
$profileCustom = 7
$stateRoot = Join-Path $env:LOCALAPPDATA 'ClawLab\Intel-Arc-Sync-Full-Range'
$backupPath = Join-Path $stateRoot 'original-profile.json'
$experimentalStatePath = Join-Path $stateRoot 'experimental-edid.json'
$managedModeStatePath = Join-Path $stateRoot 'managed-mode.json'
$installedScriptPath = Join-Path $stateRoot 'MSI-Claw-VRR-Fix.ps1'
$startupLauncherName = 'ClawLab-VRR-Startup.vbs'
$installedLauncherPath = Join-Path $stateRoot $startupLauncherName
$startupStatusPath = Join-Path $stateRoot 'startup-last-run.json'
$startupTaskName = 'ClawLab MSI Claw 8 VRR Range'
$experimental144TrialTaskName = 'ClawLab MSI Claw 144 Hz Trial Confirmation'
$experimental144TrialStatePath = Join-Path $stateRoot 'experimental-144-trial.json'
$installedExperimental144TrialPath = Join-Path $stateRoot 'Experimental-144-VRR-Trial.ps1'
$installedExperimental144TrialLauncherPath = Join-Path $stateRoot 'ClawLab-144-Trial-Startup.vbs'
$installedExperimental144TrialDriverPath = Join-Path $stateRoot 'Intel-VRR-144-Trial-Driver-Interface.ps1'
$intelStartupBackupPath = Join-Path $stateRoot 'intel-graphics-startup.json'
$intelStartupRegistryPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
$intelStartupValueName = 'Intel' + [char]0x00AE + ' Graphics Software'
$script:intelStartupIdentityRenewed = $false
$validatedPhysicalEdidSha256 = 'E49BC570225510B7C889ED292570F1345CAA07F5840DB57EA6998A403DB5CEF0'
$validated30_120EdidSha256 = '14CDDC390CF69367C4B6821A46728518200446A33F708A1A87CA673B68B66918'
$validated30_120Block0Sha256 = '597D5A95C28171B7B9DF111C1BB12830532F63831EA38111E02D618850E76698'
$validated30_120Block1Sha256 = 'C2000A5E8A3D91C80DCE75DC5BB2F63269C77501338FD059B4CF71CD0CE94743'
$validated48_144EdidSha256 = '4CFB165CE96119BA37A07176F9D346691D447E0A40E8697777E499E1556A744E'
$validated48_144Block0Sha256 = '65E46C6D528BF69D31D17BB88FD47A17C98576597508CC75D3AD047A029A7172'
$validated48_144Block1Sha256 = 'CA1A52F35378CB58709876EDD9BC648224D3C8AE0FA176E96A587BE8DABD8EB2'
$validated30_144EdidSha256 = '0B8E8A25325B4D9CAC2B6A03CF9B574688B1A6D2DEDF10401605C4898E0CAC05'
$validated30_144Block0Sha256 = '7773D16AFD7F0C9AE0363D1FDE684C12E20F460DB5815516EF76633F70FBF60D'
$validated30_144Block1Sha256 = '8AD37320E4C2FF8DF4E71E205241A152DA3136CB0BE25F54E7A78D6273317640'

function Convert-WmiText {
    param([AllowNull()][object]$Values)

    if ($null -eq $Values) {
        return ''
    }
    return (-join @($Values | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }))
}

function Remove-FileIfPresent {
    param([Parameter(Mandatory)][string]$LiteralPath)

    if (Test-Path -LiteralPath $LiteralPath -PathType Leaf) {
        [IO.File]::Delete($LiteralPath)
    }
}

function Get-ValidatedPanel {
    $matches = @(
        Get-CimInstance -Namespace 'root\wmi' -ClassName 'WmiMonitorID' -ErrorAction Stop |
            ForEach-Object {
                [pscustomobject]@{
                    InstanceName = [string]$_.InstanceName
                    Manufacturer = Convert-WmiText -Values $_.ManufacturerName
                    ProductCode = Convert-WmiText -Values $_.ProductCodeID
                    Name = Convert-WmiText -Values $_.UserFriendlyName
                }
            } |
            Where-Object {
                $_.Manufacturer -eq $targetManufacturer -and
                $_.ProductCode -eq $targetProductCode -and
                $_.Name -eq $targetPanelName
            }
    )

    if ($matches.Count -ne 1) {
        throw "The validated $targetPanelName panel was not found exactly once. No display setting was changed."
    }
    return $matches[0]
}

function Get-IntelGpu {
    $gpus = @(
        Get-CimInstance -ClassName 'Win32_VideoController' -ErrorAction Stop |
            Where-Object { $_.PNPDeviceID -like 'PCI\VEN_8086&*' }
    )
    if ($gpus.Count -lt 1) {
        throw 'No Intel graphics adapter was found. No display setting was changed.'
    }
    return $gpus[0]
}

function Get-ByteArraySha256 {
    param([Parameter(Mandatory)][byte[]]$Bytes)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
}

function Get-FileSha256 {
    param([Parameter(Mandatory)][string]$LiteralPath)

    $stream = [IO.File]::OpenRead($LiteralPath)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '')
    }
    finally {
        $sha.Dispose()
        $stream.Dispose()
    }
}

function Test-ByteArrayEqual {
    param(
        [AllowNull()][byte[]]$Left,
        [AllowNull()][byte[]]$Right
    )

    if ($null -eq $Left -or $null -eq $Right -or $Left.Length -ne $Right.Length) {
        return $false
    }
    for ($index = 0; $index -lt $Left.Length; $index++) {
        if ($Left[$index] -ne $Right[$index]) {
            return $false
        }
    }
    return $true
}

function Get-KnownOverrideHashes {
    param([Parameter(Mandatory)][string]$EdidSha256)

    if ($EdidSha256 -eq $validated30_120EdidSha256) {
        return [pscustomobject]@{ Block0 = $validated30_120Block0Sha256; Block1 = $validated30_120Block1Sha256 }
    }
    if ($EdidSha256 -eq $validated48_144EdidSha256) {
        return [pscustomobject]@{ Block0 = $validated48_144Block0Sha256; Block1 = $validated48_144Block1Sha256 }
    }
    if ($EdidSha256 -eq $validated30_144EdidSha256) {
        return [pscustomobject]@{ Block0 = $validated30_144Block0Sha256; Block1 = $validated30_144Block1Sha256 }
    }
    throw "Unknown ClawLab custom EDID hash: $EdidSha256"
}

function Get-PanelRegistryContext {
    param([Parameter(Mandatory)][object]$Panel)

    $instanceId = $Panel.InstanceName -replace '_\d+$', ''
    if ($instanceId -notlike 'DISPLAY\CSW0801\*') {
        throw "Unexpected validated-panel instance ID: $instanceId"
    }

    $deviceParameters = "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\$instanceId\Device Parameters"
    if (-not (Test-Path -LiteralPath $deviceParameters -PathType Container)) {
        throw 'The validated panel registry key is missing.'
    }

    $reportedEdid = [byte[]](Get-ItemPropertyValue -LiteralPath $deviceParameters -Name 'EDID' -ErrorAction Stop)
    if ($reportedEdid.Length -ne 256) {
        throw "Unexpected panel EDID length: $($reportedEdid.Length) bytes."
    }

    # After the Intel display device reloads an override, Windows can expose the
    # exact overridden EDID through the EDID value itself. Reconstruct the
    # validated physical baseline only from one of our three exact, pinned
    # experimental hashes. No arbitrary EDID is accepted or normalized.
    $reportedHash = Get-ByteArraySha256 -Bytes $reportedEdid
    $physicalEdid = [byte[]]$reportedEdid.Clone()
    if ($reportedHash -ne $validatedPhysicalEdidSha256) {
        $knownCompleteOverride = $reportedHash -in @(
                $validated30_120EdidSha256,
                $validated48_144EdidSha256,
                $validated30_144EdidSha256
            )
        $recoverableClawLabBlocks = $false
        if (-not $knownCompleteOverride -and $Action -eq 'FactoryReset') {
            $overridePath = Join-Path $deviceParameters 'EDID_OVERRIDE'
            if (Test-Path -LiteralPath $overridePath -PathType Container) {
                $block0 = $null
                $block1 = $null
                try { $block0 = [byte[]](Get-ItemPropertyValue -LiteralPath $overridePath -Name '0' -ErrorAction Stop) } catch {}
                try { $block1 = [byte[]](Get-ItemPropertyValue -LiteralPath $overridePath -Name '1' -ErrorAction Stop) } catch {}
                $knownBlock0 = $null -eq $block0 -or
                    (Get-ByteArraySha256 -Bytes $block0) -in @(
                        $validated30_120Block0Sha256,
                        $validated48_144Block0Sha256,
                        $validated30_144Block0Sha256
                    )
                $knownBlock1 = $null -eq $block1 -or
                    (Get-ByteArraySha256 -Bytes $block1) -in @(
                        $validated30_120Block1Sha256,
                        $validated48_144Block1Sha256,
                        $validated30_144Block1Sha256
                    )
                $recoverableClawLabBlocks = ($null -ne $block0 -or $null -ne $block1) -and $knownBlock0 -and $knownBlock1
            }
        }
        if (-not $knownCompleteOverride -and -not $recoverableClawLabBlocks) {
            throw "Unsupported panel EDID: $reportedHash. Custom modes are restricted to the validated EDID."
        }

        $physicalEdid[95] = 48
        $physicalEdid[96] = 120
        $physicalEdid[142] = 48
        $physicalEdid[143] = 120
        foreach ($offset in 156..178) {
            $physicalEdid[$offset] = 0
        }
        Set-EdidChecksum -Edid $physicalEdid -Start 0
        Set-EdidChecksum -Edid $physicalEdid -Start 128
        if ((Get-ByteArraySha256 -Bytes $physicalEdid) -ne $validatedPhysicalEdidSha256) {
            throw 'The known custom EDID could not be reduced to the validated physical baseline.'
        }
    }

    [pscustomobject]@{
        InstanceId = $instanceId
        DeviceParametersPath = $deviceParameters
        OverridePath = Join-Path $deviceParameters 'EDID_OVERRIDE'
        PhysicalEdid = $physicalEdid
        PhysicalEdidSha256 = $validatedPhysicalEdidSha256
        ReportedEdidSha256 = $reportedHash
    }
}

function Set-EdidChecksum {
    param(
        [Parameter(Mandatory)][byte[]]$Edid,
        [Parameter(Mandatory)][int]$Start
    )

    $sum = 0
    for ($offset = $Start; $offset -lt ($Start + 127); $offset++) {
        $sum += $Edid[$offset]
    }
    $Edid[$Start + 127] = [byte]((256 - ($sum % 256)) % 256)
}

function New-ExperimentalEdidVariant {
    param(
        [Parameter(Mandatory)][byte[]]$PhysicalEdid,
        [Parameter(Mandatory)][string]$State,
        [Parameter(Mandatory)][float]$MinimumHz,
        [Parameter(Mandatory)][float]$MaximumHz,
        [Parameter(Mandatory)][string]$ExpectedEdidSha256,
        [Parameter(Mandatory)][string]$ExpectedBlock0Sha256,
        [Parameter(Mandatory)][string]$ExpectedBlock1Sha256
    )

    $physicalHash = Get-ByteArraySha256 -Bytes $PhysicalEdid
    if ($physicalHash -ne $validatedPhysicalEdidSha256) {
        throw "Unsupported panel EDID: $physicalHash. Custom modes are restricted to the validated EDID."
    }
    if ($PhysicalEdid[95] -ne 48 -or $PhysicalEdid[96] -ne 120 -or
        $PhysicalEdid[142] -ne 48 -or $PhysicalEdid[143] -ne 120) {
        throw 'The validated EDID no longer contains the expected 48-120 Hz range fields.'
    }

    foreach ($start in @(0, 128)) {
        $sum = 0
        for ($offset = $start; $offset -lt ($start + 128); $offset++) {
            $sum += $PhysicalEdid[$offset]
        }
        if (($sum % 256) -ne 0) {
            throw "The physical EDID block at offset $start has an invalid checksum."
        }
    }

    $modified = [byte[]]$PhysicalEdid.Clone()
    $modified[95] = [byte]$MinimumHz
    $modified[96] = [byte]$MaximumHz
    $modified[142] = [byte]$MinimumHz
    $modified[143] = [byte]$MaximumHz

    if ([Math]::Abs($MaximumHz - $experimentalMaximumHz) -le 0.1) {
        foreach ($offset in 156..178) {
            if ($PhysicalEdid[$offset] -ne 0) {
                throw 'The validated DisplayID extension no longer has the empty slot required for the 144 Hz timing.'
            }
        }

        # DisplayID 2.0 Type VII detailed timing: 1920x1200 @ 144 Hz.
        # The 2080x1264 totals match the validated native 120 Hz timing.
        $timingBlock = [byte[]]@(
            0x22, 0x00, 0x14,
            0xE0, 0xC6, 0x05, 0x00,
            0x7F, 0x07, 0x9F, 0x00,
            0x2F, 0x00, 0x1F, 0x00,
            0xAF, 0x04, 0x3F, 0x00,
            0x35, 0x00, 0x05, 0x00
        )
        [Array]::Copy($timingBlock, 0, $modified, 156, $timingBlock.Length)
    }

    Set-EdidChecksum -Edid $modified -Start 0
    Set-EdidChecksum -Edid $modified -Start 128

    $modifiedHash = Get-ByteArraySha256 -Bytes $modified
    $block0 = [byte[]]$modified[0..127]
    $block1 = [byte[]]$modified[128..255]
    if ($modifiedHash -ne $ExpectedEdidSha256 -or
        (Get-ByteArraySha256 -Bytes $block0) -ne $ExpectedBlock0Sha256 -or
        (Get-ByteArraySha256 -Bytes $block1) -ne $ExpectedBlock1Sha256) {
        throw "Internal $State EDID verification failed: $modifiedHash"
    }

    [pscustomobject]@{
        State = $State
        MinimumHz = $MinimumHz
        MaximumHz = $MaximumHz
        Complete = $modified
        Block0 = $block0
        Block1 = $block1
        Sha256 = $modifiedHash
        Block0Sha256 = $ExpectedBlock0Sha256
        Block1Sha256 = $ExpectedBlock1Sha256
    }
}

function Get-ExperimentalEdidCatalog {
    param([Parameter(Mandatory)][byte[]]$PhysicalEdid)

    return @(
        New-ExperimentalEdidVariant -PhysicalEdid $PhysicalEdid -State 'CLAWLAB_30_120' `
            -MinimumHz $experimentalMinimumHz -MaximumHz $targetMaximumHz `
            -ExpectedEdidSha256 $validated30_120EdidSha256 `
            -ExpectedBlock0Sha256 $validated30_120Block0Sha256 `
            -ExpectedBlock1Sha256 $validated30_120Block1Sha256
        New-ExperimentalEdidVariant -PhysicalEdid $PhysicalEdid -State 'CLAWLAB_48_144' `
            -MinimumHz $targetMinimumHz -MaximumHz $experimentalMaximumHz `
            -ExpectedEdidSha256 $validated48_144EdidSha256 `
            -ExpectedBlock0Sha256 $validated48_144Block0Sha256 `
            -ExpectedBlock1Sha256 $validated48_144Block1Sha256
        New-ExperimentalEdidVariant -PhysicalEdid $PhysicalEdid -State 'CLAWLAB_30_144' `
            -MinimumHz $experimentalMinimumHz -MaximumHz $experimentalMaximumHz `
            -ExpectedEdidSha256 $validated30_144EdidSha256 `
            -ExpectedBlock0Sha256 $validated30_144Block0Sha256 `
            -ExpectedBlock1Sha256 $validated30_144Block1Sha256
    )
}

function Get-EdidOverrideState {
    param(
        [Parameter(Mandatory)][object]$RegistryContext,
        [Parameter(Mandatory)][object[]]$ExperimentalEdids
    )

    if (-not (Test-Path -LiteralPath $RegistryContext.OverridePath -PathType Container)) {
        return [pscustomobject]@{
            State = 'NONE'; Block0 = $null; Block1 = $null
            MinimumHz = $targetMinimumHz; MaximumHz = $targetMaximumHz; Variant = $null
        }
    }

    $block0 = $null
    $block1 = $null
    try { $block0 = [byte[]](Get-ItemPropertyValue -LiteralPath $RegistryContext.OverridePath -Name '0' -ErrorAction Stop) } catch {}
    try { $block1 = [byte[]](Get-ItemPropertyValue -LiteralPath $RegistryContext.OverridePath -Name '1' -ErrorAction Stop) } catch {}

    if ($null -eq $block0 -and $null -eq $block1) {
        return [pscustomobject]@{
            State = 'NONE'; Block0 = $null; Block1 = $null
            MinimumHz = $targetMinimumHz; MaximumHz = $targetMaximumHz; Variant = $null
        }
    }

    foreach ($variant in $ExperimentalEdids) {
        if ((Test-ByteArrayEqual -Left $block0 -Right $variant.Block0) -and
            (Test-ByteArrayEqual -Left $block1 -Right $variant.Block1)) {
            return [pscustomobject]@{
                State = $variant.State
                Block0 = $block0
                Block1 = $block1
                MinimumHz = $variant.MinimumHz
                MaximumHz = $variant.MaximumHz
                Variant = $variant
            }
        }
    }

    return [pscustomobject]@{
        State = 'UNKNOWN_OVERRIDE'; Block0 = $block0; Block1 = $block1
        MinimumHz = $null; MaximumHz = $null; Variant = $null
    }
}

function Get-ClawLabRecoveryBlockState {
    param(
        [AllowNull()][byte[]]$Block0,
        [AllowNull()][byte[]]$Block1
    )

    $block0 = $Block0
    $block1 = $Block1
    if ($null -eq $block0 -and $null -eq $block1) {
        return [pscustomobject]@{ State = 'NONE'; Block0Present = $false; Block1Present = $false }
    }

    $knownBlock0 = $null -eq $block0 -or
        (Get-ByteArraySha256 -Bytes $block0) -in @(
            $validated30_120Block0Sha256,
            $validated48_144Block0Sha256,
            $validated30_144Block0Sha256
        )
    $knownBlock1 = $null -eq $block1 -or
        (Get-ByteArraySha256 -Bytes $block1) -in @(
            $validated30_120Block1Sha256,
            $validated48_144Block1Sha256,
            $validated30_144Block1Sha256
        )
    if (-not $knownBlock0 -or -not $knownBlock1) {
        return [pscustomobject]@{ State = 'UNKNOWN_THIRD_PARTY'; Block0Present = $null -ne $block0; Block1Present = $null -ne $block1 }
    }
    return [pscustomobject]@{
        State = 'CLAWLAB_RECOVERABLE'
        Block0Present = $null -ne $block0
        Block1Present = $null -ne $block1
    }
}

function Get-ClawLabRecoveryOverrideState {
    param([Parameter(Mandatory)][object]$RegistryContext)

    $block0 = $null
    $block1 = $null
    if (Test-Path -LiteralPath $RegistryContext.OverridePath -PathType Container) {
        try { $block0 = [byte[]](Get-ItemPropertyValue -LiteralPath $RegistryContext.OverridePath -Name '0' -ErrorAction Stop) } catch {}
        try { $block1 = [byte[]](Get-ItemPropertyValue -LiteralPath $RegistryContext.OverridePath -Name '1' -ErrorAction Stop) } catch {}
    }
    return Get-ClawLabRecoveryBlockState -Block0 $block0 -Block1 $block1
}

function Get-ManagedArtifactSnapshot {
    $task = Get-ScheduledTask -TaskName $startupTaskName -ErrorAction SilentlyContinue
    $snapshot = [pscustomobject]@{
        OriginalProfile = Test-Path -LiteralPath $backupPath -PathType Leaf
        ExperimentalState = Test-Path -LiteralPath $experimentalStatePath -PathType Leaf
        InstalledScript = Test-Path -LiteralPath $installedScriptPath -PathType Leaf
        InstalledLauncher = Test-Path -LiteralPath $installedLauncherPath -PathType Leaf
        StartupStatus = Test-Path -LiteralPath $startupStatusPath -PathType Leaf
        IntelStartupBackup = Test-Path -LiteralPath $intelStartupBackupPath -PathType Leaf
        StartupTask = $null -ne $task
    }
    $snapshot | Add-Member -NotePropertyName Any -NotePropertyValue (
        $snapshot.OriginalProfile -or
        $snapshot.ExperimentalState -or
        $snapshot.InstalledScript -or
        $snapshot.InstalledLauncher -or
        $snapshot.StartupStatus -or
        $snapshot.IntelStartupBackup -or
        $snapshot.StartupTask
    )
    return $snapshot
}

function Get-ManagedModeRecord {
    if (-not (Test-Path -LiteralPath $managedModeStatePath -PathType Leaf)) {
        return $null
    }

    $record = [IO.File]::ReadAllText($managedModeStatePath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($property in @('SchemaVersion', 'FixVersion', 'Mode', 'InstalledAt')) {
        if ($property -notin $record.PSObject.Properties.Name) {
            throw "The managed VRR mode record is invalid: missing $property. Run RESTORE_ORIGINAL_VRR.bat."
        }
    }
    if ([int]$record.SchemaVersion -ne 1 -or
        [string]$record.Mode -notin @('OFFICIAL_48_120', 'CLAWLAB_30_120', 'CLAWLAB_48_144', 'CLAWLAB_30_144')) {
        throw 'The managed VRR mode record contains an unsupported value. Run RESTORE_ORIGINAL_VRR.bat.'
    }
    return $record
}

function Get-EffectiveManagedMode {
    param([Parameter(Mandatory)][object]$OverrideState)

    $record = Get-ManagedModeRecord
    $overrideMode = if ($OverrideState.State -eq 'NONE') { 'NONE' } else { [string]$OverrideState.State }
    if ($null -ne $record) {
        $expectedOverride = if ([string]$record.Mode -eq 'OFFICIAL_48_120') { 'NONE' } else { [string]$record.Mode }
        $artifacts = Get-ManagedArtifactSnapshot
        $requiresExperimentalState = [string]$record.Mode -ne 'OFFICIAL_48_120'
        $artifactsComplete = (
            $artifacts.OriginalProfile -and
            $artifacts.InstalledScript -and
            $artifacts.InstalledLauncher -and
            $artifacts.IntelStartupBackup -and
            $artifacts.StartupTask -and
            ($artifacts.ExperimentalState -eq $requiresExperimentalState)
        )
        if ($overrideMode -ne $expectedOverride -or -not $artifactsComplete) {
            return [pscustomobject]@{
                Mode = [string]$record.Mode
                State = 'INCONSISTENT_RESTORE_REQUIRED'
                Source = 'MANAGED_RECORD'
            }
        }
        return [pscustomobject]@{
            Mode = [string]$record.Mode
            State = 'CONSISTENT'
            Source = 'MANAGED_RECORD'
        }
    }

    if ($OverrideState.State -in @('CLAWLAB_30_120', 'CLAWLAB_48_144', 'CLAWLAB_30_144')) {
        return [pscustomobject]@{
            Mode = [string]$OverrideState.State
            State = 'LEGACY_MATCHING_OVERRIDE'
            Source = 'EDID_OVERRIDE'
        }
    }
    if ($OverrideState.State -ne 'NONE') {
        return [pscustomobject]@{
            Mode = [string]$OverrideState.State
            State = 'UNSUPPORTED_RESTORE_REQUIRED'
            Source = 'EDID_OVERRIDE'
        }
    }

    $artifacts = Get-ManagedArtifactSnapshot
    if ($artifacts.Any) {
        return [pscustomobject]@{
            Mode = 'LEGACY_MANAGED_STATE'
            State = 'RESTORE_REQUIRED'
            Source = 'MANAGED_ARTIFACTS'
        }
    }
    return [pscustomobject]@{
        Mode = 'NONE'
        State = 'CLEAN'
        Source = 'NONE'
    }
}

function Assert-ProfileTransitionAllowed {
    param(
        [Parameter(Mandatory)][object]$OverrideState,
        [Parameter(Mandatory)][string]$DesiredMode
    )

    $current = Get-EffectiveManagedMode -OverrideState $OverrideState
    $sameMode = $current.Mode -eq $DesiredMode -and
        $current.State -in @('CONSISTENT', 'LEGACY_MATCHING_OVERRIDE')
    if ($current.Mode -eq 'NONE' -and $current.State -eq 'CLEAN') {
        return $current
    }
    if ($sameMode) {
        return $current
    }
    throw "VRR profile switch refused. Current managed state: $($current.Mode) / $($current.State). Run RESTORE_ORIGINAL_VRR.bat successfully before installing $DesiredMode."
}

function Set-ManagedModeRecord {
    param([Parameter(Mandatory)][string]$Mode)

    if ($Mode -notin @('OFFICIAL_48_120', 'CLAWLAB_30_120', 'CLAWLAB_48_144', 'CLAWLAB_30_144')) {
        throw "Internal managed VRR mode is invalid: $Mode"
    }
    [IO.Directory]::CreateDirectory($stateRoot) | Out-Null
    $record = [ordered]@{
        SchemaVersion = 1
        FixVersion = $fixVersion
        Mode = $Mode
        InstalledAt = (Get-Date).ToString('o')
    }
    [IO.File]::WriteAllText(
        $managedModeStatePath,
        ($record | ConvertTo-Json),
        [Text.UTF8Encoding]::new($false)
    )
    $verified = Get-ManagedModeRecord
    if ([string]$verified.Mode -ne $Mode) {
        throw 'The managed VRR mode record failed verification.'
    }
}

function Confirm-AdministratorOrRelaunch {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        return
    }

    $arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Action $Action"
    $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments -Wait -PassThru
    exit $process.ExitCode
}

function Get-StartupReapplyState {
    $task = Get-ScheduledTask -TaskName $startupTaskName -ErrorAction SilentlyContinue
    if ($null -eq $task) {
        return 'NOT_INSTALLED'
    }
    if (-not (Test-Path -LiteralPath $installedScriptPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $installedLauncherPath -PathType Leaf)) {
        return 'TASK_WITHOUT_FILES'
    }
    return [string]$task.State
}

function Remove-Experimental144Trial {
    $trialTask = Get-ScheduledTask -TaskName $experimental144TrialTaskName -ErrorAction SilentlyContinue
    if ($null -ne $trialTask) {
        Unregister-ScheduledTask -TaskName $experimental144TrialTaskName -Confirm:$false -ErrorAction Stop
    }
    Remove-FileIfPresent -LiteralPath $experimental144TrialStatePath
    Remove-FileIfPresent -LiteralPath $installedExperimental144TrialPath
    Remove-FileIfPresent -LiteralPath $installedExperimental144TrialLauncherPath
    Remove-FileIfPresent -LiteralPath $installedExperimental144TrialDriverPath
}

function Install-StartupReapply {
    [IO.Directory]::CreateDirectory($stateRoot) | Out-Null
    $sourceLauncherPath = Join-Path (Split-Path $PSCommandPath -Parent) $startupLauncherName
    if (-not (Test-Path -LiteralPath $sourceLauncherPath -PathType Leaf)) {
        throw "The windowless startup launcher is missing: $startupLauncherName"
    }
    [IO.File]::Copy($PSCommandPath, $installedScriptPath, $true)
    [IO.File]::Copy($sourceLauncherPath, $installedLauncherPath, $true)

    $sourceHash = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
    $installedHash = (Get-FileHash -LiteralPath $installedScriptPath -Algorithm SHA256).Hash
    $sourceLauncherHash = (Get-FileHash -LiteralPath $sourceLauncherPath -Algorithm SHA256).Hash
    $installedLauncherHash = (Get-FileHash -LiteralPath $installedLauncherPath -Algorithm SHA256).Hash
    if ($sourceHash -ne $installedHash -or $sourceLauncherHash -ne $installedLauncherHash) {
        throw 'The installed startup files failed their integrity check.'
    }

    $wscriptPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
    $arguments = "//B //Nologo `"$installedLauncherPath`""
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $identity.Name
    $taskAction = New-ScheduledTaskAction -Execute $wscriptPath -Argument $arguments
    $principal = New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 3)
    $task = New-ScheduledTask -Action $taskAction -Trigger $trigger -Principal $principal `
        -Settings $settings -Description 'Silently applies MSI Claw Intel Arc Sync VRR, then starts Intel Graphics Software.'
    try {
        Register-ScheduledTask -TaskName $startupTaskName -InputObject $task -Force | Out-Null
        if ((Get-StartupReapplyState) -eq 'NOT_INSTALLED') {
            throw 'The startup reapply task could not be verified.'
        }
        Set-ManagedIntelStartupOrder
    }
    catch {
        try { Restore-IntelStartupOrder } catch { Write-Warning "Intel startup rollback failed: $($_.Exception.Message)" }
        try { Remove-StartupReapply } catch {}
        throw
    }
}

function Remove-StartupReapply {
    $task = Get-ScheduledTask -TaskName $startupTaskName -ErrorAction SilentlyContinue
    if ($null -ne $task) {
        Unregister-ScheduledTask -TaskName $startupTaskName -Confirm:$false -ErrorAction Stop
    }
    Remove-Experimental144Trial
    Remove-FileIfPresent -LiteralPath $installedScriptPath
    Remove-FileIfPresent -LiteralPath $installedLauncherPath
    Remove-FileIfPresent -LiteralPath $startupStatusPath
    if ((Get-StartupReapplyState) -ne 'NOT_INSTALLED') {
        throw 'The startup reapply task could not be removed completely.'
    }
}

function Write-StartupResult {
    param(
        [Parameter(Mandatory)][bool]$Success,
        [Parameter(Mandatory)][string]$Message
    )

    [IO.Directory]::CreateDirectory($stateRoot) | Out-Null
    $result = [ordered]@{
        SchemaVersion = 1
        FixVersion = $fixVersion
        Timestamp = (Get-Date).ToString('o')
        Success = $Success
        Message = $Message
    }
    [IO.File]::WriteAllText(
        $startupStatusPath,
        ($result | ConvertTo-Json),
        [Text.UTF8Encoding]::new($false)
    )
}

function Resolve-IntelGraphicsStartupCommand {
    param(
        [Parameter(Mandatory)][string]$Command,
        [switch]$SkipAuthenticode
    )

    $match = [regex]::Match(
        $Command,
        '^"(?<Executable>[A-Za-z]:\\[^"]+\\IntelGraphicsSoftware\.exe)"\s+(?<Arguments>-s)$'
    )
    if (-not $match.Success) {
        throw "Unexpected Intel Graphics Software startup command: $Command"
    }

    $executable = [IO.Path]::GetFullPath($match.Groups['Executable'].Value)
    $expectedRoot = [IO.Path]::GetFullPath((Join-Path $env:ProgramFiles 'Intel\Intel Graphics Software'))
    if (-not $executable.StartsWith($expectedRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Intel Graphics Software is outside its expected installation directory: $executable"
    }
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        throw "Intel Graphics Software executable is missing: $executable"
    }

    $signerThumbprint = $null
    if (-not $SkipAuthenticode) {
        $signature = Get-AuthenticodeSignature -LiteralPath $executable
        if ($signature.Status -ne [Management.Automation.SignatureStatus]::Valid -or
            $null -eq $signature.SignerCertificate -or
            $signature.SignerCertificate.Subject -notmatch '(^|, )O=Intel Corporation(,|$)') {
            throw 'Intel Graphics Software does not have the expected valid Intel signature.'
        }
        $signerThumbprint = $signature.SignerCertificate.Thumbprint
    }

    [pscustomobject]@{
        Command = $Command
        Executable = $executable
        Arguments = $match.Groups['Arguments'].Value
        SignerThumbprint = $signerThumbprint
        FileSha256 = Get-FileSha256 -LiteralPath $executable
        FileVersion = [string](Get-Item -LiteralPath $executable).VersionInfo.FileVersion
    }
}

function Write-IntelStartupBackupAtomically {
    param([Parameter(Mandatory)][object]$Backup)

    [IO.Directory]::CreateDirectory($stateRoot) | Out-Null
    $temporaryPath = Join-Path $stateRoot ('.intel-graphics-startup-{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
    $replacementBackupPath = Join-Path $stateRoot ('.intel-graphics-startup-previous-{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText(
            $temporaryPath,
            ($Backup | ConvertTo-Json),
            [Text.UTF8Encoding]::new($false)
        )
        if (Test-Path -LiteralPath $intelStartupBackupPath -PathType Leaf) {
            [IO.File]::Replace($temporaryPath, $intelStartupBackupPath, $replacementBackupPath)
            [IO.File]::Delete($replacementBackupPath)
        }
        else {
            [IO.File]::Move($temporaryPath, $intelStartupBackupPath)
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            [IO.File]::Delete($temporaryPath)
        }
        if (Test-Path -LiteralPath $replacementBackupPath -PathType Leaf) {
            [IO.File]::Delete($replacementBackupPath)
        }
    }
}

function Set-IntelStartupTrustedIdentity {
    param(
        [AllowNull()][object]$ExistingBackup,
        [Parameter(Mandatory)][object]$Resolved,
        [bool]$OriginalEntryPresent = $true
    )

    if ([string]::IsNullOrWhiteSpace([string]$Resolved.SignerThumbprint) -or
        [string]::IsNullOrWhiteSpace([string]$Resolved.FileSha256) -or
        [string]::IsNullOrWhiteSpace([string]$Resolved.FileVersion)) {
        throw 'An incomplete Intel Graphics Software identity cannot be trusted.'
    }

    $savedAt = (Get-Date).ToString('o')
    if ($null -ne $ExistingBackup -and 'SavedAt' -in $ExistingBackup.PSObject.Properties.Name) {
        $savedAt = [string]$ExistingBackup.SavedAt
    }
    if ($null -ne $ExistingBackup -and 'OriginalEntryPresent' -in $ExistingBackup.PSObject.Properties.Name) {
        $OriginalEntryPresent = [bool]$ExistingBackup.OriginalEntryPresent
    }
    $record = [ordered]@{
        SchemaVersion = 3
        FixVersion = $fixVersion
        SavedAt = $savedAt
        IdentityVerifiedAt = (Get-Date).ToString('o')
        OriginalEntryPresent = $OriginalEntryPresent
        RegistryPath = $intelStartupRegistryPath
        ValueName = $intelStartupValueName
        Command = $Resolved.Command
        Executable = $Resolved.Executable
        Arguments = $Resolved.Arguments
        SignerThumbprint = $Resolved.SignerThumbprint
        FileSha256 = $Resolved.FileSha256
        FileVersion = $Resolved.FileVersion
    }
    Write-IntelStartupBackupAtomically -Backup $record

    $verified = [IO.File]::ReadAllText($intelStartupBackupPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if ([int]$verified.SchemaVersion -ne 3 -or
        [bool]$verified.OriginalEntryPresent -ne $OriginalEntryPresent -or
        [string]$verified.Command -ne [string]$Resolved.Command -or
        [string]$verified.SignerThumbprint -ne [string]$Resolved.SignerThumbprint -or
        [string]$verified.FileSha256 -ne [string]$Resolved.FileSha256 -or
        [string]$verified.FileVersion -ne [string]$Resolved.FileVersion) {
        throw 'The verified Intel Graphics Software identity could not be saved safely.'
    }
    return $verified
}

function Get-IntelStartupBackup {
    if (-not (Test-Path -LiteralPath $intelStartupBackupPath -PathType Leaf)) {
        return $null
    }
    $backup = [IO.File]::ReadAllText($intelStartupBackupPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($property in @('RegistryPath', 'ValueName', 'Command', 'Executable', 'Arguments', 'SignerThumbprint')) {
        if ($property -notin $backup.PSObject.Properties.Name) {
            throw "The saved Intel startup entry is invalid: missing $property."
        }
    }
    if ([string]$backup.RegistryPath -ne $intelStartupRegistryPath -or
        [string]$backup.ValueName -ne $intelStartupValueName) {
        throw 'The saved Intel startup registry target is invalid.'
    }
    if ('SchemaVersion' -in $backup.PSObject.Properties.Name -and
        [int]$backup.SchemaVersion -notin @(1, 2, 3)) {
        throw 'The saved Intel startup entry uses an unsupported schema.'
    }

    $startupMode = $Action -eq 'ApplyStartup'
    $resolved = Resolve-IntelGraphicsStartupCommand -Command ([string]$backup.Command) -SkipAuthenticode:$startupMode
    if ($resolved.Executable -ne [string]$backup.Executable -or
        $resolved.Arguments -ne [string]$backup.Arguments) {
        throw 'The saved Intel startup command no longer passes verification.'
    }

    $hasPinnedIdentity = (
        'FileSha256' -in $backup.PSObject.Properties.Name -and
        'FileVersion' -in $backup.PSObject.Properties.Name -and
        'SchemaVersion' -in $backup.PSObject.Properties.Name -and
        [int]$backup.SchemaVersion -in @(2, 3)
    )
    $hashChanged = -not $hasPinnedIdentity -or
        $resolved.FileSha256 -ne [string]$backup.FileSha256
    $signerChanged = -not $startupMode -and
        $resolved.SignerThumbprint -ne [string]$backup.SignerThumbprint

    if ($hashChanged -or $signerChanged) {
        # A graphics-driver update can replace IntelGraphicsSoftware.exe. Trust
        # is renewed only after a fresh Authenticode check of the canonical
        # Intel path; a changed hash by itself is never accepted.
        $verifiedUpdate = Resolve-IntelGraphicsStartupCommand -Command ([string]$backup.Command)
        if ($verifiedUpdate.Executable -ne [string]$backup.Executable -or
            $verifiedUpdate.Arguments -ne [string]$backup.Arguments) {
            throw 'The updated Intel Graphics Software command no longer matches the saved command.'
        }
        $stableHash = Get-FileSha256 -LiteralPath $verifiedUpdate.Executable
        if ($stableHash -ne $verifiedUpdate.FileSha256) {
            throw 'Intel Graphics Software changed while its signed update was being verified. Startup reapply was cancelled.'
        }
        $backup = Set-IntelStartupTrustedIdentity -ExistingBackup $backup -Resolved $verifiedUpdate
        $script:intelStartupIdentityRenewed = $true
    }

    $final = Resolve-IntelGraphicsStartupCommand -Command ([string]$backup.Command) -SkipAuthenticode
    if ($final.FileSha256 -ne [string]$backup.FileSha256) {
        throw 'Intel Graphics Software no longer matches the trusted identity after verification.'
    }
    return $backup
}

function Get-IntelStartupRegistryValue {
    try {
        $key = Get-Item -LiteralPath $intelStartupRegistryPath -ErrorAction Stop
        if ($intelStartupValueName -notin @($key.GetValueNames())) {
            return $null
        }
        return [string]$key.GetValue(
            $intelStartupValueName,
            $null,
            [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
        )
    }
    catch [Management.Automation.ItemNotFoundException] {
        return $null
    }
}

function Test-OriginalIntelStartupEntryPresent {
    param([Parameter(Mandatory)][object]$Backup)

    if ('OriginalEntryPresent' -in $Backup.PSObject.Properties.Name) {
        return [bool]$Backup.OriginalEntryPresent
    }
    # Schemas 1 and 2 were only created from an existing Intel Run value.
    return $true
}

function Get-IntelStartupOrderState {
    $backup = Get-IntelStartupBackup
    $current = Get-IntelStartupRegistryValue
    if ($null -eq $backup) {
        if ([string]::IsNullOrEmpty($current)) {
            return 'MISSING_WITHOUT_BACKUP'
        }
        [void](Resolve-IntelGraphicsStartupCommand -Command $current)
        return 'INTEL_DEFAULT'
    }
    if ([string]::IsNullOrEmpty($current)) {
        return 'CLAWLAB_ORDERED'
    }
    if ($current -eq [string]$backup.Command) {
        if (Test-OriginalIntelStartupEntryPresent -Backup $backup) {
            return 'ORIGINAL_STILL_PRESENT'
        }
        return 'MANAGED_COMMAND_REAPPEARED'
    }
    return 'UNKNOWN_STARTUP_ENTRY'
}

function Set-ManagedIntelStartupOrder {
    $backup = Get-IntelStartupBackup
    $current = Get-IntelStartupRegistryValue

    if ($null -eq $backup) {
        if ([string]::IsNullOrEmpty($current)) {
            $canonicalExecutable = Join-Path $env:ProgramFiles 'Intel\Intel Graphics Software\IntelGraphicsSoftware.exe'
            $canonicalCommand = '"{0}" -s' -f $canonicalExecutable
            $resolved = Resolve-IntelGraphicsStartupCommand -Command $canonicalCommand
            [IO.Directory]::CreateDirectory($stateRoot) | Out-Null
            [void](Set-IntelStartupTrustedIdentity -ExistingBackup $null -Resolved $resolved -OriginalEntryPresent $false)
            $backup = Get-IntelStartupBackup
        }
        else {
            $resolved = Resolve-IntelGraphicsStartupCommand -Command $current
            [IO.Directory]::CreateDirectory($stateRoot) | Out-Null
            [void](Set-IntelStartupTrustedIdentity -ExistingBackup $null -Resolved $resolved -OriginalEntryPresent $true)
            $backup = Get-IntelStartupBackup
        }
    }
    elseif (-not [string]::IsNullOrEmpty($current) -and $current -ne [string]$backup.Command) {
        throw 'An unknown Intel Graphics Software startup entry is present. It was not modified.'
    }

    if (-not [string]::IsNullOrEmpty($current)) {
        Remove-ItemProperty -LiteralPath $intelStartupRegistryPath -Name $intelStartupValueName -ErrorAction Stop
    }
    if ((Get-IntelStartupOrderState) -ne 'CLAWLAB_ORDERED') {
        throw 'Could not establish the verified ClawLab Intel startup order.'
    }
}

function Restore-IntelStartupOrder {
    $backup = Get-IntelStartupBackup
    if ($null -eq $backup) {
        return
    }
    $current = Get-IntelStartupRegistryValue
    if (-not [string]::IsNullOrEmpty($current) -and $current -ne [string]$backup.Command) {
        throw 'An unknown Intel Graphics Software startup entry is present. The saved entry was not restored.'
    }
    if (Test-OriginalIntelStartupEntryPresent -Backup $backup) {
        New-ItemProperty -LiteralPath $intelStartupRegistryPath -Name $intelStartupValueName `
            -PropertyType String -Value ([string]$backup.Command) -Force | Out-Null
        if ((Get-IntelStartupRegistryValue) -ne [string]$backup.Command) {
            throw 'The original Intel Graphics Software startup entry could not be verified after restoration.'
        }
    }
    else {
        if (-not [string]::IsNullOrEmpty($current)) {
            Remove-ItemProperty -LiteralPath $intelStartupRegistryPath -Name $intelStartupValueName -ErrorAction Stop
        }
        if (-not [string]::IsNullOrEmpty((Get-IntelStartupRegistryValue))) {
            throw 'The originally absent Intel Graphics Software startup entry could not be restored safely.'
        }
    }
    Remove-FileIfPresent -LiteralPath $intelStartupBackupPath
}

function Get-FactoryIntelStartupCommand {
    $current = Get-IntelStartupRegistryValue
    if (-not [string]::IsNullOrEmpty($current)) {
        [void](Resolve-IntelGraphicsStartupCommand -Command $current)
        return $current
    }

    if (Test-Path -LiteralPath $intelStartupBackupPath -PathType Leaf) {
        try {
            $backup = Get-IntelStartupBackup
            if ($null -ne $backup) {
                return [string]$backup.Command
            }
        }
        catch {
            Write-Warning "The saved Intel startup entry is unusable; attempting signed factory-path recovery: $($_.Exception.Message)"
        }
    }

    $executable = Join-Path $env:ProgramFiles 'Intel\Intel Graphics Software\IntelGraphicsSoftware.exe'
    $command = '"{0}" -s' -f $executable
    [void](Resolve-IntelGraphicsStartupCommand -Command $command)
    return $command
}

function Set-FactoryIntelStartupCommand {
    param([Parameter(Mandatory)][string]$Command)

    [void](Resolve-IntelGraphicsStartupCommand -Command $Command)
    $current = Get-IntelStartupRegistryValue
    if (-not [string]::IsNullOrEmpty($current) -and $current -ne $Command) {
        throw 'An unexpected Intel Graphics Software startup entry appeared during factory reset. It was not overwritten.'
    }
    if ([string]::IsNullOrEmpty($current)) {
        New-ItemProperty -LiteralPath $intelStartupRegistryPath -Name $intelStartupValueName `
            -PropertyType String -Value $Command -Force | Out-Null
    }
    if ((Get-IntelStartupRegistryValue) -ne $Command) {
        throw 'Factory reset could not verify the Intel Graphics Software startup entry.'
    }
}

function Start-ManagedIntelGraphicsSoftware {
    $backup = Get-IntelStartupBackup
    if ($null -eq $backup) {
        return
    }
    if ($null -ne (Get-Process -Name 'IntelGraphicsSoftware' -ErrorAction SilentlyContinue)) {
        return
    }
    $resolved = Resolve-IntelGraphicsStartupCommand -Command ([string]$backup.Command)
    if ($resolved.FileSha256 -ne [string]$backup.FileSha256 -or
        $resolved.SignerThumbprint -ne [string]$backup.SignerThumbprint) {
        throw 'Intel Graphics Software changed between trust verification and launch.'
    }
    Start-Process -FilePath $resolved.Executable -ArgumentList $resolved.Arguments -WindowStyle Hidden
}

function Add-ArcSyncControlType {
    if ($null -ne ('ClawLab.VrrFix.ArcSyncControl' -as [type])) {
        return
    }

    $controlLibrary = Join-Path $env:SystemRoot 'System32\ControlLib.dll'
    if (-not (Test-Path -LiteralPath $controlLibrary -PathType Leaf)) {
        throw 'Intel Control Library (ControlLib.dll) is missing. Install a current Intel graphics driver first.'
    }

    $source = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace ClawLab.VrrFix
{
    [StructLayout(LayoutKind.Sequential)]
    public struct CtlApplicationId
    {
        public UInt32 Data1;
        public UInt16 Data2;
        public UInt16 Data3;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 8)]
        public byte[] Data4;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct CtlInitArgs
    {
        public UInt32 Size;
        public byte Version;
        public UInt32 AppVersion;
        public UInt32 Flags;
        public UInt32 SupportedVersion;
        public CtlApplicationId ApplicationUid;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct ArcSyncMonitorParams
    {
        public UInt32 Size;
        public byte Version;
        [MarshalAs(UnmanagedType.U1)] public bool IsSupported;
        public float MinimumRefreshRateInHz;
        public float MaximumRefreshRateInHz;
        public UInt32 MaxFrameTimeIncreaseInUs;
        public UInt32 MaxFrameTimeDecreaseInUs;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct ArcSyncProfileParams
    {
        public UInt32 Size;
        public byte Version;
        public Int32 Profile;
        public float MaxRefreshRateInHz;
        public float MinRefreshRateInHz;
        public UInt32 MaxFrameTimeIncreaseInUs;
        public UInt32 MaxFrameTimeDecreaseInUs;
    }

    public sealed class ArcSyncSnapshot
    {
        public int AdapterIndex { get; set; }
        public int DisplayIndex { get; set; }
        public int MonitorResult { get; set; }
        public bool Supported { get; set; }
        public float MonitorMinimumHz { get; set; }
        public float MonitorMaximumHz { get; set; }
        public UInt32 MonitorMaxIncreaseUs { get; set; }
        public UInt32 MonitorMaxDecreaseUs { get; set; }
        public int ProfileResult { get; set; }
        public int ProfileId { get; set; }
        public string ProfileName { get; set; }
        public float ActiveMinimumHz { get; set; }
        public float ActiveMaximumHz { get; set; }
        public UInt32 ActiveMaxIncreaseUs { get; set; }
        public UInt32 ActiveMaxDecreaseUs { get; set; }
    }

    public static class ArcSyncControl
    {
        [DllImport("ControlLib.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int ctlInit(ref CtlInitArgs args, out IntPtr api);

        [DllImport("ControlLib.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int ctlClose(IntPtr api);

        [DllImport("ControlLib.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int ctlEnumerateDevices(IntPtr api, ref UInt32 count, IntPtr devices);

        [DllImport("ControlLib.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int ctlEnumerateDisplayOutputs(IntPtr adapter, ref UInt32 count, IntPtr displays);

        [DllImport("ControlLib.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int ctlGetIntelArcSyncInfoForMonitor(IntPtr display, ref ArcSyncMonitorParams parameters);

        [DllImport("ControlLib.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int ctlGetIntelArcSyncProfile(IntPtr display, ref ArcSyncProfileParams parameters);

        [DllImport("ControlLib.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int ctlSetIntelArcSyncProfile(IntPtr display, ref ArcSyncProfileParams parameters);

        private static CtlInitArgs CreateInitArgs()
        {
            return new CtlInitArgs
            {
                Size = (UInt32)Marshal.SizeOf(typeof(CtlInitArgs)),
                Version = 0,
                AppVersion = 0x00010001,
                Flags = 0,
                ApplicationUid = new CtlApplicationId { Data4 = new byte[8] }
            };
        }

        private static string GetProfileName(int profile)
        {
            string[] names = { "INVALID", "RECOMMENDED", "EXCELLENT", "GOOD", "COMPATIBLE", "OFF", "VESA", "CUSTOM" };
            return profile >= 0 && profile < names.Length ? names[profile] : "UNKNOWN_" + profile;
        }

        public static ArcSyncSnapshot[] Query()
        {
            List<ArcSyncSnapshot> results = new List<ArcSyncSnapshot>();
            CtlInitArgs init = CreateInitArgs();
            IntPtr api;
            int result = ctlInit(ref init, out api);
            if (result != 0)
                throw new InvalidOperationException("ctlInit failed: 0x" + result.ToString("X8"));

            IntPtr adapters = IntPtr.Zero;
            try
            {
                UInt32 adapterCount = 0;
                result = ctlEnumerateDevices(api, ref adapterCount, IntPtr.Zero);
                if (result != 0)
                    throw new InvalidOperationException("ctlEnumerateDevices(count) failed: 0x" + result.ToString("X8"));

                adapters = Marshal.AllocHGlobal(checked((int)adapterCount * IntPtr.Size));
                result = ctlEnumerateDevices(api, ref adapterCount, adapters);
                if (result != 0)
                    throw new InvalidOperationException("ctlEnumerateDevices(list) failed: 0x" + result.ToString("X8"));

                for (int adapterIndex = 0; adapterIndex < adapterCount; adapterIndex++)
                {
                    IntPtr adapter = Marshal.ReadIntPtr(adapters, adapterIndex * IntPtr.Size);
                    UInt32 displayCount = 0;
                    result = ctlEnumerateDisplayOutputs(adapter, ref displayCount, IntPtr.Zero);
                    if (result != 0 || displayCount == 0)
                        continue;

                    IntPtr displays = Marshal.AllocHGlobal(checked((int)displayCount * IntPtr.Size));
                    try
                    {
                        result = ctlEnumerateDisplayOutputs(adapter, ref displayCount, displays);
                        if (result != 0)
                            continue;

                        for (int displayIndex = 0; displayIndex < displayCount; displayIndex++)
                        {
                            IntPtr display = Marshal.ReadIntPtr(displays, displayIndex * IntPtr.Size);
                            ArcSyncMonitorParams monitor = new ArcSyncMonitorParams
                            {
                                Size = (UInt32)Marshal.SizeOf(typeof(ArcSyncMonitorParams)),
                                Version = 0
                            };
                            int monitorResult = ctlGetIntelArcSyncInfoForMonitor(display, ref monitor);

                            ArcSyncProfileParams profile = new ArcSyncProfileParams
                            {
                                Size = (UInt32)Marshal.SizeOf(typeof(ArcSyncProfileParams)),
                                Version = 0
                            };
                            int profileResult = ctlGetIntelArcSyncProfile(display, ref profile);

                            results.Add(new ArcSyncSnapshot
                            {
                                AdapterIndex = adapterIndex,
                                DisplayIndex = displayIndex,
                                MonitorResult = monitorResult,
                                Supported = monitor.IsSupported,
                                MonitorMinimumHz = monitor.MinimumRefreshRateInHz,
                                MonitorMaximumHz = monitor.MaximumRefreshRateInHz,
                                MonitorMaxIncreaseUs = monitor.MaxFrameTimeIncreaseInUs,
                                MonitorMaxDecreaseUs = monitor.MaxFrameTimeDecreaseInUs,
                                ProfileResult = profileResult,
                                ProfileId = profile.Profile,
                                ProfileName = GetProfileName(profile.Profile),
                                ActiveMinimumHz = profile.MinRefreshRateInHz,
                                ActiveMaximumHz = profile.MaxRefreshRateInHz,
                                ActiveMaxIncreaseUs = profile.MaxFrameTimeIncreaseInUs,
                                ActiveMaxDecreaseUs = profile.MaxFrameTimeDecreaseInUs
                            });
                        }
                    }
                    finally
                    {
                        Marshal.FreeHGlobal(displays);
                    }
                }
            }
            finally
            {
                if (adapters != IntPtr.Zero)
                    Marshal.FreeHGlobal(adapters);
                ctlClose(api);
            }
            return results.ToArray();
        }

        public static int SetProfile(int targetAdapterIndex, int targetDisplayIndex,
            float expectedMonitorMinimumHz, float expectedMonitorMaximumHz, int profileId,
            float minimumHz, float maximumHz, UInt32 maxIncreaseUs, UInt32 maxDecreaseUs)
        {
            CtlInitArgs init = CreateInitArgs();
            IntPtr api;
            int result = ctlInit(ref init, out api);
            if (result != 0)
                return result;

            IntPtr adapters = IntPtr.Zero;
            try
            {
                UInt32 adapterCount = 0;
                result = ctlEnumerateDevices(api, ref adapterCount, IntPtr.Zero);
                if (result != 0)
                    return result;
                if (targetAdapterIndex < 0 || targetAdapterIndex >= adapterCount)
                    return unchecked((int)0x40000017);

                adapters = Marshal.AllocHGlobal(checked((int)adapterCount * IntPtr.Size));
                result = ctlEnumerateDevices(api, ref adapterCount, adapters);
                if (result != 0)
                    return result;

                IntPtr adapter = Marshal.ReadIntPtr(adapters, targetAdapterIndex * IntPtr.Size);
                UInt32 displayCount = 0;
                result = ctlEnumerateDisplayOutputs(adapter, ref displayCount, IntPtr.Zero);
                if (result != 0)
                    return result;
                if (targetDisplayIndex < 0 || targetDisplayIndex >= displayCount)
                    return unchecked((int)0x40000017);

                IntPtr displays = Marshal.AllocHGlobal(checked((int)displayCount * IntPtr.Size));
                try
                {
                    result = ctlEnumerateDisplayOutputs(adapter, ref displayCount, displays);
                    if (result != 0)
                        return result;

                    IntPtr display = Marshal.ReadIntPtr(displays, targetDisplayIndex * IntPtr.Size);
                    ArcSyncMonitorParams monitor = new ArcSyncMonitorParams
                    {
                        Size = (UInt32)Marshal.SizeOf(typeof(ArcSyncMonitorParams)),
                        Version = 0
                    };
                    result = ctlGetIntelArcSyncInfoForMonitor(display, ref monitor);
                    if (result != 0 || !monitor.IsSupported)
                        return result != 0 ? result : unchecked((int)0x40000017);
                    if (Math.Abs(monitor.MinimumRefreshRateInHz - expectedMonitorMinimumHz) > 0.1f ||
                        Math.Abs(monitor.MaximumRefreshRateInHz - expectedMonitorMaximumHz) > 0.1f)
                        return unchecked((int)0x40000017);

                    ArcSyncProfileParams profile = new ArcSyncProfileParams
                    {
                        Size = (UInt32)Marshal.SizeOf(typeof(ArcSyncProfileParams)),
                        Version = 0,
                        Profile = profileId,
                        MinRefreshRateInHz = minimumHz,
                        MaxRefreshRateInHz = maximumHz,
                        MaxFrameTimeIncreaseInUs = maxIncreaseUs,
                        MaxFrameTimeDecreaseInUs = maxDecreaseUs
                    };
                    return ctlSetIntelArcSyncProfile(display, ref profile);
                }
                finally
                {
                    Marshal.FreeHGlobal(displays);
                }
            }
            finally
            {
                if (adapters != IntPtr.Zero)
                    Marshal.FreeHGlobal(adapters);
                ctlClose(api);
            }
        }
    }
}
'@

    Add-Type -TypeDefinition $source -Language CSharp
}

function Add-DisplayModeControlType {
    if ($null -ne ('ClawLab.VrrFix.DisplayModeControl' -as [type])) {
        return
    }

    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace ClawLab.VrrFix
{
    public sealed class DisplayModeSnapshot
    {
        public int Width { get; set; }
        public int Height { get; set; }
        public int RefreshHz { get; set; }
    }

    public static class DisplayModeControl
    {
        private const int ENUM_CURRENT_SETTINGS = -1;
        private const int DM_DISPLAYFREQUENCY = 0x00400000;
        private const int CDS_UPDATEREGISTRY = 0x00000001;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct DEVMODE
        {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
            public short dmSpecVersion;
            public short dmDriverVersion;
            public short dmSize;
            public short dmDriverExtra;
            public int dmFields;
            public int dmPositionX;
            public int dmPositionY;
            public int dmDisplayOrientation;
            public int dmDisplayFixedOutput;
            public short dmColor;
            public short dmDuplex;
            public short dmYResolution;
            public short dmTTOption;
            public short dmCollate;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
            public short dmLogPixels;
            public int dmBitsPerPel;
            public int dmPelsWidth;
            public int dmPelsHeight;
            public int dmDisplayFlags;
            public int dmDisplayFrequency;
            public int dmICMMethod;
            public int dmICMIntent;
            public int dmMediaType;
            public int dmDitherType;
            public int dmReserved1;
            public int dmReserved2;
            public int dmPanningWidth;
            public int dmPanningHeight;
        }

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int ChangeDisplaySettingsEx(string deviceName, ref DEVMODE devMode, IntPtr hwnd, int flags, IntPtr param);

        private static DEVMODE NewMode()
        {
            DEVMODE mode = new DEVMODE();
            mode.dmDeviceName = new string('\0', 32);
            mode.dmFormName = new string('\0', 32);
            mode.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
            return mode;
        }

        public static DisplayModeSnapshot Current()
        {
            DEVMODE mode = NewMode();
            if (!EnumDisplaySettings(null, ENUM_CURRENT_SETTINGS, ref mode))
                throw new InvalidOperationException("EnumDisplaySettings(current) failed.");
            return new DisplayModeSnapshot
            {
                Width = mode.dmPelsWidth,
                Height = mode.dmPelsHeight,
                RefreshHz = mode.dmDisplayFrequency
            };
        }

        public static bool HasMode(int width, int height, int refreshHz)
        {
            for (int index = 0; index < 1024; index++)
            {
                DEVMODE mode = NewMode();
                if (!EnumDisplaySettings(null, index, ref mode))
                    break;
                if (mode.dmPelsWidth == width && mode.dmPelsHeight == height && mode.dmDisplayFrequency == refreshHz)
                    return true;
            }
            return false;
        }

        public static int SetRefresh(int refreshHz)
        {
            DEVMODE mode = NewMode();
            if (!EnumDisplaySettings(null, ENUM_CURRENT_SETTINGS, ref mode))
                throw new InvalidOperationException("EnumDisplaySettings(current) failed.");
            mode.dmFields = DM_DISPLAYFREQUENCY;
            mode.dmDisplayFrequency = refreshHz;
            return ChangeDisplaySettingsEx(null, ref mode, IntPtr.Zero, CDS_UPDATEREGISTRY, IntPtr.Zero);
        }
    }
}
'@
}

function Get-CurrentDisplayMode {
    $mode = [ClawLab.VrrFix.DisplayModeControl]::Current()
    return [pscustomobject]@{
        Width = [int]$mode.Width
        Height = [int]$mode.Height
        RefreshHz = [int]$mode.RefreshHz
    }
}

function Set-Safe120DisplayMode {
    if (-not [ClawLab.VrrFix.DisplayModeControl]::HasMode(1920, 1200, 120)) {
        throw 'The validated 1920x1200 120 Hz Windows display mode is not available.'
    }

    $current = Get-CurrentDisplayMode
    if ($current.Width -eq 1920 -and $current.Height -eq 1200 -and $current.RefreshHz -eq 120) {
        return $current
    }
    $result = [ClawLab.VrrFix.DisplayModeControl]::SetRefresh(120)
    if ($result -notin @(0, 1)) {
        throw "Windows rejected the 120 Hz recovery mode with code $result."
    }
    Start-Sleep -Seconds 1
    $after = Get-CurrentDisplayMode
    if ($after.Width -ne 1920 -or $after.Height -ne 1200 -or $after.RefreshHz -ne 120) {
        throw "Factory reset did not activate 1920x1200 at 120 Hz; current mode is $($after.Width)x$($after.Height) at $($after.RefreshHz) Hz."
    }
    return $after
}

function Get-TargetSnapshot {
    param([int]$Attempts = 1)

    $lastError = $null
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            $candidates = @(
                [ClawLab.VrrFix.ArcSyncControl]::Query() |
                    Where-Object {
                        $_.MonitorResult -eq 0 -and
                        $_.ProfileResult -eq 0 -and
                        $_.Supported
                    }
            )
            if ($candidates.Count -eq 1) {
                $knownMinimum = (
                    [Math]::Abs($candidates[0].MonitorMinimumHz - $targetMinimumHz) -le 0.1 -or
                    [Math]::Abs($candidates[0].MonitorMinimumHz - $experimentalMinimumHz) -le 0.1
                )
                $knownMaximum = (
                    [Math]::Abs($candidates[0].MonitorMaximumHz - $targetMaximumHz) -le 0.1 -or
                    [Math]::Abs($candidates[0].MonitorMaximumHz - $experimentalMaximumHz) -le 0.1
                )
                if (-not $knownMinimum -or -not $knownMaximum) {
                    throw "Unexpected Arc Sync monitor range: $($candidates[0].MonitorMinimumHz)-$($candidates[0].MonitorMaximumHz) Hz."
                }
                return $candidates[0]
            }
            $lastError = "Expected exactly one active Intel Arc Sync output; found $($candidates.Count). Disconnect external VRR displays and retry."
        }
        catch {
            $lastError = $_.Exception.Message
        }

        if ($attempt -lt $Attempts) {
            Start-Sleep -Milliseconds 500
        }
    }
    throw "$lastError No display setting was changed."
}

function Get-OriginalProfile {
    if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
        return $null
    }
    $backup = [IO.File]::ReadAllText($backupPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($property in @(
        'ProfileId',
        'ProfileName',
        'MinRefreshRateInHz',
        'MaxRefreshRateInHz',
        'MaxFrameTimeIncreaseInUs',
        'MaxFrameTimeDecreaseInUs'
    )) {
        if ($property -notin $backup.PSObject.Properties.Name) {
            throw "The saved original profile is invalid: missing $property. No display setting was changed."
        }
    }
    if ([int]$backup.ProfileId -lt 1 -or [int]$backup.ProfileId -gt 7) {
        throw 'The saved original profile ID is invalid. No display setting was changed.'
    }
    return $backup
}

function Save-OriginalProfile {
    param(
        [Parameter(Mandatory)][object]$Snapshot,
        [Parameter(Mandatory)][object]$Panel,
        [Parameter(Mandatory)][object]$Gpu
    )

    if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
        [void](Get-OriginalProfile)
        return
    }

    [IO.Directory]::CreateDirectory($stateRoot) | Out-Null
    $backup = [ordered]@{
        SchemaVersion = 1
        FixVersion = $fixVersion
        SavedAt = (Get-Date).ToString('o')
        PanelInstanceName = $Panel.InstanceName
        PanelName = $Panel.Name
        IntelDriverVersion = [string]$Gpu.DriverVersion
        ProfileId = $Snapshot.ProfileId
        ProfileName = $Snapshot.ProfileName
        MinRefreshRateInHz = $Snapshot.ActiveMinimumHz
        MaxRefreshRateInHz = $Snapshot.ActiveMaximumHz
        MaxFrameTimeIncreaseInUs = $Snapshot.ActiveMaxIncreaseUs
        MaxFrameTimeDecreaseInUs = $Snapshot.ActiveMaxDecreaseUs
    }
    [IO.File]::WriteAllText(
        $backupPath,
        ($backup | ConvertTo-Json),
        [Text.UTF8Encoding]::new($false)
    )
}

function Invoke-SetProfile {
    param(
        [Parameter(Mandatory)][object]$Target,
        [Parameter(Mandatory)][int]$ProfileId,
        [float]$MinimumHz = 0,
        [float]$MaximumHz = 0,
        [uint32]$MaxIncreaseUs = 0,
        [uint32]$MaxDecreaseUs = 0
    )

    $result = [ClawLab.VrrFix.ArcSyncControl]::SetProfile(
        [int]$Target.AdapterIndex,
        [int]$Target.DisplayIndex,
        [float]$Target.MonitorMinimumHz,
        [float]$Target.MonitorMaximumHz,
        $ProfileId,
        $MinimumHz,
        $MaximumHz,
        $MaxIncreaseUs,
        $MaxDecreaseUs
    )
    if ($result -ne 0) {
        throw ('Intel ctlSetIntelArcSyncProfile failed with code 0x{0:X8}.' -f ([int64]$result))
    }
}

function Restore-SnapshotProfile {
    param(
        [Parameter(Mandatory)][object]$Target,
        [Parameter(Mandatory)][object]$Profile
    )

    if ([int]$Profile.ProfileId -eq $profileCustom) {
        Invoke-SetProfile -Target $Target -ProfileId ([int]$Profile.ProfileId) `
            -MinimumHz ([float]$Profile.MinRefreshRateInHz) `
            -MaximumHz ([float]$Profile.MaxRefreshRateInHz) `
            -MaxIncreaseUs ([uint32]$Profile.MaxFrameTimeIncreaseInUs) `
            -MaxDecreaseUs ([uint32]$Profile.MaxFrameTimeDecreaseInUs)
    }
    else {
        Invoke-SetProfile -Target $Target -ProfileId ([int]$Profile.ProfileId)
    }
}

function Install-CustomEdidMode {
    param(
        [Parameter(Mandatory)][object]$Panel,
        [Parameter(Mandatory)][object]$Gpu,
        [Parameter(Mandatory)][object]$RegistryContext,
        [Parameter(Mandatory)][object[]]$ExperimentalEdids,
        [Parameter(Mandatory)][object]$OverrideState,
        [Parameter(Mandatory)][object]$Before,
        [Parameter(Mandatory)][string]$DesiredState
    )

    if ($DesiredState -ne 'CLAWLAB_30_120') {
        throw "Unknown ClawLab custom profile: $DesiredState"
    }

    $desired = @($ExperimentalEdids | Where-Object { $_.State -eq $DesiredState })
    if ($desired.Count -ne 1) {
        throw "Internal custom profile lookup failed: $DesiredState"
    }
    $variant = $desired[0]
    [void](Assert-ProfileTransitionAllowed -OverrideState $OverrideState -DesiredMode $DesiredState)

    if ($OverrideState.State -eq 'UNKNOWN_OVERRIDE') {
        throw 'An unknown EDID override is installed. Remove it with its original tool before using a ClawLab custom range.'
    }
    if ($OverrideState.State -ne 'NONE' -and $OverrideState.State -ne $DesiredState) {
        throw "Another ClawLab custom range is installed ($($OverrideState.State)). Run RESTORE_ORIGINAL_VRR.bat before changing modes."
    }

    Confirm-AdministratorOrRelaunch
    Save-OriginalProfile -Snapshot $Before -Panel $Panel -Gpu $Gpu

    if ($OverrideState.State -eq 'NONE') {
        if (Test-Path -LiteralPath $experimentalStatePath -PathType Leaf) {
            throw 'A stale custom-range state file exists without its EDID override. Run RESTORE_ORIGINAL_VRR.bat before retrying.'
        }
        if ([Math]::Abs($Before.MonitorMinimumHz - $targetMinimumHz) -gt 0.1 -or
            [Math]::Abs($Before.MonitorMaximumHz - $targetMaximumHz) -gt 0.1) {
            throw "Custom-range installation must start from the native 48-120 Hz EDID, but the driver reports $($Before.MonitorMinimumHz)-$($Before.MonitorMaximumHz) Hz."
        }

        Invoke-SetProfile -Target $Before -ProfileId $profileExcellent
        $official = Get-TargetSnapshot -Attempts 10
        if ($official.ProfileId -ne $profileExcellent -or
            [Math]::Abs($official.ActiveMinimumHz - $targetMinimumHz) -gt 0.1 -or
            [Math]::Abs($official.ActiveMaximumHz - $targetMaximumHz) -gt 0.1) {
            throw 'Could not establish the verified official 48-120 Hz baseline before applying the custom EDID.'
        }

        [IO.Directory]::CreateDirectory($stateRoot) | Out-Null
        $experimentalState = [ordered]@{
            SchemaVersion = 2
            FixVersion = $fixVersion
            InstalledAt = (Get-Date).ToString('o')
            Mode = $variant.State
            PanelInstanceId = $RegistryContext.InstanceId
            RegistryPath = $RegistryContext.OverridePath
            PhysicalEdidSha256 = $RegistryContext.PhysicalEdidSha256
            ExperimentalEdidSha256 = $variant.Sha256
            Block0Sha256 = $variant.Block0Sha256
            Block1Sha256 = $variant.Block1Sha256
            ExperimentalMinimumHz = $variant.MinimumHz
            MaximumHz = $variant.MaximumHz
        }
        [IO.File]::WriteAllText(
            $experimentalStatePath,
            ($experimentalState | ConvertTo-Json),
            [Text.UTF8Encoding]::new($false)
        )

        try {
            New-Item -Path $RegistryContext.OverridePath -Force | Out-Null
            New-ItemProperty -LiteralPath $RegistryContext.OverridePath -Name '0' -PropertyType Binary -Value $variant.Block0 -Force | Out-Null
            New-ItemProperty -LiteralPath $RegistryContext.OverridePath -Name '1' -PropertyType Binary -Value $variant.Block1 -Force | Out-Null
            $writtenState = Get-EdidOverrideState -RegistryContext $RegistryContext -ExperimentalEdids $ExperimentalEdids
            if ($writtenState.State -ne $DesiredState) {
                throw 'The custom EDID registry write did not verify.'
            }
            Install-StartupReapply
            Set-ManagedModeRecord -Mode $DesiredState
        }
        catch {
            Remove-ItemProperty -LiteralPath $RegistryContext.OverridePath -Name '0' -ErrorAction SilentlyContinue
            Remove-ItemProperty -LiteralPath $RegistryContext.OverridePath -Name '1' -ErrorAction SilentlyContinue
            Remove-FileIfPresent -LiteralPath $experimentalStatePath
            Remove-FileIfPresent -LiteralPath $managedModeStatePath
            try { Restore-SnapshotProfile -Target $official -Profile $Before } catch {}
            throw
        }

        Write-Host "ClawLab default $($variant.MinimumHz)-$($variant.MaximumHz) Hz EDID override is installed and verified." -ForegroundColor Yellow
        Write-Host 'Restart the PC to make Windows and the Intel driver reload the display EDID.' -ForegroundColor Yellow
        $status = Get-StatusObject -Panel $Panel -Gpu $Gpu -Snapshot $official -OverrideState $writtenState
        $status.RestartRequired = $true
        return $status
    }

    if (-not (Test-Path -LiteralPath $experimentalStatePath -PathType Leaf)) {
        throw 'The matching EDID override exists without its ClawLab state file. It was not adopted or modified.'
    }

    if ([Math]::Abs($Before.MonitorMinimumHz - $variant.MinimumHz) -le 0.1 -and
        [Math]::Abs($Before.MonitorMaximumHz - $variant.MaximumHz) -le 0.1) {
        Invoke-SetProfile -Target $Before -ProfileId $profileExcellent
        $after = Get-TargetSnapshot -Attempts 10
        if ($after.ProfileId -ne $profileExcellent -or
            [Math]::Abs($after.ActiveMinimumHz - $variant.MinimumHz) -gt 0.1 -or
            [Math]::Abs($after.ActiveMaximumHz - $variant.MaximumHz) -gt 0.1) {
            throw "Custom-range driver verification failed: $($after.ProfileName), $($after.ActiveMinimumHz)-$($after.ActiveMaximumHz) Hz."
        }
        Install-StartupReapply
        Set-ManagedModeRecord -Mode $DesiredState
        $modeLabel = if ($DesiredState -eq 'CLAWLAB_30_120') { 'ClawLab default' } else { 'Experimental' }
        Write-Host "$modeLabel $($variant.MinimumHz)-$($variant.MaximumHz) Hz mode is active and verified by the Intel driver." -ForegroundColor Yellow
        $status = Get-StatusObject -Panel $Panel -Gpu $Gpu -Snapshot $after -OverrideState $OverrideState
        return $status
    }

    Install-StartupReapply
    Set-ManagedModeRecord -Mode $DesiredState
    Write-Host 'The custom EDID override is present but has not been loaded by Windows yet.' -ForegroundColor Yellow
    Write-Host 'Restart the PC, then run CHECK_STATUS.bat.' -ForegroundColor Yellow
    $status = Get-StatusObject -Panel $Panel -Gpu $Gpu -Snapshot $Before -OverrideState $OverrideState
    $status.RestartRequired = $true
    return $status
}

function Get-StatusObject {
    param(
        [Parameter(Mandatory)][object]$Panel,
        [Parameter(Mandatory)][object]$Gpu,
        [Parameter(Mandatory)][object]$Snapshot,
        [Parameter(Mandatory)][object]$OverrideState
    )

    $officialRangeActive = (
        $Snapshot.ProfileId -eq $profileExcellent -and
        [Math]::Abs($Snapshot.ActiveMinimumHz - $targetMinimumHz) -le 0.1 -and
        [Math]::Abs($Snapshot.ActiveMaximumHz - $targetMaximumHz) -le 0.1
    )
    $knownExperimentalOverride = $OverrideState.State -in @('CLAWLAB_30_120', 'CLAWLAB_48_144', 'CLAWLAB_30_144')
    $experimentalRangeActive = (
        $knownExperimentalOverride -and
        $Snapshot.ProfileId -eq $profileExcellent -and
        [Math]::Abs($Snapshot.ActiveMinimumHz - [float]$OverrideState.MinimumHz) -le 0.1 -and
        [Math]::Abs($Snapshot.ActiveMaximumHz - [float]$OverrideState.MaximumHz) -le 0.1
    )

    $state = if ($experimentalRangeActive) {
        if ($OverrideState.State -eq 'CLAWLAB_30_120') {
            'CLAWLAB_30_120_ACTIVE'
        }
        else {
            'EXPERIMENTAL_{0}_{1}_ACTIVE' -f ([int]$OverrideState.MinimumHz), ([int]$OverrideState.MaximumHz)
        }
    }
    elseif ($knownExperimentalOverride) {
        if ($OverrideState.State -eq 'CLAWLAB_30_120') {
            'CLAWLAB_30_120_PENDING_RESTART'
        }
        else {
            'EXPERIMENTAL_{0}_{1}_PENDING_RESTART' -f ([int]$OverrideState.MinimumHz), ([int]$OverrideState.MaximumHz)
        }
    }
    elseif ($OverrideState.State -eq 'UNKNOWN_OVERRIDE') {
        'UNKNOWN_EDID_OVERRIDE'
    }
    elseif ($officialRangeActive) {
        'OFFICIAL_48_120_ACTIVE'
    }
    else {
        'DRIVER_PROFILE_CONSTRAINED'
    }

    $intelStartupState = Get-IntelStartupOrderState

    $displayMode = Get-CurrentDisplayMode
    $managedMode = Get-EffectiveManagedMode -OverrideState $OverrideState

    [pscustomobject]@{
        FixVersion = $fixVersion
        State = $state
        Panel = $Panel.Name
        PanelId = "$($Panel.Manufacturer)$($Panel.ProductCode)"
        IntelGpu = [string]$Gpu.Name
        IntelDriver = [string]$Gpu.DriverVersion
        MonitorSupportedRange = '{0:0.#}-{1:0.#} Hz' -f $Snapshot.MonitorMinimumHz, $Snapshot.MonitorMaximumHz
        DriverProfile = $Snapshot.ProfileName
        DriverActiveRange = '{0:0.#}-{1:0.#} Hz' -f $Snapshot.ActiveMinimumHz, $Snapshot.ActiveMaximumHz
        WindowsDisplayMode = '{0}x{1} @ {2} Hz' -f $displayMode.Width, $displayMode.Height, $displayMode.RefreshHz
        ManagedMode = $managedMode.Mode
        ProfileSwitchGuard = $managedMode.State
        OriginalProfileSaved = Test-Path -LiteralPath $backupPath -PathType Leaf
        BackupPath = $backupPath
        StartupReapply = Get-StartupReapplyState
        IntelGraphicsStartup = $intelStartupState
        EdidOverride = $OverrideState.State
        RecoveryRequired = $false
        RestartRequired = $knownExperimentalOverride -and -not $experimentalRangeActive
        RegistryModified = (
            $knownExperimentalOverride -or
            $intelStartupState -eq 'CLAWLAB_ORDERED'
        )
        DriverFilesModified = $false
    }
}

try {
    if ($Action -eq 'EmergencyRestoreEdid') {
        Confirm-AdministratorOrRelaunch
        if (-not (Test-Path -LiteralPath $experimentalStatePath -PathType Leaf)) {
            throw 'The ClawLab custom EDID state file is missing. Nothing was removed.'
        }
        $emergencyState = [IO.File]::ReadAllText($experimentalStatePath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        if ('RegistryPath' -notin $emergencyState.PSObject.Properties.Name) {
            throw 'The ClawLab custom EDID state file is invalid. Nothing was removed.'
        }
        $emergencyOverridePath = [string]$emergencyState.RegistryPath
        if ($emergencyOverridePath -notlike 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\DISPLAY\CSW0801\*\Device Parameters\EDID_OVERRIDE') {
            throw "Unsafe or unexpected EDID override path: $emergencyOverridePath"
        }
        if ('ExperimentalEdidSha256' -notin $emergencyState.PSObject.Properties.Name) {
            throw 'The ClawLab custom-range state file has no EDID hash. Nothing was removed.'
        }
        $expectedEmergencyHashes = Get-KnownOverrideHashes -EdidSha256 ([string]$emergencyState.ExperimentalEdidSha256)
        $emergencyBlock0 = [byte[]](Get-ItemPropertyValue -LiteralPath $emergencyOverridePath -Name '0' -ErrorAction Stop)
        $emergencyBlock1 = [byte[]](Get-ItemPropertyValue -LiteralPath $emergencyOverridePath -Name '1' -ErrorAction Stop)
        if ((Get-ByteArraySha256 -Bytes $emergencyBlock0) -ne $expectedEmergencyHashes.Block0 -or
            (Get-ByteArraySha256 -Bytes $emergencyBlock1) -ne $expectedEmergencyHashes.Block1) {
            throw 'The installed EDID override does not match a known ClawLab custom mode. Nothing was removed.'
        }
        Remove-ItemProperty -LiteralPath $emergencyOverridePath -Name '0' -ErrorAction Stop
        Remove-ItemProperty -LiteralPath $emergencyOverridePath -Name '1' -ErrorAction Stop
        Remove-FileIfPresent -LiteralPath $experimentalStatePath
        Write-Host 'Removed the verified ClawLab custom EDID override.' -ForegroundColor Green
        Write-Host 'Restart the PC. Then run RESTORE_ORIGINAL_VRR.bat in normal Windows to restore the saved Intel profile.' -ForegroundColor Yellow
        exit 0
    }

    $panel = Get-ValidatedPanel
    $gpu = Get-IntelGpu
    $registryContext = Get-PanelRegistryContext -Panel $panel
    $experimentalEdids = @(Get-ExperimentalEdidCatalog -PhysicalEdid $registryContext.PhysicalEdid)
    $overrideState = Get-EdidOverrideState -RegistryContext $registryContext -ExperimentalEdids $experimentalEdids
    Add-ArcSyncControlType
    Add-DisplayModeControlType
    $snapshotAttempts = if ($Action -eq 'ApplyStartup') { 180 } else { 5 }
    $before = Get-TargetSnapshot -Attempts $snapshotAttempts

    switch ($Action) {
        'Status' {
            Get-StatusObject -Panel $panel -Gpu $gpu -Snapshot $before -OverrideState $overrideState
        }

        'ApplyStartup' {
            if ($overrideState.State -eq 'UNKNOWN_OVERRIDE') {
                throw 'An unknown EDID override is installed. Startup reapply was cancelled.'
            }
            $expectedManagedMode = if ($overrideState.State -eq 'NONE') { 'OFFICIAL_48_120' } else { [string]$overrideState.State }
            if ($expectedManagedMode -in @('CLAWLAB_48_144', 'CLAWLAB_30_144')) {
                throw 'This retired 144 Hz profile is no longer reapplied. Run RESTORE_ORIGINAL_VRR.bat to return to a supported 120 Hz profile.'
            }
            $managedMode = Get-EffectiveManagedMode -OverrideState $overrideState
            if ($managedMode.Mode -ne $expectedManagedMode -or $managedMode.State -ne 'CONSISTENT') {
                throw "Startup reapply refused an unmanaged or inconsistent VRR state: $($managedMode.Mode) / $($managedMode.State). Run RESTORE_ORIGINAL_VRR.bat."
            }
            $expectedMinimumHz = [float]$overrideState.MinimumHz
            $expectedMaximumHz = [float]$overrideState.MaximumHz
            if ([Math]::Abs($before.MonitorMinimumHz - $expectedMinimumHz) -gt 0.1 -or
                [Math]::Abs($before.MonitorMaximumHz - $expectedMaximumHz) -gt 0.1) {
                throw "Startup reapply found an unexpected monitor range: $($before.MonitorMinimumHz)-$($before.MonitorMaximumHz) Hz."
            }

            $displayMode = $null

            # The refresh transition and Intel Graphics Software startup can
            # transiently restore RECOMMENDED. Start the UI first, then apply
            # EXCELLENT against the settled output and verify the final state.
            Start-ManagedIntelGraphicsSoftware
            Start-Sleep -Seconds 2

            $after = $null
            for ($profileAttempt = 1; $profileAttempt -le 3; $profileAttempt++) {
                $target = Get-TargetSnapshot -Attempts 10
                Invoke-SetProfile -Target $target -ProfileId $profileExcellent
                Start-Sleep -Seconds 1
                $after = Get-TargetSnapshot -Attempts 10
                if ($after.ProfileId -eq $profileExcellent -and
                    [Math]::Abs($after.ActiveMinimumHz - $expectedMinimumHz) -le 0.1 -and
                    [Math]::Abs($after.ActiveMaximumHz - $expectedMaximumHz) -le 0.1) {
                    break
                }
                if ($profileAttempt -lt 3) { Start-Sleep -Seconds 1 }
            }
            if ($after.ProfileId -ne $profileExcellent -or
                [Math]::Abs($after.ActiveMinimumHz - $expectedMinimumHz) -gt 0.1 -or
                [Math]::Abs($after.ActiveMaximumHz - $expectedMaximumHz) -gt 0.1) {
                throw "Startup profile verification failed after display stabilization: $($after.ProfileName), $($after.ActiveMinimumHz)-$($after.ActiveMaximumHz) Hz."
            }
            $displaySuffix = ''
            if ($null -ne $displayMode) {
                $displaySuffix = ", $($displayMode.Width)x$($displayMode.Height) at $($displayMode.RefreshHz) Hz"
            }
            $identitySuffix = if ($script:intelStartupIdentityRenewed) { ', signed Intel Graphics Software update trusted' } else { '' }
            Write-StartupResult -Success $true -Message (("{0}, {1}-{2} Hz" -f $after.ProfileName, $after.ActiveMinimumHz, $after.ActiveMaximumHz) + $displaySuffix + $identitySuffix)
            exit 0
        }

        'Install48' {
            [void](Assert-ProfileTransitionAllowed -OverrideState $overrideState -DesiredMode 'OFFICIAL_48_120')
            if ($overrideState.State -eq 'UNKNOWN_OVERRIDE') {
                throw 'An unknown EDID override is installed. Remove it with its original tool before using official mode.'
            }
            if ($overrideState.State -ne 'NONE') {
                throw "ClawLab custom mode $($overrideState.State) is installed. Run RESTORE_ORIGINAL_VRR.bat before installing official mode."
            }
            if ([Math]::Abs($before.MonitorMinimumHz - $targetMinimumHz) -gt 0.1 -or
                [Math]::Abs($before.MonitorMaximumHz - $targetMaximumHz) -gt 0.1) {
                throw "Official mode expected the panel's native 48-120 Hz range, but the driver reports $($before.MonitorMinimumHz)-$($before.MonitorMaximumHz) Hz."
            }

            Confirm-AdministratorOrRelaunch
            Save-OriginalProfile -Snapshot $before -Panel $panel -Gpu $gpu
            if ($before.ProfileId -eq $profileExcellent -and
                [Math]::Abs($before.ActiveMinimumHz - $targetMinimumHz) -le 0.1 -and
                [Math]::Abs($before.ActiveMaximumHz - $targetMaximumHz) -le 0.1) {
                Install-StartupReapply
                Set-ManagedModeRecord -Mode 'OFFICIAL_48_120'
                Write-Host 'Official Intel Arc Sync 48-120 Hz mode is already active.' -ForegroundColor Green
                Get-StatusObject -Panel $panel -Gpu $gpu -Snapshot $before -OverrideState $overrideState
                break
            }

            try {
                Invoke-SetProfile -Target $before -ProfileId $profileExcellent
                $after = Get-TargetSnapshot -Attempts 10
                if ($after.ProfileId -ne $profileExcellent -or
                    [Math]::Abs($after.ActiveMinimumHz - $targetMinimumHz) -gt 0.1 -or
                    [Math]::Abs($after.ActiveMaximumHz - $targetMaximumHz) -gt 0.1) {
                    throw "Driver verification failed: profile $($after.ProfileName), range $($after.ActiveMinimumHz)-$($after.ActiveMaximumHz) Hz."
                }
            }
            catch {
                try {
                    Restore-SnapshotProfile -Target $before -Profile $before
                }
                catch {
                    Write-Warning "Automatic rollback also failed: $($_.Exception.Message)"
                }
                throw
            }

            Install-StartupReapply
            Set-ManagedModeRecord -Mode 'OFFICIAL_48_120'
            Write-Host 'Official Intel Arc Sync 48-120 Hz mode is active and verified.' -ForegroundColor Green
            Write-Host 'Automatic reapply is installed for future Windows sign-ins.' -ForegroundColor Green
            Get-StatusObject -Panel $panel -Gpu $gpu -Snapshot $after -OverrideState $overrideState
        }

        'Install30' {
            Install-CustomEdidMode -Panel $panel -Gpu $gpu -RegistryContext $registryContext `
                -ExperimentalEdids $experimentalEdids -OverrideState $overrideState -Before $before `
                -DesiredState 'CLAWLAB_30_120'
        }

        'FactoryReset' {
            $recoveryOverride = Get-ClawLabRecoveryOverrideState -RegistryContext $registryContext
            if ($recoveryOverride.State -eq 'UNKNOWN_THIRD_PARTY') {
                throw 'Factory reset found an unknown EDID override block. It was not created by ClawLab and will not be removed.'
            }

            # Resolve and validate a signed Intel startup command before making
            # any display or profile change.
            $factoryIntelStartupCommand = Get-FactoryIntelStartupCommand
            Confirm-AdministratorOrRelaunch

            $safeMode = Set-Safe120DisplayMode
            Start-Sleep -Seconds 2
            $factoryTarget = Get-TargetSnapshot -Attempts 10
            Invoke-SetProfile -Target $factoryTarget -ProfileId $profileRecommended
            Start-Sleep -Seconds 1
            $factoryProfile = Get-TargetSnapshot -Attempts 10
            if ($factoryProfile.ProfileId -ne $profileRecommended) {
                throw "Factory reset could not verify Intel RECOMMENDED mode; current profile is $($factoryProfile.ProfileName)."
            }

            if ($recoveryOverride.State -eq 'CLAWLAB_RECOVERABLE') {
                if ($recoveryOverride.Block0Present) {
                    Remove-ItemProperty -LiteralPath $registryContext.OverridePath -Name '0' -ErrorAction Stop
                }
                if ($recoveryOverride.Block1Present) {
                    Remove-ItemProperty -LiteralPath $registryContext.OverridePath -Name '1' -ErrorAction Stop
                }
                $overrideState = Get-EdidOverrideState -RegistryContext $registryContext -ExperimentalEdids $experimentalEdids
                if ($overrideState.State -ne 'NONE') {
                    throw 'Factory reset could not remove the verified ClawLab EDID override completely.'
                }
            }

            Remove-StartupReapply
            Set-FactoryIntelStartupCommand -Command $factoryIntelStartupCommand
            Remove-FileIfPresent -LiteralPath $backupPath
            Remove-FileIfPresent -LiteralPath $experimentalStatePath
            Remove-FileIfPresent -LiteralPath $managedModeStatePath
            Remove-FileIfPresent -LiteralPath $intelStartupBackupPath

            Write-Host 'ClawLab VRR factory reset completed.' -ForegroundColor Green
            Write-Host 'Windows is at 1920x1200 120 Hz and Intel RECOMMENDED is selected.' -ForegroundColor Green
            Write-Host 'Restart the PC to unload any previously active EDID override and restore the physical 48-120 Hz panel data.' -ForegroundColor Yellow
            [pscustomobject]@{
                FixVersion = $fixVersion
                State = 'FACTORY_RESET_COMPLETE_RESTART_REQUIRED'
                WindowsDisplayMode = '{0}x{1} @ {2} Hz' -f $safeMode.Width, $safeMode.Height, $safeMode.RefreshHz
                DriverProfile = $factoryProfile.ProfileName
                EdidOverride = $overrideState.State
                StartupReapply = Get-StartupReapplyState
                IntelGraphicsStartup = Get-IntelStartupOrderState
                RestartRequired = $true
            }
        }

        'Restore' {
            $original = Get-OriginalProfile
            if ($null -eq $original) {
                throw 'No saved original profile is available. No display setting was changed.'
            }

            if ($overrideState.State -eq 'UNKNOWN_OVERRIDE') {
                throw 'An unknown EDID override is installed. It was not created by this package and will not be removed.'
            }
            $knownExperimentalOverride = $overrideState.State -in @('CLAWLAB_30_120', 'CLAWLAB_48_144', 'CLAWLAB_30_144')
            if (Test-Path -LiteralPath $intelStartupBackupPath -PathType Leaf) {
                $startupOrderState = Get-IntelStartupOrderState
                if ($startupOrderState -notin @('CLAWLAB_ORDERED', 'ORIGINAL_STILL_PRESENT', 'MANAGED_COMMAND_REAPPEARED')) {
                    throw "Intel Graphics Software startup state is unsafe to restore: $startupOrderState. Nothing was changed."
                }
            }
            if ($knownExperimentalOverride -or
                (Test-Path -LiteralPath $intelStartupBackupPath -PathType Leaf)) {
                Confirm-AdministratorOrRelaunch
            }

            if ($overrideState.State -in @('CLAWLAB_48_144', 'CLAWLAB_30_144')) {
                # Leave the experimental fixed 144 Hz timing before removing
                # its EDID blocks. This gives trial rollback a visibly safe
                # 120 Hz mode even before the required restart.
                [void](Set-Safe120DisplayMode)
                Start-Sleep -Seconds 2
                $before = Get-TargetSnapshot -Attempts 10
            }

            Restore-SnapshotProfile -Target $before -Profile $original
            $after = Get-TargetSnapshot -Attempts 10
            if ($after.ProfileId -ne [int]$original.ProfileId) {
                throw "Original profile verification failed: expected ID $($original.ProfileId), got $($after.ProfileId)."
            }

            if ($knownExperimentalOverride) {
                Remove-ItemProperty -LiteralPath $registryContext.OverridePath -Name '0' -ErrorAction Stop
                Remove-ItemProperty -LiteralPath $registryContext.OverridePath -Name '1' -ErrorAction Stop
                $overrideState = Get-EdidOverrideState -RegistryContext $registryContext -ExperimentalEdids $experimentalEdids
                if ($overrideState.State -ne 'NONE') {
                    throw 'The ClawLab custom EDID override could not be removed completely.'
                }
            }
            Remove-StartupReapply
            Restore-IntelStartupOrder
            Remove-FileIfPresent -LiteralPath $backupPath
            Remove-FileIfPresent -LiteralPath $experimentalStatePath
            Remove-FileIfPresent -LiteralPath $managedModeStatePath
            Write-Host "Restored the original Intel Arc Sync profile: $($after.ProfileName)." -ForegroundColor Green
            Write-Host 'Restart the PC to make Windows reload the physical panel EDID.' -ForegroundColor Yellow
            $status = Get-StatusObject -Panel $panel -Gpu $gpu -Snapshot $after -OverrideState $overrideState
            $status.RestartRequired = $true
            $status
        }
    }
}
catch {
    if ($Action -eq 'ApplyStartup') {
        try { Write-StartupResult -Success $false -Message $_.Exception.Message } catch {}
        try { Start-ManagedIntelGraphicsSoftware } catch {}
    }
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
