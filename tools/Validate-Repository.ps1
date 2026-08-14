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
    'utilities\msi-claw-8-intel-vrr-range-fix\INSTALL_48_120_VRR.bat',
    'utilities\msi-claw-8-intel-vrr-range-fix\INSTALL_EXPERIMENTAL_30_120_VRR.bat',
    'utilities\msi-claw-8-intel-vrr-range-fix\RESTORE_ORIGINAL_VRR.bat',
    'utilities\msi-claw-8-intel-vrr-range-fix\EMERGENCY_REMOVE_EXPERIMENTAL_EDID.bat'
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

$textExtensions = @('.md', '.txt', '.ps1', '.bat', '.cmd', '.yml', '.yaml', '.json')
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
    'E49BC570225510B7C889ED292570F1345CAA07F5840DB57EA6998A403DB5CEF0',
    '14CDDC390CF69367C4B6821A46728518200446A33F708A1A87CA673B68B66918',
    '597D5A95C28171B7B9DF111C1BB12830532F63831EA38111E02D618850E76698',
    'C2000A5E8A3D91C80DCE75DC5BB2F63269C77501338FD059B4CF71CD0CE94743',
    "[ValidateSet('Status', 'Install48', 'Install30', 'Restore', 'EmergencyRestoreEdid')]",
    'ctlSetIntelArcSyncProfile'
)
foreach ($value in $requiredVrrValues) {
    if ($vrrScript -notmatch [regex]::Escape($value)) {
        throw "VRR utility no longer contains required integrity value: $value"
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
    VrrIntegrityValues = $requiredVrrValues.Count
}
