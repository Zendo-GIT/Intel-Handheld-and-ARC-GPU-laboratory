[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version = '1.0.0'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$packageName = 'IEVR-Offline-Stutter-Fix'
$distRoot = Join-Path $repositoryRoot 'dist'
$stagingRoot = Join-Path $distRoot ".staging-$packageName-$Version"
$stagedPackageRoot = Join-Path $stagingRoot $packageName
$archiveName = "$packageName-$Version.zip"
$archivePath = Join-Path $distRoot $archiveName
$releaseHashPath = Join-Path $distRoot 'RELEASE_SHA256.txt'

$releaseFiles = @(
    'IEVR-Offline-Stutter-Fix.ps1'
    'INSTALL_OFFLINE_FIX.bat'
    'UNINSTALL_RESTORE_ONLINE.bat'
    'CHECK_STATUS.bat'
    'README.txt'
    'CHANGELOG.txt'
    'LICENSE.txt'
)

foreach ($relativePath in $releaseFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $repositoryRoot $relativePath) -PathType Leaf)) {
        throw "Release file missing: $relativePath"
    }
}

$forbiddenExtensions = @('.exe', '.dll', '.bak', '.etl', '.dmp', '.zip', '.7z', '.rar')
$forbiddenFiles = @(
    Get-ChildItem -LiteralPath $repositoryRoot -File -Recurse | Where-Object {
        $_.FullName -notmatch '[\\/]dist[\\/]' -and
        $_.FullName -notmatch '[\\/]\.git[\\/]' -and
        $forbiddenExtensions -contains $_.Extension.ToLowerInvariant()
    }
)
if ($forbiddenFiles.Count -gt 0) {
    throw "Forbidden binary, trace, backup, or archive found in source:`n$($forbiddenFiles.FullName -join "`n")"
}

$sourceTextFiles = @(
    Get-ChildItem -LiteralPath $repositoryRoot -File -Recurse | Where-Object {
        $_.FullName -notmatch '[\\/]dist[\\/]' -and
        $_.Extension.ToLowerInvariant() -in @('.ps1', '.bat', '.md', '.txt', '.yml')
    }
)
foreach ($file in $sourceTextFiles) {
    $text = Get-Content -LiteralPath $file.FullName -Raw
    if ($text -match '(?i)https?://[^\s)]*(wemod|anti.?cheat.?bypass)') {
        throw "A prohibited bypass link was found: $($file.FullName)"
    }
}

$powerShellFiles = @(Get-ChildItem -LiteralPath $repositoryRoot -Filter '*.ps1' -File -Recurse | Where-Object {
    $_.FullName -notmatch '[\\/]dist[\\/]'
})
foreach ($file in $powerShellFiles) {
    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if ($parseErrors.Count -gt 0) {
        throw "PowerShell parse failure in $($file.FullName):`n$($parseErrors | Out-String)"
    }
}

$distFull = [IO.Path]::GetFullPath($distRoot)
$stagingFull = [IO.Path]::GetFullPath($stagingRoot)
if (-not $stagingFull.StartsWith(
        $distFull + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase
    )) {
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

foreach ($relativePath in $releaseFiles) {
    Copy-Item -LiteralPath (Join-Path $repositoryRoot $relativePath) -Destination $stagedPackageRoot
}

$manifest = @(
    Get-ChildItem -LiteralPath $stagedPackageRoot -File |
        Sort-Object Name |
        ForEach-Object {
            $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            "$hash *$($_.Name)"
        }
)
[IO.File]::WriteAllLines(
    (Join-Path $stagedPackageRoot 'FILES_SHA256.txt'),
    $manifest,
    [Text.Encoding]::ASCII
)

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
    $entryNames = @($entries | ForEach-Object { $_.FullName.Replace('\', '/') })
    if ($entries.Count -ne 8) {
        throw "Unexpected release entry count: $($entries.Count)"
    }
    if (@($entries | Where-Object { $_.FullName -match '\.(exe|dll|bak|etl|dmp|zip|7z|rar)$' }).Count -gt 0) {
        throw 'Forbidden file detected inside the release ZIP.'
    }
    if (@($entryNames | Where-Object { $_ -notlike "$packageName/*" }).Count -gt 0) {
        throw 'A release entry is outside the expected top-level package folder.'
    }
}
finally {
    $zip.Dispose()
}

$releaseHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText(
    $releaseHashPath,
    "$releaseHash *$archiveName`r`n",
    [Text.Encoding]::ASCII
)
[IO.Directory]::Delete($stagingRoot, $true)

[pscustomobject]@{
    Archive = $archivePath
    Sha256 = $releaseHash.ToUpperInvariant()
    Entries = $entries.Count
}
