[CmdletBinding()]
param(
    [string]$Version = '1.0.0'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$arcRoot = [System.IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$packageName = 'JWE3-Intel-Arc-Water-Glitch-Fix'
$runtimeSource = Join-Path $arcRoot "nexus\$packageName"
$githubTemplate = Join-Path $arcRoot 'github'
$publishSource = Join-Path $arcRoot 'publish'
$distRoot = Join-Path $arcRoot 'dist'
$nexusZip = Join-Path $distRoot "$packageName-$Version.zip"
$releaseHash = Join-Path $distRoot 'RELEASE_SHA256.txt'
$publicationRoot = Join-Path $arcRoot 'Publish-Ready'
$bundleRoot = Join-Path $publicationRoot $packageName
$githubOutput = Join-Path $bundleRoot 'GitHub-Repository'
$nexusOutput = Join-Path $bundleRoot 'Nexus-Mods'

& (Join-Path $PSScriptRoot 'Build-NexusRelease.ps1') -Version $Version | Out-Host

foreach ($requiredPath in @($runtimeSource, $githubTemplate, $publishSource, $nexusZip, $releaseHash)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required publication input missing: $requiredPath"
    }
}

$publicationFull = [System.IO.Path]::GetFullPath($publicationRoot)
$bundleFull = [System.IO.Path]::GetFullPath($bundleRoot)
if (-not $bundleFull.StartsWith(
        $publicationFull + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
    throw "Unsafe publication output: $bundleFull"
}

New-Item -ItemType Directory -Path $publicationRoot -Force | Out-Null
if (Test-Path -LiteralPath $bundleRoot) {
    [System.IO.Directory]::Delete($bundleRoot, $true)
}
New-Item -ItemType Directory -Path $githubOutput -Force | Out-Null
New-Item -ItemType Directory -Path $nexusOutput -Force | Out-Null

Get-ChildItem -LiteralPath $githubTemplate -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $githubOutput -Recurse
}
Get-ChildItem -LiteralPath $runtimeSource -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $githubOutput -Recurse
}

Copy-Item -LiteralPath $nexusZip -Destination $nexusOutput
Copy-Item -LiteralPath $releaseHash -Destination $nexusOutput
foreach ($file in @('NEXUS_PAGE.txt', 'MAIN_FILE_DESCRIPTION.txt', 'UPLOAD_CHECKLIST.md')) {
    Copy-Item -LiteralPath (Join-Path $publishSource $file) -Destination $nexusOutput
}
$publishImages = Join-Path $publishSource 'images'
if (Test-Path -LiteralPath $publishImages -PathType Container) {
    Copy-Item -LiteralPath $publishImages -Destination $nexusOutput -Recurse
}
Copy-Item -LiteralPath (Join-Path $publishSource 'PUBLISH_READY_README.txt') -Destination (Join-Path $bundleRoot 'README_FIRST.txt')

$forbiddenRepositoryExtensions = @('.exe', '.dll', '.ovl', '.arc', '.bak', '.dxil', '.zip', '.7z', '.rar')
$forbiddenRepositoryFiles = @(
    Get-ChildItem -LiteralPath $githubOutput -Recurse -File | Where-Object {
        $forbiddenRepositoryExtensions -contains $_.Extension.ToLowerInvariant()
    }
)
if ($forbiddenRepositoryFiles.Count -gt 0) {
    throw "Forbidden file in public repository:`n$($forbiddenRepositoryFiles.FullName -join "`n")"
}

$zipInfo = [System.IO.Compression.ZipFile]::OpenRead((Join-Path $nexusOutput "$packageName-$Version.zip"))
try {
    $zipEntries = @($zipInfo.Entries)
    $nestedArchives = @(
        $zipEntries | Where-Object { $_.FullName -match '\.(zip|7z|rar)$' }
    )
    if ($nestedArchives.Count -gt 0) {
        throw 'The Nexus ZIP contains a nested archive.'
    }
}
finally {
    $zipInfo.Dispose()
}

$artifactLines = @(
    Get-ChildItem -LiteralPath $bundleRoot -Recurse -File |
        Sort-Object FullName |
        ForEach-Object {
            $relative = $_.FullName.Substring($bundleRoot.Length + 1).Replace('\', '/')
            $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            "$hash *$relative"
        }
)
[System.IO.File]::WriteAllLines(
    (Join-Path $bundleRoot 'ARTIFACTS_SHA256.txt'),
    $artifactLines,
    [System.Text.Encoding]::ASCII
)

[pscustomobject]@{
    PublicationFolder = $bundleRoot
    GitHubRepositoryFolder = $githubOutput
    NexusFolder = $nexusOutput
    NexusZip = Join-Path $nexusOutput "$packageName-$Version.zip"
    NexusZipSha256 = (Get-FileHash -LiteralPath (Join-Path $nexusOutput "$packageName-$Version.zip") -Algorithm SHA256).Hash
    NexusZipEntries = $zipEntries.Count
    NestedArchives = 0
    RepositoryGameBinaries = 0
}
