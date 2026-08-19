[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$publicRoots = @(
    (Join-Path $repositoryRoot '.github'),
    (Join-Path $repositoryRoot 'docs'),
    (Join-Path $repositoryRoot 'games'),
    (Join-Path $repositoryRoot 'utilities'),
    (Join-Path $repositoryRoot 'tools')
)

$requiredFiles = @(
    'README.md',
    'LICENSE',
    'SECURITY.md',
    'docs\ANTI_CHEAT_POLICY.md',
    'games\jurassic-world-evolution-3\JWE3-IntelArc-WaterFix.ps1',
    'games\kena-bridge-of-spirits\mod\Kena-WindowsNoEditor_IntelArcWaterFlashFix_P.pak',
    'games\inazuma-eleven-victory-road\IEVR-Offline-Stutter-Fix.ps1',
    'games\the-isle-evrima\The-Isle-Evrima-Claw-Fix.ps1',
    'games\the-isle-evrima\INSTALL_FIX.bat',
    'games\the-isle-evrima\UNINSTALL_FIX.bat',
    'games\the-isle-evrima\CHECK_STATUS.bat',
    'games\the-isle-evrima\README.md',
    'games\the-isle-evrima\docs\COMPATIBILITY.md',
    'games\the-isle-evrima\docs\SAFETY.md',
    'games\the-isle-evrima\docs\TECHNICAL_DETAILS.md',
    'games\the-isle-evrima\docs\RELEASE_NOTES_1.0.0.md',
    'games\the-isle-evrima\tools\Test-Profile.ps1',
    'games\the-isle-evrima\tools\Build-Release.ps1',
    'utilities\msi-claw-8-intel-vrr-range-fix\MSI-Claw-VRR-Fix.ps1',
    'utilities\msi-claw-8-intel-vrr-range-fix\MSI-Claw-Intel-LFC-Fix.ps1',
    'utilities\msi-claw-8-intel-vrr-range-fix\Edid-Normalization.ps1',
    'utilities\msi-claw-8-intel-vrr-range-fix\ArcSync-Range-Policy.ps1',
    'utilities\msi-claw-8-intel-vrr-range-fix\Lfc-Backup-Identity.ps1',
    'utilities\msi-claw-8-intel-vrr-range-fix\Intel-VRR-LFC-Driver-Interface.ps1',
    'utilities\msi-claw-8-intel-vrr-range-fix\ClawLab-Cursor-Refresh-Helper.exe',
    'utilities\msi-claw-8-intel-vrr-range-fix\ClawLab-Health-Check.ps1',
    'utilities\msi-claw-8-intel-vrr-range-fix\Export-ClawLab-Status.ps1',
    'utilities\msi-claw-8-intel-vrr-range-fix\tools\CursorRefreshHelper\ClawLabCursorRefreshHelperWpf.cs',
    'utilities\msi-claw-8-intel-vrr-range-fix\tools\CursorRefreshHelper\Build-CursorRefreshHelper.ps1',
    'utilities\msi-claw-8-intel-vrr-range-fix\tools\Test-A1M-Edid.ps1',
    'utilities\msi-claw-8-intel-vrr-range-fix\tools\Test-Lfc-Backup-Identity.ps1',
    'utilities\msi-claw-8-intel-vrr-range-fix\tools\Test-Lfc-Atomic-Replace.ps1',
    'utilities\msi-claw-8-intel-vrr-range-fix\tools\Test-ArcSync-Range-Policy.ps1',
    'utilities\msi-claw-8-intel-vrr-range-fix\tools\Test-Experimental-Overclock-Edids.ps1',
    'utilities\msi-claw-8-intel-vrr-range-fix\tools\Test-Public-Installer-Matrix.ps1',
    'utilities\msi-claw-8-intel-vrr-range-fix\ClawLab-VRR-Startup.vbs',
    'utilities\msi-claw-8-intel-vrr-range-fix\ClawLab-LFC-Startup.vbs',
    'utilities\msi-claw-8-intel-vrr-range-fix\ClawLab-Experimental-Trial-Startup.vbs',
    'utilities\msi-claw-8-intel-vrr-range-fix\Experimental-Overclock-VRR-Trial.ps1',
    'utilities\msi-claw-8-intel-vrr-range-fix\INSTALL_48_120_VRR.bat',
    'utilities\msi-claw-8-intel-vrr-range-fix\INSTALL_30_120_VRR.bat',
    'utilities\msi-claw-8-intel-vrr-range-fix\FACTORY_RESET_CLAWLAB_VRR.bat',
    'utilities\msi-claw-8-intel-vrr-range-fix\COLLECT_UNSUPPORTED_CLAW_DISPLAY.bat',
    'utilities\msi-claw-8-intel-vrr-range-fix\EXPORT_STATUS_REPORT.bat',
    'utilities\msi-claw-8-intel-vrr-range-fix\Collect-Claw-Display-Diagnostics.ps1',
    'utilities\msi-claw-8-intel-vrr-range-fix\RESTORE_ORIGINAL_VRR.bat',
    'utilities\msi-claw-8-intel-vrr-range-fix\RESTORE_INTEL_LFC_DEFAULTS.bat',
    'utilities\msi-claw-8-intel-vrr-range-fix\docs\RELEASE_NOTES_2.2.1.md',
    'utilities\msi-claw-8-intel-vrr-range-fix\docs\A1M_EDID_REFERENCE.md',
    'utilities\msi-claw-8-intel-vrr-range-fix\EXPERIMENTAL\INSTALL_STABLE_EXPERIMENTAL_48_144_VRR.bat',
    'utilities\msi-claw-8-intel-vrr-range-fix\EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_48_165_VRR.bat',
    'utilities\msi-claw-8-intel-vrr-range-fix\EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_48_180_VRR.bat',
    'utilities\msi-claw-8-intel-vrr-range-fix\EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_48_192_VRR.bat',
    'utilities\msi-claw-8-intel-vrr-range-fix\EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_30_144_VRR.bat',
    'utilities\msi-claw-8-intel-vrr-range-fix\EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_30_165_VRR.bat',
    'utilities\msi-claw-8-intel-vrr-range-fix\EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_30_180_VRR.bat',
    'utilities\msi-claw-8-intel-vrr-range-fix\EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_30_192_VRR.bat',
    'utilities\msi-claw-8-intel-vrr-range-fix\EMERGENCY_REMOVE_CLAWLAB_EDID.bat'
    'utilities\msi-claw-8-intel-vrr-range-fix\SET_INTEL_LFC_FACTORY_DEFAULTS.bat'
)
foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $repositoryRoot $relativePath) -PathType Leaf)) {
        throw "Required public file is missing: $relativePath"
    }
}

