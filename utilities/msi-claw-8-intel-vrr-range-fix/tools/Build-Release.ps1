[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version = '2.1.2'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$packageName = 'MSI-Claw-Intel-VRR-Range-Fix'
$distRoot = Join-Path $projectRoot 'dist'
$stagingRoot = Join-Path $distRoot ".staging-$packageName-$Version"
$stagedPackageRoot = Join-Path $stagingRoot $packageName
$archiveName = "$packageName-$Version.zip"
$archivePath = Join-Path $distRoot $archiveName
$hashPath = Join-Path $distRoot 'RELEASE_SHA256.txt'
$cursorHelperRelativePath = 'ClawLab-Cursor-Refresh-Helper.exe'
$cursorHelperPath = Join-Path $projectRoot $cursorHelperRelativePath
$cursorHelperBuilder = Join-Path $projectRoot 'tools\CursorRefreshHelper\Build-CursorRefreshHelper.ps1'

& $cursorHelperBuilder -OutputDirectory $projectRoot | Out-Host
if (-not (Test-Path -LiteralPath $cursorHelperPath -PathType Leaf)) {
    throw 'Cursor Refresh Helper build did not produce the expected executable.'
}
$cursorHelperAssembly = [Reflection.AssemblyName]::GetAssemblyName($cursorHelperPath)
if ($cursorHelperAssembly.Version.ToString() -ne "$Version.0") {
    throw "Cursor Refresh Helper version $($cursorHelperAssembly.Version) does not match release $Version."
}
$cursorHelperSourcePath = Join-Path $projectRoot 'tools\CursorRefreshHelper\ClawLabCursorRefreshHelperWpf.cs'
$cursorHelperSourceText = Get-Content -LiteralPath $cursorHelperSourcePath -Raw
foreach ($value in @('1500L / 1000L', 'NearBlackBrush', 'RegisterRawInputDevices', 'SetProcessWorkingSetSize', 'timeEndPeriod(1)')) {
    if ($cursorHelperSourceText -notmatch [regex]::Escape($value)) {
        throw "Cursor Refresh Helper source is missing the validated allocation-free marker: $value"
    }
}
foreach ($forbiddenMarker in @('GetRawInputData', 'AllocHGlobal', 'FreeHGlobal')) {
    if ($cursorHelperSourceText -match [regex]::Escape($forbiddenMarker)) {
        throw "Cursor Refresh Helper source reintroduced a per-packet native allocation path: $forbiddenMarker"
    }
}

$releaseFiles = @(
    [pscustomobject]@{ Source = 'INSTALL_48_120_VRR.bat'; Destination = 'INSTALL_48_120_VRR.bat' },
    [pscustomobject]@{ Source = 'INSTALL_30_120_VRR.bat'; Destination = 'INSTALL_30_120_VRR.bat' },
    [pscustomobject]@{ Source = 'CHECK_STATUS.bat'; Destination = 'CHECK_STATUS.bat' },
    [pscustomobject]@{ Source = 'README.txt'; Destination = 'README.txt' },
    [pscustomobject]@{ Source = 'CHANGELOG.txt'; Destination = 'CHANGELOG.txt' },
    [pscustomobject]@{ Source = 'LICENSE.txt'; Destination = 'LICENSE.txt' },

    [pscustomobject]@{ Source = 'RESTORE_ORIGINAL_VRR.bat'; Destination = 'RECOVERY\RESTORE_ORIGINAL_VRR.bat' },
    [pscustomobject]@{ Source = 'RESTORE_INTEL_LFC_DEFAULTS.bat'; Destination = 'RECOVERY\RESTORE_INTEL_LFC_DEFAULTS.bat' },
    [pscustomobject]@{ Source = 'FACTORY_RESET_CLAWLAB_VRR.bat'; Destination = 'EMERGENCY\FACTORY_RESET_CLAWLAB_VRR.bat' },
    [pscustomobject]@{ Source = 'EMERGENCY_REMOVE_CLAWLAB_EDID.bat'; Destination = 'EMERGENCY\EMERGENCY_REMOVE_CLAWLAB_EDID.bat' },
    [pscustomobject]@{ Source = 'SET_INTEL_LFC_FACTORY_DEFAULTS.bat'; Destination = 'EMERGENCY\SET_INTEL_LFC_FACTORY_DEFAULTS.bat' },
    [pscustomobject]@{ Source = 'COLLECT_UNSUPPORTED_CLAW_DISPLAY.bat'; Destination = 'DIAGNOSTICS\COLLECT_UNSUPPORTED_CLAW_DISPLAY.bat' },
    [pscustomobject]@{ Source = 'EXPORT_STATUS_REPORT.bat'; Destination = 'DIAGNOSTICS\EXPORT_STATUS_REPORT.bat' },

    [pscustomobject]@{ Source = 'MSI-Claw-VRR-Fix.ps1'; Destination = 'scripts\MSI-Claw-VRR-Fix.ps1' },
    [pscustomobject]@{ Source = 'MSI-Claw-Intel-LFC-Fix.ps1'; Destination = 'scripts\MSI-Claw-Intel-LFC-Fix.ps1' },
    [pscustomobject]@{ Source = 'Intel-VRR-LFC-Driver-Interface.ps1'; Destination = 'scripts\Intel-VRR-LFC-Driver-Interface.ps1' },
    [pscustomobject]@{ Source = 'ClawLab-Health-Check.ps1'; Destination = 'scripts\ClawLab-Health-Check.ps1' },
    [pscustomobject]@{ Source = 'Export-ClawLab-Status.ps1'; Destination = 'scripts\Export-ClawLab-Status.ps1' },
    [pscustomobject]@{ Source = 'Collect-Claw-Display-Diagnostics.ps1'; Destination = 'scripts\Collect-Claw-Display-Diagnostics.ps1' },
    [pscustomobject]@{ Source = 'Edid-Normalization.ps1'; Destination = 'scripts\Edid-Normalization.ps1' },
    [pscustomobject]@{ Source = 'Lfc-Backup-Identity.ps1'; Destination = 'scripts\Lfc-Backup-Identity.ps1' },
    [pscustomobject]@{ Source = 'ClawLab-Cursor-Refresh-Helper.exe'; Destination = 'scripts\ClawLab-Cursor-Refresh-Helper.exe' },
    [pscustomobject]@{ Source = 'ClawLab-VRR-Startup.vbs'; Destination = 'scripts\ClawLab-VRR-Startup.vbs' },
    [pscustomobject]@{ Source = 'ClawLab-LFC-Startup.vbs'; Destination = 'scripts\ClawLab-LFC-Startup.vbs' },

    [pscustomobject]@{ Source = 'docs\COMPATIBILITY.md'; Destination = 'docs\COMPATIBILITY.md' },
    [pscustomobject]@{ Source = 'docs\SAFETY.md'; Destination = 'docs\SAFETY.md' },
    [pscustomobject]@{ Source = 'docs\TECHNICAL_DETAILS.md'; Destination = 'docs\TECHNICAL_DETAILS.md' },
    [pscustomobject]@{ Source = 'docs\NEXUS_MODS.md'; Destination = 'docs\NEXUS_MODS.md' },
    [pscustomobject]@{ Source = 'docs\A1M_EDID_REFERENCE.md'; Destination = 'docs\A1M_EDID_REFERENCE.md' },
    [pscustomobject]@{ Source = 'docs\RELEASE_NOTES_2.1.2.md'; Destination = 'docs\RELEASE_NOTES_2.1.2.md' },

    [pscustomobject]@{ Source = 'tools\Test-A1M-Edid.ps1'; Destination = 'SOURCE\Test-A1M-Edid.ps1' },
    [pscustomobject]@{ Source = 'tools\Test-Lfc-Backup-Identity.ps1'; Destination = 'SOURCE\Test-Lfc-Backup-Identity.ps1' },
    [pscustomobject]@{ Source = 'tools\CursorRefreshHelper\ClawLabCursorRefreshHelperWpf.cs'; Destination = 'SOURCE\CursorRefreshHelper\ClawLabCursorRefreshHelperWpf.cs' },
    [pscustomobject]@{ Source = 'tools\CursorRefreshHelper\Build-CursorRefreshHelper.ps1'; Destination = 'SOURCE\CursorRefreshHelper\Build-CursorRefreshHelper.ps1' },
    [pscustomobject]@{ Source = 'tools\CursorRefreshHelper\README.md'; Destination = 'SOURCE\CursorRefreshHelper\README.md' }
)

foreach ($releaseFile in $releaseFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $releaseFile.Source) -PathType Leaf)) {
        throw "Release file missing: $($releaseFile.Source)"
    }
}

