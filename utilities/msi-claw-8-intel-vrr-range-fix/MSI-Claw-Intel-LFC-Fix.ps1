[CmdletBinding()]
param(
    [ValidateSet(
        'Status', 'Apply', 'Restore', 'PrepareRestore', 'CommitRestore', 'FinalizeRestore',
        'ApplyStartup', 'FactoryDefaults'
    )]
    [string]$Action = 'Status'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$toolVersion = '2.0.7'

# Intel LFC companion for every ClawLab-managed VRR mode. It
# disables Intel's low- and high-FPS VRR solutions as one tested combination,
# preventing the observed x2 refresh-rate multiplication inside the managed
# range. This is a global display-driver setting: no game process is opened,
# injected into, patched or monitored.

$panelCatalog = @(
    [pscustomobject]@{
        Key = 'CLAW_8_AI_PLUS'
        Manufacturer = 'CSW'; ProductCode = '0801'; Name = 'PN8007QB1-2'
        EdidLength = 256
        PhysicalEdidHash = 'E49BC570225510B7C889ED292570F1345CAA07F5840DB57EA6998A403DB5CEF0'
        Experimental30EdidHash = '14CDDC390CF69367C4B6821A46728518200446A33F708A1A87CA673B68B66918'
        Legacy48_144EdidHash = '4CFB165CE96119BA37A07176F9D346691D447E0A40E8697777E499E1556A744E'
        Legacy30_144EdidHash = '0B8E8A25325B4D9CAC2B6A03CF9B574688B1A6D2DEDF10401605C4898E0CAC05'
        SupportsLegacy144Recovery = $true
        Overclock48_144EdidHash = '4CFB165CE96119BA37A07176F9D346691D447E0A40E8697777E499E1556A744E'
        Overclock48_165EdidHash = 'FBB2CEFA8A0CC36CD5231D1070D4271165CAB9EA43A22271E3B2FD49D6914677'
        Overclock48_180EdidHash = '279EA02FF5AEB3FA474235ECFCD3119AE7845A969C2F6BB7A63866CC3151EF62'
        Overclock48_192EdidHash = 'DC60F9E3CC7B33C4F094181C57E4AF271C1BFB4449AFDE2614B4EAC27C032752'
        Overclock30_144EdidHash = '0B8E8A25325B4D9CAC2B6A03CF9B574688B1A6D2DEDF10401605C4898E0CAC05'
        Overclock30_165EdidHash = '8EDC82A04D9E1FAD037CA4D794D53BD0D374C9554059B137E75C40D9F9C416A7'
        Overclock30_180EdidHash = '0D1969CF0C7CFBA3CF9F077667C1427E202DB895DFA0A750FAF1323F57A88E4B'
        Overclock30_192EdidHash = '949A7143DB4549FC7D0D36F9F2521A528C1C796DE8F3F1FA948E4B3DBF5ECED6'
    },
    [pscustomobject]@{
        Key = 'CLAW_A1M_CLAW_7_AI_PLUS'
        Manufacturer = 'TMA'; ProductCode = '2027'; Name = 'TL070FVXS02-0'
        EdidLength = 128
        PhysicalEdidHash = '3518AB4456669D12A7B8D254F63005EAE143C784DCE02EC56C3753C41A664CA1'
        Experimental30EdidHash = '7B5EE7D96BC91E83EBD2419B3A4F12771035D76303F77EEB0E356C996BFA4647'
        Legacy48_144EdidHash = $null
        Legacy30_144EdidHash = $null
        SupportsLegacy144Recovery = $false
        Overclock48_144EdidHash = 'AF1F6DEB144767F089522C37B89C1171DE59D06107B5F5073877A5693EBC9ADB'
        Overclock48_165EdidHash = '89B0BDD6ACEB5A2320F235864314CC33CD67E4F3E4107E21573D506594E902D2'
        Overclock48_180EdidHash = '0AA3BFD4DA2D6EB8D36BBA9F87CD476D453AD86651348CC3D17E8314BD3C898D'
        Overclock48_192EdidHash = '4FA15135645E89BF10DA6B007921BA6702E03951C8FB9D2E2576F2837AD02BDE'
        Overclock30_144EdidHash = 'DFD9CBDDB7C0B8A711F026C43E3EB73165958F2E129857B97EB7EB008CB71B5E'
        Overclock30_165EdidHash = 'C0147C505E16907C62E66B56A3436870B591E1CB7B2FBA6CA410EEE3BEBDDC51'
        Overclock30_180EdidHash = 'CE853C0CB689CC6247E72E59C7965FEDCAE49479BCFD04EE7959FA3113A9D679'
        Overclock30_192EdidHash = '6553A5DA6651D29D447F0E0D14EC80CA631B1178544DA60E1CC2D54C4FAFB4C9'
    }
)
$vrrStateRoot = Join-Path $env:LOCALAPPDATA 'ClawLab\Intel-Arc-Sync-Full-Range'
$managedModePath = Join-Path $vrrStateRoot 'managed-mode.json'
$experimentalStatePath = Join-Path $vrrStateRoot 'experimental-edid.json'
$lfcStateRoot = Join-Path $env:LOCALAPPDATA 'ClawLab\Intel-LFC-Fix'
$lfcBackupPath = Join-Path $lfcStateRoot 'original-intel-vrr-solutions.json'
$lfcRestoreCommittedPath = Join-Path $lfcStateRoot 'restore-committed.json'
$lfcRestoreFinalizedPath = Join-Path $lfcStateRoot 'restore-finalized.json'
$lfcFactoryIntentPath = Join-Path $lfcStateRoot 'factory-default-intent.json'
$lfcFactoryFinalizedPath = Join-Path $lfcStateRoot 'factory-finalized.json'
$installedToolPath = Join-Path $lfcStateRoot 'MSI-Claw-Intel-LFC-Fix.ps1'
$installedDriverInterfacePath = Join-Path $lfcStateRoot 'Intel-VRR-LFC-Driver-Interface.ps1'
$backupIdentityModulePath = Join-Path $PSScriptRoot 'Lfc-Backup-Identity.ps1'
$edidNormalizationModulePath = Join-Path $PSScriptRoot 'Edid-Normalization.ps1'
$arcSyncRangePolicyModulePath = Join-Path $PSScriptRoot 'ArcSync-Range-Policy.ps1'
$scheduledTaskPersistenceModulePath = Join-Path $PSScriptRoot 'Scheduled-Task-Persistence.ps1'
$installedBackupIdentityModulePath = Join-Path $lfcStateRoot 'Lfc-Backup-Identity.ps1'
$installedEdidNormalizationModulePath = Join-Path $lfcStateRoot 'Edid-Normalization.ps1'
$installedArcSyncRangePolicyModulePath = Join-Path $lfcStateRoot 'ArcSync-Range-Policy.ps1'
$installedScheduledTaskPersistenceModulePath = Join-Path $lfcStateRoot 'Scheduled-Task-Persistence.ps1'
$installedLauncherPath = Join-Path $lfcStateRoot 'ClawLab-LFC-Startup.vbs'
$startupTaskName = 'ClawLab MSI Claw Intel LFC Fix'
$startupApplyMutexName = 'Global\ClawLab.MSIClaw.VrrApplyStartup'

foreach ($modulePath in @(
    $backupIdentityModulePath,
    $edidNormalizationModulePath,
    $arcSyncRangePolicyModulePath,
    $scheduledTaskPersistenceModulePath
)) {
    if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
        throw "A required LFC safety module is missing: $modulePath"
    }
    . $modulePath
}

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

function Write-LfcJsonFileAtomically {
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)][object]$Value
    )

    [IO.Directory]::CreateDirectory($lfcStateRoot) | Out-Null
    if (Test-Path -LiteralPath $LiteralPath) {
        throw "Atomic LFC journal creation refused because the destination already exists: $LiteralPath"
    }

    $temporaryPath = Join-Path $lfcStateRoot ('.lfc-journal-{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
    try {
        $encoding = [Text.UTF8Encoding]::new($false)
        $bytes = $encoding.GetBytes(($Value | ConvertTo-Json -Depth 8))
        $stream = [IO.FileStream]::new(
            $temporaryPath,
            [IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,
            [IO.FileShare]::None,
            4096,
            [IO.FileOptions]::WriteThrough
        )
        try {
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
        }
        finally {
            $stream.Dispose()
        }
        # Move is atomic on the same volume and refuses to replace an existing
        # destination. A crash therefore leaves either no record or one complete
        # record, never a partially written recovery journal.
        [IO.File]::Move($temporaryPath, $LiteralPath)
        if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
            throw "Atomic LFC journal readback failed: $LiteralPath"
        }
        [void]([IO.File]::ReadAllText($LiteralPath, [Text.Encoding]::UTF8) | ConvertFrom-Json)
    }
    finally {
        Remove-FileIfPresent -LiteralPath $temporaryPath
    }
}

