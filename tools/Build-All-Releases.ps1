[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version = '1.0.0',
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$IevrVersion = '1.0.1',
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$VrrVersion = '2.2.0',
    [switch]$SkipValidation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
if (-not $SkipValidation) {
    & (Join-Path $PSScriptRoot 'Validate-Repository.ps1') | Out-Host
}

$builders = @(
    [pscustomobject]@{ Path = 'games\jurassic-world-evolution-3\tools\Build-Release.ps1'; Version = $Version },
    [pscustomobject]@{ Path = 'games\kena-bridge-of-spirits\tools\Build-Release.ps1'; Version = $Version },
    [pscustomobject]@{ Path = 'games\inazuma-eleven-victory-road\tools\Build-Release.ps1'; Version = $IevrVersion },
    [pscustomobject]@{ Path = 'games\detroit-become-human\tools\Build-Release.ps1'; Version = $Version },
    [pscustomobject]@{ Path = 'utilities\msi-claw-8-intel-vrr-range-fix\tools\Build-Release.ps1'; Version = $VrrVersion }
)

$results = foreach ($definition in $builders) {
    $relativePath = [string]$definition.Path
    $builder = Join-Path $repositoryRoot $relativePath
    if (-not (Test-Path -LiteralPath $builder -PathType Leaf)) {
        throw "Release builder missing: $relativePath"
    }
    & $builder -Version ([string]$definition.Version)
}

$distRoot = Join-Path $repositoryRoot 'dist'
New-Item -ItemType Directory -Force -Path $distRoot | Out-Null

$centralPackages = foreach ($result in $results) {
    $sourceArchive = [string]$result.Archive
    if (-not (Test-Path -LiteralPath $sourceArchive -PathType Leaf)) {
        throw "Built archive is missing: $sourceArchive"
    }
    $destination = Join-Path $distRoot ([IO.Path]::GetFileName($sourceArchive))
    Copy-Item -LiteralPath $sourceArchive -Destination $destination -Force
    $hash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText(
        "$destination.sha256.txt",
        "$hash *$([IO.Path]::GetFileName($destination))`r`n",
        [Text.Encoding]::ASCII
    )
    Get-Item -LiteralPath $destination
}

$manifestLines = @(
    $centralPackages | Sort-Object Name | ForEach-Object {
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash *$($_.Name)"
    }
)
[IO.File]::WriteAllLines(
    (Join-Path $distRoot 'SHA256SUMS.txt'),
    $manifestLines,
    [Text.Encoding]::ASCII
)

[pscustomobject]@{
    Result = 'PASS'
    Output = $distRoot
    Packages = $centralPackages.Count
    Files = @($centralPackages.Name)
}