$publicFiles = @(
    foreach ($root in $publicRoots) {
        if (Test-Path -LiteralPath $root -PathType Container) {
            Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {
                $_.FullName -notmatch '[\\/]dist[\\/]'
            }
        }
    }
)

$forbiddenExtensions = @('.exe', '.dll', '.ovl', '.arc', '.bak', '.etl', '.dmp', '.dxil', '.zip', '.7z', '.rar')
$allowedCursorHelperPath = [IO.Path]::GetFullPath((Join-Path $repositoryRoot 'utilities\msi-claw-8-intel-vrr-range-fix\ClawLab-Cursor-Refresh-Helper.exe'))
$forbiddenFiles = @($publicFiles | Where-Object {
    $forbiddenExtensions -contains $_.Extension.ToLowerInvariant() -and
    -not $_.FullName.Equals($allowedCursorHelperPath, [StringComparison]::OrdinalIgnoreCase)
})
if ($forbiddenFiles.Count -gt 0) {
    throw "Forbidden binary, trace, backup, shader dump, or archive found in the public tree:`n$($forbiddenFiles.FullName -join "`n")"
}

$textExtensions = @('.md', '.txt', '.ps1', '.bat', '.cmd', '.vbs', '.yml', '.yaml', '.json', '.cs')
foreach ($file in @($publicFiles | Where-Object { $_.Extension.ToLowerInvariant() -in $textExtensions })) {
    $text = Get-Content -LiteralPath $file.FullName -Raw
    if ($text -match '(?i)https?://[^\s)>]*(wemod|anti.?cheat.?bypass)') {
        throw "Prohibited anti-cheat bypass link found: $($file.FullName)"
    }
    if ($text -match '(?i)clawptimize.{0,40}\bdev\b|\bdev\b.{0,40}clawptimize') {
        throw "Private Clawptimize development reference found: $($file.FullName)"
    }
}

$powerShellFiles = @($publicFiles | Where-Object { $_.Extension -ieq '.ps1' })
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

$kenaPakPath = Join-Path $repositoryRoot 'games\kena-bridge-of-spirits\mod\Kena-WindowsNoEditor_IntelArcWaterFlashFix_P.pak'
$expectedKenaPakHash = '6B8A19873CB65EA6CA33BA8A50CC90581A32F62A6A24C20E03A245A150CAD072'
$actualKenaPakHash = (Get-FileHash -LiteralPath $kenaPakPath -Algorithm SHA256).Hash
if ($actualKenaPakHash -ne $expectedKenaPakHash) {
    throw "Kena PAK hash mismatch. Expected $expectedKenaPakHash, got $actualKenaPakHash"
}

$inazumaScript = Get-Content -LiteralPath (Join-Path $repositoryRoot 'games\inazuma-eleven-victory-road\IEVR-Offline-Stutter-Fix.ps1') -Raw
$requiredInazumaHashes = @(
    'B1FA04EA365868E5C8933ACA393366F82D0D446187E2187F2737DC4FA2ACD40C',
    '4059F004915EC3462BB7E7348283A72C8738F9A3CCEB110C1475F2ADFBE2A3DF'
)
foreach ($hash in $requiredInazumaHashes) {
    if ($inazumaScript -notmatch [regex]::Escape($hash)) {
        throw "Inazuma source no longer contains required executable hash: $hash"
    }
}
if ($inazumaScript -notmatch [regex]::Escape('$rules = @(Get-IsolationRules)')) {
    throw 'Inazuma uninstaller no longer guards the single-firewall-rule case.'
}

$theIsleScript = Get-Content -LiteralPath (
    Join-Path $repositoryRoot 'games\the-isle-evrima\The-Isle-Evrima-Claw-Fix.ps1'
) -Raw
foreach ($marker in @(
        "`$FixVersion = '1.0.0'",
        "`$ValidatedBuildId = '24664737'",
        "`$ValidatedGameVersion = '0.21.784'",
        'BuildIdOverride is restricted to an isolated test configuration directory.',
        'CONFIGURATION_ONLY_NO_INJECTION',
        'Set-ReadOnly -LiteralPath $enginePath -Enabled $true',
        'Set-ReadOnly -LiteralPath $gameUserSettingsPath -Enabled $true',
        'Assert-SupportedDisplayProfile',
        'Restore-OperationSnapshot',
        'Unsupported or unverified Steam build',
        "'ScreenPercentage' = '40'",
        "'sg.ViewDistanceQuality' = '1'",
        "'sg.FoliageQuality' = '0'"
    )) {
    if ($theIsleScript -notmatch [regex]::Escape($marker)) {
        throw "The Isle source is missing a required profile or safety marker: $marker"
    }
}
foreach ($forbiddenMarker in @(
        'D3D12.PSO.DiskCache',
        'D3D12.PSO.DriverOptimizedDiskCache',
        'WriteProcessMemory',
        'netsh advfirewall'
    )) {
    if ($theIsleScript -match [regex]::Escape($forbiddenMarker)) {
        throw "The Isle source contains a forbidden or ineffective public mechanism: $forbiddenMarker"
    }
}
& (Join-Path $repositoryRoot 'games\the-isle-evrima\tools\Test-Profile.ps1') | Out-Host

