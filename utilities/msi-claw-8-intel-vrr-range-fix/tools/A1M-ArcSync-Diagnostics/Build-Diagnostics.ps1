[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version = '1.0.0'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$projectRoot = [IO.Path]::GetFullPath((Join-Path $sourceRoot '..\..'))
$distRoot = Join-Path $projectRoot 'dist'
$packageName = 'ClawLab-A1M-ArcSync-Raw-Diagnostics'
$stagingRoot = Join-Path $distRoot ('.staging-{0}-{1}' -f $packageName, $Version)
$packageRoot = Join-Path $stagingRoot $packageName
$archivePath = Join-Path $distRoot ("$packageName-$Version.zip")
$hashPath = "$archivePath.sha256.txt"

$distFull = [IO.Path]::GetFullPath($distRoot)
$stagingFull = [IO.Path]::GetFullPath($stagingRoot)
if (-not $stagingFull.StartsWith($distFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe staging path: $stagingFull"
}

$files = @(
    [pscustomobject]@{ Source = (Join-Path $sourceRoot 'COLLECT_A1M_ARCSYNC_RAW.bat'); Destination = 'COLLECT_A1M_ARCSYNC_RAW.bat' },
    [pscustomobject]@{ Source = (Join-Path $sourceRoot 'Collect-A1M-ArcSync-Diagnostics.ps1'); Destination = 'Collect-A1M-ArcSync-Diagnostics.ps1' },
    [pscustomobject]@{ Source = (Join-Path $sourceRoot 'Intel-ArcSync-Raw-Query.ps1'); Destination = 'Intel-ArcSync-Raw-Query.ps1' },
    [pscustomobject]@{ Source = (Join-Path $sourceRoot 'README.txt'); Destination = 'README.txt' },
    [pscustomobject]@{ Source = (Join-Path $projectRoot 'Intel-VRR-LFC-Driver-Interface.ps1'); Destination = 'internal\Intel-VRR-LFC-Driver-Interface.ps1' }
)
foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath $file.Source -PathType Leaf)) {
        throw "Required source file is missing: $($file.Source)"
    }
}

$rawQueryText = Get-Content -LiteralPath (Join-Path $sourceRoot 'Intel-ArcSync-Raw-Query.ps1') -Raw
foreach ($forbidden in @('ctlSetIntelArcSyncProfile', 'SetProfile(', 'ChangeDisplaySettings', 'Set-LowFps', 'Set-HighFps')) {
    if ($rawQueryText -match [regex]::Escape($forbidden)) {
        throw "The read-only Arc Sync query contains a forbidden setter: $forbidden"
    }
}
$collectorText = Get-Content -LiteralPath (Join-Path $sourceRoot 'Collect-A1M-ArcSync-Diagnostics.ps1') -Raw
foreach ($required in @(
        "-Action Status",
        "ReadOnlyCollection = `$true",
        "ArcSyncSetterIncluded = `$false",
        '3518AB4456669D12A7B8D254F63005EAE143C784DCE02EC56C3753C41A664CA1'
    )) {
    if ($collectorText -notmatch [regex]::Escape($required)) {
        throw "Collector safety marker is missing: $required"
    }
}
foreach ($forbidden in @('-Action Apply', '-Action Restore', '-Action FactoryDefaults', 'Set-ItemProperty', 'Remove-ItemProperty', 'New-ScheduledTask', 'Register-ScheduledTask')) {
    if ($collectorText -match [regex]::Escape($forbidden)) {
        throw "Collector contains a forbidden mutating operation: $forbidden"
    }
}

foreach ($path in @(
        (Join-Path $sourceRoot 'Collect-A1M-ArcSync-Diagnostics.ps1'),
        (Join-Path $sourceRoot 'Intel-ArcSync-Raw-Query.ps1')
    )) {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        throw "PowerShell parse failure in $path`: $($errors.Message -join '; ')"
    }
}

[IO.Directory]::CreateDirectory($distRoot) | Out-Null
if (Test-Path -LiteralPath $stagingRoot) { [IO.Directory]::Delete($stagingRoot, $true) }
if (Test-Path -LiteralPath $archivePath) { [IO.File]::Delete($archivePath) }
if (Test-Path -LiteralPath $hashPath) { [IO.File]::Delete($hashPath) }
[IO.Directory]::CreateDirectory($packageRoot) | Out-Null
try {
    foreach ($file in $files) {
        $destination = Join-Path $packageRoot $file.Destination
        [IO.Directory]::CreateDirectory((Split-Path $destination -Parent)) | Out-Null
        Copy-Item -LiteralPath $file.Source -Destination $destination
    }

    $manifest = @(Get-ChildItem -LiteralPath $packageRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
        $relative = $_.FullName.Substring($packageRoot.Length + 1).Replace('\', '/')
        "$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()) *$relative"
    })
    [IO.File]::WriteAllLines((Join-Path $packageRoot 'FILES_SHA256.txt'), $manifest, [Text.Encoding]::ASCII)
    Compress-Archive -LiteralPath $packageRoot -DestinationPath $archivePath -CompressionLevel Optimal
}
finally {
    if (Test-Path -LiteralPath $stagingRoot) { [IO.Directory]::Delete($stagingRoot, $true) }
}

$hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
[IO.File]::WriteAllText($hashPath, "$($hash.ToLowerInvariant()) *$([IO.Path]::GetFileName($archivePath))`r`n", [Text.Encoding]::ASCII)
[pscustomobject]@{ Archive = $archivePath; Sha256 = $hash; Files = $files.Count + 1 }
