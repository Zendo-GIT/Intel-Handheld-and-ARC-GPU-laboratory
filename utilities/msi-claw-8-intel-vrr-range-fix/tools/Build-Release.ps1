[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version = '2.2.0'
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
foreach ($value in @(
        '1500L / 1000L', 'NearBlackBrush', 'RegisterRawInputDevices',
        'SetProcessWorkingSetSize', 'timeEndPeriod(1)',
        'WaitForInteractiveDesktop();', 'GetShellWindow()', 'DwmIsCompositionEnabled'
    )) {
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
    [pscustomobject]@{ Source = 'EXPERIMENTAL\INSTALL_STABLE_EXPERIMENTAL_48_144_VRR.bat'; Destination = 'EXPERIMENTAL\INSTALL_STABLE_EXPERIMENTAL_48_144_VRR.bat' },
    [pscustomobject]@{ Source = 'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_48_165_VRR.bat'; Destination = 'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_48_165_VRR.bat' },
    [pscustomobject]@{ Source = 'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_48_180_VRR.bat'; Destination = 'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_48_180_VRR.bat' },
    [pscustomobject]@{ Source = 'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_30_144_VRR.bat'; Destination = 'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_30_144_VRR.bat' },
    [pscustomobject]@{ Source = 'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_30_165_VRR.bat'; Destination = 'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_30_165_VRR.bat' },
    [pscustomobject]@{ Source = 'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_30_180_VRR.bat'; Destination = 'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_30_180_VRR.bat' },
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
    [pscustomobject]@{ Source = 'ArcSync-Range-Policy.ps1'; Destination = 'scripts\ArcSync-Range-Policy.ps1' },
    [pscustomobject]@{ Source = 'Experimental-Overclock-VRR-Trial.ps1'; Destination = 'scripts\Experimental-Overclock-VRR-Trial.ps1' },
    [pscustomobject]@{ Source = 'ClawLab-Cursor-Refresh-Helper.exe'; Destination = 'scripts\ClawLab-Cursor-Refresh-Helper.exe' },
    [pscustomobject]@{ Source = 'ClawLab-VRR-Startup.vbs'; Destination = 'scripts\ClawLab-VRR-Startup.vbs' },
    [pscustomobject]@{ Source = 'ClawLab-LFC-Startup.vbs'; Destination = 'scripts\ClawLab-LFC-Startup.vbs' },
    [pscustomobject]@{ Source = 'ClawLab-Experimental-Trial-Startup.vbs'; Destination = 'scripts\ClawLab-Experimental-Trial-Startup.vbs' },

    [pscustomobject]@{ Source = 'docs\COMPATIBILITY.md'; Destination = 'docs\COMPATIBILITY.md' },
    [pscustomobject]@{ Source = 'docs\SAFETY.md'; Destination = 'docs\SAFETY.md' },
    [pscustomobject]@{ Source = 'docs\TECHNICAL_DETAILS.md'; Destination = 'docs\TECHNICAL_DETAILS.md' },
    [pscustomobject]@{ Source = 'docs\NEXUS_MODS.md'; Destination = 'docs\NEXUS_MODS.md' },
    [pscustomobject]@{ Source = 'docs\A1M_EDID_REFERENCE.md'; Destination = 'docs\A1M_EDID_REFERENCE.md' },
    [pscustomobject]@{ Source = 'docs\RELEASE_NOTES_2.2.0.md'; Destination = 'docs\RELEASE_NOTES_2.2.0.md' },

    [pscustomobject]@{ Source = 'tools\Test-A1M-Edid.ps1'; Destination = 'SOURCE\Test-A1M-Edid.ps1' },
    [pscustomobject]@{ Source = 'tools\Test-Lfc-Backup-Identity.ps1'; Destination = 'SOURCE\Test-Lfc-Backup-Identity.ps1' },
    [pscustomobject]@{ Source = 'tools\Test-Lfc-Atomic-Replace.ps1'; Destination = 'SOURCE\Test-Lfc-Atomic-Replace.ps1' },
    [pscustomobject]@{ Source = 'tools\Test-ArcSync-Range-Policy.ps1'; Destination = 'SOURCE\Test-ArcSync-Range-Policy.ps1' },
    [pscustomobject]@{ Source = 'tools\Test-Experimental-Overclock-Edids.ps1'; Destination = 'SOURCE\Test-Experimental-Overclock-Edids.ps1' },
    [pscustomobject]@{ Source = 'tools\Test-Public-Installer-Matrix.ps1'; Destination = 'SOURCE\Test-Public-Installer-Matrix.ps1' },
    [pscustomobject]@{ Source = 'tools\Test-Protected-Runtime-Acl.ps1'; Destination = 'SOURCE\Test-Protected-Runtime-Acl.ps1' },
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
    'FBB2CEFA8A0CC36CD5231D1070D4271165CAB9EA43A22271E3B2FD49D6914677',
    '279EA02FF5AEB3FA474235ECFCD3119AE7845A969C2F6BB7A63866CC3151EF62',
    '8EDC82A04D9E1FAD037CA4D794D53BD0D374C9554059B137E75C40D9F9C416A7',
    '0D1969CF0C7CFBA3CF9F077667C1427E202DB895DFA0A750FAF1323F57A88E4B',
    'AF1F6DEB144767F089522C37B89C1171DE59D06107B5F5073877A5693EBC9ADB',
    '89B0BDD6ACEB5A2320F235864314CC33CD67E4F3E4107E21573D506594E902D2',
    '0AA3BFD4DA2D6EB8D36BBA9F87CD476D453AD86651348CC3D17E8314BD3C898D',
    'DFD9CBDDB7C0B8A711F026C43E3EB73165958F2E129857B97EB7EB008CB71B5E',
    'C0147C505E16907C62E66B56A3436870B591E1CB7B2FBA6CA410EEE3BEBDDC51',
    'CE853C0CB689CC6247E72E59C7965FEDCAE49479BCFD04EE7959FA3113A9D679',
    "Name = 'TL070FVXS02-0'",
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
    'ApplyExperimentalTrial',
    'ConfirmExperimentalTrial',
    'SetSafe120ForTrial',
    'Set-Safe120DisplayMode',
    'ActiveDisplayCount()',
    'Exactly one active display is required',
    'ClawLab.MSIClaw.VrrApplyStartup',
    'Enter-StartupApplyMutex',
    'Exit-StartupApplyMutex',
    '$expectedEmergencyPattern',
    '[^\\]+\\Device Parameters\\EDID_OVERRIDE',
    "'Intel' + [char]0x00AE + ' Graphics Software'"
    'Install-CursorRefreshHelper',
    'Start-CursorRefreshHelper',
    'Restart-CursorRefreshHelper',
    'Remove-CursorRefreshHelper',
    'RUNNING_EVENT_DRIVEN',
    'VERSION_MISMATCH'
    'CLAW_A1M_CLAW_7_AI_PLUS'
    'Overclock48_180EdidSha256'
    'Overclock30_180EdidSha256'
)
foreach ($value in $requiredIntegrityValues) {
    if ($scriptText -notmatch [regex]::Escape($value)) {
        throw "Required integrity value is missing from the release source: $value"
    }
}
$installActions = @(
    [regex]::Matches($scriptText, "'Install\d+(?:_\d+)?'") |
        ForEach-Object { $_.Value } |
        Sort-Object -Unique
)
$expectedInstallActions = @(
    "'Install30'", "'Install48'",
    "'Install30_144'", "'Install30_165'", "'Install30_180'",
    "'Install48_144'", "'Install48_165'", "'Install48_180'"
)
if (@(Compare-Object -ReferenceObject $expectedInstallActions -DifferenceObject $installActions).Count -ne 0) {
    throw "Unexpected VRR installation actions: $($installActions -join ', ')"
}
foreach ($requiredRangeMarker in @(
        '$targetMinimumHz = 48.0',
        '$experimentalMinimumHz = 30.0',
        '$targetMaximumHz = 120.0',
        "'Install48_144', 'Install48_165', 'Install48_180'",
        "'Install30_144', 'Install30_165', 'Install30_180'"
    )) {
    if ($scriptText -notmatch [regex]::Escape($requiredRangeMarker)) {
        throw "Required 30-120 / 48-120 range guard is missing: $requiredRangeMarker"
    }
}
foreach ($forbiddenRangeMarker in @('24-120', '24_120', 'Install24', 'MinimumHz = 24', 'MinimumHz=24')) {
    if ($scriptText -match [regex]::Escape($forbiddenRangeMarker)) {
        throw "Forbidden 24 Hz profile marker found in the VRR source: $forbiddenRangeMarker"
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

$rangePolicyTest = Join-Path $projectRoot 'tools\Test-ArcSync-Range-Policy.ps1'
$rangePolicyResult = & $rangePolicyTest
if ($null -eq $rangePolicyResult -or [string]$rangePolicyResult.Result -ne 'PASS' -or
    [string]$rangePolicyResult.ProfileSwitchMatrix -ne 'PASS' -or
    [bool]$rangePolicyResult.TelemetryFloorInstallable) {
    throw 'The Arc Sync telemetry and all-profile transition-guard test failed.'
}

$overclockEdidTest = Join-Path $projectRoot 'tools\Test-Experimental-Overclock-Edids.ps1'
$overclockEdidResult = & $overclockEdidTest
if ($null -eq $overclockEdidResult -or [string]$overclockEdidResult.Result -ne 'PASS' -or
    [int]$overclockEdidResult.ProfilesVerified -ne 12 -or
    [int]$overclockEdidResult.Unsupported24HzProfiles -ne 0) {
    throw 'The two-panel guarded overclock EDID test failed.'
}

$installerMatrixTest = Join-Path $projectRoot 'tools\Test-Public-Installer-Matrix.ps1'
$installerMatrixResult = & $installerMatrixTest
if ($null -eq $installerMatrixResult -or [string]$installerMatrixResult.Result -ne 'PASS' -or
    [int]$installerMatrixResult.LfcIntegratedProfiles -ne 8 -or
    [string]$installerMatrixResult.GuardedTrialOrder -ne 'PASS' -or
    [int]$installerMatrixResult.Forbidden24HzProfiles -ne 0) {
    throw 'The public installer/action/LFC/guarded-trial matrix test failed.'
}

$protectedAclTest = Join-Path $projectRoot 'tools\Test-Protected-Runtime-Acl.ps1'
$protectedAclResult = & $protectedAclTest
if ($null -eq $protectedAclResult -or
    [string]$protectedAclResult.Result -ne 'PASS' -or
    -not [bool]$protectedAclResult.DistinctAclObjects -or
    -not [bool]$protectedAclResult.StandardUserReadExecute -or
    [bool]$protectedAclResult.StandardUserWrite) {
    throw 'The protected-runtime fresh-ACL and standard-user access test failed.'
}

$lfcIdentityTest = Join-Path $projectRoot 'tools\Test-Lfc-Backup-Identity.ps1'
$lfcIdentityResult = & $lfcIdentityTest
if ($null -eq $lfcIdentityResult -or [string]$lfcIdentityResult.Result -ne 'PASS') {
    throw 'The Intel LFC stable backup identity test failed.'
}

$lfcAtomicTest = Join-Path $projectRoot 'tools\Test-Lfc-Atomic-Replace.ps1'
$lfcAtomicResult = & $lfcAtomicTest
if ($null -eq $lfcAtomicResult -or [string]$lfcAtomicResult.Result -ne 'PASS') {
    throw 'The Windows PowerShell atomic LFC backup replacement test failed.'
}

$launcherPath = Join-Path $projectRoot 'ClawLab-VRR-Startup.vbs'
$launcherText = Get-Content -LiteralPath $launcherPath -Raw
foreach ($value in @(
    '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe',
    '%LOCALAPPDATA%\ClawLab\Intel-Arc-Sync-Full-Range\ClawLab-Cursor-Refresh-Helper.exe',
    'fileSystem.FileExists(helperPath)',
    'shell.Run helperCommand, 0, False',
    'shell.Run(command, 0, True)',
    '-Action ApplyStartup'
)) {
    if ($launcherText -notmatch [regex]::Escape($value)) {
        throw "Windowless launcher no longer contains required value: $value"
    }
}
$helperLaunchIndex = $launcherText.IndexOf('shell.Run helperCommand, 0, False', [StringComparison]::Ordinal)
$startupApplyIndex = $launcherText.IndexOf('-Action ApplyStartup', [StringComparison]::Ordinal)
if ($helperLaunchIndex -lt 0 -or $startupApplyIndex -lt 0 -or $helperLaunchIndex -gt $startupApplyIndex) {
    throw 'The cursor helper must launch before the slower PowerShell startup reapply path.'
}

$lfcScriptText = Get-Content -LiteralPath (Join-Path $projectRoot 'MSI-Claw-Intel-LFC-Fix.ps1') -Raw
foreach ($value in @(
    "`$toolVersion = '2.0.5'",
    'DIRECT_D3DKMT_INTEL_PRIVATE_ESCAPE',
    "'OFFICIAL_48_120'",
    "'CLAWLAB_30_120'",
    "'CLAWLAB_48_144'",
    "'CLAWLAB_30_144'",
    "'CLAWLAB_48_165'",
    "'CLAWLAB_48_180'",
    "'CLAWLAB_30_165'",
    "'CLAWLAB_30_180'",
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
    '[IO.File]::Replace($temporaryPath, $lfcBackupPath, $replacementBackupPath)'
    'No backup, persistence task or LFC flag was changed.'
    'Refusing to save an unknown modified state as the original.'
)) {
    if ($lfcScriptText -notmatch [regex]::Escape($value)) {
        throw "Required LFC safety value is missing from the release source: $value"
    }
}
if ($lfcScriptText -match [regex]::Escape('[IO.File]::Replace($temporaryPath, $lfcBackupPath, $null)')) {
    throw 'The invalid null destination-backup path was reintroduced into LFC atomic replacement.'
}
$rangeRefusalIndex = $lfcScriptText.IndexOf('if (-not $rangeReady -and -not $validCustomRestartPending)', [StringComparison]::Ordinal)
$backupReadIndex = $lfcScriptText.IndexOf('$backup = Get-LfcBackup', [StringComparison]::Ordinal)
if ($rangeRefusalIndex -lt 0 -or $backupReadIndex -lt 0 -or $rangeRefusalIndex -gt $backupReadIndex) {
    throw 'The exact LFC range refusal must execute before any backup migration or creation.'
}
foreach ($forbiddenRangeMarker in @('24-120', '24_120', 'MinimumHz -eq 24', 'MinimumHz = 24')) {
    if ($lfcScriptText -match [regex]::Escape($forbiddenRangeMarker)) {
        throw "Forbidden 24 Hz profile marker found in the LFC source: $forbiddenRangeMarker"
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
    foreach ($marker in @('reset-all.exe', 'If CRU has never been used', 'VRR ownership preflight', 'ClawTweaks', '3.0 or later', 'ClawLab VRR compatibility patch', 'optional and is not required')) {
        if ($installerText -notmatch [regex]::Escape($marker)) {
            throw "Managed VRR installer is missing a conflict preflight: $installerName / $marker"
        }
    }
}

$experimentalInstallers = @(
    'EXPERIMENTAL\INSTALL_STABLE_EXPERIMENTAL_48_144_VRR.bat',
    'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_48_165_VRR.bat',
    'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_48_180_VRR.bat',
    'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_30_144_VRR.bat',
    'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_30_165_VRR.bat',
    'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_30_180_VRR.bat'
)
foreach ($installerName in $experimentalInstallers) {
    $installerText = Get-Content -LiteralPath (Join-Path $projectRoot $installerName) -Raw
    foreach ($marker in @(
            'DISPLAY OVERCLOCK',
            'silicon lottery',
            'timeout /t 10 /nobreak',
            'I ACCEPT THE OVERCLOCK RISK',
            '15 SECONDS',
            'DO NOT POWER OFF OR REBOOT',
            'Disconnect every external display',
            'reset-all.exe',
            'If CRU has never been used',
            'Has CRU never been used, or was reset-all.exe followed by a restart?',
            'Is every conflicting VRR/EDID tool disabled or removed?',
            'ClawLab VRR compatibility patch',
            '3.0 or later',
            'optional and is not required'
        )) {
        if ($installerText -notmatch [regex]::Escape($marker)) {
            throw "Experimental installer is missing a mandatory guard: $installerName / $marker"
        }
    }
}

$mainVrrScriptText = Get-Content -LiteralPath (Join-Path $projectRoot 'MSI-Claw-VRR-Fix.ps1') -Raw
foreach ($marker in @(
        '& $trialSchedulerPath -Action Schedule -Mode $DesiredState',
        'try { Remove-ExperimentalOverclockTrial }',
        '$backupPath,',
        "(Join-Path `$stateRoot 'MSI-Claw-Intel-LFC-Fix.ps1')",
        'ClawLab-VRR-Privileged\2.2.0',
        'Assert-ProtectedRuntimeIntegrity',
        'protected-runtime.json',
        'Remove-ProtectedExperimentalRuntime',
        '& $protectedLfcToolPath -Action Apply',
        'LfcFixActive'
        'OLDER_VERSION_RESTORE_REQUIRED'
        'Test-ClawLabFirstInstallProfileSafe'
        'Resolve-FirstInstallProfileBaseline'
        'Invoke-SetProfile -Target $Snapshot -ProfileId $profileRecommended'
        'No ClawLab original-profile backup was created.'
        'Test-SnapshotMatchesSavedProfile'
        'CTL_RESULT_ERROR_KMD_CALL'
    )) {
    if ($mainVrrScriptText -notmatch [regex]::Escape($marker)) {
        throw "Atomic experimental install transaction is missing: $marker"
    }
}
$baselineResolverCount = [regex]::Matches(
    $mainVrrScriptText,
    [regex]::Escape('Resolve-FirstInstallProfileBaseline')
).Count
if ($baselineResolverCount -ne 3) {
    throw "Every stable/custom first-install path must use the shared baseline resolver; found $baselineResolverCount definition/call markers."
}
$normalizationWriteIndex = $mainVrrScriptText.IndexOf(
    'Invoke-SetProfile -Target $Snapshot -ProfileId $profileRecommended',
    [StringComparison]::Ordinal
)
$normalizationReadbackIndex = $mainVrrScriptText.IndexOf(
    '$normalized = Get-TargetSnapshot -Attempts 10',
    [StringComparison]::Ordinal
)
$normalizationVerificationIndex = $mainVrrScriptText.IndexOf(
    'if ([int]$normalized.ProfileId -ne $profileRecommended)',
    [StringComparison]::Ordinal
)
if ($normalizationWriteIndex -lt 0 -or
    $normalizationReadbackIndex -le $normalizationWriteIndex -or
    $normalizationVerificationIndex -le $normalizationReadbackIndex) {
    throw 'Unmanaged CUSTOM normalization must write Intel RECOMMENDED, obtain fresh readback and verify it in that order.'
}
$customResolverIndex = $mainVrrScriptText.IndexOf(
    '$Before = Resolve-FirstInstallProfileBaseline -Transition $transition -Snapshot $Before',
    [StringComparison]::Ordinal
)
$customBackupIndex = $mainVrrScriptText.IndexOf(
    'Save-OriginalProfile -Snapshot $Before',
    [StringComparison]::Ordinal
)
$officialResolverIndex = $mainVrrScriptText.IndexOf(
    '$before = Resolve-FirstInstallProfileBaseline -Transition $transition -Snapshot $before',
    [StringComparison]::Ordinal
)
$officialBackupIndex = $mainVrrScriptText.IndexOf(
    'Save-OriginalProfile -Snapshot $before',
    [StringComparison]::Ordinal
)
if ($customResolverIndex -lt 0 -or $customBackupIndex -le $customResolverIndex -or
    $officialResolverIndex -lt 0 -or $officialBackupIndex -le $officialResolverIndex) {
    throw 'Every stable/custom installer must resolve and verify its first-install baseline before saving the original profile.'
}

$healthScriptText = Get-Content -LiteralPath (Join-Path $projectRoot 'ClawLab-Health-Check.ps1') -Raw
foreach ($marker in @('Test-ClawLabCleanNotInstalledState', 'CLEAN_NOT_INSTALLED', 'InstallationState')) {
    if ($healthScriptText -notmatch [regex]::Escape($marker)) {
        throw "Health status is missing a clean-uninstalled marker: $marker"
    }
}

$trialScriptText = Get-Content -LiteralPath (Join-Path $projectRoot 'Experimental-Overclock-VRR-Trial.ps1') -Raw
foreach ($marker in @(
        "`$fixVersion = '$Version'",
        'ObservationSeconds = 15',
        'Stability = [string]$profile.Stability',
        'TimeoutSeconds 15',
        "-ToolAction 'SetSafe120ForTrial'",
        'UserConfirmed = $false',
        'Confirm-AdministratorOrRelaunch',
        '-RunLevel Limited',
        'ClawLab-VRR-Privileged\2.2.0',
        'Initialize-ProtectedRuntimeDirectory',
        'New-ProtectedRuntimeAcl',
        'DirectorySecurity',
        'Write-ProtectedRuntimeManifest',
        'Assert-ProtectedRuntimeIntegrity',
        "-ToolAction 'ConfirmExperimentalTrial'",
        "-ToolAction 'Restore'"
    )) {
    if ($trialScriptText -notmatch [regex]::Escape($marker)) {
        throw "Guarded trial source is missing: $marker"
    }
}
$protectedAclFactoryCount = [regex]::Matches(
    $trialScriptText,
    [regex]::Escape('New-ProtectedRuntimeAcl')
).Count
if ($protectedAclFactoryCount -ne 3 -or
    $trialScriptText -match [regex]::Escape('SetAccessControl($acl)')) {
    throw 'The protected parent and versioned runtime must each receive a fresh explicit ACL object.'
}
$trialLauncherText = Get-Content -LiteralPath (Join-Path $projectRoot 'ClawLab-Experimental-Trial-Startup.vbs') -Raw
foreach ($marker in @('WScript.ScriptFullName', 'Experimental-Overclock-VRR-Trial.ps1')) {
    if ($trialLauncherText -notmatch [regex]::Escape($marker)) {
        throw "Protected guarded-trial launcher is missing: $marker"
    }
}
if ($trialLauncherText -match [regex]::Escape('%LOCALAPPDATA%')) {
    throw 'The guarded-trial launcher still executes a user-writable LocalAppData script.'
}
if ($trialScriptText -match [regex]::Escape('-RunLevel Highest')) {
    throw 'Guarded trial source must never schedule its user-writable runtime at Highest privilege.'
}
if (([regex]::Matches($trialScriptText, 'Confirm-AdministratorOrRelaunch')).Count -ne 2) {
    throw 'Guarded trial elevation must exist only as one function definition and one Schedule action call.'
}
foreach ($unsafeTimeout in @(
        "-ToolAction 'ConfirmExperimentalTrial' -TimeoutSeconds",
        "-ToolPath `$installedVrrToolPath -ToolAction 'Restore' -TimeoutSeconds",
        '-ExecutionTimeLimit'
    )) {
    if ($trialScriptText -match [regex]::Escape($unsafeTimeout)) {
        throw "Guarded trial can force-terminate an elevation-sensitive action: $unsafeTimeout"
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
            $normalizedEntryName = $_.FullName.Replace('\', '/')
            if (-not $normalizedEntryName.StartsWith($packagePrefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Release ZIP entry escaped the package root: $($_.FullName)"
            }
            $normalizedEntryName.Substring($packagePrefix.Length)
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
            'scripts/ArcSync-Range-Policy.ps1',
            'scripts/Experimental-Overclock-VRR-Trial.ps1',
            'scripts/ClawLab-Experimental-Trial-Startup.vbs',
            'scripts/ClawLab-Cursor-Refresh-Helper.exe'
            'SOURCE/Test-Lfc-Atomic-Replace.ps1'
            'SOURCE/Test-ArcSync-Range-Policy.ps1'
            'SOURCE/Test-Experimental-Overclock-Edids.ps1'
            'SOURCE/Test-Public-Installer-Matrix.ps1'
            'EXPERIMENTAL/INSTALL_STABLE_EXPERIMENTAL_48_144_VRR.bat'
            'EXPERIMENTAL/INSTALL_UNSTABLE_EXPERIMENTAL_48_165_VRR.bat'
            'EXPERIMENTAL/INSTALL_UNSTABLE_EXPERIMENTAL_48_180_VRR.bat'
            'EXPERIMENTAL/INSTALL_UNSTABLE_EXPERIMENTAL_30_144_VRR.bat'
            'EXPERIMENTAL/INSTALL_UNSTABLE_EXPERIMENTAL_30_165_VRR.bat'
            'EXPERIMENTAL/INSTALL_UNSTABLE_EXPERIMENTAL_30_180_VRR.bat'
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
