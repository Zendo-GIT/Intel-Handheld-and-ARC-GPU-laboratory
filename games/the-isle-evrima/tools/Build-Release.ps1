[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version = '1.0.0'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$packageName = 'The-Isle-Evrima-MSI-Claw-Performance-Fix'
$distRoot = Join-Path $projectRoot 'dist'
$stagingRoot = Join-Path $distRoot ".staging-$packageName-$Version"
$stagedPackageRoot = Join-Path $stagingRoot $packageName
$archiveName = "$packageName-$Version.zip"
$archivePath = Join-Path $distRoot $archiveName
$releaseHashPath = Join-Path $distRoot 'RELEASE_SHA256.txt'

$releaseFiles = @(
    'The-Isle-Evrima-Claw-Fix.ps1',
    'INSTALL_FIX.bat',
    'UNINSTALL_FIX.bat',
    'CHECK_STATUS.bat',
    'README.txt',
    'CHANGELOG.txt',
    'LICENSE.txt'
)

foreach ($relativePath in $releaseFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $relativePath) -PathType Leaf)) {
        throw "Release file missing: $relativePath"
    }
}

$toolPath = Join-Path $projectRoot 'The-Isle-Evrima-Claw-Fix.ps1'
$toolText = Get-Content -LiteralPath $toolPath -Raw
foreach ($marker in @(
        "`$FixVersion = '$Version'",
        "`$ValidatedBuildId = '24664737'",
        "`$ValidatedGameVersion = '0.21.784'",
        'BuildIdOverride is restricted to an isolated test configuration directory.',
        'CONFIGURATION_ONLY_NO_INJECTION',
        'Set-ReadOnly -LiteralPath $enginePath -Enabled $true',
        'Set-ReadOnly -LiteralPath $gameUserSettingsPath -Enabled $true',
        'Assert-SupportedDisplayProfile',
        'Restore-OperationSnapshot',
        'Unsupported or unverified Steam build'
    )) {
    if ($toolText -notmatch [regex]::Escape($marker)) {
        throw "Required release safeguard is missing: $marker"
    }
}
foreach ($forbiddenMarker in @(
        'D3D12.PSO.DiskCache',
        'D3D12.PSO.DriverOptimizedDiskCache',
        'WriteProcessMemory',
        'EasyAntiCheat_EOS_Setup',
        'netsh advfirewall'
    )) {
    if ($toolText -match [regex]::Escape($forbiddenMarker)) {
        throw "Forbidden or ineffective public mechanism found: $forbiddenMarker"
    }
}

$powerShellFiles = @(
    Get-ChildItem -LiteralPath $projectRoot -Filter '*.ps1' -File -Recurse |
        Where-Object { $_.FullName -notmatch '[\\/]dist[\\/]' }
)
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

& (Join-Path $PSScriptRoot 'Test-Profile.ps1') | Out-Host

$forbiddenExtensions = @('.exe', '.dll', '.pak', '.bak', '.etl', '.dmp', '.zip', '.7z', '.rar')
$forbiddenSourceFiles = @(
    Get-ChildItem -LiteralPath $projectRoot -Recurse -File | Where-Object {
        $_.FullName -notmatch '[\\/]dist[\\/]' -and
        $forbiddenExtensions -contains $_.Extension.ToLowerInvariant()
    }
)
if ($forbiddenSourceFiles.Count -gt 0) {
    throw "Forbidden binary, game asset, trace, backup or archive found:`n$($forbiddenSourceFiles.FullName -join "`n")"
}

$distFull = [IO.Path]::GetFullPath($distRoot)
$stagingFull = [IO.Path]::GetFullPath($stagingRoot)
if (-not $stagingFull.StartsWith(
        $distFull + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase
    )) {
    throw "Unsafe staging path: $stagingFull"
}

[IO.Directory]::CreateDirectory($distRoot) | Out-Null
if (Test-Path -LiteralPath $stagingRoot) {
    [IO.Directory]::Delete($stagingRoot, $true)
}
if (Test-Path -LiteralPath $archivePath) {
    [IO.File]::Delete($archivePath)
}
[IO.Directory]::CreateDirectory($stagedPackageRoot) | Out-Null

foreach ($relativePath in $releaseFiles) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $relativePath) -Destination $stagedPackageRoot
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
    foreach ($requiredEntry in @(
            "$packageName/The-Isle-Evrima-Claw-Fix.ps1",
            "$packageName/INSTALL_FIX.bat",
            "$packageName/UNINSTALL_FIX.bat",
            "$packageName/CHECK_STATUS.bat",
            "$packageName/README.txt",
            "$packageName/CHANGELOG.txt",
            "$packageName/LICENSE.txt",
            "$packageName/FILES_SHA256.txt"
        )) {
        if ($requiredEntry -notin $entryNames) {
            throw "Required ZIP entry missing: $requiredEntry"
        }
    }
    if (@($entries | Where-Object { $_.FullName -match '\.(exe|dll|pak|bak|etl|dmp|zip|7z|rar)$' }).Count -gt 0) {
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
    Version = $Version
    Archive = $archivePath
    Sha256 = $releaseHash.ToUpperInvariant()
    Entries = $entries.Count
    ContainsGameBinary = $false
    AntiCheatMethod = 'CONFIGURATION_ONLY_NO_INJECTION'
}
