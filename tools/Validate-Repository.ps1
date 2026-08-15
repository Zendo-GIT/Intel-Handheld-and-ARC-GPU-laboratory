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
    'games\detroit-become-human\Detroit-IntelArc-StabilityFix.ps1',
    'games\detroit-become-human\INSTALL_STEAM_INTEGRATION.bat',
    'games\detroit-become-human\REMOVE_STEAM_INTEGRATION.bat',
    'utilities\msi-claw-8-intel-vrr-range-fix\MSI-Claw-VRR-Fix.ps1',
    'utilities\msi-claw-8-intel-vrr-range-fix\MSI-Claw-Intel-LFC-Fix.ps1',
    'utilities\msi-claw-8-intel-vrr-range-fix\Intel-VRR-LFC-Driver-Interface.ps1',
    'utilities\msi-claw-8-intel-vrr-range-fix\ClawLab-Cursor-Refresh-Helper.exe',
    'utilities\msi-claw-8-intel-vrr-range-fix\tools\CursorRefreshHelper\ClawLabCursorRefreshHelperWpf.cs',
    'utilities\msi-claw-8-intel-vrr-range-fix\tools\CursorRefreshHelper\Build-CursorRefreshHelper.ps1',
    'utilities\msi-claw-8-intel-vrr-range-fix\tools\Test-A1M-Edid.ps1',
    'utilities\msi-claw-8-intel-vrr-range-fix\ClawLab-VRR-Startup.vbs',
    'utilities\msi-claw-8-intel-vrr-range-fix\ClawLab-LFC-Startup.vbs',
    'utilities\msi-claw-8-intel-vrr-range-fix\INSTALL_48_120_VRR.bat',
    'utilities\msi-claw-8-intel-vrr-range-fix\INSTALL_30_120_VRR.bat',
    'utilities\msi-claw-8-intel-vrr-range-fix\FACTORY_RESET_CLAWLAB_VRR.bat',
    'utilities\msi-claw-8-intel-vrr-range-fix\COLLECT_UNSUPPORTED_CLAW_DISPLAY.bat',
    'utilities\msi-claw-8-intel-vrr-range-fix\Collect-Claw-Display-Diagnostics.ps1',
    'utilities\msi-claw-8-intel-vrr-range-fix\RESTORE_ORIGINAL_VRR.bat',
    'utilities\msi-claw-8-intel-vrr-range-fix\RESTORE_INTEL_LFC_DEFAULTS.bat',
    'utilities\msi-claw-8-intel-vrr-range-fix\docs\RELEASE_NOTES_2.1.0.md',
    'utilities\msi-claw-8-intel-vrr-range-fix\docs\A1M_EDID_REFERENCE.md',
    'utilities\msi-claw-8-intel-vrr-range-fix\EMERGENCY_REMOVE_CLAWLAB_EDID.bat'
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

$detroitScript = Get-Content -LiteralPath (Join-Path $repositoryRoot 'games\detroit-become-human\Detroit-IntelArc-StabilityFix.ps1') -Raw
$requiredDetroitValues = @(
    'ECF52321921387E683904E089082D76B973326FC093AF14E524056715519C1CF',
    '1B31A15AC8AF8A236B3B7FB721DF439D03EB40ACAA5ECF59BC6BCF0CDF49D2AE',
    '0x661E57',
    'DetroitBecomeHuman.ClawLab.real.exe'
)
foreach ($value in $requiredDetroitValues) {
    if ($detroitScript -notmatch [regex]::Escape($value)) {
        throw "Detroit source no longer contains required integrity value: $value"
    }
}

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
    "`$fixVersion = '2.1.0'",
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
    'RUNNING_EVENT_DRIVEN'
)
foreach ($value in $requiredVrrValues) {
    if ($vrrScript -notmatch [regex]::Escape($value)) {
        throw "VRR utility no longer contains required integrity value: $value"
    }
}
foreach ($forbiddenMarker in @("'Install48_144'", "'Install30_144'", 'function Set-Experimental144DisplayMode')) {
    if ($vrrScript -match [regex]::Escape($forbiddenMarker)) {
        throw "Retired 144 Hz installation capability remains in the VRR source: $forbiddenMarker"
    }
}

$a1mCatalogTestPath = Join-Path $repositoryRoot 'utilities\msi-claw-8-intel-vrr-range-fix\tools\Test-A1M-Edid.ps1'
$a1mCatalogResult = & $a1mCatalogTestPath
if ($null -eq $a1mCatalogResult -or [string]$a1mCatalogResult.Result -ne 'PASS') {
    throw 'The pinned Claw A1M EDID generator test failed.'
}

$cursorHelperPath = Join-Path $repositoryRoot 'utilities\msi-claw-8-intel-vrr-range-fix\ClawLab-Cursor-Refresh-Helper.exe'
$cursorHelperAssembly = [Reflection.AssemblyName]::GetAssemblyName($cursorHelperPath)
if ($cursorHelperAssembly.Version.ToString() -ne '2.1.0.0') {
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
    '500L / 1000L',
    'NearBlackBrush'
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
    "`$toolVersion = '2.0.3'",
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
)) {
    if ($lfcScript -notmatch [regex]::Escape($value)) {
        throw "Intel LFC source no longer contains required safety value: $value"
    }
}
if ($lfcScript -match [regex]::Escape('-WindowStyle Hidden -Wait -PassThru')) {
    throw 'The LFC startup path must not wait for the resident helper process tree.'
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
    DetroitIntegrityValues = $requiredDetroitValues.Count
    VrrIntegrityValues = $requiredVrrValues.Count + 3
}
