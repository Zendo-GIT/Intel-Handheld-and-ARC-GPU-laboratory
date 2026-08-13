[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Status', 'Reset', 'Restore')]
    [string]$Action,

    [string]$BackupPath
)

$ErrorActionPreference = 'Stop'

$gameProcessName = 'JWE3'
$d3dCacheRoot = Join-Path $env:LOCALAPPDATA 'D3DSCache'
$d3dCachePath = Join-Path $d3dCacheRoot 'c68ef6650597d61f'
$intelCacheRoot = 'C:\Users\david\AppData\LocalLow\Intel\ShaderCache'
$intelCacheName = '8f2e4cf6af467acd8dad85773128d5fd560a5156d1d71135e8c829a0f784c735'
$intelCachePath = Join-Path $intelCacheRoot $intelCacheName
$defaultBackupRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'cache-backups'

function Assert-JWE3Closed {
    if (Get-Process -Name $gameProcessName -ErrorAction SilentlyContinue) {
        throw 'JWE3.exe est encore lancé. Fermez le jeu avant de modifier ses caches.'
    }
}

function Assert-ChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedRoot
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullRoot = [IO.Path]::GetFullPath($ExpectedRoot).TrimEnd('\') + '\'
    if (-not $fullPath.StartsWith($fullRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Chemin refusé hors du répertoire attendu : $fullPath"
    }
}

function Get-CacheState {
    [pscustomobject]@{
        DirectXCachePath = $d3dCachePath
        DirectXCachePresent = Test-Path -LiteralPath $d3dCachePath
        IntelCachePath = $intelCachePath
        IntelCachePresent = Test-Path -LiteralPath $intelCachePath
        BackupRoot = $defaultBackupRoot
        Backups = @(
            if (Test-Path -LiteralPath $defaultBackupRoot) {
                Get-ChildItem -LiteralPath $defaultBackupRoot -Directory |
                    Sort-Object Name -Descending |
                    Select-Object -ExpandProperty FullName
            }
        )
    }
}

function Move-CacheIfPresent {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$ExpectedRoot,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    Assert-ChildPath -Path $Source -ExpectedRoot $ExpectedRoot
    if (Test-Path -LiteralPath $Source) {
        Move-Item -LiteralPath $Source -Destination $Destination
        return $true
    }
    return $false
}

switch ($Action) {
    'Status' {
        Get-CacheState | ConvertTo-Json -Depth 4
    }

    'Reset' {
        Assert-JWE3Closed
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $sessionBackup = Join-Path $defaultBackupRoot $stamp
        Assert-ChildPath -Path $sessionBackup -ExpectedRoot (Split-Path $defaultBackupRoot -Parent)
        New-Item -ItemType Directory -Path $sessionBackup -Force | Out-Null

        $d3dMoved = Move-CacheIfPresent `
            -Source $d3dCachePath `
            -ExpectedRoot $d3dCacheRoot `
            -Destination (Join-Path $sessionBackup 'D3DSCache-c68ef6650597d61f')
        $intelMoved = Move-CacheIfPresent `
            -Source $intelCachePath `
            -ExpectedRoot $intelCacheRoot `
            -Destination (Join-Path $sessionBackup "IntelShaderCache-$intelCacheName")

        $manifest = [ordered]@{
            Created = (Get-Date).ToString('o')
            DirectX = [ordered]@{ Original = $d3dCachePath; Moved = $d3dMoved }
            Intel = [ordered]@{ Original = $intelCachePath; Moved = $intelMoved }
        }
        $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $sessionBackup 'manifest.json') -Encoding utf8
        Write-Output "Cache JWE3 mis de côté : $sessionBackup"
    }

    'Restore' {
        Assert-JWE3Closed
        if (-not $BackupPath) {
            $BackupPath = Get-ChildItem -LiteralPath $defaultBackupRoot -Directory -ErrorAction Stop |
                Sort-Object Name -Descending |
                Select-Object -First 1 -ExpandProperty FullName
        }
        if (-not $BackupPath -or -not (Test-Path -LiteralPath $BackupPath -PathType Container)) {
            throw 'Aucune sauvegarde de cache valide à restaurer.'
        }
        Assert-ChildPath -Path $BackupPath -ExpectedRoot $defaultBackupRoot

        $savedD3d = Join-Path $BackupPath 'D3DSCache-c68ef6650597d61f'
        $savedIntel = Join-Path $BackupPath "IntelShaderCache-$intelCacheName"
        $postTest = Join-Path $BackupPath 'post-test-cache'
        New-Item -ItemType Directory -Path $postTest -Force | Out-Null

        if (Test-Path -LiteralPath $d3dCachePath) {
            Assert-ChildPath -Path $d3dCachePath -ExpectedRoot $d3dCacheRoot
            Move-Item -LiteralPath $d3dCachePath -Destination (Join-Path $postTest 'D3DSCache-c68ef6650597d61f')
        }
        if (Test-Path -LiteralPath $intelCachePath) {
            Assert-ChildPath -Path $intelCachePath -ExpectedRoot $intelCacheRoot
            Move-Item -LiteralPath $intelCachePath -Destination (Join-Path $postTest "IntelShaderCache-$intelCacheName")
        }
        if (Test-Path -LiteralPath $savedD3d) {
            Move-Item -LiteralPath $savedD3d -Destination $d3dCachePath
        }
        if (Test-Path -LiteralPath $savedIntel) {
            Move-Item -LiteralPath $savedIntel -Destination $intelCachePath
        }
        Write-Output "Cache JWE3 restauré depuis : $BackupPath"
    }
}
