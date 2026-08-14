[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version = '1.0.0'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$packageName = 'Detroit-Intel-Arc-Stability-Fix'
$distRoot = Join-Path $projectRoot 'dist'
$stagingRoot = Join-Path $distRoot ".staging-$packageName-$Version"
$stagedPackageRoot = Join-Path $stagingRoot $packageName
$archiveName = "$packageName-$Version.zip"
$archivePath = Join-Path $distRoot $archiveName
$hashPath = Join-Path $distRoot 'RELEASE_SHA256.txt'

$releaseFiles = @(
    'Detroit-IntelArc-StabilityFix.ps1',
    'INSTALL_FIX.bat',
    'INSTALL_STEAM_INTEGRATION.bat',
    'LAUNCH_OPTIMIZED.bat',
    'REMOVE_STEAM_INTEGRATION.bat',
    'UNINSTALL_FIX.bat',
    'CHECK_STATUS.bat',
    'README.txt',
    'CHANGELOG.txt',
    'LICENSE.txt'
)
foreach ($file in $releaseFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $file) -PathType Leaf)) {
        throw "Release file missing: $file"
    }
}

$scriptPath = Join-Path $projectRoot 'Detroit-IntelArc-StabilityFix.ps1'
$scriptText = Get-Content -LiteralPath $scriptPath -Raw
foreach ($requiredValue in @(
    'ECF52321921387E683904E089082D76B973326FC093AF14E524056715519C1CF',
    '1B31A15AC8AF8A236B3B7FB721DF439D03EB40ACAA5ECF59BC6BCF0CDF49D2AE',
    '0x661E57',
    'DetroitBecomeHuman.ClawLab.real.exe'
)) {
    if ($scriptText -notmatch [regex]::Escape($requiredValue)) {
        throw "Required integrity value is missing from the release source: $requiredValue"
    }
}

$forbiddenExtensions = @('.exe', '.dll', '.ovl', '.arc', '.bak', '.etl', '.dmp', '.zip', '.7z', '.rar', '.dxil')
$forbiddenFiles = @(Get-ChildItem -LiteralPath $projectRoot -Recurse -File | Where-Object {
    $_.FullName -notmatch '[\\/]dist[\\/]' -and
    $forbiddenExtensions -contains $_.Extension.ToLowerInvariant()
})
if ($forbiddenFiles.Count -gt 0) {
    throw "Forbidden binary, cache, trace or archive found:`n$($forbiddenFiles.FullName -join "`n")"
}

$distFull = [IO.Path]::GetFullPath($distRoot)
$stagingFull = [IO.Path]::GetFullPath($stagingRoot)
if (-not $stagingFull.StartsWith($distFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe staging path: $stagingFull"
}

New-Item -ItemType Directory -Path $distRoot -Force | Out-Null
if (Test-Path -LiteralPath $stagingRoot) {
    [IO.Directory]::Delete($stagingRoot, $true)
}
if (Test-Path -LiteralPath $archivePath) {
    [IO.File]::Delete($archivePath)
}
New-Item -ItemType Directory -Path $stagedPackageRoot -Force | Out-Null

foreach ($file in $releaseFiles) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $file) -Destination $stagedPackageRoot
}

$manifest = @(Get-ChildItem -LiteralPath $stagedPackageRoot -File | Sort-Object Name | ForEach-Object {
    $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash *$($_.Name)"
})
[IO.File]::WriteAllLines((Join-Path $stagedPackageRoot 'FILES_SHA256.txt'), $manifest, [Text.Encoding]::ASCII)

Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory(
    $stagingRoot,
    $archivePath,
    [IO.Compression.CompressionLevel]::Optimal,
    $false
)

$zip = [IO.Compression.ZipFile]::OpenRead($archivePath)
try {
    $entries = @($zip.Entries)
    if (@($entries | Where-Object { $_.FullName -match '\.(zip|7z|rar|exe|dll|bak|dmp|etl)$' }).Count -gt 0) {
        throw 'Forbidden nested binary, backup, trace or archive detected in release ZIP.'
    }
}
finally {
    $zip.Dispose()
}

$releaseHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText($hashPath, "$releaseHash *$archiveName`r`n", [Text.Encoding]::ASCII)
[IO.Directory]::Delete($stagingRoot, $true)

[pscustomobject]@{
    Archive = $archivePath
    Sha256 = $releaseHash.ToUpperInvariant()
    Entries = $entries.Count
}
