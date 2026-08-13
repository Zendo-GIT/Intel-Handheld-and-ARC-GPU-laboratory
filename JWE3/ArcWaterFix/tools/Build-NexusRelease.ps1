[CmdletBinding()]
param(
    [string]$Version = '1.0.0'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$arcWaterFixRoot = [System.IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$packageName = 'JWE3-Intel-Arc-Water-Glitch-Fix'
$sourceRoot = Join-Path $arcWaterFixRoot "nexus\$packageName"
$distRoot = Join-Path $arcWaterFixRoot 'dist'
$archiveName = "$packageName-$Version.zip"
$archivePath = Join-Path $distRoot $archiveName
$releaseHashPath = Join-Path $distRoot 'RELEASE_SHA256.txt'
$stagingRoot = Join-Path $distRoot ".staging-$packageName-$Version"
$stagedPackageRoot = Join-Path $stagingRoot $packageName

if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
    throw "Package source not found: $sourceRoot"
}

$requiredFiles = @(
    'JWE3-IntelArc-WaterFix.ps1',
    'INSTALL_FIX.bat',
    'UNINSTALL_FIX.bat',
    'CHECK_STATUS.bat',
    'README.txt',
    'CHANGELOG.txt',
    'LICENSE.txt'
)
foreach ($requiredFile in $requiredFiles) {
    $requiredPath = Join-Path $sourceRoot $requiredFile
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required package file missing: $requiredPath"
    }
}

$forbiddenExtensions = @('.exe', '.dll', '.ovl', '.arc', '.bak', '.zip', '.7z', '.rar')
$forbiddenFiles = @(
    Get-ChildItem -LiteralPath $sourceRoot -Recurse -File | Where-Object {
        $forbiddenExtensions -contains $_.Extension.ToLowerInvariant()
    }
)
if ($forbiddenFiles.Count -gt 0) {
    throw "Forbidden or copyrighted binary/archive in package source:`n$($forbiddenFiles.FullName -join "`n")"
}

$parseErrors = $null
$scriptPath = Join-Path $sourceRoot 'JWE3-IntelArc-WaterFix.ps1'
[System.Management.Automation.Language.Parser]::ParseFile(
    $scriptPath,
    [ref]$null,
    [ref]$parseErrors
) | Out-Null
if ($parseErrors.Count -gt 0) {
    throw "PowerShell syntax validation failed:`n$($parseErrors.Message -join "`n")"
}

New-Item -ItemType Directory -Path $distRoot -Force | Out-Null
$distFullPath = [System.IO.Path]::GetFullPath($distRoot)
$stagingFullPath = [System.IO.Path]::GetFullPath($stagingRoot)
if (-not $stagingFullPath.StartsWith(
        $distFullPath + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
    throw "Unsafe staging path: $stagingFullPath"
}

if (Test-Path -LiteralPath $stagingRoot) {
    [System.IO.Directory]::Delete($stagingRoot, $true)
}
if (Test-Path -LiteralPath $archivePath) {
    [System.IO.File]::Delete($archivePath)
}

New-Item -ItemType Directory -Path $stagedPackageRoot -Force | Out-Null
Copy-Item -Path (Join-Path $sourceRoot '*') -Destination $stagedPackageRoot -Recurse

$manifestLines = @(
    Get-ChildItem -LiteralPath $stagedPackageRoot -Recurse -File |
        Sort-Object FullName |
        ForEach-Object {
            $relative = $_.FullName.Substring($stagedPackageRoot.Length + 1).Replace('\', '/')
            $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            "$hash *$relative"
        }
)
$manifestPath = Join-Path $stagedPackageRoot 'FILES_SHA256.txt'
[System.IO.File]::WriteAllLines($manifestPath, $manifestLines, [System.Text.Encoding]::ASCII)

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory(
    $stagingRoot,
    $archivePath,
    [System.IO.Compression.CompressionLevel]::Optimal,
    $false
)

$archive = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
try {
    $entries = @($archive.Entries)
    $nestedArchives = @(
        $entries | Where-Object {
            [System.IO.Path]::GetExtension($_.FullName).ToLowerInvariant() -in @('.zip', '.7z', '.rar')
        }
    )
    if ($nestedArchives.Count -gt 0) {
        throw "Nested archive detected in release: $($nestedArchives.FullName -join ', ')"
    }
    foreach ($requiredFile in $requiredFiles) {
        $expectedEntry = "$packageName/$requiredFile"
        if ($expectedEntry -notin $entries.FullName) {
            throw "Required ZIP entry missing: $expectedEntry"
        }
    }
}
finally {
    $archive.Dispose()
}

$releaseHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
[System.IO.File]::WriteAllText(
    $releaseHashPath,
    "$releaseHash *$archiveName`r`n",
    [System.Text.Encoding]::ASCII
)

[System.IO.Directory]::Delete($stagingRoot, $true)

[pscustomobject]@{
    Version = $Version
    Archive = $archivePath
    Bytes = (Get-Item -LiteralPath $archivePath).Length
    Sha256 = $releaseHash.ToUpperInvariant()
    Entries = $entries.Count
    NestedArchives = 0
    ContainsGameExecutable = $false
}