$vrrScript = Get-Content -LiteralPath (Join-Path $repositoryRoot 'utilities\msi-claw-8-intel-vrr-range-fix\MSI-Claw-VRR-Fix.ps1') -Raw
$retiredVrrPublicFiles = @(
    'INSTALL_EXPERIMENTAL_48_144_VRR.bat',
    'INSTALL_EXPERIMENTAL_30_144_VRR.bat',
    'Experimental-144-VRR-Trial.ps1',
    'ClawLab-144-Trial-Startup.vbs'
)
foreach ($relativePath in $retiredVrrPublicFiles) {
    $candidate = Join-Path $repositoryRoot "utilities\msi-claw-8-intel-vrr-range-fix\$relativePath"
    if (Test-Path -LiteralPath $candidate) {
        throw "Retired 144 Hz public file must not exist: $relativePath"
    }
}
$requiredVrrValues = @(
    "`$fixVersion = '2.2.1'",
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
    'DC60F9E3CC7B33C4F094181C57E4AF271C1BFB4449AFDE2614B4EAC27C032752',
    '949A7143DB4549FC7D0D36F9F2521A528C1C796DE8F3F1FA948E4B3DBF5ECED6',
    '4FA15135645E89BF10DA6B007921BA6702E03951C8FB9D2E2576F2837AD02BDE',
    '6553A5DA6651D29D447F0E0D14EC80CA631B1178544DA60E1CC2D54C4FAFB4C9',
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
    'Remove-CursorRefreshHelper',
    'RUNNING_EVENT_DRIVEN'
    'DEEP_IDLE_NO_TIMER_RESOLUTION'
    'VERSION_MISMATCH'
    'CLAW_A1M_CLAW_7_AI_PLUS'
    'Overclock48_180EdidSha256'
    'Overclock30_180EdidSha256'
    'Overclock48_192EdidSha256'
    'Overclock30_192EdidSha256'
    'OLDER_VERSION_RESTORE_REQUIRED'
    'Test-ClawLabFirstInstallProfileSafe'
    'Test-SnapshotMatchesSavedProfile'
    'CTL_RESULT_ERROR_KMD_CALL'
)
foreach ($value in $requiredVrrValues) {
    if ($vrrScript -notmatch [regex]::Escape($value)) {
        throw "VRR utility no longer contains required integrity value: $value"
    }
}
$vrrHealthScript = Get-Content -LiteralPath (Join-Path $repositoryRoot 'utilities\msi-claw-8-intel-vrr-range-fix\ClawLab-Health-Check.ps1') -Raw
foreach ($value in @('Test-ClawLabCleanNotInstalledState', 'CLEAN_NOT_INSTALLED', 'InstallationState')) {
    if ($vrrHealthScript -notmatch [regex]::Escape($value)) {
        throw "VRR health check no longer contains required clean-state value: $value"
    }
}
$installActions = @(
    [regex]::Matches($vrrScript, "'Install\d+(?:_\d+)?'") |
        ForEach-Object { $_.Value } |
        Sort-Object -Unique
)
$expectedInstallActions = @(
    "'Install30'", "'Install48'",
    "'Install30_144'", "'Install30_165'", "'Install30_180'", "'Install30_192'",
    "'Install48_144'", "'Install48_165'", "'Install48_180'", "'Install48_192'"
)
if (@(Compare-Object -ReferenceObject $expectedInstallActions -DifferenceObject $installActions).Count -ne 0) {
    throw "Unexpected VRR installation actions: $($installActions -join ', ')"
}
foreach ($requiredRangeMarker in @(
        '$targetMinimumHz = 48.0',
        '$experimentalMinimumHz = 30.0',
        '$targetMaximumHz = 120.0',
        "'Install48_144', 'Install48_165', 'Install48_180', 'Install48_192'",
        "'Install30_144', 'Install30_165', 'Install30_180', 'Install30_192'"
    )) {
    if ($vrrScript -notmatch [regex]::Escape($requiredRangeMarker)) {
        throw "Required 30-120 / 48-120 range guard is missing: $requiredRangeMarker"
    }
}
foreach ($forbiddenRangeMarker in @('24-120', '24_120', 'Install24', 'MinimumHz = 24', 'MinimumHz=24')) {
    if ($vrrScript -match [regex]::Escape($forbiddenRangeMarker)) {
        throw "Forbidden 24 Hz profile marker found in the VRR source: $forbiddenRangeMarker"
    }
}

