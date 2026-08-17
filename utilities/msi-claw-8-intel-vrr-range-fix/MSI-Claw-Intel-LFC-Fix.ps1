[CmdletBinding()]
param(
    [ValidateSet('Status', 'Apply', 'Restore', 'ApplyStartup', 'FactoryDefaults')]
    [string]$Action = 'Status'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$toolVersion = '2.0.5'

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
        Overclock30_144EdidHash = '0B8E8A25325B4D9CAC2B6A03CF9B574688B1A6D2DEDF10401605C4898E0CAC05'
        Overclock30_165EdidHash = '8EDC82A04D9E1FAD037CA4D794D53BD0D374C9554059B137E75C40D9F9C416A7'
        Overclock30_180EdidHash = '0D1969CF0C7CFBA3CF9F077667C1427E202DB895DFA0A750FAF1323F57A88E4B'
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
        Overclock30_144EdidHash = 'DFD9CBDDB7C0B8A711F026C43E3EB73165958F2E129857B97EB7EB008CB71B5E'
        Overclock30_165EdidHash = 'C0147C505E16907C62E66B56A3436870B591E1CB7B2FBA6CA410EEE3BEBDDC51'
        Overclock30_180EdidHash = 'CE853C0CB689CC6247E72E59C7965FEDCAE49479BCFD04EE7959FA3113A9D679'
    }
)
$vrrStateRoot = Join-Path $env:LOCALAPPDATA 'ClawLab\Intel-Arc-Sync-Full-Range'
$managedModePath = Join-Path $vrrStateRoot 'managed-mode.json'
$experimentalStatePath = Join-Path $vrrStateRoot 'experimental-edid.json'
$lfcStateRoot = Join-Path $env:LOCALAPPDATA 'ClawLab\Intel-LFC-Fix'
$lfcBackupPath = Join-Path $lfcStateRoot 'original-intel-vrr-solutions.json'
$installedToolPath = Join-Path $lfcStateRoot 'MSI-Claw-Intel-LFC-Fix.ps1'
$installedDriverInterfacePath = Join-Path $lfcStateRoot 'Intel-VRR-LFC-Driver-Interface.ps1'
$backupIdentityModulePath = Join-Path $PSScriptRoot 'Lfc-Backup-Identity.ps1'
$edidNormalizationModulePath = Join-Path $PSScriptRoot 'Edid-Normalization.ps1'
$arcSyncRangePolicyModulePath = Join-Path $PSScriptRoot 'ArcSync-Range-Policy.ps1'
$installedBackupIdentityModulePath = Join-Path $lfcStateRoot 'Lfc-Backup-Identity.ps1'
$installedEdidNormalizationModulePath = Join-Path $lfcStateRoot 'Edid-Normalization.ps1'
$installedArcSyncRangePolicyModulePath = Join-Path $lfcStateRoot 'ArcSync-Range-Policy.ps1'
$installedLauncherPath = Join-Path $lfcStateRoot 'ClawLab-LFC-Startup.vbs'
$startupTaskName = 'ClawLab MSI Claw Intel LFC Fix'

