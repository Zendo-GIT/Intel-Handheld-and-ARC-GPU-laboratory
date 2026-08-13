[CmdletBinding()]
param(
    [string]$Version = '1.0.0'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [System.IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$packageName = 'Kena-Intel-Arc-Water-Flash-Fix'
$pakName = 'Kena-WindowsNoEditor_IntelArcWaterFlashFix_P.pak'
$pakPath = Join-Path $repositoryRoot "mod\$pakName"
$expectedPakHash = '6B8A19873CB65EA6CA33BA8A50CC90581A32F62A6A24C20E03A245A150CAD072'
$distRoot = Join-Path $repositoryRoot 'dist'
$archiveName = "$packageName-$Version.zip"
$archivePath = Join-Path $distRoot $archiveName
$releaseHashPath = Join-Path $distRoot 'RELEASE_SHA256.txt'
$stagingRoot = Join-Path $distRoot ".staging-$packageName-$Version"
$stagedPakDirectory = Join-Path $stagingRoot 'Kena\Content\Paks\~Mods'

$requiredSourceFiles = @(
    'nexus\README.txt',
    'nexus\CHANGELOG.txt',
    'nexus\LICENSE.txt'
)

if (-not (Test-Path -LiteralPath $pakPath -PathType Leaf)) {
    throw "Validated PAK not found: $pakPath"
}

$actualPakHash = (Get-FileHash -LiteralPath $pakPath -Algorithm SHA256).Hash
if ($actualPakHash -ne $expectedPakHash) {
    throw "PAK hash mismatch. Expected $expectedPakHash, got $actualPakHash"
}

foreach ($relativePath in $requiredSourceFiles) {
    $fullPath = Join-Path $repositoryRoot $relativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "Required release file missing: $fullPath"
    }
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

New-Item -ItemType Directory -Path $stagedPakDirectory -Force | Out-Null
Copy-Item -LiteralPath $pakPath -Destination $stagedPakDirectory
Copy-Item -LiteralPath (Join-Path $repositoryRoot 'nexus\README.txt') -Destination $stagingRoot
Copy-Item -LiteralPath (Join-Path $repositoryRoot 'nexus\CHANGELOG.txt') -Destination $stagingRoot
Copy-Item -LiteralPath (Join-Path $repositoryRoot 'nexus\LICENSE.txt') -Destination $stagingRoot

$manifestLines = @(
    Get-ChildItem -LiteralPath $stagingRoot -Recurse -File |
        Sort-Object FullName |
        ForEach-Object {
            $relative = $_.FullName.Substring($stagingRoot.Length + 1).Replace('\', '/')
            $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            "$hash *$relative"
        }
)
$manifestPath = Join-Path $stagingRoot 'FILES_SHA256.txt'
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
    $requiredEntries = @(
        "Kena/Content/Paks/~Mods/$pakName",
        'README.txt',
        'CHANGELOG.txt',
        'LICENSE.txt',
        'FILES_SHA256.txt'
    )
    foreach ($requiredEntry in $requiredEntries) {
        if ($requiredEntry -notin $entries.FullName) {
            throw "Required ZIP entry missing: $requiredEntry"
        }
    }

    $forbiddenEntries = @(
        $entries | Where-Object {
            [System.IO.Path]::GetExtension($_.FullName).ToLowerInvariant() -in
                @('.exe', '.dll', '.bat', '.cmd', '.zip', '.7z', '.rar')
        }
    )
    if ($forbiddenEntries.Count -gt 0) {
        throw "Forbidden release entry: $($forbiddenEntries.FullName -join ', ')"
    }
}
finally {
    $archive.Dispose()
}

$releaseHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
[System.IO.File]::WriteAllText(
    $releaseHashPath,
    "$($releaseHash.ToLowerInvariant()) *$archiveName`r`n",
    [System.Text.Encoding]::ASCII
)

[System.IO.Directory]::Delete($stagingRoot, $true)

[pscustomobject]@{
    Version = $Version
    Archive = $archivePath
    Bytes = (Get-Item -LiteralPath $archivePath).Length
    Sha256 = $releaseHash
    Entries = $entries.Count
    PakSha256 = $actualPakHash
    ContainsExecutable = $false
}