$edidNormalizationScript = Get-Content -LiteralPath (Join-Path $repositoryRoot 'utilities\msi-claw-8-intel-vrr-range-fix\Edid-Normalization.ps1') -Raw
foreach ($value in @('ZERO_PADDED_128_NORMALIZED', '$baseBlock[126] -eq 0', '$Bytes[$index] -ne 0')) {
    if ($edidNormalizationScript -notmatch [regex]::Escape($value)) {
        throw "EDID normalization safety module is missing: $value"
    }
}

$a1mCatalogTestPath = Join-Path $repositoryRoot 'utilities\msi-claw-8-intel-vrr-range-fix\tools\Test-A1M-Edid.ps1'
$a1mCatalogResult = & $a1mCatalogTestPath
if ($null -eq $a1mCatalogResult -or [string]$a1mCatalogResult.Result -ne 'PASS') {
    throw 'The pinned Claw A1M EDID generator test failed.'
}

$rangePolicyTestPath = Join-Path $repositoryRoot 'utilities\msi-claw-8-intel-vrr-range-fix\tools\Test-ArcSync-Range-Policy.ps1'
$rangePolicyResult = & $rangePolicyTestPath
if ($null -eq $rangePolicyResult -or [string]$rangePolicyResult.Result -ne 'PASS' -or
    [string]$rangePolicyResult.ProfileSwitchMatrix -ne 'PASS' -or
    [bool]$rangePolicyResult.TelemetryFloorInstallable) {
    throw 'The Arc Sync telemetry and all-profile transition-guard test failed.'
}