foreach ($modulePath in @($backupIdentityModulePath, $edidNormalizationModulePath, $arcSyncRangePolicyModulePath)) {
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
    $panelDefinition.Overclock30_144EdidHash,
    $panelDefinition.Overclock30_165EdidHash,
    $panelDefinition.Overclock30_180EdidHash
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
        [pscustomobject]@{ Name = 'CLAWLAB_30_144'; MinimumHz = 30; MaximumHz = 144; Hash = $panelDefinition.Overclock30_144EdidHash },
        [pscustomobject]@{ Name = 'CLAWLAB_30_165'; MinimumHz = 30; MaximumHz = 165; Hash = $panelDefinition.Overclock30_165EdidHash },
        [pscustomobject]@{ Name = 'CLAWLAB_30_180'; MinimumHz = 30; MaximumHz = 180; Hash = $panelDefinition.Overclock30_180EdidHash }
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

if ($Action -eq 'ApplyStartup') {
    $clawTweaksTask = Get-ScheduledTask -TaskPath '\ClawTweaks\' -TaskName 'ClawTweaksHelper' -ErrorAction SilentlyContinue
    if ($null -ne $clawTweaksTask) {
        for ($attempt = 1; $attempt -le 30; $attempt++) {
            $clawTweaksTask = Get-ScheduledTask -TaskPath '\ClawTweaks\' -TaskName 'ClawTweaksHelper' -ErrorAction SilentlyContinue
            if ($null -ne $clawTweaksTask -and [string]$clawTweaksTask.State -eq 'Running') {
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
    $rangeArguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$installedVrrToolPath`" -Action ApplyStartup"
    $rangeProcess = Start-Process -FilePath 'powershell.exe' -ArgumentList $rangeArguments `
        -WindowStyle Hidden -PassThru
    # Start-Process -Wait waits for the complete descendant process tree on
    # Windows PowerShell. Release 2.1 launches the resident Cursor Refresh
    # Helper from the VRR child, so -Wait would never return while that helper
    # correctly remains active. Wait only for the direct VRR child instead.
    $rangeProcess.WaitForExit()
    if ($rangeProcess.ExitCode -ne 0) {
        throw "The installed ClawLab VRR startup reapply failed with exit code $($rangeProcess.ExitCode)."
    }
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
if ($Action -in @('Restore', 'FactoryDefaults') -and (-not $current.Supported -or $current.Result -ne 'Success')) {
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
    $backup = [IO.File]::ReadAllText($lfcBackupPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $identityAction = if ($Action -eq 'Status') { 'Restore' } else { $Action }
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
    if ([int]$backup.SchemaVersion -eq 1 -and $Action -ne 'Restore') {
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
    $task = Get-ScheduledTask -TaskName $startupTaskName -ErrorAction SilentlyContinue
    if ($null -eq $task) {
        return 'NOT_INSTALLED'
    }
    if (-not (Test-Path -LiteralPath $installedToolPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $installedDriverInterfacePath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $installedBackupIdentityModulePath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $installedEdidNormalizationModulePath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $installedArcSyncRangePolicyModulePath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $installedLauncherPath -PathType Leaf)) {
        return 'INCOMPLETE'
    }
    return 'INSTALLED_ONE_SHOT_AT_LOGON'
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
    [IO.File]::Copy($sourceLauncherPath, $installedLauncherPath, $true)

    foreach ($pair in @(
        @($PSCommandPath, $installedToolPath),
        @($driverInterfacePath, $installedDriverInterfacePath),
        @($backupIdentityModulePath, $installedBackupIdentityModulePath),
        @($edidNormalizationModulePath, $installedEdidNormalizationModulePath),
        @($arcSyncRangePolicyModulePath, $installedArcSyncRangePolicyModulePath),
        @($sourceLauncherPath, $installedLauncherPath)
    )) {
        if ((Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash -ne
            (Get-FileHash -LiteralPath $pair[1] -Algorithm SHA256).Hash) {
            throw "Startup persistence copy verification failed: $($pair[1])"
        }
    }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $wscriptPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
    $arguments = "//B //Nologo `"$installedLauncherPath`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $identity.Name
    $taskAction = New-ScheduledTaskAction -Execute $wscriptPath -Argument $arguments
    $principal = New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 4)
    $task = New-ScheduledTask -Action $taskAction -Trigger $trigger -Principal $principal `
        -Settings $settings -Description 'Silently reapplies the selected ClawLab VRR range and Intel LFC state once at logon, then exits.'
    Register-ScheduledTask -TaskName $startupTaskName -InputObject $task -Force | Out-Null
    if ((Get-StartupPersistenceState) -ne 'INSTALLED_ONE_SHOT_AT_LOGON') {
        throw 'The one-shot startup persistence task could not be verified.'
    }
}

function Remove-StartupPersistence {
    $task = Get-ScheduledTask -TaskName $startupTaskName -ErrorAction SilentlyContinue
    if ($null -ne $task) {
        Unregister-ScheduledTask -TaskName $startupTaskName -Confirm:$false -ErrorAction Stop
    }
    Remove-FileIfPresent -LiteralPath $installedToolPath
    Remove-FileIfPresent -LiteralPath $installedDriverInterfacePath
    Remove-FileIfPresent -LiteralPath $installedBackupIdentityModulePath
    Remove-FileIfPresent -LiteralPath $installedEdidNormalizationModulePath
    Remove-FileIfPresent -LiteralPath $installedArcSyncRangePolicyModulePath
    Remove-FileIfPresent -LiteralPath $installedLauncherPath
    if ((Get-StartupPersistenceState) -ne 'NOT_INSTALLED') {
        throw 'The one-shot startup persistence task was not fully removed.'
    }
}

$state = switch ($Action) {
    'Status' {
        $now = Get-CurrentIntelVrrState
        $statusBackupIdentity = Get-LfcBackupIdentityStatus
        [pscustomobject]@{
            State = if (-not (Test-Path -LiteralPath $lfcBackupPath -PathType Leaf) -and
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
        }
    }

    { $_ -in @('Apply', 'ApplyStartup') } {
        $startupApplication = $Action -eq 'ApplyStartup'
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

    'Restore' {
        $backup = Get-LfcBackup
        if ($null -eq $backup) {
            Remove-StartupPersistence
            $after = Get-CurrentIntelVrrState
            if (-not $after.LowFpsSolutionEnabled -or -not $after.HighFpsSolutionEnabled) {
                throw 'The original Intel LFC backup is missing while one or both solution flags are disabled. Original values cannot be inferred. Do not delete ClawLab AppData; use EMERGENCY\SET_INTEL_LFC_FACTORY_DEFAULTS.bat only if factory defaults are explicitly intended.'
            }
            [pscustomobject]@{
                State = 'ALREADY_RESTORED'
                Current = $after
                BackupPresent = $false
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
        Remove-FileIfPresent -LiteralPath $lfcBackupPath
        [pscustomobject]@{
            State = 'ORIGINAL_LFC_STATE_RESTORED'
            Current = $after
            BackupPresent = $false
        }
    }

    'FactoryDefaults' {
        if (Test-Path -LiteralPath $lfcBackupPath -PathType Leaf) {
            throw 'A valid original LFC backup is still present. Use RECOVERY\RESTORE_INTEL_LFC_DEFAULTS.bat so the exact saved values are restored.'
        }
        Remove-StartupPersistence
        Set-LowFpsSolution -Enabled $true
        Set-HighFpsSolution -Enabled $true
        Start-Sleep -Milliseconds 750
        $after = Get-CurrentIntelVrrState
        if ($after.Result -ne 'Success' -or
            -not $after.LowFpsSolutionEnabled -or
            -not $after.HighFpsSolutionEnabled) {
            throw "Intel LFC factory-default verification failed: $($after | ConvertTo-Json -Compress)"
        }
        [pscustomobject]@{
            State = 'INTEL_VRR_SOLUTIONS_FACTORY_DEFAULTS_APPLIED'
            Current = $after
            BackupPresent = $false
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
    StartupPersistence = Get-StartupPersistenceState
    LfcFixActive = $null -ne $managedProfile -and
        (Test-Path -LiteralPath $lfcBackupPath -PathType Leaf) -and
        $finalBackupIdentity.Accepted -and
        (Get-StartupPersistenceState) -eq 'INSTALLED_ONE_SHOT_AT_LOGON' -and
        (Test-ManagedDirectRangeReady -State $state.Current) -and
        (-not [bool]$state.Current.LowFpsSolutionEnabled) -and
        (-not [bool]$state.Current.HighFpsSolutionEnabled)
}
