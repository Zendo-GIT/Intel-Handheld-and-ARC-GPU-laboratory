[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$toolVersion = '1.0.0'
$packageRoot = $PSScriptRoot
$rawArcSyncTool = Join-Path $packageRoot 'Intel-ArcSync-Raw-Query.ps1'
$directIntelTool = Join-Path $packageRoot 'internal\Intel-VRR-LFC-Driver-Interface.ps1'
if (-not (Test-Path -LiteralPath $directIntelTool -PathType Leaf)) {
    $directIntelTool = Join-Path $packageRoot '..\..\Intel-VRR-LFC-Driver-Interface.ps1'
}
foreach ($path in @($rawArcSyncTool, $directIntelTool)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required diagnostic component is missing: $path"
    }
}

function Convert-WmiText {
    param([AllowNull()][object]$Values)
    if ($null -eq $Values) { return '' }
    return (-join @($Values | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }))
}

function Get-ByteArraySha256 {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '') }
    finally { $sha.Dispose() }
}

$expectedPhysicalSha256 = '3518AB4456669D12A7B8D254F63005EAE143C784DCE02EC56C3753C41A664CA1'
$matchingMonitors = @(
    Get-CimInstance -Namespace 'root\wmi' -ClassName 'WmiMonitorID' |
        Where-Object {
            (Convert-WmiText $_.ManufacturerName) -eq 'TMA' -and
            (Convert-WmiText $_.ProductCodeID) -eq '2027' -and
            (Convert-WmiText $_.UserFriendlyName) -eq 'TL070FVXS02-0'
        }
)
if ($matchingMonitors.Count -ne 1) {
    throw "Expected exactly one active TMA2027 / TL070FVXS02-0 panel; found $($matchingMonitors.Count). No display setting was changed."
}

$monitor = $matchingMonitors[0]
$panelInstanceId = ([string]$monitor.InstanceName) -replace '_\d+$', ''
$deviceParametersPath = "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\$panelInstanceId\Device Parameters"
$rawEdid = [byte[]](Get-ItemPropertyValue -LiteralPath $deviceParametersPath -Name 'EDID')
$baseEdid = if ($rawEdid.Length -ge 128) { [byte[]]$rawEdid[0..127] } else { [byte[]]@() }
$zeroPaddedTail = $false
if ($rawEdid.Length -eq 256) {
    $zeroPaddedTail = -not (@($rawEdid[128..255] | Where-Object { $_ -ne 0 }).Count -gt 0)
}
$baseSha256 = if ($baseEdid.Length -eq 128) { Get-ByteArraySha256 -Bytes $baseEdid } else { 'INVALID_LENGTH' }
if ($baseSha256 -ne $expectedPhysicalSha256) {
    throw "The A1M base EDID is not the pinned physical state: $baseSha256. No display setting was changed."
}
if ($rawEdid.Length -notin @(128, 256) -or ($rawEdid.Length -eq 256 -and -not $zeroPaddedTail)) {
    throw "The A1M EDID representation is not an approved 128-byte block or zero-padded 256-byte buffer. No display setting was changed."
}

$overrideBlocks = [ordered]@{}
foreach ($name in @('0', '1')) {
    try {
        $value = [byte[]](Get-ItemPropertyValue -LiteralPath (Join-Path $deviceParametersPath 'EDID_OVERRIDE') -Name $name -ErrorAction Stop)
        $overrideBlocks[$name] = [ordered]@{ Present = $true; Length = $value.Length; Sha256 = Get-ByteArraySha256 -Bytes $value }
    }
    catch {
        $overrideBlocks[$name] = [ordered]@{ Present = $false }
    }
}

$arcSyncRaw = @(& $rawArcSyncTool)
$directState = & $directIntelTool -Action Status
$gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.PNPDeviceID -like 'PCI\VEN_8086&*' } | Select-Object -First 1
$computer = Get-CimInstance Win32_ComputerSystem
$operatingSystem = Get-CimInstance Win32_OperatingSystem
$controlLibModule = @(
    (Get-Process -Id $PID).Modules |
        Where-Object { $_.ModuleName -ieq 'ControlLib.dll' } |
        Select-Object -First 1
)
$controlLib = if ($controlLibModule.Count -eq 1) {
    $modulePath = [string]$controlLibModule[0].FileName
    [ordered]@{
        Path = $modulePath
        FileVersion = [string]$controlLibModule[0].FileVersionInfo.FileVersion
        Sha256 = (Get-FileHash -LiteralPath $modulePath -Algorithm SHA256).Hash
    }
}
else { $null }

