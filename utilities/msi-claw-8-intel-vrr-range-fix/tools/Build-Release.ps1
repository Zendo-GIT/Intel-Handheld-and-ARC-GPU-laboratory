[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version = '1.0.2'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$packageName = 'MSI-Claw-8-Intel-VRR-Range-Fix'
$distRoot = Join-Path $projectRoot 'dist'
$stagingRoot = Join-Path $distRoot ".staging-$packageName-$Version"
$stagedPackageRoot = Join-Path $stagingRoot $packageName
$archiveName = "$packageName-$Version.zip"
$archivePath = Join-Path $distRoot $archiveName
$hashPath = Join-Path $distRoot 'RELEASE_SHA256.txt'

$releaseFiles = @(
    'MSI-Claw-VRR-Fix.ps1',
    'ClawLab-VRR-Startup.vbs',
    'INSTALL_48_120_VRR.bat',
    'INSTALL_EXPERIMENTAL_30_120_VRR.bat',
    'INSTALL_EXPERIMENTAL_48_144_VRR.bat',
    'FACTORY_RESET_CLAWLAB_VRR.bat',
    'COLLECT_UNSUPPORTED_CLAW_DISPLAY.bat',
    'Collect-Claw-Display-Diagnostics.ps1',
    'RESTORE_ORIGINAL_VRR.bat',
    'CHECK_STATUS.bat',
    'EMERGENCY_REMOVE_EXPERIMENTAL_EDID.bat',
    'README.txt',
    'CHANGELOG.txt',
    'LICENSE.txt',
    'docs\COMPATIBILITY.md',
    'docs\SAFETY.md',
    'docs\TECHNICAL_DETAILS.md',
    'docs\NEXUS_MODS.md'
)

foreach ($relativePath in $releaseFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $relativePath) -PathType Leaf)) {
        throw "Release file missing: $relativePath"
    }
}

$scriptPath = Join-Path $projectRoot 'MSI-Claw-VRR-Fix.ps1'
$scriptText = Get-Content -LiteralPath $scriptPath -Raw
$expectedFixVersionLine = "`$fixVersion = '$Version'"
if ($scriptText -notmatch [regex]::Escape($expectedFixVersionLine)) {
    throw "Release version $Version does not match the source fix version."
}
$requiredIntegrityValues = @(
    'E49BC570225510B7C889ED292570F1345CAA07F5840DB57EA6998A403DB5CEF0',
    '14CDDC390CF69367C4B6821A46728518200446A33F708A1A87CA673B68B66918',
    '597D5A95C28171B7B9DF111C1BB12830532F63831EA38111E02D618850E76698',
    'C2000A5E8A3D91C80DCE75DC5BB2F63269C77501338FD059B4CF71CD0CE94743',
    '4CFB165CE96119BA37A07176F9D346691D447E0A40E8697777E499E1556A744E',
    '65E46C6D528BF69D31D17BB88FD47A17C98576597508CC75D3AD047A029A7172',
    'CA1A52F35378CB58709876EDD9BC648224D3C8AE0FA176E96A587BE8DABD8EB2',
    "[ValidateSet('Status', 'Install48', 'Install30', 'Install48_144', 'Restore', 'FactoryReset', 'EmergencyRestoreEdid', 'ApplyStartup')]",
    'ctlSetIntelArcSyncProfile',
    'Get-AuthenticodeSignature',
    'Start-ManagedIntelGraphicsSoftware',
    'Set-Experimental144DisplayMode',
    'WindowsDisplayMode',
    'FileSha256',
    'Assert-ProfileTransitionAllowed',
    'managed-mode.json',
    "'FactoryReset'",
    'Set-Safe120DisplayMode',
    "'Intel' + [char]0x00AE + ' Graphics Software'"
)
foreach ($value in $requiredIntegrityValues) {
    if ($scriptText -notmatch [regex]::Escape($value)) {
        throw "Required integrity value is missing from the release source: $value"
    }
}

$launcherPath = Join-Path $projectRoot 'ClawLab-VRR-Startup.vbs'
$launcherText = Get-Content -LiteralPath $launcherPath -Raw
foreach ($value in @(
    '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe',
    'shell.Run(command, 0, True)',
    '-Action ApplyStartup'
)) {
    if ($launcherText -notmatch [regex]::Escape($value)) {
        throw "Windowless launcher no longer contains required value: $value"
    }
}

$forbiddenExtensions = @('.exe', '.dll', '.sys', '.bin', '.rom', '.zip', '.7z', '.rar', '.bak', '.dmp', '.etl')
$forbiddenFiles = @(Get-ChildItem -LiteralPath $projectRoot -Recurse -File | Where-Object {
    $_.FullName -notmatch '[\\/]dist[\\/]' -and
    $forbiddenExtensions -contains $_.Extension.ToLowerInvariant()
})
if ($forbiddenFiles.Count -gt 0) {
    throw "Forbidden binary, driver, EDID dump, trace, backup or archive found:`n$($forbiddenFiles.FullName -join "`n")"
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

foreach ($relativePath in $releaseFiles) {
    $destination = Join-Path $stagedPackageRoot $relativePath
    [IO.Directory]::CreateDirectory((Split-Path $destination -Parent)) | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot $relativePath) -Destination $destination
}

$manifest = @(Get-ChildItem -LiteralPath $stagedPackageRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
    $relativePath = $_.FullName.Substring($stagedPackageRoot.Length + 1).Replace('\', '/')
    $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash *$relativePath"
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
    $forbiddenEntries = @($entries | Where-Object {
        [IO.Path]::GetExtension($_.FullName).ToLowerInvariant() -in $forbiddenExtensions
    })
    if ($forbiddenEntries.Count -gt 0) {
        throw "Forbidden file detected in release ZIP:`n$($forbiddenEntries.FullName -join "`n")"
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
