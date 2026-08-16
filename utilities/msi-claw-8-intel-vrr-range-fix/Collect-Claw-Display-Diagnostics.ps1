[CmdletBinding()]
param(
    [string]$OutputRoot = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ClawLab-Display-Diagnostics')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

function Get-EdidChecksumState {
    param([Parameter(Mandatory)][byte[]]$Edid)
    $results = @()
    for ($start = 0; $start -lt $Edid.Length; $start += 128) {
        $length = [Math]::Min(128, $Edid.Length - $start)
        $sum = 0
        for ($offset = $start; $offset -lt ($start + $length); $offset++) { $sum += $Edid[$offset] }
        $results += [pscustomobject]@{
            Block = [int]($start / 128)
            Length = $length
            Valid = ($length -eq 128 -and ($sum % 256) -eq 0)
        }
    }
    return $results
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outputDirectory = Join-Path ([IO.Path]::GetFullPath($OutputRoot)) $timestamp
[IO.Directory]::CreateDirectory($outputDirectory) | Out-Null

$system = Get-CimInstance -ClassName Win32_ComputerSystem
$bios = Get-CimInstance -ClassName Win32_BIOS
$gpus = @(
    Get-CimInstance -ClassName Win32_VideoController | ForEach-Object {
        [pscustomobject]@{
            Name = [string]$_.Name
            PnpDeviceId = [string]$_.PNPDeviceID
            DriverVersion = [string]$_.DriverVersion
            AdapterRam = [uint64]$_.AdapterRAM
            CurrentResolution = if ($null -ne $_.CurrentHorizontalResolution) {
                '{0}x{1} @ {2} Hz' -f $_.CurrentHorizontalResolution, $_.CurrentVerticalResolution, $_.CurrentRefreshRate
            } else { $null }
        }
    }
)

$monitorIds = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID)
$modeSources = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorListedSupportedSourceModes -ErrorAction SilentlyContinue)
$monitors = @()

foreach ($monitor in $monitorIds) {
    $instanceId = [string]$monitor.InstanceName -replace '_\d+$', ''
    $deviceParameters = "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\$instanceId\Device Parameters"
    $edid = $null
    try { $edid = [byte[]](Get-ItemPropertyValue -LiteralPath $deviceParameters -Name 'EDID' -ErrorAction Stop) } catch {}

    $edidFile = $null
    $edidHash = $null
    $canonicalEdidLength = $null
    $canonicalEdidHash = $null
    $edidBufferShape = 'UNAVAILABLE'
    $checksums = @()
    if ($null -ne $edid -and $edid.Length -gt 0) {
        $safeId = ($instanceId -replace '[^A-Za-z0-9._-]', '_')
        $edidFile = "EDID-$safeId.bin"
        [IO.File]::WriteAllBytes((Join-Path $outputDirectory $edidFile), $edid)
        $edidHash = Get-ByteArraySha256 -Bytes $edid
        $checksums = @(Get-EdidChecksumState -Edid $edid)
        $canonicalEdidLength = $edid.Length
        $canonicalEdidHash = $edidHash
        $edidBufferShape = 'EXACT_REPORTED_BUFFER'
        if ($edid.Length -eq 256 -and $edid[126] -eq 0) {
            $tailAllZero = $true
            for ($index = 128; $index -lt 256; $index++) {
                if ($edid[$index] -ne 0) { $tailAllZero = $false; break }
            }
            if ($tailAllZero) {
                $baseBlock = [byte[]]$edid[0..127]
                $canonicalEdidLength = 128
                $canonicalEdidHash = Get-ByteArraySha256 -Bytes $baseBlock
                $edidBufferShape = '128_BYTE_BASE_PLUS_128_ZERO_PADDING'
            }
        }
    }

    $overrideBlocks = @()
    $overridePath = Join-Path $deviceParameters 'EDID_OVERRIDE'
    if (Test-Path -LiteralPath $overridePath -PathType Container) {
        foreach ($name in @((Get-Item -LiteralPath $overridePath).GetValueNames() | Sort-Object)) {
            try {
                $bytes = [byte[]](Get-ItemPropertyValue -LiteralPath $overridePath -Name $name -ErrorAction Stop)
                $overrideBlocks += [pscustomobject]@{
                    Name = $name
                    Length = $bytes.Length
                    Sha256 = Get-ByteArraySha256 -Bytes $bytes
                }
            } catch {}
        }
    }

    $source = @($modeSources | Where-Object { $_.InstanceName -eq $monitor.InstanceName }) | Select-Object -First 1
    $modes = @()
    if ($null -ne $source) {
        $modes = @($source.MonitorSourceModes | ForEach-Object {
            $denominator = [double]$_.VerticalRefreshRateDenominator
            $refresh = if ($denominator -ne 0) { [double]$_.VerticalRefreshRateNumerator / $denominator } else { 0 }
            [pscustomobject]@{
                Width = [int]$_.HorizontalActivePixels
                Height = [int]$_.VerticalActivePixels
                RefreshHz = [Math]::Round($refresh, 3)
            }
        } | Sort-Object Width, Height, RefreshHz -Unique)
    }

    $monitors += [pscustomobject]@{
        Active = [bool]$monitor.Active
        InstanceName = [string]$monitor.InstanceName
        Manufacturer = Convert-WmiText $monitor.ManufacturerName
        ProductCode = Convert-WmiText $monitor.ProductCodeID
        FriendlyName = Convert-WmiText $monitor.UserFriendlyName
        SerialNumber = Convert-WmiText $monitor.SerialNumberID
        EdidLength = if ($null -ne $edid) { $edid.Length } else { 0 }
        EdidSha256 = $edidHash
        EdidBufferShape = $edidBufferShape
        CanonicalEdidLength = $canonicalEdidLength
        CanonicalEdidSha256 = $canonicalEdidHash
        EdidFile = $edidFile
        EdidChecksums = $checksums
        OverrideBlocks = $overrideBlocks
        ListedModes = $modes
    }
}

$report = [ordered]@{
    SchemaVersion = 1
    CollectedAt = (Get-Date).ToString('o')
    ReadOnlyCollection = $true
    Computer = [ordered]@{
        Manufacturer = [string]$system.Manufacturer
        Model = [string]$system.Model
        SystemType = [string]$system.SystemType
        BiosManufacturer = [string]$bios.Manufacturer
        BiosVersion = @($bios.BIOSVersion)
    }
    OperatingSystem = [Environment]::OSVersion.VersionString
    GraphicsAdapters = $gpus
    Monitors = $monitors
}

$reportPath = Join-Path $outputDirectory 'display-diagnostics.json'
[IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))

$archivePath = "$outputDirectory.zip"
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path -LiteralPath $archivePath -PathType Leaf) { [IO.File]::Delete($archivePath) }
[IO.Compression.ZipFile]::CreateFromDirectory($outputDirectory, $archivePath, [IO.Compression.CompressionLevel]::Optimal, $false)

Write-Host 'Display diagnostics collected without changing the display configuration.' -ForegroundColor Green
Write-Host "Output: $outputDirectory"
Write-Host "Shareable ZIP: $archivePath" -ForegroundColor Cyan
Write-Host 'Review the JSON before sharing it publicly. The archive contains monitor identity and EDID data.' -ForegroundColor Yellow