$successfulArcOutputs = @($arcSyncRaw | Where-Object { $_.MonitorResult -eq 0 -and $_.ProfileResult -eq 0 -and $_.Supported })
$halfFloorMismatch = $false
if ($successfulArcOutputs.Count -eq 1 -and $null -ne $directState) {
    $halfFloorMismatch = [Math]::Abs(([float]$successfulArcOutputs[0].MonitorMinimumHz * 2.0) - [float]$directState.MinimumHz) -le 0.1 -and
        [Math]::Abs([float]$successfulArcOutputs[0].MonitorMaximumHz - [float]$directState.MaximumHz) -le 0.1
}

$report = [ordered]@{
    SchemaVersion = 1
    ToolVersion = $toolVersion
    CollectedAt = (Get-Date).ToString('o')
    ReadOnlyCollection = $true
    ArcSyncSetterIncluded = $false
    DirectIntelActionExecuted = 'Status'
    Computer = [ordered]@{
        Manufacturer = [string]$computer.Manufacturer
        Model = [string]$computer.Model
        WindowsCaption = [string]$operatingSystem.Caption
        WindowsVersion = [string]$operatingSystem.Version
        WindowsBuild = [string]$operatingSystem.BuildNumber
    }
    IntelGpu = [ordered]@{
        Name = [string]$gpu.Name
        PnpDeviceId = [string]$gpu.PNPDeviceID
        DriverVersion = [string]$gpu.DriverVersion
        CurrentMode = '{0}x{1} @ {2} Hz' -f $gpu.CurrentHorizontalResolution, $gpu.CurrentVerticalResolution, $gpu.CurrentRefreshRate
    }
    Panel = [ordered]@{
        InstanceName = [string]$monitor.InstanceName
        Manufacturer = Convert-WmiText $monitor.ManufacturerName
        ProductCode = Convert-WmiText $monitor.ProductCodeID
        Name = Convert-WmiText $monitor.UserFriendlyName
        RawEdidLength = $rawEdid.Length
        RawEdidSha256 = Get-ByteArraySha256 -Bytes $rawEdid
        CanonicalBaseSha256 = $baseSha256
        ZeroPaddedTail = $zeroPaddedTail
        ExtensionCount = if ($baseEdid.Length -eq 128) { [int]$baseEdid[126] } else { $null }
        DescriptorMinimumHzByte = if ($baseEdid.Length -eq 128) { [int]$baseEdid[95] } else { $null }
        DescriptorMaximumHzByte = if ($baseEdid.Length -eq 128) { [int]$baseEdid[96] } else { $null }
        OverrideBlocks = $overrideBlocks
    }
    ArcSyncControlLib = $controlLib
    ArcSyncRaw = $arcSyncRaw
    DirectIntelVrr = $directState
    Comparison = [ordered]@{
        SuccessfulArcSyncOutputs = $successfulArcOutputs.Count
        DirectExactPhysical48To120 = $null -ne $directState -and [int]$directState.MinimumHz -eq 48 -and [int]$directState.MaximumHz -eq 120
        ArcSyncReportsExactlyHalfDirectFloor = $halfFloorMismatch
    }
}

$desktop = [Environment]::GetFolderPath('Desktop')
if ([string]::IsNullOrWhiteSpace($desktop) -or -not (Test-Path -LiteralPath $desktop -PathType Container)) {
    $desktop = [Environment]::GetFolderPath('MyDocuments')
}
$outputPath = Join-Path $desktop ('ClawLab-A1M-ArcSync-Raw-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
[IO.File]::WriteAllText($outputPath, ($report | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))

Write-Host 'Read-only A1M Arc Sync diagnostics completed.' -ForegroundColor Green
Write-Host 'No profile, EDID, Intel flag, task, service or registry value was changed.' -ForegroundColor Green
Write-Host "Send this file to the developer: $outputPath" -ForegroundColor Cyan
[pscustomobject]@{ Result = 'PASS'; Output = $outputPath }
