[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$publicRoots = @(
    (Join-Path $repositoryRoot '.github'),
    (Join-Path $repositoryRoot 'docs'),
    (Join-Path $repositoryRoot 'games'),
    (Join-Path $repositoryRoot 'tools')
)

$requiredFiles = @(
    'README.md',
    'LICENSE',
    'SECURITY.md',
    'docs\ANTI_CHEAT_POLICY.md',
    'games\jurassic-world-evolution-3\JWE3-IntelArc-WaterFix.ps1',
    'games\kena-bridge-of-spirits\mod\Kena-WindowsNoEditor_IntelArcWaterFlashFix_P.pak',
    'games\inazuma-eleven-victory-road\IEVR-Offline-Stutter-Fix.ps1'
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

$nestedGitDirectories = @(
    Get-ChildItem -LiteralPath (Join-Path $repositoryRoot 'games') -Directory -Recurse -Force |
        Where-Object { $_.Name -eq '.git' }
)
if ($nestedGitDirectories.Count -gt 0) {
    throw "Nested Git repository found under games/:`n$($nestedGitDirectories.FullName -join "`n")"
}

[pscustomobject]@{
    Result = 'PASS'
    PublicFiles = $publicFiles.Count
    PowerShellFiles = $powerShellFiles.Count
    KenaPakSha256 = $actualKenaPakHash
    InazumaKnownHashes = $requiredInazumaHashes.Count
}