$retiredPublicFiles = @(
    'INSTALL_EXPERIMENTAL_48_144_VRR.bat',
    'INSTALL_EXPERIMENTAL_30_144_VRR.bat',
    'Experimental-144-VRR-Trial.ps1',
    'ClawLab-144-Trial-Startup.vbs'
)
foreach ($relativePath in $retiredPublicFiles) {
    if (Test-Path -LiteralPath (Join-Path $projectRoot $relativePath)) {
        throw "Retired 144 Hz public file must not exist: $relativePath"
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
    '0B8E8A25325B4D9CAC2B6A03CF9B574688B1A6D2DEDF10401605C4898E0CAC05',
    '7773D16AFD7F0C9AE0363D1FDE684C12E20F460DB5815516EF76633F70FBF60D',
    '8AD37320E4C2FF8DF4E71E205241A152DA3136CB0BE25F54E7A78D6273317640',
    '3518AB4456669D12A7B8D254F63005EAE143C784DCE02EC56C3753C41A664CA1',
    '7B5EE7D96BC91E83EBD2419B3A4F12771035D76303F77EEB0E356C996BFA4647',
    "Name = 'TL070FVXS02-0'",
    "[ValidateSet('Status', 'Install48', 'Install30', 'Restore', 'FactoryReset', 'EmergencyRestoreEdid', 'ApplyStartup')]",
    'ctlSetIntelArcSyncProfile',
    'Get-AuthenticodeSignature',
    'Start-ManagedIntelGraphicsSoftware',
    'Write-IntelStartupBackupAtomically',
    'Set-IntelStartupTrustedIdentity',
    'OriginalEntryPresent',
    'SchemaVersion = 4',
    'Set-IntelStartupAbsentState',
    'last-error.txt',
    'Remove-FileIfPresent',
    'IdentityVerifiedAt',
    'WindowsDisplayMode',
    'FileSha256',
    'Assert-ProfileTransitionAllowed',
    'managed-mode.json',
    "'FactoryReset'",
    'This retired 144 Hz profile is no longer reapplied',
    'Set-Safe120DisplayMode',
    "'Intel' + [char]0x00AE + ' Graphics Software'"
    'Install-CursorRefreshHelper',
    'Start-CursorRefreshHelper',
    'Remove-CursorRefreshHelper',
    'RUNNING_EVENT_DRIVEN',
    'VERSION_MISMATCH'
    'CLAW_A1M_CLAW_7_AI_PLUS'
)
foreach ($value in $requiredIntegrityValues) {
    if ($scriptText -notmatch [regex]::Escape($value)) {
        throw "Required integrity value is missing from the release source: $value"
    }
}
foreach ($forbiddenMarker in @("'Install48_144'", "'Install30_144'", 'function Set-Experimental144DisplayMode')) {
    if ($scriptText -match [regex]::Escape($forbiddenMarker)) {
        throw "Retired 144 Hz installation capability remains in the release source: $forbiddenMarker"
    }
}

$edidNormalizationText = Get-Content -LiteralPath (Join-Path $projectRoot 'Edid-Normalization.ps1') -Raw
foreach ($value in @('ZERO_PADDED_128_NORMALIZED', '$baseBlock[126] -eq 0', '$Bytes[$index] -ne 0')) {
    if ($edidNormalizationText -notmatch [regex]::Escape($value)) {
        throw "EDID normalization safety module is missing: $value"
    }
}

$a1mCatalogTest = Join-Path $projectRoot 'tools\Test-A1M-Edid.ps1'
$a1mResult = & $a1mCatalogTest
if ($null -eq $a1mResult -or [string]$a1mResult.Result -ne 'PASS') {
    throw 'The pinned Claw A1M EDID generator test failed.'
}

$lfcIdentityTest = Join-Path $projectRoot 'tools\Test-Lfc-Backup-Identity.ps1'
$lfcIdentityResult = & $lfcIdentityTest
if ($null -eq $lfcIdentityResult -or [string]$lfcIdentityResult.Result -ne 'PASS') {
    throw 'The Intel LFC stable backup identity test failed.'
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

$lfcScriptText = Get-Content -LiteralPath (Join-Path $projectRoot 'MSI-Claw-Intel-LFC-Fix.ps1') -Raw
foreach ($value in @(
    "`$toolVersion = '2.0.4'",
    'DIRECT_D3DKMT_INTEL_PRIVATE_ESCAPE',
    "'OFFICIAL_48_120'",
    "'CLAWLAB_30_120'",
    "'CLAWLAB_48_144'",
    "'CLAWLAB_30_144'",
    '$managedProfiles.ContainsKey($managedModeName)',
    'OriginalLowFpsSolutionEnabled',
    'OriginalHighFpsSolutionEnabled',
    'Remove-FileIfPresent',
    'ClawLab MSI Claw Intel LFC Fix'
    '$rangeProcess.WaitForExit()'
    'TL070FVXS02-0'
    '3518AB4456669D12A7B8D254F63005EAE143C784DCE02EC56C3753C41A664CA1'
    '7B5EE7D96BC91E83EBD2419B3A4F12771035D76303F77EEB0E356C996BFA4647'
    'Resolve-ClawLabLfcBackupIdentity'
    'SchemaVersion = 4'
    'InstanceMigrationCount'
)) {
    if ($lfcScriptText -notmatch [regex]::Escape($value)) {
        throw "Required LFC safety value is missing from the release source: $value"
    }
}
if ($lfcScriptText -match [regex]::Escape('-WindowStyle Hidden -Wait -PassThru')) {
    throw 'The LFC startup path must not wait for the resident helper process tree.'
}

$lfcInstallers = @(
    'INSTALL_30_120_VRR.bat',
    'INSTALL_48_120_VRR.bat'
)
foreach ($installerName in $lfcInstallers) {
    $installerText = Get-Content -LiteralPath (Join-Path $projectRoot $installerName) -Raw
    if ($installerText -notmatch [regex]::Escape('MSI-Claw-Intel-LFC-Fix.ps1" -Action Apply')) {
        throw "Managed VRR installer does not integrate the shared LFC fix: $installerName"
    }
}

$forbiddenExtensions = @('.exe', '.dll', '.sys', '.bin', '.rom', '.zip', '.7z', '.rar', '.bak', '.dmp', '.etl')
$forbiddenFiles = @(Get-ChildItem -LiteralPath $projectRoot -Recurse -File | Where-Object {
    $_.FullName -notmatch '[\\/]dist[\\/]' -and
    $forbiddenExtensions -contains $_.Extension.ToLowerInvariant() -and
    -not $_.FullName.Equals($cursorHelperPath, [StringComparison]::OrdinalIgnoreCase)
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

foreach ($releaseFile in $releaseFiles) {
    $destination = Join-Path $stagedPackageRoot $releaseFile.Destination
    [IO.Directory]::CreateDirectory((Split-Path $destination -Parent)) | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot $releaseFile.Source) -Destination $destination
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
        [IO.Path]::GetExtension($_.FullName).ToLowerInvariant() -in $forbiddenExtensions -and
        -not $_.FullName.Replace('/', '\').EndsWith("\$cursorHelperRelativePath", [StringComparison]::OrdinalIgnoreCase)
    })
    if ($forbiddenEntries.Count -gt 0) {
        throw "Forbidden file detected in release ZIP:`n$($forbiddenEntries.FullName -join "`n")"
    }

    $packagePrefix = "$packageName/"
    $relativeEntries = @($entries | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Name) } | ForEach-Object {
            if (-not $_.FullName.StartsWith($packagePrefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Release ZIP entry escaped the package root: $($_.FullName)"
            }
            $_.FullName.Substring($packagePrefix.Length)
        })
    $expectedRootFiles = @(
        'INSTALL_30_120_VRR.bat',
        'INSTALL_48_120_VRR.bat',
        'CHECK_STATUS.bat',
        'README.txt',
        'CHANGELOG.txt',
        'LICENSE.txt',
        'FILES_SHA256.txt'
    )
    $actualRootFiles = @($relativeEntries | Where-Object { $_ -notmatch '/' } | Sort-Object)
    $unexpectedRootFiles = @($actualRootFiles | Where-Object { $_ -notin $expectedRootFiles })
    $missingRootFiles = @($expectedRootFiles | Where-Object { $_ -notin $actualRootFiles })
    if ($unexpectedRootFiles.Count -gt 0 -or $missingRootFiles.Count -gt 0) {
        throw "Unexpected public ZIP root layout. Missing: $($missingRootFiles -join ', '). Unexpected: $($unexpectedRootFiles -join ', ')."
    }
    foreach ($requiredEntry in @(
            'RECOVERY/RESTORE_ORIGINAL_VRR.bat',
            'RECOVERY/RESTORE_INTEL_LFC_DEFAULTS.bat',
            'EMERGENCY/FACTORY_RESET_CLAWLAB_VRR.bat',
            'EMERGENCY/EMERGENCY_REMOVE_CLAWLAB_EDID.bat',
            'EMERGENCY/SET_INTEL_LFC_FACTORY_DEFAULTS.bat',
            'DIAGNOSTICS/COLLECT_UNSUPPORTED_CLAW_DISPLAY.bat',
            'DIAGNOSTICS/EXPORT_STATUS_REPORT.bat',
            'scripts/MSI-Claw-VRR-Fix.ps1',
            'scripts/MSI-Claw-Intel-LFC-Fix.ps1',
            'scripts/ClawLab-Health-Check.ps1',
            'scripts/Export-ClawLab-Status.ps1',
            'scripts/Edid-Normalization.ps1',
            'scripts/Lfc-Backup-Identity.ps1',
            'scripts/ClawLab-Cursor-Refresh-Helper.exe'
        )) {
        if ($requiredEntry -notin $relativeEntries) {
            throw "Required structured ZIP entry is missing: $requiredEntry"
        }
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