$overclockEdidTestPath = Join-Path $repositoryRoot 'utilities\msi-claw-8-intel-vrr-range-fix\tools\Test-Experimental-Overclock-Edids.ps1'
$overclockEdidResult = & $overclockEdidTestPath
if ($null -eq $overclockEdidResult -or [string]$overclockEdidResult.Result -ne 'PASS' -or
    [int]$overclockEdidResult.ProfilesVerified -ne 16 -or
    [int]$overclockEdidResult.Unsupported24HzProfiles -ne 0) {
    throw 'The two-panel guarded overclock EDID test failed.'
}

$installerMatrixTestPath = Join-Path $repositoryRoot 'utilities\msi-claw-8-intel-vrr-range-fix\tools\Test-Public-Installer-Matrix.ps1'
$installerMatrixResult = & $installerMatrixTestPath
if ($null -eq $installerMatrixResult -or [string]$installerMatrixResult.Result -ne 'PASS' -or
    [int]$installerMatrixResult.LfcIntegratedProfiles -ne 10 -or
    [string]$installerMatrixResult.GuardedTrialOrder -ne 'PASS' -or
    [int]$installerMatrixResult.Forbidden24HzProfiles -ne 0) {
    throw 'The public installer/action/LFC/guarded-trial matrix test failed.'
}

