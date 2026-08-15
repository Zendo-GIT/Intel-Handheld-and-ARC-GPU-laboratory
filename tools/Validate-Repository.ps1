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
    'utilities\msi-claw-8-intel-vrr-range-fix\Experimental-144-VRR-Trial.ps1',
    'utilities\msi-claw-8-intel-vrr-range-fix\ClawLab-VRR-Startup.vbs',
    'utilities\msi-claw-8-intel-vrr-range-fix\ClawLab-LFC-Startup.vbs',
    'utilities\msi-claw-8-intel-vrr-range-fix\ClawLab-144-Trial-Startup.vbs',
    'utilities\msi-claw-8-intel-vrr-range-fix\INSTALL_48_120_VRR.bat',
    'utilities\msi-claw-8-intel-vrr-range-fix\INSTALL_30_120_VRR.bat',
    'utilities\msi-claw-8-intel-vrr-range-fix\INSTALL_EXPERIMENTAL_48_144_VRR.bat',
    'utilities\msi-claw-8-intel-vrr-range-fix\INSTALL_EXPERIMENTAL_30_144_VRR.bat',
    'utilities\msi-claw-8-intel-vrr-range-fix\FACTORY_RESET_CLAWLAB_VRR.bat',
    'utilities\msi-claw-8-intel-vrr-range-fix\COLLECT_UNSUPPORTED_CLAW_DISPLAY.bat',
    'utilities\msi-claw-8-intel-vrr-range-fix\Collect-Claw-Display-Diagnostics.ps1',
    'utilities\msi-claw-8-intel-vrr-range-fix\RESTORE_ORIGINAL_VRR.bat',
    'utilities\msi-claw-8-intel-vrr-range-fix\RESTORE_INTEL_LFC_DEFAULTS.bat',
    'utilities\msi-claw-8-intel-vrr-range-fix\docs\RELEASE_NOTES_2.0.1.md',
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
$forbiddenFiles = @($publicFiles | Where-Object {
    $forbiddenExtensions -contains $_.Extension.ToLowerInvariant()
})
if ($forbiddenFiles.Count -gt 0) {
    throw "Forbidden binary, trace, backup, shader dump, or archive found in the public tree:`n$($forbiddenFiles.FullName -join "`n")"
}

$textExtensions = @('.md', '.txt', '.ps1', '.bat', '.cmd', '.vbs', '.yml', '.yaml', '.json')
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
$requiredVrrValues = @(
    "`$fixVersion = '2.0.1'",
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
    "[ValidateSet('Status', 'Install48', 'Install30', 'Install48_144', 'Install30_144', 'Restore', 'FactoryReset', 'EmergencyRestoreEdid', 'ApplyStartup')]",
    'ctlSetIntelArcSyncProfile',
    'Get-AuthenticodeSignature',
    'Start-ManagedIntelGraphicsSoftware',
    'Write-IntelStartupBackupAtomically',
    'Set-IntelStartupTrustedIdentity',
    'IdentityVerifiedAt',
    'ClawLab MSI Claw 144 Hz Trial Confirmation',
    'WindowsDisplayMode',
    'FileSha256',
    'Assert-ProfileTransitionAllowed',
    'managed-mode.json',
    "'FactoryReset'",
    'Set-Experimental144DisplayMode',
    'Set-Safe120DisplayMode',
    "'Intel' + [char]0x00AE + ' Graphics Software'"
)
foreach ($value in $requiredVrrValues) {
    if ($vrrScript -notmatch [regex]::Escape($value)) {
        throw "VRR utility no longer contains required integrity value: $value"
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
    "`$toolVersion = '2.0.1'",
    'DIRECT_D3DKMT_INTEL_PRIVATE_ESCAPE',
    "'OFFICIAL_48_120'",
    "'CLAWLAB_30_120'",
    "'CLAWLAB_48_144'",
    "'CLAWLAB_30_144'",
    '$managedProfiles.ContainsKey($managedModeName)',
    'OriginalLowFpsSolutionEnabled',
    'OriginalHighFpsSolutionEnabled',
    'ClawLab MSI Claw Intel LFC Fix'
)) {
    if ($lfcScript -notmatch [regex]::Escape($value)) {
        throw "Intel LFC source no longer contains required safety value: $value"
    }
}

$lfcInstallers = @(
    'INSTALL_30_120_VRR.bat',
    'INSTALL_48_120_VRR.bat',
    'INSTALL_EXPERIMENTAL_48_144_VRR.bat',
    'INSTALL_EXPERIMENTAL_30_144_VRR.bat'
)
foreach ($installerName in $lfcInstallers) {
    $installerPath = Join-Path $repositoryRoot "utilities\msi-claw-8-intel-vrr-range-fix\$installerName"
    $installerText = Get-Content -LiteralPath $installerPath -Raw
    if ($installerText -notmatch [regex]::Escape('MSI-Claw-Intel-LFC-Fix.ps1" -Action Apply')) {
        throw "Managed VRR installer does not integrate the shared LFC fix: $installerName"
    }
}

$trialScript = Get-Content -LiteralPath (Join-Path $repositoryRoot 'utilities\msi-claw-8-intel-vrr-range-fix\Experimental-144-VRR-Trial.ps1') -Raw
foreach ($value in @(
    "`$toolVersion = '2.0.1'",
    "`$observationSeconds = 20",
    "`$confirmationTimeoutSeconds = 30",
    'CLAWLAB_48_144',
    'CLAWLAB_30_144',
    'Restore-ExperimentalProfile',
    'LowFpsSolutionEnabled',
    'HighFpsSolutionEnabled',
    'shared LFC x2 correction',
    'ClawLab MSI Claw 144 Hz Trial Confirmation'
)) {
    if ($trialScript -notmatch [regex]::Escape($value)) {
        throw "144 Hz trial source no longer contains required safety value: $value"
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