function Get-LfcFactoryTransitionStage {
    param(
        [Parameter(Mandatory)][bool]$InitialLowFpsSolutionEnabled,
        [Parameter(Mandatory)][bool]$InitialHighFpsSolutionEnabled,
        [Parameter(Mandatory)][bool]$CurrentLowFpsSolutionEnabled,
        [Parameter(Mandatory)][bool]$CurrentHighFpsSolutionEnabled
    )

    if ($CurrentLowFpsSolutionEnabled -and $CurrentHighFpsSolutionEnabled) {
        return 'TARGET_REACHED'
    }
    if ($CurrentLowFpsSolutionEnabled -and
        $CurrentHighFpsSolutionEnabled -eq $InitialHighFpsSolutionEnabled) {
        return 'LOW_APPLIED'
    }
    if ($CurrentLowFpsSolutionEnabled -eq $InitialLowFpsSolutionEnabled -and
        $CurrentHighFpsSolutionEnabled -eq $InitialHighFpsSolutionEnabled) {
        return 'INTENT_RECORDED'
    }
    return 'UNSAFE_STATE'
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

function Get-ThirdPartyEdidOverrideValueNames {
    param([Parameter(Mandatory)][string]$OverridePath)

    if (-not (Test-Path -LiteralPath $OverridePath -PathType Container)) {
        return @()
    }

    $overrideKey = Get-Item -LiteralPath $OverridePath -ErrorAction Stop
    return @(
        $overrideKey.GetValueNames() |
            Where-Object { [string]$_ -notin @('0', '1') } |
            Sort-Object -Unique
    )
}

$script:startupTransactionMutex = $null
$script:startupApplyMutex = $null

function Enter-LfcStartupTransactionMutex {
    $mutex = [Threading.Mutex]::new($false, 'Global\ClawLab.VRR.DisplayTransaction')
    $acquired = $false
    try {
        try {
            $acquired = $mutex.WaitOne(180000)
        }
        catch [Threading.AbandonedMutexException] {
            $acquired = $true
        }
        if (-not $acquired) {
            throw 'Another ClawLab VRR transaction did not finish within three minutes.'
        }
        $script:startupTransactionMutex = $mutex
    }
    catch {
        if (-not $acquired) {
            $mutex.Dispose()
        }
        throw
    }
}

function Exit-LfcStartupTransactionMutex {
    if ($null -eq $script:startupTransactionMutex) {
        return
    }
    try {
        $script:startupTransactionMutex.ReleaseMutex()
    }
    finally {
        $script:startupTransactionMutex.Dispose()
        $script:startupTransactionMutex = $null
    }
}

function Enter-LfcStartupApplyMutex {
    $mutex = [Threading.Mutex]::new($false, $startupApplyMutexName)
    $acquired = $false
    try {
        try {
            $acquired = $mutex.WaitOne(180000)
        }
        catch [Threading.AbandonedMutexException] {
            $acquired = $true
        }
        if (-not $acquired) {
            throw 'Another ClawLab VRR startup reapply did not finish within three minutes.'
        }
        $script:startupApplyMutex = $mutex
    }
    catch {
        if (-not $acquired) {
            $mutex.Dispose()
        }
        throw
    }
}

function Exit-LfcStartupApplyMutex {
    if ($null -eq $script:startupApplyMutex) {
        return
    }
    try {
        $script:startupApplyMutex.ReleaseMutex()
    }
    finally {
        $script:startupApplyMutex.Dispose()
        $script:startupApplyMutex = $null
    }
}

if ($Action -eq 'ApplyStartup') {
    Enter-LfcStartupTransactionMutex
}

try {

$panels = [Collections.Generic.List[object]]::new()
foreach ($monitor in @(Get-CimInstance -Namespace 'root\wmi' -ClassName 'WmiMonitorID')) {
    $manufacturer = Convert-WmiText -Values $monitor.ManufacturerName
    $productCode = Convert-WmiText -Values $monitor.ProductCodeID
    $name = Convert-WmiText -Values $monitor.UserFriendlyName
    foreach ($definition in @($panelCatalog | Where-Object {
                $_.Manufacturer -eq $manufacturer -and
                $_.ProductCode -eq $productCode -and
                $_.Name -eq $name
            })) {
        $panels.Add([pscustomobject]@{
                InstanceName = [string]$monitor.InstanceName
                Manufacturer = $manufacturer
                ProductCode = $productCode
                Name = $name
                Definition = $definition
            })
    }
}
if ($panels.Count -ne 1) {
    throw 'A supported MSI Claw internal panel was not found exactly once.'
}
$panel = $panels[0]
$panelDefinition = $panel.Definition
$physicalEdidHash = [string]$panelDefinition.PhysicalEdidHash
$experimental30EdidHash = [string]$panelDefinition.Experimental30EdidHash
$validatedEdidHashes = @(
    $physicalEdidHash,
    $experimental30EdidHash,
    $panelDefinition.Legacy48_144EdidHash,
    $panelDefinition.Legacy30_144EdidHash,
    $panelDefinition.Overclock48_144EdidHash,
    $panelDefinition.Overclock48_165EdidHash,
    $panelDefinition.Overclock48_180EdidHash,
    $panelDefinition.Overclock48_192EdidHash,
    $panelDefinition.Overclock30_144EdidHash,
    $panelDefinition.Overclock30_165EdidHash,
    $panelDefinition.Overclock30_180EdidHash,
    $panelDefinition.Overclock30_192EdidHash
) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
$panelInstanceId = $panel.InstanceName -replace '_\d+$', ''
$panelDeviceParameters = "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\$panelInstanceId\Device Parameters"
$panelOverridePath = Join-Path $panelDeviceParameters 'EDID_OVERRIDE'
$thirdPartyOverrideValueNames = @(Get-ThirdPartyEdidOverrideValueNames -OverridePath $panelOverridePath)
$rawReportedEdid = [byte[]](Get-ItemPropertyValue -LiteralPath $panelDeviceParameters -Name 'EDID')
$canonicalEdid = Get-ClawLabCanonicalEdid -Bytes $rawReportedEdid -ExpectedLength ([int]$panelDefinition.EdidLength)
$reportedEdid = [byte[]]$canonicalEdid.Bytes
$reportedEdidSha256 = Get-ByteArraySha256 -Bytes $reportedEdid
if ($reportedEdidSha256 -notin $validatedEdidHashes) {
    if ($thirdPartyOverrideValueNames.Count -gt 0) {
        $listedNames = $thirdPartyOverrideValueNames -join ', '
        throw "The active panel EDID is not an approved ClawLab state and third-party override metadata is present: $listedNames. If CRU was ever used, run reset-all.exe from the current official CRU release and restart Windows before reinstalling ClawLab. Unknown EDID hash: $reportedEdidSha256"
    }
    throw "The active panel EDID is not an approved ClawLab state: $reportedEdidSha256"
}
if ($thirdPartyOverrideValueNames.Count -gt 0 -and $Action -in @('Apply', 'ApplyStartup')) {
    $listedNames = $thirdPartyOverrideValueNames -join ', '
    throw "The Intel LFC patch refused to run while third-party EDID override metadata is installed: $listedNames. If CRU was ever used, run reset-all.exe from the current official CRU release and restart Windows first."
}

$managedMode = $null
if (Test-Path -LiteralPath $managedModePath -PathType Leaf) {
    $managedMode = [IO.File]::ReadAllText($managedModePath, [Text.Encoding]::UTF8) | ConvertFrom-Json
}
$managedModeName = if ($null -eq $managedMode) { 'UNMANAGED' } else { [string]$managedMode.Mode }
$managedProfiles = @{
    'OFFICIAL_48_120' = [pscustomobject]@{ MinimumHz = 48; MaximumHz = 120; EdidSha256 = $physicalEdidHash; UsesCustomEdid = $false }
    'CLAWLAB_30_120' = [pscustomobject]@{ MinimumHz = 30; MaximumHz = 120; EdidSha256 = $experimental30EdidHash; UsesCustomEdid = $true }
}
foreach ($profile in @(
        [pscustomobject]@{ Name = 'CLAWLAB_48_144'; MinimumHz = 48; MaximumHz = 144; Hash = $panelDefinition.Overclock48_144EdidHash },
        [pscustomobject]@{ Name = 'CLAWLAB_48_165'; MinimumHz = 48; MaximumHz = 165; Hash = $panelDefinition.Overclock48_165EdidHash },
        [pscustomobject]@{ Name = 'CLAWLAB_48_180'; MinimumHz = 48; MaximumHz = 180; Hash = $panelDefinition.Overclock48_180EdidHash },
        [pscustomobject]@{ Name = 'CLAWLAB_48_192'; MinimumHz = 48; MaximumHz = 192; Hash = $panelDefinition.Overclock48_192EdidHash },
        [pscustomobject]@{ Name = 'CLAWLAB_30_144'; MinimumHz = 30; MaximumHz = 144; Hash = $panelDefinition.Overclock30_144EdidHash },
        [pscustomobject]@{ Name = 'CLAWLAB_30_165'; MinimumHz = 30; MaximumHz = 165; Hash = $panelDefinition.Overclock30_165EdidHash },
        [pscustomobject]@{ Name = 'CLAWLAB_30_180'; MinimumHz = 30; MaximumHz = 180; Hash = $panelDefinition.Overclock30_180EdidHash },
        [pscustomobject]@{ Name = 'CLAWLAB_30_192'; MinimumHz = 30; MaximumHz = 192; Hash = $panelDefinition.Overclock30_192EdidHash }
    )) {
    $managedProfiles[$profile.Name] = [pscustomobject]@{
        MinimumHz = $profile.MinimumHz
        MaximumHz = $profile.MaximumHz
        EdidSha256 = [string]$profile.Hash
        UsesCustomEdid = $true
    }
}
$managedProfile = if ($managedProfiles.ContainsKey($managedModeName)) { $managedProfiles[$managedModeName] } else { $null }
if ($Action -in @('Apply', 'ApplyStartup') -and $null -eq $managedProfile) {
    throw "The LFC fix requires an exact ClawLab-managed VRR profile; current mode is $managedModeName."
}
$expectedMinimumHz = if ($null -eq $managedProfile) { 0 } else { [int]$managedProfile.MinimumHz }
$expectedMaximumHz = if ($null -eq $managedProfile) { 0 } else { [int]$managedProfile.MaximumHz }
$expectedEdidSha256 = if ($null -eq $managedProfile) { '' } else { [string]$managedProfile.EdidSha256 }
if ($Action -eq 'ApplyStartup' -and $reportedEdidSha256 -ne $expectedEdidSha256) {
    throw "The LFC fix requires the exact $managedModeName EDID; current hash is $reportedEdidSha256."
}
if ($Action -eq 'Apply' -and $reportedEdidSha256 -ne $expectedEdidSha256) {
    if (-not [bool]$managedProfile.UsesCustomEdid -or
        $reportedEdidSha256 -ne $physicalEdidHash -or
        -not (Test-Path -LiteralPath $experimentalStatePath -PathType Leaf)) {
        throw "The pending $managedModeName EDID state could not be verified."
    }
    $pendingEdidState = [IO.File]::ReadAllText($experimentalStatePath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if ([string]$pendingEdidState.Mode -ne $managedModeName -or
        [string]$pendingEdidState.ExperimentalEdidSha256 -ne $expectedEdidSha256) {
        throw "The pending custom EDID does not match $managedModeName."
    }
}

$intelGpus = @(
    Get-CimInstance Win32_VideoController |
        Where-Object { $_.PNPDeviceID -like 'PCI\VEN_8086&*' }
)
if ($intelGpus.Count -ne 1) {
    throw "Expected exactly one Intel graphics adapter; found $($intelGpus.Count)."
}
$intelGpu = $intelGpus[0]
$driverInterfacePath = Join-Path $PSScriptRoot 'Intel-VRR-LFC-Driver-Interface.ps1'
if (-not (Test-Path -LiteralPath $driverInterfacePath -PathType Leaf)) {
    throw 'The direct Intel VRR driver interface is missing from this package.'
}

function Convert-DirectVrrState {
    param([Parameter(Mandatory)][object]$RawState)

    [pscustomobject]@{
        Result = if ([uint32]$RawState.NtStatus -eq 0) { 'Success' } else { '0x{0:X8}' -f [uint32]$RawState.NtStatus }
        Supported = [bool]$RawState.Supported
        MinimumHz = [uint32]$RawState.MinimumHz
        MaximumHz = [uint32]$RawState.MaximumHz
        VrrEnabled = [bool]$RawState.Enabled
        LowFpsSolutionEnabled = [bool]$RawState.LowFpsSolutionEnabled
        HighFpsSolutionEnabled = [bool]$RawState.HighFpsSolutionEnabled
        TargetId = [uint32]$RawState.TargetId
        DisplayDeviceName = [string]$RawState.DisplayDeviceName
    }
}

function Invoke-DirectVrrDriverAction {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Status', 'EnableLowFps', 'DisableLowFps', 'EnableHighFps', 'DisableHighFps')]
        [string]$DriverAction
    )

    $raw = & $driverInterfacePath -Action $DriverAction
    if ($null -eq $raw) {
        throw "The direct Intel VRR driver action returned no state: $DriverAction"
    }
    return Convert-DirectVrrState -RawState $raw
}

function Test-ManagedDirectRangeReady {
    param([Parameter(Mandatory)][object]$State)

    if ($null -eq $managedProfile -or -not $State.Supported -or -not $State.VrrEnabled) {
        return $false
    }
    return Test-ClawLabDirectRangeReady -PanelKey ([string]$panelDefinition.Key) `
        -DirectMinimumHz ([int]$State.MinimumHz) -DirectMaximumHz ([int]$State.MaximumHz) `
        -ExpectedMinimumHz $expectedMinimumHz -ExpectedMaximumHz $expectedMaximumHz `
        -ReportedEdidSha256 $reportedEdidSha256 -ExpectedEdidSha256 $expectedEdidSha256
}

function Get-ClawTweaksHelperTaskState {
    $service = $null
    $folder = $null
    $task = $null
    try {
        $service = New-Object -ComObject 'Schedule.Service'
        $service.Connect()
        try {
            $folder = $service.GetFolder('\ClawTweaks')
            $task = $folder.GetTask('ClawTweaksHelper')
        }
        catch {
            $hresult = ConvertTo-ClawLabHResultUInt32 -HResult ([int]$_.Exception.HResult)
            if ($hresult -in @(
                    [Convert]::ToUInt32('80070002', 16),
                    [Convert]::ToUInt32('8004130F', 16)
                )) {
                return 'NOT_INSTALLED'
            }
            throw ('Task Scheduler query failed for "\ClawTweaks\ClawTweaksHelper" with HRESULT 0x{0:X8}: {1}' -f
                $hresult, $_.Exception.Message)
        }

        $stateNames = @('Unknown', 'Disabled', 'Queued', 'Ready', 'Running')
        $stateNumber = [int]$task.State
        if ($stateNumber -ge 0 -and $stateNumber -lt $stateNames.Count) {
            return $stateNames[$stateNumber]
        }
        return "Unknown_$stateNumber"
    }
    finally {
        foreach ($comObject in @($task, $folder, $service)) {
            if ($null -ne $comObject -and [Runtime.InteropServices.Marshal]::IsComObject($comObject)) {
                [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($comObject)
            }
        }
    }
}

if ($Action -eq 'ApplyStartup') {
    $clawTweaksTaskState = Get-ClawTweaksHelperTaskState
    if ($clawTweaksTaskState -ne 'NOT_INSTALLED') {
        for ($attempt = 1; $attempt -le 30; $attempt++) {
            $clawTweaksTaskState = Get-ClawTweaksHelperTaskState
            if ($clawTweaksTaskState -eq 'Running') {
                break
            }
            Start-Sleep -Seconds 2
        }
        # ClawTweaks may restore its saved display profile during helper
        # initialization. Wait once for that initialization to settle; this is
        # deliberately not a persistent watcher.
        Start-Sleep -Seconds 8
    }

    $installedVrrToolPath = Join-Path $vrrStateRoot 'MSI-Claw-VRR-Fix.ps1'
    if (-not (Test-Path -LiteralPath $installedVrrToolPath -PathType Leaf)) {
        throw 'The installed ClawLab VRR startup tool is missing.'
    }
    # Run the range reapply in a child host. Its successful ApplyStartup path
    # deliberately calls exit 0; invoking it in this host would terminate the
    # LFC script before the Intel solution flags are reapplied.
    $windowsPowerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $windowsPowerShellPath -PathType Leaf)) {
        throw "Windows PowerShell was not found at the trusted system path: $windowsPowerShellPath"
    }
    $rangeArguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$installedVrrToolPath`" -Action ApplyStartup -StartupSource LfcTask"
    $rangeProcess = Start-Process -FilePath $windowsPowerShellPath -ArgumentList $rangeArguments `
        -WindowStyle Hidden -PassThru
    # Start-Process -Wait waits for the complete descendant process tree on
    # Windows PowerShell. Release 2.1 launches the resident Cursor Refresh
    # Helper from the VRR child, so -Wait would never return while that helper
    # correctly remains active. Wait only for the direct VRR child instead.
    $rangeProcess.WaitForExit()
    if ($rangeProcess.ExitCode -ne 0) {
        throw "The installed ClawLab VRR startup reapply failed with exit code $($rangeProcess.ExitCode)."
    }
    # The VRR child has released this second lock after its verified readback.
    # Hold it now while the Intel LFC flags are applied and verified, while the
    # parent keeps the machine-wide DisplayTransaction lock for the whole flow.
    Enter-LfcStartupApplyMutex
}
$current = Invoke-DirectVrrDriverAction -DriverAction Status
if ($Action -eq 'ApplyStartup') {
    for ($attempt = 1; $attempt -le 90; $attempt++) {
        if (Test-ManagedDirectRangeReady -State $current) {
            break
        }
        Start-Sleep -Seconds 2
        $current = Invoke-DirectVrrDriverAction -DriverAction Status
    }
}
if ($Action -eq 'ApplyStartup' -and
    -not (Test-ManagedDirectRangeReady -State $current)) {
    throw "Unexpected active VRR state for ${managedModeName}: supported=$($current.Supported), enabled=$($current.VrrEnabled), range=$($current.MinimumHz)-$($current.MaximumHz)."
}
if ($Action -eq 'Apply' -and (-not $current.Supported -or $current.Result -ne 'Success')) {
    throw 'The Intel VRR driver interface is unavailable, so the LFC state cannot be backed up safely.'
}
if ($Action -in @('Restore', 'PrepareRestore', 'CommitRestore', 'FinalizeRestore', 'FactoryDefaults') -and
    (-not $current.Supported -or $current.Result -ne 'Success')) {
    throw 'The signed Intel driver escape is unavailable, so the saved LFC state cannot be restored safely.'
}

function Get-CurrentIntelVrrState {
    Invoke-DirectVrrDriverAction -DriverAction Status
}

function Set-LowFpsSolution {
    param([Parameter(Mandatory)][bool]$Enabled)

    $driverAction = if ($Enabled) { 'EnableLowFps' } else { 'DisableLowFps' }
    $result = Invoke-DirectVrrDriverAction -DriverAction $driverAction
    if ($result.Result -ne 'Success') {
        throw "The direct Intel low-FPS driver action failed: $($result.Result)"
    }
}

function Set-HighFpsSolution {
    param([Parameter(Mandatory)][bool]$Enabled)

    $driverAction = if ($Enabled) { 'EnableHighFps' } else { 'DisableHighFps' }
    $result = Invoke-DirectVrrDriverAction -DriverAction $driverAction
    if ($result.Result -ne 'Success') {
        throw "The direct Intel high-FPS driver action failed: $($result.Result)"
    }
}

function Get-LfcBackup {
    if (-not (Test-Path -LiteralPath $lfcBackupPath -PathType Leaf)) {
        return $null
    }
    if ((Test-Path -LiteralPath $lfcRestoreCommittedPath -PathType Leaf) -or
        (Test-Path -LiteralPath $lfcFactoryIntentPath -PathType Leaf) -or
        (Test-Path -LiteralPath $lfcFactoryFinalizedPath -PathType Leaf)) {
        throw 'The active LFC backup overlaps a restore or factory-default recovery record. Recovery was refused because the transaction identity is ambiguous.'
    }
    $backup = [IO.File]::ReadAllText($lfcBackupPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $identityAction = if ($Action -in @('Status', 'PrepareRestore', 'CommitRestore', 'FinalizeRestore')) { 'Restore' } else { $Action }
    $resolution = Resolve-ClawLabLfcBackupIdentity -Backup $backup `
        -PanelManufacturer ([string]$panel.Manufacturer) `
        -PanelProductCode ([string]$panel.ProductCode) `
        -PanelName ([string]$panel.Name) `
        -PhysicalEdidSha256 $physicalEdidHash `
        -ValidatedEdidHashes $validatedEdidHashes `
        -CurrentPanelInstanceName ([string]$panel.InstanceName) `
        -CurrentManagedMode $managedModeName `
        -Action $identityAction
    if (-not $resolution.Accepted) {
        throw "The LFC backup identity was refused ($($resolution.State)): $($resolution.Reason)"
    }
    if ([int]$backup.SchemaVersion -eq 1 -and
        $Action -notin @('Restore', 'PrepareRestore', 'CommitRestore', 'FinalizeRestore')) {
        throw 'A legacy low-FPS-only experiment is still active. Restore it before applying this release.'
    }
    if ([int]$backup.SchemaVersion -in @(2, 3, 4) -and
        'OriginalHighFpsSolutionEnabled' -notin $backup.PSObject.Properties.Name) {
        throw 'The Intel VRR solution backup is invalid.'
    }

    if ($resolution.NeedsSchema4Migration) {
        $schema = [int]$backup.SchemaVersion
        $savedAt = if ('SavedAt' -in $backup.PSObject.Properties.Name) { [string]$backup.SavedAt } else { (Get-Date).ToString('o') }
        $instanceAtSave = if ($schema -eq 3) { [string]$backup.PanelInstanceName } else { [string]$backup.PanelInstanceNameAtSave }
        $edidAtSave = if ($schema -eq 3) { [string]$backup.PanelEdidSha256 } else { [string]$backup.PanelEdidSha256AtSave }
        $migrationCount = if ($schema -eq 4) { [int]$backup.InstanceMigrationCount } else { 0 }
        if ($resolution.InstanceChanged) { $migrationCount++ }
        $previousMigrationAt = if ('LastInstanceMigrationAt' -in $backup.PSObject.Properties.Name) { [string]$backup.LastInstanceMigrationAt } else { $null }
        $migrated = [ordered]@{
            SchemaVersion = 4
            SavedAt = $savedAt
            PanelManufacturer = [string]$panel.Manufacturer
            PanelProductCode = [string]$panel.ProductCode
            PanelName = [string]$panel.Name
            PhysicalEdidSha256 = $physicalEdidHash
            PanelInstanceNameAtSave = $instanceAtSave
            LastValidatedPanelInstanceName = [string]$panel.InstanceName
            PanelEdidSha256AtSave = $edidAtSave
            InstanceMigrationCount = $migrationCount
            LastInstanceMigrationAt = if ($resolution.InstanceChanged) { (Get-Date).ToString('o') } else { $previousMigrationAt }
            PanelInstanceName = [string]$panel.InstanceName
            PanelEdidSha256 = $edidAtSave
            ManagedVrrMode = [string]$backup.ManagedVrrMode
            IntelDriverVersion = if ('IntelDriverVersion' -in $backup.PSObject.Properties.Name) { [string]$backup.IntelDriverVersion } else { 'NOT_RECORDED' }
            DriverInterface = if ('DriverInterface' -in $backup.PSObject.Properties.Name) { [string]$backup.DriverInterface } else { 'DIRECT_D3DKMT_INTEL_PRIVATE_ESCAPE' }
            OriginalLowFpsSolutionEnabled = [bool]$backup.OriginalLowFpsSolutionEnabled
            OriginalHighFpsSolutionEnabled = [bool]$backup.OriginalHighFpsSolutionEnabled
        }
        Write-LfcBackupAtomically -Backup $migrated
        $backup = [IO.File]::ReadAllText($lfcBackupPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $postMigration = Resolve-ClawLabLfcBackupIdentity -Backup $backup `
            -PanelManufacturer ([string]$panel.Manufacturer) `
            -PanelProductCode ([string]$panel.ProductCode) `
            -PanelName ([string]$panel.Name) `
            -PhysicalEdidSha256 $physicalEdidHash `
            -ValidatedEdidHashes $validatedEdidHashes `
            -CurrentPanelInstanceName ([string]$panel.InstanceName) `
            -CurrentManagedMode $managedModeName `
            -Action $identityAction
        if (-not $postMigration.Accepted -or $postMigration.NeedsSchema4Migration) {
            throw "The migrated schema-4 LFC backup failed readback verification: $($postMigration.State)"
        }
    }
    return $backup
}

function Get-LfcRestoreCommittedRecord {
    if (-not (Test-Path -LiteralPath $lfcRestoreCommittedPath -PathType Leaf)) {
        return $null
    }
    if (Test-Path -LiteralPath $lfcBackupPath -PathType Leaf) {
        throw 'Both the active LFC backup and restore-commit tombstone exist. Recovery was refused because the transaction identity is ambiguous.'
    }
    $record = [IO.File]::ReadAllText($lfcRestoreCommittedPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $resolution = Resolve-ClawLabLfcBackupIdentity -Backup $record `
        -PanelManufacturer ([string]$panel.Manufacturer) `
        -PanelProductCode ([string]$panel.ProductCode) `
        -PanelName ([string]$panel.Name) `
        -PhysicalEdidSha256 $physicalEdidHash `
        -ValidatedEdidHashes $validatedEdidHashes `
        -CurrentPanelInstanceName ([string]$panel.InstanceName) `
        -CurrentManagedMode $managedModeName `
        -Action Restore
    if (-not $resolution.Accepted) {
        throw "The LFC restore-commit tombstone identity was refused ($($resolution.State)): $($resolution.Reason)"
    }
    if ([int]$record.SchemaVersion -in @(2, 3, 4) -and
        'OriginalHighFpsSolutionEnabled' -notin $record.PSObject.Properties.Name) {
        throw 'The LFC restore-commit tombstone is invalid.'
    }
    return $record
}

function Get-LfcRestoreFinalizedRecord {
    if (-not (Test-Path -LiteralPath $lfcRestoreFinalizedPath -PathType Leaf)) {
        return $null
    }
    if ((Test-Path -LiteralPath $lfcBackupPath -PathType Leaf) -or
        (Test-Path -LiteralPath $lfcRestoreCommittedPath -PathType Leaf)) {
        throw 'The finalized LFC restore provenance overlaps another active recovery record. Recovery was refused because the transaction identity is ambiguous.'
    }
    $record = [IO.File]::ReadAllText($lfcRestoreFinalizedPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $resolution = Resolve-ClawLabLfcBackupIdentity -Backup $record `
        -PanelManufacturer ([string]$panel.Manufacturer) `
        -PanelProductCode ([string]$panel.ProductCode) `
        -PanelName ([string]$panel.Name) `
        -PhysicalEdidSha256 $physicalEdidHash `
        -ValidatedEdidHashes $validatedEdidHashes `
        -CurrentPanelInstanceName ([string]$panel.InstanceName) `
        -CurrentManagedMode $managedModeName `
        -Action Restore
    if (-not $resolution.Accepted) {
        throw "The finalized LFC restore provenance was refused ($($resolution.State)): $($resolution.Reason)"
    }
    if ([int]$record.SchemaVersion -in @(2, 3, 4) -and
        'OriginalHighFpsSolutionEnabled' -notin $record.PSObject.Properties.Name) {
        throw 'The finalized LFC restore provenance is invalid.'
    }
    return $record
}

function Get-LfcFactoryFinalizedRecord {
    param([AllowNull()][string]$ExpectedTransactionId)

    if (-not (Test-Path -LiteralPath $lfcFactoryFinalizedPath -PathType Leaf)) {
        return $null
    }
    if ((Test-Path -LiteralPath $lfcBackupPath -PathType Leaf) -or
        (Test-Path -LiteralPath $lfcRestoreCommittedPath -PathType Leaf)) {
        throw 'The factory-finalized LFC provenance overlaps an active backup or restore tombstone. Recovery was refused because the transaction identity is ambiguous.'
    }

    $record = [IO.File]::ReadAllText($lfcFactoryFinalizedPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($property in @(
            'SchemaVersion', 'FactoryProvenanceSchemaVersion', 'FactoryTransactionId',
            'FactorySourceKind', 'FactorySourceSha256',
            'OriginalLowFpsSolutionEnabled', 'OriginalHighFpsSolutionEnabled'
        )) {
        if ($property -notin $record.PSObject.Properties.Name) {
            throw "The factory-finalized LFC provenance is missing $property."
        }
    }
    $transactionGuid = [Guid]::Empty
    if ([int]$record.SchemaVersion -ne 4 -or
        [int]$record.FactoryProvenanceSchemaVersion -ne 1 -or
        -not [Guid]::TryParse([string]$record.FactoryTransactionId, [ref]$transactionGuid) -or
        -not ($record.OriginalLowFpsSolutionEnabled -is [bool]) -or
        -not ($record.OriginalHighFpsSolutionEnabled -is [bool]) -or
        -not [bool]$record.OriginalLowFpsSolutionEnabled -or
        -not [bool]$record.OriginalHighFpsSolutionEnabled -or
        [string]$record.FactorySourceKind -notin @('RESTORE_FINALIZED', 'CURRENT_STATE_NO_PROVENANCE')) {
        throw 'The factory-finalized LFC provenance is invalid.'
    }
    if (([string]$record.FactorySourceKind -eq 'RESTORE_FINALIZED' -and
            [string]$record.FactorySourceSha256 -notmatch '^[0-9A-Fa-f]{64}$') -or
        ([string]$record.FactorySourceKind -eq 'CURRENT_STATE_NO_PROVENANCE' -and
            -not [string]::IsNullOrEmpty([string]$record.FactorySourceSha256))) {
        throw 'The factory-finalized LFC provenance has an invalid source binding.'
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedTransactionId) -and
        [string]$record.FactoryTransactionId -ne $ExpectedTransactionId) {
        throw 'The factory-finalized LFC provenance belongs to a different factory-default transaction.'
    }

    $resolution = Resolve-ClawLabLfcBackupIdentity -Backup $record `
        -PanelManufacturer ([string]$panel.Manufacturer) `
        -PanelProductCode ([string]$panel.ProductCode) `
        -PanelName ([string]$panel.Name) `
        -PhysicalEdidSha256 $physicalEdidHash `
        -ValidatedEdidHashes $validatedEdidHashes `
        -CurrentPanelInstanceName ([string]$panel.InstanceName) `
        -CurrentManagedMode $managedModeName `
        -Action Restore
    if (-not $resolution.Accepted) {
        throw "The factory-finalized LFC provenance identity was refused ($($resolution.State)): $($resolution.Reason)"
    }
    return $record
}

function Get-LfcFactoryIntentRecord {
    if (-not (Test-Path -LiteralPath $lfcFactoryIntentPath -PathType Leaf)) {
        return $null
    }
    if ((Test-Path -LiteralPath $lfcBackupPath -PathType Leaf) -or
        (Test-Path -LiteralPath $lfcRestoreCommittedPath -PathType Leaf)) {
        throw 'The factory-default intent overlaps an active LFC backup or restore tombstone. Recovery was refused because the transaction identity is ambiguous.'
    }

    $record = [IO.File]::ReadAllText($lfcFactoryIntentPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($property in @(
            'SchemaVersion', 'TransactionId', 'CreatedAt', 'PanelManufacturer',
            'PanelProductCode', 'PanelName', 'PhysicalEdidSha256', 'PanelInstanceName',
            'PanelEdidSha256', 'ManagedVrrMode', 'IntelDriverVersion',
            'InitialLowFpsSolutionEnabled', 'InitialHighFpsSolutionEnabled',
            'TargetLowFpsSolutionEnabled', 'TargetHighFpsSolutionEnabled',
            'SourceKind', 'SourceRestoreFinalizedSha256'
        )) {
        if ($property -notin $record.PSObject.Properties.Name) {
            throw "The LFC factory-default intent is missing $property."
        }
    }
    $transactionGuid = [Guid]::Empty
    if ([int]$record.SchemaVersion -ne 1 -or
        -not [Guid]::TryParse([string]$record.TransactionId, [ref]$transactionGuid) -or
        -not ($record.InitialLowFpsSolutionEnabled -is [bool]) -or
        -not ($record.InitialHighFpsSolutionEnabled -is [bool]) -or
        -not ($record.TargetLowFpsSolutionEnabled -is [bool]) -or
        -not ($record.TargetHighFpsSolutionEnabled -is [bool]) -or
        -not [bool]$record.TargetLowFpsSolutionEnabled -or
        -not [bool]$record.TargetHighFpsSolutionEnabled -or
        [string]$record.SourceKind -notin @('RESTORE_FINALIZED', 'CURRENT_STATE_NO_PROVENANCE')) {
        throw 'The LFC factory-default intent is invalid.'
    }
    if ([string]$record.PanelManufacturer -ne [string]$panel.Manufacturer -or
        [string]$record.PanelProductCode -ne [string]$panel.ProductCode -or
        [string]$record.PanelName -ne [string]$panel.Name -or
        [string]$record.PhysicalEdidSha256 -ne $physicalEdidHash -or
        [string]$record.PanelInstanceName -ne [string]$panel.InstanceName -or
        [string]$record.PanelEdidSha256 -ne $reportedEdidSha256 -or
        [string]$record.PanelEdidSha256 -notin $validatedEdidHashes -or
        [string]$record.ManagedVrrMode -ne $managedModeName -or
        [string]$record.IntelDriverVersion -ne [string]$intelGpu.DriverVersion) {
        throw 'The LFC factory-default intent no longer matches the exact driver, panel, EDID and managed-mode identity that created it.'
    }

    $factoryFinalizedPresent = Test-Path -LiteralPath $lfcFactoryFinalizedPath -PathType Leaf
    if ([string]$record.SourceKind -eq 'RESTORE_FINALIZED') {
        if ([string]$record.SourceRestoreFinalizedSha256 -notmatch '^[0-9A-Fa-f]{64}$') {
            throw 'The LFC factory-default intent has no valid source-provenance hash.'
        }
        if (Test-Path -LiteralPath $lfcRestoreFinalizedPath -PathType Leaf) {
            $actualSourceHash = (Get-FileHash -LiteralPath $lfcRestoreFinalizedPath -Algorithm SHA256).Hash
            if ($actualSourceHash -ne [string]$record.SourceRestoreFinalizedSha256) {
                throw 'The retained restore-finalized provenance does not match the factory-default intent.'
            }
        }
        elseif (-not $factoryFinalizedPresent) {
            throw 'The factory-default intent lost its source provenance before durable factory finalization.'
        }
    }
    elseif (-not [string]::IsNullOrEmpty([string]$record.SourceRestoreFinalizedSha256) -or
        (Test-Path -LiteralPath $lfcRestoreFinalizedPath -PathType Leaf)) {
        throw 'A factory-default intent without restore provenance overlaps unexpected restore provenance.'
    }

    if ($factoryFinalizedPresent) {
        [void](Get-LfcFactoryFinalizedRecord -ExpectedTransactionId ([string]$record.TransactionId))
    }
    return $record
}

function Assert-LfcFactoryFinalizedMatchesCurrentState {
    param([Parameter(Mandatory)][object]$Record)

    if ((Get-StartupPersistenceState) -ne 'NOT_INSTALLED') {
        throw 'Intel LFC factory finalization requires startup persistence to be absent.'
    }
    $after = Get-CurrentIntelVrrState
    if ($after.Result -ne 'Success' -or
        -not $after.LowFpsSolutionEnabled -or
        -not $after.HighFpsSolutionEnabled) {
        throw "The durable Intel LFC factory provenance does not match the current driver flags: $($after | ConvertTo-Json -Compress)"
    }
    return $after
}

function Get-LfcFactoryIntentStage {
    param(
        [Parameter(Mandatory)][object]$Intent,
        [AllowNull()][object]$CurrentState
    )

    $now = if ($null -eq $CurrentState) { Get-CurrentIntelVrrState } else { $CurrentState }
    if ($now.Result -ne 'Success') {
        throw 'The Intel LFC factory-default transaction cannot read the current driver flags.'
    }
    $stage = Get-LfcFactoryTransitionStage `
        -InitialLowFpsSolutionEnabled ([bool]$Intent.InitialLowFpsSolutionEnabled) `
        -InitialHighFpsSolutionEnabled ([bool]$Intent.InitialHighFpsSolutionEnabled) `
        -CurrentLowFpsSolutionEnabled ([bool]$now.LowFpsSolutionEnabled) `
        -CurrentHighFpsSolutionEnabled ([bool]$now.HighFpsSolutionEnabled)
    if ($stage -eq 'UNSAFE_STATE') {
        throw "The current Intel LFC flags are not a safe prefix of the retained factory-default transaction: $($now | ConvertTo-Json -Compress)"
    }
    return [pscustomobject]@{ Stage = $stage; Current = $now }
}

function New-LfcFactoryIntentRecord {
    param(
        [Parameter(Mandatory)][object]$CurrentState,
        [AllowNull()][object]$RestoreFinalizedRecord
    )

    $sourceKind = if ($null -eq $RestoreFinalizedRecord) {
        'CURRENT_STATE_NO_PROVENANCE'
    }
    else {
        'RESTORE_FINALIZED'
    }
    $sourceHash = if ($sourceKind -eq 'RESTORE_FINALIZED') {
        (Get-FileHash -LiteralPath $lfcRestoreFinalizedPath -Algorithm SHA256).Hash
    }
    else {
        ''
    }
    return [ordered]@{
        SchemaVersion = 1
        TransactionId = [Guid]::NewGuid().ToString('D')
        CreatedAt = (Get-Date).ToString('o')
        PanelManufacturer = [string]$panel.Manufacturer
        PanelProductCode = [string]$panel.ProductCode
        PanelName = [string]$panel.Name
        PhysicalEdidSha256 = $physicalEdidHash
        PanelInstanceName = [string]$panel.InstanceName
        PanelEdidSha256 = $reportedEdidSha256
        ManagedVrrMode = $managedModeName
        IntelDriverVersion = [string]$intelGpu.DriverVersion
        InitialLowFpsSolutionEnabled = [bool]$CurrentState.LowFpsSolutionEnabled
        InitialHighFpsSolutionEnabled = [bool]$CurrentState.HighFpsSolutionEnabled
        TargetLowFpsSolutionEnabled = $true
        TargetHighFpsSolutionEnabled = $true
        SourceKind = $sourceKind
        SourceRestoreFinalizedSha256 = $sourceHash
    }
}

function New-LfcFactoryFinalizedRecord {
    param([Parameter(Mandatory)][object]$Intent)

    return [ordered]@{
        SchemaVersion = 4
        SavedAt = (Get-Date).ToString('o')
        PanelManufacturer = [string]$panel.Manufacturer
        PanelProductCode = [string]$panel.ProductCode
        PanelName = [string]$panel.Name
        PhysicalEdidSha256 = $physicalEdidHash
        PanelInstanceNameAtSave = [string]$panel.InstanceName
        LastValidatedPanelInstanceName = [string]$panel.InstanceName
        PanelEdidSha256AtSave = $reportedEdidSha256
        InstanceMigrationCount = 0
        LastInstanceMigrationAt = $null
        PanelInstanceName = [string]$panel.InstanceName
        PanelEdidSha256 = $reportedEdidSha256
        ManagedVrrMode = $managedModeName
        IntelDriverVersion = [string]$intelGpu.DriverVersion
        DriverInterface = 'DIRECT_D3DKMT_INTEL_PRIVATE_ESCAPE'
        OriginalLowFpsSolutionEnabled = $true
        OriginalHighFpsSolutionEnabled = $true
        FactoryProvenanceSchemaVersion = 1
        FactoryTransactionId = [string]$Intent.TransactionId
        FactoryFinalizedAt = (Get-Date).ToString('o')
        FactorySourceKind = [string]$Intent.SourceKind
        FactorySourceSha256 = [string]$Intent.SourceRestoreFinalizedSha256
    }
}

function Complete-LfcFactoryDefaultsTransaction {
    param([Parameter(Mandatory)][object]$Intent)

    $progress = Get-LfcFactoryIntentStage -Intent $Intent
    if (-not [bool]$progress.Current.LowFpsSolutionEnabled) {
        Set-LowFpsSolution -Enabled $true
        Start-Sleep -Milliseconds 150
        $progress = Get-LfcFactoryIntentStage -Intent $Intent
        if (-not [bool]$progress.Current.LowFpsSolutionEnabled) {
            throw 'Intel did not retain the low-FPS factory-default flag.'
        }
    }
    if (-not [bool]$progress.Current.HighFpsSolutionEnabled) {
        Set-HighFpsSolution -Enabled $true
        Start-Sleep -Milliseconds 150
        $progress = Get-LfcFactoryIntentStage -Intent $Intent
    }
    if ([string]$progress.Stage -ne 'TARGET_REACHED') {
        throw "Intel LFC factory-default transition stopped before its true/true target: $($progress.Current | ConvertTo-Json -Compress)"
    }

    Start-Sleep -Milliseconds 750
    $after = Get-CurrentIntelVrrState
    if ($after.Result -ne 'Success' -or
        -not $after.LowFpsSolutionEnabled -or
        -not $after.HighFpsSolutionEnabled) {
        throw "Intel LFC factory-default verification failed: $($after | ConvertTo-Json -Compress)"
    }

    if (-not (Test-Path -LiteralPath $lfcFactoryFinalizedPath -PathType Leaf)) {
        $factoryRecord = New-LfcFactoryFinalizedRecord -Intent $Intent
        Write-LfcJsonFileAtomically -LiteralPath $lfcFactoryFinalizedPath -Value $factoryRecord
    }
    $verifiedFactoryRecord = Get-LfcFactoryFinalizedRecord -ExpectedTransactionId ([string]$Intent.TransactionId)
    [void](Assert-LfcFactoryFinalizedMatchesCurrentState -Record $verifiedFactoryRecord)

    # The target provenance is durable before the source provenance is retired.
    # A crash before either delete is therefore resumed from the same exact WAL.
    if (Test-Path -LiteralPath $lfcRestoreFinalizedPath -PathType Leaf) {
        if ([string]$Intent.SourceKind -ne 'RESTORE_FINALIZED' -or
            (Get-FileHash -LiteralPath $lfcRestoreFinalizedPath -Algorithm SHA256).Hash -ne
                [string]$Intent.SourceRestoreFinalizedSha256) {
            throw 'Factory-default cleanup refused to retire an unbound restore-finalized provenance.'
        }
        Remove-FileIfPresent -LiteralPath $lfcRestoreFinalizedPath
    }
    Remove-FileIfPresent -LiteralPath $lfcFactoryIntentPath
    if ((Test-Path -LiteralPath $lfcFactoryIntentPath) -or
        (Test-Path -LiteralPath $lfcRestoreFinalizedPath) -or
        -not (Test-Path -LiteralPath $lfcFactoryFinalizedPath -PathType Leaf)) {
        throw 'Intel LFC factory-default finalization could not retain one unambiguous durable provenance.'
    }
    return $after
}

function Activate-LfcFinalizedProvenanceForApply {
    if (Test-Path -LiteralPath $lfcFactoryIntentPath -PathType Leaf) {
        [void](Get-LfcFactoryIntentRecord)
        throw 'An interrupted Intel LFC factory-default transaction must be resumed with the emergency Factory Defaults action before applying a managed profile.'
    }

    $restoreRecord = Get-LfcRestoreFinalizedRecord
    $factoryRecord = Get-LfcFactoryFinalizedRecord
    if ($null -ne $restoreRecord -and $null -ne $factoryRecord) {
        throw 'Both restore-finalized and factory-finalized LFC provenance exist without an active transaction. Recovery was refused because ownership is ambiguous.'
    }
    $sourcePath = $null
    $record = $null
    if ($null -ne $restoreRecord) {
        $sourcePath = $lfcRestoreFinalizedPath
        $record = $restoreRecord
        [void](Assert-LfcRestoreRecordMatchesCurrentState -Record $record)
    }
    elseif ($null -ne $factoryRecord) {
        $sourcePath = $lfcFactoryFinalizedPath
        $record = $factoryRecord
        [void](Assert-LfcFactoryFinalizedMatchesCurrentState -Record $record)
    }
    else {
        return
    }

    [IO.Directory]::CreateDirectory($lfcStateRoot) | Out-Null
    [IO.File]::Move($sourcePath, $lfcBackupPath)
    if (-not (Test-Path -LiteralPath $lfcBackupPath -PathType Leaf) -or
        (Test-Path -LiteralPath $sourcePath)) {
        throw 'The finalized LFC original-state provenance could not be reactivated atomically.'
    }

    # A finalized provenance marker may come from a different previously
    # restored ClawLab range. Rebind only its managed-mode ownership while
    # preserving the exact original Intel flags and stable panel identity.
    $reactivated = [IO.File]::ReadAllText($lfcBackupPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if ('ManagedVrrMode' -in $reactivated.PSObject.Properties.Name) {
        $reactivated.ManagedVrrMode = $managedModeName
    }
    else {
        $reactivated | Add-Member -NotePropertyName ManagedVrrMode -NotePropertyValue $managedModeName
    }
    Write-LfcBackupAtomically -Backup $reactivated
}

function Assert-LfcRestoreRecordMatchesCurrentState {
    param([Parameter(Mandatory)][object]$Record)

    if ((Get-StartupPersistenceState) -ne 'NOT_INSTALLED') {
        throw 'Intel LFC restore cannot commit or finalize while startup persistence is still installed.'
    }
    $after = Get-CurrentIntelVrrState
    $expectedHigh = if ([int]$Record.SchemaVersion -in @(2, 3, 4)) {
        [bool]$Record.OriginalHighFpsSolutionEnabled
    }
    else {
        [bool]$after.HighFpsSolutionEnabled
    }
    if ($after.Result -ne 'Success' -or
        $after.LowFpsSolutionEnabled -ne [bool]$Record.OriginalLowFpsSolutionEnabled -or
        $after.HighFpsSolutionEnabled -ne $expectedHigh) {
        throw "Intel LFC restore verification failed because the current flags do not match the retained recovery record: $($after | ConvertTo-Json -Compress)"
    }
    return $after
}

function Write-LfcBackupAtomically {
    param([Parameter(Mandatory)][object]$Backup)

    [IO.Directory]::CreateDirectory($lfcStateRoot) | Out-Null
    $temporaryPath = Join-Path $lfcStateRoot ('.lfc-backup-{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
    $replacementBackupPath = Join-Path $lfcStateRoot ('.lfc-previous-{0}.bak' -f [Guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText($temporaryPath, ($Backup | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $lfcBackupPath -PathType Leaf) {
            # Windows PowerShell/.NET rejects a null destination-backup path.
            # A real same-directory path preserves atomic replacement and is
            # removed only after Replace returns successfully.
            [IO.File]::Replace($temporaryPath, $lfcBackupPath, $replacementBackupPath)
            Remove-FileIfPresent -LiteralPath $replacementBackupPath
        }
        else {
            [IO.File]::Move($temporaryPath, $lfcBackupPath)
        }
    }
    finally {
        Remove-FileIfPresent -LiteralPath $temporaryPath
        Remove-FileIfPresent -LiteralPath $replacementBackupPath
    }
}

function Get-LfcBackupIdentityStatus {
    if (-not (Test-Path -LiteralPath $lfcBackupPath -PathType Leaf)) {
        return [pscustomobject]@{ SchemaVersion = 0; State = 'NO_BACKUP'; Accepted = $true; InstanceChanged = $false }
    }
    try {
        $backup = [IO.File]::ReadAllText($lfcBackupPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $resolution = Resolve-ClawLabLfcBackupIdentity -Backup $backup `
            -PanelManufacturer ([string]$panel.Manufacturer) `
            -PanelProductCode ([string]$panel.ProductCode) `
            -PanelName ([string]$panel.Name) `
            -PhysicalEdidSha256 $physicalEdidHash `
            -ValidatedEdidHashes $validatedEdidHashes `
            -CurrentPanelInstanceName ([string]$panel.InstanceName) `
            -CurrentManagedMode $managedModeName `
            -Action Restore
        return [pscustomobject]@{
            SchemaVersion = [int]$backup.SchemaVersion
            State = [string]$resolution.State
            Accepted = [bool]$resolution.Accepted
            InstanceChanged = [bool]$resolution.InstanceChanged
        }
    }
    catch {
        return [pscustomobject]@{ SchemaVersion = -1; State = 'INVALID_BACKUP'; Accepted = $false; InstanceChanged = $false }
    }
}

function Get-StartupPersistenceState {
    $task = Get-ClawLabScheduledTaskRecord -TaskName $startupTaskName
    $payloadPaths = @(
        $installedToolPath,
        $installedDriverInterfacePath,
        $installedBackupIdentityModulePath,
        $installedEdidNormalizationModulePath,
        $installedArcSyncRangePolicyModulePath,
        $installedScheduledTaskPersistenceModulePath,
        $installedLauncherPath
    )
    $missingPayload = @($payloadPaths | Where-Object {
        -not (Test-Path -LiteralPath $_ -PathType Leaf)
    })

    if ($null -eq $task) {
        if ($missingPayload.Count -eq $payloadPaths.Count) {
            return 'NOT_INSTALLED'
        }
        return 'ORPHANED_PAYLOAD'
    }
    if ($missingPayload.Count -gt 0) {
        return 'INCOMPLETE'
    }

    $validation = Test-ClawLabScheduledTaskRecord -Record $task -Spec (Get-StartupTaskSpec)
    if (-not $validation.Valid) {
        return 'INVALID_TASK_CONFIGURATION'
    }
    return 'INSTALLED_ONE_SHOT_AT_LOGON'
}

function Get-StartupTaskSpec {
    $wscriptPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
    return New-ClawLabLogonTaskSpec `
        -TaskName $startupTaskName `
        -ExecutePath $wscriptPath `
        -Arguments "//B //Nologo `"$installedLauncherPath`"" `
        -Description 'Silently reapplies the selected ClawLab VRR range and Intel LFC state once at logon, then exits.' `
        -ExecutionTimeLimitMinutes 12 `
        -TriggerDelaySeconds 15
}

function Install-StartupPersistence {
    $sourceLauncherPath = Join-Path $PSScriptRoot 'ClawLab-LFC-Startup.vbs'
    if (-not (Test-Path -LiteralPath $sourceLauncherPath -PathType Leaf)) {
        throw 'The windowless one-shot startup launcher is missing from this package.'
    }
    [IO.Directory]::CreateDirectory($lfcStateRoot) | Out-Null
    [IO.File]::Copy($PSCommandPath, $installedToolPath, $true)
    [IO.File]::Copy($driverInterfacePath, $installedDriverInterfacePath, $true)
    [IO.File]::Copy($backupIdentityModulePath, $installedBackupIdentityModulePath, $true)
    [IO.File]::Copy($edidNormalizationModulePath, $installedEdidNormalizationModulePath, $true)
    [IO.File]::Copy($arcSyncRangePolicyModulePath, $installedArcSyncRangePolicyModulePath, $true)
    [IO.File]::Copy($scheduledTaskPersistenceModulePath, $installedScheduledTaskPersistenceModulePath, $true)
    [IO.File]::Copy($sourceLauncherPath, $installedLauncherPath, $true)

    foreach ($pair in @(
        @($PSCommandPath, $installedToolPath),
        @($driverInterfacePath, $installedDriverInterfacePath),
        @($backupIdentityModulePath, $installedBackupIdentityModulePath),
        @($edidNormalizationModulePath, $installedEdidNormalizationModulePath),
        @($arcSyncRangePolicyModulePath, $installedArcSyncRangePolicyModulePath),
        @($scheduledTaskPersistenceModulePath, $installedScheduledTaskPersistenceModulePath),
        @($sourceLauncherPath, $installedLauncherPath)
    )) {
        if ((Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash -ne
            (Get-FileHash -LiteralPath $pair[1] -Algorithm SHA256).Hash) {
            throw "Startup persistence copy verification failed: $($pair[1])"
        }
    }

    [void](Install-ClawLabScheduledTask -Spec (Get-StartupTaskSpec))
    if ((Get-StartupPersistenceState) -ne 'INSTALLED_ONE_SHOT_AT_LOGON') {
        throw 'The one-shot startup persistence task could not be verified.'
    }
}

function Remove-StartupPersistence {
    # The task must be confirmed absent before its executable payload is
    # removed. This prevents an orphaned registered task from targeting files
    # that a failed cleanup already deleted.
    [void](Remove-ClawLabScheduledTask -Spec (Get-StartupTaskSpec) -AllowAbsent)
    Remove-FileIfPresent -LiteralPath $installedToolPath
    Remove-FileIfPresent -LiteralPath $installedDriverInterfacePath
    Remove-FileIfPresent -LiteralPath $installedBackupIdentityModulePath
    Remove-FileIfPresent -LiteralPath $installedEdidNormalizationModulePath
    Remove-FileIfPresent -LiteralPath $installedArcSyncRangePolicyModulePath
    Remove-FileIfPresent -LiteralPath $installedScheduledTaskPersistenceModulePath
    Remove-FileIfPresent -LiteralPath $installedLauncherPath
    if ((Get-StartupPersistenceState) -ne 'NOT_INSTALLED') {
        throw 'The one-shot startup persistence task was not fully removed.'
    }
}

$state = switch ($Action) {
    'Status' {
        $now = Get-CurrentIntelVrrState
        $statusBackupIdentity = Get-LfcBackupIdentityStatus
        $restoreTombstonePresent = Test-Path -LiteralPath $lfcRestoreCommittedPath -PathType Leaf
        $restoreTombstoneRecord = if ($restoreTombstonePresent) {
            Get-LfcRestoreCommittedRecord
        }
        else {
            $null
        }
        $restoreFinalizedPresent = Test-Path -LiteralPath $lfcRestoreFinalizedPath -PathType Leaf
        $restoreFinalizedRecord = if ($restoreFinalizedPresent) {
            Get-LfcRestoreFinalizedRecord
        }
        else {
            $null
        }
        $factoryIntentPresent = Test-Path -LiteralPath $lfcFactoryIntentPath -PathType Leaf
        $factoryIntentRecord = if ($factoryIntentPresent) {
            Get-LfcFactoryIntentRecord
        }
        else {
            $null
        }
        $factoryFinalizedPresent = Test-Path -LiteralPath $lfcFactoryFinalizedPath -PathType Leaf
        $factoryFinalizedRecord = if ($factoryFinalizedPresent) {
            Get-LfcFactoryFinalizedRecord -ExpectedTransactionId $(
                if ($null -eq $factoryIntentRecord) { $null } else { [string]$factoryIntentRecord.TransactionId }
            )
        }
        else {
            $null
        }
        if ($null -eq $factoryIntentRecord -and
            $null -ne $restoreFinalizedRecord -and
            $null -ne $factoryFinalizedRecord) {
            throw 'Restore-finalized and factory-finalized LFC provenance overlap without their binding transaction intent.'
        }

        $factoryIntentStage = $null
        $restoreFinalizedStateVerified = $false
        if ($null -ne $factoryIntentRecord) {
            $factoryIntentStage = Get-LfcFactoryIntentStage -Intent $factoryIntentRecord -CurrentState $now
            if ($null -ne $factoryFinalizedRecord) {
                [void](Assert-LfcFactoryFinalizedMatchesCurrentState -Record $factoryFinalizedRecord)
            }
        }
        elseif ($null -ne $factoryFinalizedRecord) {
            [void](Assert-LfcFactoryFinalizedMatchesCurrentState -Record $factoryFinalizedRecord)
        }
        elseif ($null -ne $restoreFinalizedRecord) {
            [void](Assert-LfcRestoreRecordMatchesCurrentState -Record $restoreFinalizedRecord)
            $restoreFinalizedStateVerified = $true
        }
        [pscustomobject]@{
            State = if ($factoryIntentPresent -and $factoryFinalizedPresent) {
                'INTEL_VRR_SOLUTIONS_FACTORY_DEFAULTS_FINALIZATION_PENDING'
            }
            elseif ($factoryIntentPresent) {
                'INTEL_VRR_SOLUTIONS_FACTORY_DEFAULTS_PENDING_RESUME'
            }
            elseif ($factoryFinalizedPresent) {
                'INTEL_VRR_SOLUTIONS_FACTORY_DEFAULTS_FINALIZED'
            }
            elseif ($restoreTombstonePresent) {
                'ORIGINAL_LFC_RESTORE_COMMITTED_PENDING_FINALIZE'
            }
            elseif ($restoreFinalizedPresent) {
                'ORIGINAL_LFC_RESTORE_FINALIZED'
            }
            elseif (-not (Test-Path -LiteralPath $lfcBackupPath -PathType Leaf) -and
                ($now.LowFpsSolutionEnabled -eq $false -or $now.HighFpsSolutionEnabled -eq $false)) {
                'ORIGINAL_LFC_BACKUP_MISSING_CANNOT_RESTORE'
            }
            elseif ($null -ne $managedProfile -and
                (Test-Path -LiteralPath $lfcBackupPath -PathType Leaf) -and
                $statusBackupIdentity.Accepted -and
                (Test-ManagedDirectRangeReady -State $now) -and
                -not $now.LowFpsSolutionEnabled -and -not $now.HighFpsSolutionEnabled) {
                'CLAWLAB_LFC_FIX_ACTIVE'
            }
            elseif (-not $now.LowFpsSolutionEnabled) {
                'INTEL_LOW_FPS_SOLUTION_DISABLED_OUTSIDE_MANAGED_FIX'
            }
            elseif ($null -ne $managedProfile -and
                (Test-Path -LiteralPath $lfcBackupPath -PathType Leaf) -and
                $statusBackupIdentity.Accepted -and
                (Get-StartupPersistenceState) -eq 'INSTALLED_ONE_SHOT_AT_LOGON') {
                'CLAWLAB_LFC_FIX_PENDING_RESTART'
            }
            else {
                'INTEL_VRR_SOLUTIONS_NOT_PATCHED'
            }
            Current = $now
            BackupPresent = Test-Path -LiteralPath $lfcBackupPath -PathType Leaf
            RestoreTombstonePresent = $restoreTombstonePresent
            RestoreTombstoneSchemaVersion = if ($null -eq $restoreTombstoneRecord) {
                0
            }
            else {
                [int]$restoreTombstoneRecord.SchemaVersion
            }
            RestoreFinalizedPresent = $restoreFinalizedPresent
            RestoreFinalizedVerified = $restoreFinalizedStateVerified
            RestoreFinalizedSchemaVersion = if ($null -eq $restoreFinalizedRecord) {
                0
            }
            else {
                [int]$restoreFinalizedRecord.SchemaVersion
            }
            FactoryIntentPresent = $factoryIntentPresent
            FactoryIntentVerified = $null -ne $factoryIntentRecord
            FactoryIntentTransactionId = if ($null -eq $factoryIntentRecord) {
                $null
            }
            else {
                [string]$factoryIntentRecord.TransactionId
            }
            FactoryTransitionStage = if ($null -eq $factoryIntentStage) {
                'NONE'
            }
            else {
                [string]$factoryIntentStage.Stage
            }
            FactoryFinalizedPresent = $factoryFinalizedPresent
            FactoryFinalizedVerified = $null -ne $factoryFinalizedRecord
            FactoryFinalizedTransactionId = if ($null -eq $factoryFinalizedRecord) {
                $null
            }
            else {
                [string]$factoryFinalizedRecord.FactoryTransactionId
            }
        }
    }

    { $_ -in @('Apply', 'ApplyStartup') } {
        if (Test-Path -LiteralPath $lfcRestoreCommittedPath -PathType Leaf) {
            throw 'A committed LFC restore is awaiting final verification. Complete ClawLab Recovery before applying a managed profile.'
        }
        $startupApplication = $Action -eq 'ApplyStartup'
        if (-not $startupApplication) {
            Activate-LfcFinalizedProvenanceForApply
        }
        $before = Get-CurrentIntelVrrState
        $rangeReady = Test-ManagedDirectRangeReady -State $before
        $validCustomRestartPending = -not $startupApplication -and
            [bool]$managedProfile.UsesCustomEdid -and
            $before.Supported -and $before.VrrEnabled -and
            $before.MinimumHz -eq 48 -and $before.MaximumHz -eq 120 -and
            $reportedEdidSha256 -eq $physicalEdidHash
        if (-not $rangeReady -and -not $validCustomRestartPending) {
            throw "The Intel LFC fix requires the exact $expectedMinimumHz-$expectedMaximumHz Hz range; the Intel driver reports $($before.MinimumHz)-$($before.MaximumHz) Hz. No backup, persistence task or LFC flag was changed."
        }

        $backup = Get-LfcBackup
        if ($null -eq $backup) {
            if ($startupApplication) {
                throw 'Startup reapply refused to run without a saved original LFC state.'
            }
            if (-not $before.LowFpsSolutionEnabled -or -not $before.HighFpsSolutionEnabled) {
                throw 'The original Intel LFC backup is missing while one or both solution flags are already disabled. Refusing to save an unknown modified state as the original. No backup, persistence task or LFC flag was changed. Use EMERGENCY\SET_INTEL_LFC_FACTORY_DEFAULTS.bat only if Intel factory defaults are explicitly intended.'
            }
            [IO.Directory]::CreateDirectory($lfcStateRoot) | Out-Null
            $backup = [ordered]@{
                SchemaVersion = 4
                SavedAt = (Get-Date).ToString('o')
                PanelManufacturer = [string]$panel.Manufacturer
                PanelProductCode = [string]$panel.ProductCode
                PanelName = [string]$panel.Name
                PhysicalEdidSha256 = $physicalEdidHash
                PanelInstanceNameAtSave = [string]$panel.InstanceName
                LastValidatedPanelInstanceName = [string]$panel.InstanceName
                PanelEdidSha256AtSave = $reportedEdidSha256
                InstanceMigrationCount = 0
                LastInstanceMigrationAt = $null
                PanelInstanceName = [string]$panel.InstanceName
                PanelEdidSha256 = $reportedEdidSha256
                ManagedVrrMode = $managedModeName
                IntelDriverVersion = [string](Get-CimInstance Win32_VideoController | Where-Object { $_.PNPDeviceID -like 'PCI\VEN_8086&*' } | Select-Object -First 1).DriverVersion
                DriverInterface = 'DIRECT_D3DKMT_INTEL_PRIVATE_ESCAPE'
                OriginalLowFpsSolutionEnabled = [bool]$before.LowFpsSolutionEnabled
                OriginalHighFpsSolutionEnabled = [bool]$before.HighFpsSolutionEnabled
            }
            Write-LfcBackupAtomically -Backup $backup
            $backup = Get-LfcBackup
        }

        if (-not $rangeReady) {
            Install-StartupPersistence
            [pscustomobject]@{
                State = 'CLAWLAB_LFC_FIX_PENDING_RESTART'
                Before = $before
                Current = $before
                BackupPresent = $true
                StartupPersistence = Get-StartupPersistenceState
            }
            break
        }

        if ($before.LowFpsSolutionEnabled -or $before.HighFpsSolutionEnabled) {
            try {
                Set-LowFpsSolution -Enabled $false
                Set-HighFpsSolution -Enabled $false
                Start-Sleep -Milliseconds 750
                $after = Get-CurrentIntelVrrState
                if ($after.Result -ne 'Success' -or
                    $after.LowFpsSolutionEnabled -or
                    $after.HighFpsSolutionEnabled -or
                    -not $after.VrrEnabled -or
                    $after.MinimumHz -ne $before.MinimumHz -or
                    $after.MaximumHz -ne $before.MaximumHz) {
                    throw "The post-apply Intel state is invalid: $($after | ConvertTo-Json -Compress)"
                }
                if (-not $startupApplication) {
                    Install-StartupPersistence
                }
            }
            catch {
                Set-LowFpsSolution -Enabled ([bool]$backup.OriginalLowFpsSolutionEnabled)
                Set-HighFpsSolution -Enabled ([bool]$backup.OriginalHighFpsSolutionEnabled)
                if (-not $startupApplication) {
                    try { Remove-StartupPersistence } catch {}
                }
                throw
            }
        }
        else {
            $after = $before
            if (-not $startupApplication) {
                Install-StartupPersistence
            }
        }

        [pscustomobject]@{
            State = 'CLAWLAB_LFC_FIX_ACTIVE'
            Before = $before
            Current = $after
            BackupPresent = $true
            StartupPersistence = Get-StartupPersistenceState
        }
        break
    }

    { $_ -in @('Restore', 'PrepareRestore') } {
        $backup = Get-LfcBackup
        if ($null -eq $backup) {
            Remove-StartupPersistence
            $committedRecord = Get-LfcRestoreCommittedRecord
            if ($null -ne $committedRecord) {
                $after = Assert-LfcRestoreRecordMatchesCurrentState -Record $committedRecord
                [pscustomobject]@{
                    State = 'ORIGINAL_LFC_RESTORE_COMMITTED_PENDING_FINALIZE'
                    Current = $after
                    BackupPresent = $false
                    RestoreTombstonePresent = $true
                }
                break
            }
            $finalizedRecord = Get-LfcRestoreFinalizedRecord
            if ($null -ne $finalizedRecord) {
                $after = Assert-LfcRestoreRecordMatchesCurrentState -Record $finalizedRecord
                [pscustomobject]@{
                    State = 'ORIGINAL_LFC_RESTORE_FINALIZED'
                    Current = $after
                    BackupPresent = $false
                    RestoreTombstonePresent = $false
                    RestoreFinalizedPresent = $true
                    RestoreFinalizedVerified = $true
                }
                break
            }
            $after = Get-CurrentIntelVrrState
            if (-not $after.LowFpsSolutionEnabled -or -not $after.HighFpsSolutionEnabled) {
                throw 'The original Intel LFC backup is missing while one or both solution flags are disabled. Original values cannot be inferred. Do not delete ClawLab AppData; use EMERGENCY\SET_INTEL_LFC_FACTORY_DEFAULTS.bat only if factory defaults are explicitly intended.'
            }
            [pscustomobject]@{
                State = 'ALREADY_RESTORED'
                Current = $after
                BackupPresent = $false
                RestoreTombstonePresent = $false
            }
            break
        }
        Remove-StartupPersistence
        Set-LowFpsSolution -Enabled ([bool]$backup.OriginalLowFpsSolutionEnabled)
        if ([int]$backup.SchemaVersion -in @(2, 3, 4)) {
            Set-HighFpsSolution -Enabled ([bool]$backup.OriginalHighFpsSolutionEnabled)
        }
        Start-Sleep -Milliseconds 750
        $after = Get-CurrentIntelVrrState
        if ($after.Result -ne 'Success' -or
            $after.LowFpsSolutionEnabled -ne [bool]$backup.OriginalLowFpsSolutionEnabled -or
            ([int]$backup.SchemaVersion -in @(2, 3, 4) -and
                $after.HighFpsSolutionEnabled -ne [bool]$backup.OriginalHighFpsSolutionEnabled)) {
            throw "The restored Intel state did not verify: $($after | ConvertTo-Json -Compress)"
        }
        if ($Action -eq 'Restore') {
            Remove-FileIfPresent -LiteralPath $lfcBackupPath
        }
        [pscustomobject]@{
            State = if ($Action -eq 'PrepareRestore') {
                'ORIGINAL_LFC_STATE_PREPARED_BACKUP_RETAINED'
            }
            else {
                'ORIGINAL_LFC_STATE_RESTORED'
            }
            Current = $after
            BackupPresent = $Action -eq 'PrepareRestore'
            RestoreTombstonePresent = $false
        }
    }

    'CommitRestore' {
        $backup = Get-LfcBackup
        if ($null -eq $backup) {
            $committedRecord = Get-LfcRestoreCommittedRecord
            if ($null -ne $committedRecord) {
                $after = Assert-LfcRestoreRecordMatchesCurrentState -Record $committedRecord
                [pscustomobject]@{
                    State = 'ORIGINAL_LFC_RESTORE_COMMITTED_PENDING_FINALIZE'
                    Current = $after
                    BackupPresent = $false
                    RestoreTombstonePresent = $true
                }
                break
            }
            $finalizedRecord = Get-LfcRestoreFinalizedRecord
            if ($null -ne $finalizedRecord) {
                $after = Assert-LfcRestoreRecordMatchesCurrentState -Record $finalizedRecord
                [pscustomobject]@{
                    State = 'ORIGINAL_LFC_RESTORE_FINALIZED'
                    Current = $after
                    BackupPresent = $false
                    RestoreTombstonePresent = $false
                    RestoreFinalizedPresent = $true
                    RestoreFinalizedVerified = $true
                }
                break
            }
            $after = Get-CurrentIntelVrrState
            if (-not $after.LowFpsSolutionEnabled -or -not $after.HighFpsSolutionEnabled -or
                (Get-StartupPersistenceState) -ne 'NOT_INSTALLED') {
                throw 'The LFC restore backup is absent, but the already-committed original state cannot be verified.'
            }
            [pscustomobject]@{
                State = 'ORIGINAL_LFC_RESTORE_ALREADY_COMMITTED'
                Current = $after
                BackupPresent = $false
                RestoreTombstonePresent = $false
            }
            break
        }
        $after = Assert-LfcRestoreRecordMatchesCurrentState -Record $backup
        if (Test-Path -LiteralPath $lfcRestoreCommittedPath) {
            throw 'Intel LFC restore commit refused because a stale restore tombstone already exists.'
        }
        [IO.File]::Move($lfcBackupPath, $lfcRestoreCommittedPath)
        if ((Test-Path -LiteralPath $lfcBackupPath -PathType Leaf) -or
            -not (Test-Path -LiteralPath $lfcRestoreCommittedPath -PathType Leaf)) {
            throw 'Intel LFC restore commit could not atomically retain its recovery tombstone.'
        }
        [pscustomobject]@{
            State = 'ORIGINAL_LFC_RESTORE_COMMITTED_PENDING_FINALIZE'
            Current = $after
            BackupPresent = $false
            RestoreTombstonePresent = $true
        }
    }

    'FinalizeRestore' {
        if (Test-Path -LiteralPath $lfcBackupPath -PathType Leaf) {
            throw 'Intel LFC restore cannot finalize while the active original-state backup still exists.'
        }
        $committedRecord = Get-LfcRestoreCommittedRecord
        if ($null -eq $committedRecord) {
            $finalizedRecord = Get-LfcRestoreFinalizedRecord
            if ($null -ne $finalizedRecord) {
                $after = Assert-LfcRestoreRecordMatchesCurrentState -Record $finalizedRecord
                [pscustomobject]@{
                    State = 'ORIGINAL_LFC_RESTORE_ALREADY_FINALIZED'
                    Current = $after
                    BackupPresent = $false
                    RestoreTombstonePresent = $false
                    RestoreFinalizedPresent = $true
                }
                break
            }
            if ((Get-StartupPersistenceState) -ne 'NOT_INSTALLED') {
                throw 'Intel LFC restore finalization found no tombstone, but startup persistence is still installed.'
            }
            [pscustomobject]@{
                State = 'ORIGINAL_LFC_RESTORE_ALREADY_FINALIZED'
                Current = Get-CurrentIntelVrrState
                BackupPresent = $false
                RestoreTombstonePresent = $false
                RestoreFinalizedPresent = $false
            }
            break
        }
        $after = Assert-LfcRestoreRecordMatchesCurrentState -Record $committedRecord
        if (Test-Path -LiteralPath $lfcRestoreFinalizedPath) {
            throw 'Intel LFC restore finalization refused because a stale finalized provenance marker already exists.'
        }
        [IO.File]::Move($lfcRestoreCommittedPath, $lfcRestoreFinalizedPath)
        if ((Test-Path -LiteralPath $lfcRestoreCommittedPath) -or
            -not (Test-Path -LiteralPath $lfcRestoreFinalizedPath -PathType Leaf)) {
            throw 'Intel LFC restore finalization could not atomically retain its verified provenance marker.'
        }
        [pscustomobject]@{
            State = 'ORIGINAL_LFC_RESTORE_FINALIZED'
            Current = $after
            BackupPresent = $false
            RestoreTombstonePresent = $false
            RestoreFinalizedPresent = $true
        }
    }

    'FactoryDefaults' {
        if (Test-Path -LiteralPath $lfcBackupPath -PathType Leaf) {
            throw 'A valid original LFC backup is still present. Use RECOVERY\RESTORE_INTEL_LFC_DEFAULTS.bat so the exact saved values are restored.'
        }
        if (Test-Path -LiteralPath $lfcRestoreCommittedPath -PathType Leaf) {
            throw 'A committed LFC restore is awaiting final verification. Complete ClawLab Recovery instead of forcing factory defaults.'
        }

        $factoryIntent = Get-LfcFactoryIntentRecord
        $factoryFinalized = Get-LfcFactoryFinalizedRecord -ExpectedTransactionId $(
            if ($null -eq $factoryIntent) { $null } else { [string]$factoryIntent.TransactionId }
        )
        if ($null -eq $factoryIntent -and $null -ne $factoryFinalized) {
            if (Test-Path -LiteralPath $lfcRestoreFinalizedPath -PathType Leaf) {
                throw 'Factory Defaults found overlapping terminal provenance without a binding transaction intent.'
            }
            $after = Assert-LfcFactoryFinalizedMatchesCurrentState -Record $factoryFinalized
            [pscustomobject]@{
                State = 'INTEL_VRR_SOLUTIONS_FACTORY_DEFAULTS_ALREADY_FINALIZED'
                Current = $after
                BackupPresent = $false
                RestoreTombstonePresent = $false
                RestoreFinalizedPresent = $false
                FactoryIntentPresent = $false
                FactoryFinalizedPresent = $true
                FactoryFinalizedVerified = $true
            }
            break
        }

        Remove-StartupPersistence
        if ($null -eq $factoryIntent) {
            $finalizedRecord = Get-LfcRestoreFinalizedRecord
            if ($null -ne $finalizedRecord) {
                [void](Assert-LfcRestoreRecordMatchesCurrentState -Record $finalizedRecord)
            }
            $before = Get-CurrentIntelVrrState
            if ($before.Result -ne 'Success') {
                throw 'Intel LFC factory defaults could not read the original driver flags.'
            }

            # Persist and verify the exact source identity and target true/true
            # before the first driver setter. Every subsequent driver state must
            # be a safe prefix of this retained transaction.
            $factoryIntentValue = New-LfcFactoryIntentRecord `
                -CurrentState $before -RestoreFinalizedRecord $finalizedRecord
            Write-LfcJsonFileAtomically -LiteralPath $lfcFactoryIntentPath -Value $factoryIntentValue
            $factoryIntent = Get-LfcFactoryIntentRecord
        }
        $after = Complete-LfcFactoryDefaultsTransaction -Intent $factoryIntent
        [pscustomobject]@{
            State = 'INTEL_VRR_SOLUTIONS_FACTORY_DEFAULTS_APPLIED'
            Current = $after
            BackupPresent = $false
            RestoreTombstonePresent = $false
            RestoreFinalizedPresent = $false
            FactoryIntentPresent = $false
            FactoryFinalizedPresent = $true
            FactoryFinalizedVerified = $true
        }
    }
}

$finalBackupIdentity = Get-LfcBackupIdentityStatus
[pscustomobject]@{
    ToolVersion = $toolVersion
    DriverInterface = 'DIRECT_D3DKMT_INTEL_PRIVATE_ESCAPE'
    IntelGpu = [string]$intelGpu.Name
    IntelDriverVersion = [string]$intelGpu.DriverVersion
    CurrentState = $current
    ManagedVrrMode = $managedModeName
    ExpectedRange = if ($null -eq $managedProfile) { 'UNMANAGED' } else { "$expectedMinimumHz-$expectedMaximumHz Hz" }
    PanelEdidSha256 = $reportedEdidSha256
    PanelEdidSourceLength = [int]$canonicalEdid.SourceLength
    PanelEdidNormalization = [string]$canonicalEdid.State
    ThirdPartyEdidOverrideValues = if ($thirdPartyOverrideValueNames.Count -eq 0) { 'NONE' } else { $thirdPartyOverrideValueNames -join ', ' }
    LfcBackupIdentity = $finalBackupIdentity
    LfcTransition = $state
    RestoreTombstonePresent = Test-Path -LiteralPath $lfcRestoreCommittedPath -PathType Leaf
    RestoreFinalizedPresent = Test-Path -LiteralPath $lfcRestoreFinalizedPath -PathType Leaf
    FactoryIntentPresent = Test-Path -LiteralPath $lfcFactoryIntentPath -PathType Leaf
    FactoryFinalizedPresent = Test-Path -LiteralPath $lfcFactoryFinalizedPath -PathType Leaf
    StartupPersistence = Get-StartupPersistenceState
    LfcFixActive = $null -ne $managedProfile -and
        (Test-Path -LiteralPath $lfcBackupPath -PathType Leaf) -and
        $finalBackupIdentity.Accepted -and
        (Get-StartupPersistenceState) -eq 'INSTALLED_ONE_SHOT_AT_LOGON' -and
        (Test-ManagedDirectRangeReady -State $state.Current) -and
        (-not [bool]$state.Current.LowFpsSolutionEnabled) -and
        (-not [bool]$state.Current.HighFpsSolutionEnabled)
}
}
finally {
    if ($Action -eq 'ApplyStartup') {
        Exit-LfcStartupApplyMutex
        Exit-LfcStartupTransactionMutex
    }
}