$cursorHelperPath = Join-Path $repositoryRoot 'utilities\msi-claw-8-intel-vrr-range-fix\ClawLab-Cursor-Refresh-Helper.exe'
$cursorHelperAssembly = [Reflection.AssemblyName]::GetAssemblyName($cursorHelperPath)
if ($cursorHelperAssembly.Version.ToString() -ne '2.2.1.0') {
    throw "Cursor Refresh Helper has unexpected assembly version $($cursorHelperAssembly.Version)."
}
$cursorHelperSource = Get-Content -LiteralPath (Join-Path $repositoryRoot 'utilities\msi-claw-8-intel-vrr-range-fix\tools\CursorRefreshHelper\ClawLabCursorRefreshHelperWpf.cs') -Raw
foreach ($value in @(
    'RidevInputSink',
    'RegisterRawInputDevices',
    'TailTicks',
    'AllowsTransparency = true',
    'SystemParameters.PrimaryScreenWidth - Width',
    'SystemParameters.PrimaryScreenHeight - Height',
    'IsSystemCursorVisible',
    'GetCursorInfo',
    'CursorShowing',
    '1500L / 1000L',
    'NearBlackBrush',
    'EnterDeepIdle',
    'SetProcessWorkingSetSize',
    'timeEndPeriod(1)'
)) {
    if ($cursorHelperSource -notmatch [regex]::Escape($value)) {
        throw "Cursor Refresh Helper source no longer contains required safety value: $value"
    }
}
foreach ($forbiddenMarker in @('GetRawInputData', 'AllocHGlobal', 'FreeHGlobal')) {
    if ($cursorHelperSource -match [regex]::Escape($forbiddenMarker)) {
        throw "Cursor Refresh Helper reintroduced a per-packet native allocation path: $forbiddenMarker"
    }
}

$vrrLauncher = Get-Content -LiteralPath (Join-Path $repositoryRoot 'utilities\msi-claw-8-intel-vrr-range-fix\ClawLab-VRR-Startup.vbs') -Raw
foreach ($value in @(
    '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe',
    'shell.Run(command, 0, True)',
    '-Action ApplyStartup'
)) {
    if ($vrrLauncher -notmatch [regex]::Escape($value)) {
        throw "VRR windowless launcher no longer contains required value: $value"
    }
}

