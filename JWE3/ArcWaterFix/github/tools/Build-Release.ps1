[CmdletBinding()]
param(
    [string]$Version = '1.0.0'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [System.IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$packageName = 'JWE3-Intel-Arc-Water-Glitch-Fix'
$distRoot = Join-Path $repositoryRoot 'dist'
$stagingRoot = Join-Path $distRoot ".staging-$packageName-$Version"
$stagedPackageRoot = Join-Path $stagingRoot $packageName
$archiveName = "$packageName-$Version.zip"
$archivePath = Join-Path $distRoot $archiveName
$hashPath = Join-Path $distRoot 'RELEASE_SHA256.txt'

$releaseFiles = @(
    'JWE3-IntelArc-WaterFix.ps1',
    'INSTALL_FIX.bat',
    'UNINSTALL_FIX.bat',
    'CHECK_STATUS.bat',
    'README.txt',
    'CHANGELOG.txt',
    'LICENSE.txt'
)
foreach ($file in $releaseFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $repositoryRoot $file) -PathType Leaf)) {
        throw "Release file missing: $file"
    }
}

$forbiddenExtensions = @('.exe', '.dll', '.ovl', '.arc', '.bak', '.zip', '.7z', '.rar', '.dxil')
$trackedSourceFiles = @(
    Get-ChildItem -LiteralPath $repositoryRoot -Recurse -File | Where-Object {
        $_.FullName -notmatch '[\\/]dist[\\/]' -and
        $_.FullName -notmatch '[\\/]\.git[\\/]' -and
        $forbiddenExtensions -contains $_.Extension.ToLowerInvariant()
    }
)
if ($trackedSourceFiles.Count -gt 0) {
    throw "Forbidden binary or archive found:`n$($trackedSourceFiles.FullName -join "`n")"
}

$distFull = [System.IO.Path]::GetFullPath($distRoot)
$stagingFull = [System.IO.Path]::GetFullPath($stagingRoot)
if (-not $stagingFull.StartsWith(
        $distFull + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
    throw "Unsafe staging path: $stagingFull"
}

New-Item -ItemType Directory -Path $distRoot -Force | Out-Null
if (Test-Path -LiteralPath $stagingRoot) {
    [System.IO.Directory]::Delete($stagingRoot, $true)
}
if (Test-Path -LiteralPath $archivePath) {
    [System.IO.File]::Delete($archivePath)
}
New-Item -ItemType Directory -Path $stagedPackageRoot -Force | Out-Null

foreach ($file in $releaseFiles) {
    Copy-Item -LiteralPath (Join-Path $repositoryRoot $file) -Destination $stagedPackageRoot
}

$manifest = @(
    Get-ChildItem -LiteralPath $stagedPackageRoot -File |
        Sort-Object Name |
        ForEach-Object {
            $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            "$hash *$($_.Name)"
        }
)
[System.IO.File]::WriteAllLines(
    (Join-Path $stagedPackageRoot 'FILES_SHA256.txt'),
    $manifest,
    [System.Text.Encoding]::ASCII
)

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory(
    $stagingRoot,
    $archivePath,
    [System.IO.Compression.CompressionLevel]::Optimal,
    $false
)

$zip = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
try {
    $entries = @($zip.Entries)
    if (@($entries | Where-Object { $_.FullName -match '\.(zip|7z|rar)$' }).Count -gt 0) {
        throw 'Nested archive detected in release ZIP.'
    }
}
finally {
    $zip.Dispose()
}

$releaseHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
[System.IO.File]::WriteAllText(
    $hashPath,
    "$releaseHash *$archiveName`r`n",
    [System.Text.Encoding]::ASCII
)
[System.IO.Directory]::Delete($stagingRoot, $true)

[pscustomobject]@{
    Archive = $archivePath
    Sha256 = $releaseHash.ToUpperInvariant()
    Entries = $entries.Count
}
