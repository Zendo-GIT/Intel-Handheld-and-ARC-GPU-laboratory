[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Status', 'Install', 'Disable', 'Enable', 'Uninstall')]
    [string]$Action,

    [ValidateSet('lod-static', 'dither-off', 'opacity-safe', 'flat-safe')]
    [string]$Variant = 'lod-static',

    [string]$GameDirectory = 'C:\Program Files (x86)\Steam\steamapps\common\Jurassic World Evolution 3'
)

$ErrorActionPreference = 'Stop'
$moduleName = 'ZZ_ClawLab_JWE3_ArcWaterFix'
$expectedId = 'A45C5283-42D0-4D9A-BCD3-FF9BB9C25350'
$projectRoot = Split-Path -Parent $PSScriptRoot
$buildRoot = Join-Path $projectRoot 'build'
$ovldata = Join-Path $GameDirectory 'Win64\ovldata'
$target = Join-Path $ovldata $moduleName
$manifest = Join-Path $target 'Manifest.xml'
$disabledManifest = Join-Path $target 'Manifest.xml.disabled'

function Assert-GameClosed {
    if (Get-Process -Name 'JWE3' -ErrorAction SilentlyContinue) {
        throw 'JWE3.exe est lancé. Fermez le jeu avant de modifier le Content Pack.'
    }
}

function Assert-OwnModule {
    if (-not (Test-Path -LiteralPath $target)) {
        return
    }

    $candidate = $manifest
    if (-not (Test-Path -LiteralPath $candidate)) {
        $candidate = $disabledManifest
    }
    if (-not (Test-Path -LiteralPath $candidate)) {
        throw "Le dossier $target existe sans manifeste ClawLab reconnaissable."
    }

    $content = Get-Content -LiteralPath $candidate -Raw
    if ($content -notmatch [regex]::Escape($expectedId)) {
        throw "Le dossier $target n'appartient pas à ce laboratoire. Aucune modification effectuée."
    }
}

function Show-Status {
    if (-not (Test-Path -LiteralPath $target)) {
        Write-Output 'État : non installé'
        return
    }
    Assert-OwnModule
    $state = if (Test-Path -LiteralPath $manifest) { 'activé' } else { 'désactivé' }
    $variantFile = Join-Path $target 'Variant.txt'
    $activeVariant = if (Test-Path -LiteralPath $variantFile) {
        (Get-Content -LiteralPath $variantFile -Raw).Trim()
    } else {
        'inconnue'
    }
    Write-Output "État : $state"
    Write-Output "Variante : $activeVariant"
    Write-Output "Dossier : $target"
}

if (-not (Test-Path -LiteralPath $ovldata)) {
    throw "Répertoire ovldata introuvable : $ovldata"
}

switch ($Action) {
    'Status' {
        Show-Status
    }
    'Install' {
        Assert-GameClosed
        Assert-OwnModule
        $source = Join-Path $buildRoot $Variant
        foreach ($required in 'Main.ovl', 'Manifest.xml', 'Variant.txt') {
            if (-not (Test-Path -LiteralPath (Join-Path $source $required))) {
                throw "Variante non construite : fichier manquant $required dans $source"
            }
        }
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $source 'Main.ovl') -Destination (Join-Path $target 'Main.ovl') -Force
        Copy-Item -LiteralPath (Join-Path $source 'Manifest.xml') -Destination $manifest -Force
        Copy-Item -LiteralPath (Join-Path $source 'Variant.txt') -Destination (Join-Path $target 'Variant.txt') -Force
        if (Test-Path -LiteralPath $disabledManifest) {
            Remove-Item -LiteralPath $disabledManifest -Force
        }
        Show-Status
    }
    'Disable' {
        Assert-GameClosed
        Assert-OwnModule
        if (-not (Test-Path -LiteralPath $target)) {
            throw "Le correctif n'est pas installé."
        }
        if (Test-Path -LiteralPath $manifest) {
            Move-Item -LiteralPath $manifest -Destination $disabledManifest
        }
        Show-Status
    }
    'Enable' {
        Assert-GameClosed
        Assert-OwnModule
        if (-not (Test-Path -LiteralPath $target)) {
            throw "Le correctif n'est pas installé."
        }
        if (Test-Path -LiteralPath $disabledManifest) {
            Move-Item -LiteralPath $disabledManifest -Destination $manifest
        }
        Show-Status
    }
    'Uninstall' {
        Assert-GameClosed
        Assert-OwnModule
        if (-not (Test-Path -LiteralPath $target)) {
            Write-Output "Le correctif n'est pas installé."
            break
        }
        $backupRoot = Join-Path $projectRoot 'disabled-backups'
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backup = Join-Path $backupRoot "$moduleName-$stamp"
        Move-Item -LiteralPath $target -Destination $backup
        Write-Output "Correctif déplacé vers : $backup"
    }
}