$lfcScript = Get-Content -LiteralPath (Join-Path $repositoryRoot 'utilities\msi-claw-8-intel-vrr-range-fix\MSI-Claw-Intel-LFC-Fix.ps1') -Raw
foreach ($value in @(
    "`$toolVersion = '2.0.6'",
    'DIRECT_D3DKMT_INTEL_PRIVATE_ESCAPE',
    "'OFFICIAL_48_120'",
    "'CLAWLAB_30_120'",
    "'CLAWLAB_48_144'",
    "'CLAWLAB_30_144'",
    "'CLAWLAB_48_165'",
    "'CLAWLAB_48_180'",
    "'CLAWLAB_48_192'",
    "'CLAWLAB_30_165'",
    "'CLAWLAB_30_180'",
    "'CLAWLAB_30_192'",
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
    if ($lfcScript -notmatch [regex]::Escape($value)) {
        throw "Intel LFC source no longer contains required safety value: $value"
    }
}
if ($lfcScript -match [regex]::Escape('-WindowStyle Hidden -Wait -PassThru')) {
    throw 'The LFC startup path must not wait for the resident helper process tree.'
}

$lfcIdentityTestPath = Join-Path $repositoryRoot 'utilities\msi-claw-8-intel-vrr-range-fix\tools\Test-Lfc-Backup-Identity.ps1'
$lfcIdentityResult = & $lfcIdentityTestPath
if ($null -eq $lfcIdentityResult -or [string]$lfcIdentityResult.Result -ne 'PASS') {
    throw 'The Intel LFC stable backup identity test failed.'
}

$lfcAtomicTestPath = Join-Path $repositoryRoot 'utilities\msi-claw-8-intel-vrr-range-fix\tools\Test-Lfc-Atomic-Replace.ps1'
$lfcAtomicResult = & $lfcAtomicTestPath
if ($null -eq $lfcAtomicResult -or [string]$lfcAtomicResult.Result -ne 'PASS') {
    throw 'The Windows PowerShell atomic LFC backup replacement test failed.'
}

foreach ($value in @(
        '[IO.File]::Replace($temporaryPath, $lfcBackupPath, $replacementBackupPath)',
        'No backup, persistence task or LFC flag was changed.',
        'Refusing to save an unknown modified state as the original.'
    )) {
    if ($lfcScript -notmatch [regex]::Escape($value)) {
        throw "Intel LFC source is missing a required restore/range safety value: $value"
    }
}
if ($lfcScript -match [regex]::Escape('[IO.File]::Replace($temporaryPath, $lfcBackupPath, $null)')) {
    throw 'The invalid null destination-backup path was reintroduced into LFC atomic replacement.'
}
$rangeRefusalIndex = $lfcScript.IndexOf('if (-not $rangeReady -and -not $validCustomRestartPending)', [StringComparison]::Ordinal)
$backupReadIndex = $lfcScript.IndexOf('$backup = Get-LfcBackup', [StringComparison]::Ordinal)
if ($rangeRefusalIndex -lt 0 -or $backupReadIndex -lt 0 -or $rangeRefusalIndex -gt $backupReadIndex) {
    throw 'The exact LFC range refusal must execute before any backup migration or creation.'
}
foreach ($forbiddenRangeMarker in @('24-120', '24_120', 'MinimumHz -eq 24', 'MinimumHz = 24')) {
    if ($lfcScript -match [regex]::Escape($forbiddenRangeMarker)) {
        throw "Forbidden 24 Hz profile marker found in the LFC source: $forbiddenRangeMarker"
    }
}

$lfcInstallers = @(
    'INSTALL_30_120_VRR.bat',
    'INSTALL_48_120_VRR.bat'
)
foreach ($installerName in $lfcInstallers) {
    $installerPath = Join-Path $repositoryRoot "utilities\msi-claw-8-intel-vrr-range-fix\$installerName"
    $installerText = Get-Content -LiteralPath $installerPath -Raw
    if ($installerText -notmatch [regex]::Escape('MSI-Claw-Intel-LFC-Fix.ps1" -Action Apply')) {
        throw "Managed VRR installer does not integrate the shared LFC fix: $installerName"
    }
    foreach ($cruMarker in @(
            'IMPORTANT VERSION UPGRADE',
            '2.2.0 or any older release',
            'refuses to overwrite an older managed installation',
            'reset-all.exe',
            'Has CRU never been used',
            'If CRU has never been used'
        )) {
        if ($installerText -notmatch [regex]::Escape($cruMarker)) {
            throw "Managed VRR installer is missing the interactive CRU preflight: $installerName / $cruMarker"
        }
    }
    foreach ($ownershipMarker in @('VRR ownership preflight', 'ClawTweaks', '3.0 or later', 'ClawLab VRR compatibility patch', 'optional and is not required')) {
        if ($installerText -notmatch [regex]::Escape($ownershipMarker)) {
            throw "Managed VRR installer is missing the exclusive-ownership preflight: $installerName / $ownershipMarker"
        }
    }
}

$experimentalInstallers = @(
    'EXPERIMENTAL\INSTALL_STABLE_EXPERIMENTAL_48_144_VRR.bat',
    'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_48_165_VRR.bat',
    'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_48_180_VRR.bat',
    'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_48_192_VRR.bat',
    'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_30_144_VRR.bat',
    'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_30_165_VRR.bat',
    'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_30_180_VRR.bat',
    'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_30_192_VRR.bat'
)
foreach ($installerName in $experimentalInstallers) {
    $installerPath = Join-Path $repositoryRoot "utilities\msi-claw-8-intel-vrr-range-fix\$installerName"
    $installerText = Get-Content -LiteralPath $installerPath -Raw
    foreach ($marker in @(
            'DISPLAY OVERCLOCK',
            'IMPORTANT VERSION UPGRADE',
            '2.2.0 or any older release',
            'refuses to overwrite an older managed installation',
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

$mainVrrScript = Get-Content -LiteralPath (Join-Path $repositoryRoot 'utilities\msi-claw-8-intel-vrr-range-fix\MSI-Claw-VRR-Fix.ps1') -Raw
foreach ($marker in @(
        '& $trialSchedulerPath -Action Schedule -Mode $DesiredState',
        'try { Remove-ExperimentalOverclockTrial }',
        '$backupPath,',
        "(Join-Path `$stateRoot 'MSI-Claw-Intel-LFC-Fix.ps1')",
        'ClawLab-VRR-Privileged\2.2.1',
        'Assert-ProtectedRuntimeIntegrity',
        'protected-runtime.json',
        'Remove-ProtectedExperimentalRuntime',
        '& $protectedLfcToolPath -Action Apply',
        'LfcFixActive'
    )) {
    if ($mainVrrScript -notmatch [regex]::Escape($marker)) {
        throw "Atomic experimental install transaction is missing: $marker"
    }
}

$trialScript = Get-Content -LiteralPath (Join-Path $repositoryRoot 'utilities\msi-claw-8-intel-vrr-range-fix\Experimental-Overclock-VRR-Trial.ps1') -Raw
foreach ($marker in @(
        "`$fixVersion = '2.2.1'",
        'ObservationSeconds = 15',
        'TimeoutSeconds 15',
        "-ToolAction 'SetSafe120ForTrial'",
        'UserConfirmed = $false',
        'Confirm-AdministratorOrRelaunch',
        '-RunLevel Limited',
        'ClawLab-VRR-Privileged\2.2.1',
        'Initialize-ProtectedRuntimeDirectory',
        'DirectorySecurity',
        'Write-ProtectedRuntimeManifest',
        'Assert-ProtectedRuntimeIntegrity',
        "-ToolAction 'ConfirmExperimentalTrial'",
        "-ToolAction 'Restore'"
    )) {
    if ($trialScript -notmatch [regex]::Escape($marker)) {
        throw "Guarded trial source is missing a required rollback/confirmation marker: $marker"
    }
}
$trialLauncher = Get-Content -LiteralPath (Join-Path $repositoryRoot 'utilities\msi-claw-8-intel-vrr-range-fix\ClawLab-Experimental-Trial-Startup.vbs') -Raw
foreach ($marker in @('WScript.ScriptFullName', 'Experimental-Overclock-VRR-Trial.ps1')) {
    if ($trialLauncher -notmatch [regex]::Escape($marker)) {
        throw "Protected guarded-trial launcher is missing: $marker"
    }
}
if ($trialLauncher -match [regex]::Escape('%LOCALAPPDATA%')) {
    throw 'The guarded-trial launcher still executes a user-writable LocalAppData script.'
}
if ($trialScript -match [regex]::Escape('-RunLevel Highest')) {
    throw 'Guarded trial source must never schedule its user-writable runtime at Highest privilege.'
}
if (([regex]::Matches($trialScript, 'Confirm-AdministratorOrRelaunch')).Count -ne 2) {
    throw 'Guarded trial elevation must exist only as one function definition and one Schedule action call.'
}
foreach ($unsafeTimeout in @(
        "-ToolAction 'ConfirmExperimentalTrial' -TimeoutSeconds",
        "-ToolPath `$installedVrrToolPath -ToolAction 'Restore' -TimeoutSeconds",
        '-ExecutionTimeLimit'
    )) {
    if ($trialScript -match [regex]::Escape($unsafeTimeout)) {
        throw "Guarded trial can force-terminate an elevation-sensitive action: $unsafeTimeout"
    }
}

$nestedGitDirectories = @(
    foreach ($root in @(
        (Join-Path $repositoryRoot 'games'),
        (Join-Path $repositoryRoot 'utilities')
    )) {
        if (Test-Path -LiteralPath $root -PathType Container) {
            Get-ChildItem -LiteralPath $root -Directory -Recurse -Force |
                Where-Object { $_.Name -eq '.git' }
        }
    }
)
if ($nestedGitDirectories.Count -gt 0) {
    throw "Nested Git repository found in the public project tree:`n$($nestedGitDirectories.FullName -join "`n")"
}

[pscustomobject]@{
    Result = 'PASS'
    PublicFiles = $publicFiles.Count
    PowerShellFiles = $powerShellFiles.Count
    KenaPakSha256 = $actualKenaPakHash
    InazumaKnownHashes = $requiredInazumaHashes.Count
    TheIsleProfileTest = 'PASS'
    VrrIntegrityValues = $requiredVrrValues.Count + 3
}
