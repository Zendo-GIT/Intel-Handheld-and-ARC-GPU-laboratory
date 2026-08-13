[CmdletBinding()]
param(
    [ValidateSet('Status', 'Install', 'Uninstall')]
    [string]$Action = 'Status',

    [string]$GameExe = 'C:\Program Files (x86)\Steam\steamapps\common\Jurassic World Evolution 3\JWE3.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$OfficialSha256 = '04FA75D84683DE73AAFF7C0D5C28D8FDC5B4E900E5968022995CF84039F0A79F'
$PatchedSha256 = '3A172D9261075017974897A2F4EB89F16232B5E5D711B2EA77A524394BD7FAA8'
$PatchOffset = 0x1CB666D
[byte[]]$OfficialBytes = 0x0F, 0x9D, 0xC0 # setge al
[byte[]]$PatchedBytes = 0x31, 0xC0, 0x90  # xor eax,eax; nop

$GameExe = [System.IO.Path]::GetFullPath($GameExe)
$GameDirectory = [System.IO.Path]::GetDirectoryName($GameExe)
$BackupPath = Join-Path $GameDirectory 'JWE3.exe.clawlab-original-1.4.2.0.bak'

function Get-Sha256 {
    param([Parameter(Mandatory)][string]$LiteralPath)
    return (Get-FileHash -LiteralPath $LiteralPath -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Assert-SafeTarget {
    $expectedName = 'JWE3.exe'
    if ([System.IO.Path]::GetFileName($GameExe) -cne $expectedName) {
        throw "Cible refusée : le fichier doit s'appeler exactement $expectedName."
    }
    if (-not (Test-Path -LiteralPath $GameExe -PathType Leaf)) {
        throw "JWE3.exe est introuvable : $GameExe"
    }
}

function Assert-GameStopped {
    $process = Get-Process -Name 'JWE3' -ErrorAction SilentlyContinue
    if ($null -ne $process) {
        throw 'JWE3 est lancé. Fermez complètement le jeu avant cette opération.'
    }
}

function Assert-Bytes {
    param(
        [Parameter(Mandatory)][byte[]]$Data,
        [Parameter(Mandatory)][byte[]]$Expected,
        [Parameter(Mandatory)][string]$Label
    )
    for ($index = 0; $index -lt $Expected.Length; $index++) {
        if ($Data[$PatchOffset + $index] -ne $Expected[$index]) {
            $actual = [System.BitConverter]::ToString(
                $Data[$PatchOffset..($PatchOffset + $Expected.Length - 1)]
            )
            throw "Octets inattendus à l'offset 0x$($PatchOffset.ToString('X')) pour $Label : $actual"
        }
    }
}

function New-VerifiedPatchedFile {
    param([Parameter(Mandatory)][string]$Destination)
    [byte[]]$data = [System.IO.File]::ReadAllBytes($GameExe)
    Assert-Bytes -Data $data -Expected $OfficialBytes -Label 'JWE3 officiel'
    [System.Array]::Copy($PatchedBytes, 0, $data, $PatchOffset, $PatchedBytes.Length)
    [System.IO.File]::WriteAllBytes($Destination, $data)
    $hash = Get-Sha256 -LiteralPath $Destination
    if ($hash -cne $PatchedSha256) {
        throw "La copie patchée n'a pas le hash attendu : $hash"
    }
}

function Show-Status {
    $hash = Get-Sha256 -LiteralPath $GameExe
    $state = if ($hash -ceq $OfficialSha256) {
        'OFFICIEL_SM65_AUTOMATIQUE'
    }
    elseif ($hash -ceq $PatchedSha256) {
        'CLAWLAB_MESH_SHADERS_DESACTIVES'
    }
    else {
        'VERSION_INCONNUE_REFUSEE'
    }

    [pscustomobject]@{
        Etat = $state
        Jeu = $GameExe
        Sha256 = $hash
        Sauvegarde = if (Test-Path -LiteralPath $BackupPath) { $BackupPath } else { $null }
        InjectionDLL = $false
        ModificationMemoire = $false
    }
}

Assert-SafeTarget

switch ($Action) {
    'Status' {
        Show-Status
    }

    'Install' {
        Assert-GameStopped
        $currentHash = Get-Sha256 -LiteralPath $GameExe
        if ($currentHash -ceq $PatchedSha256) {
            Write-Host 'Le fallback mesh shader ClawLab est déjà installé.'
            Show-Status
            break
        }
        if ($currentHash -cne $OfficialSha256) {
            throw "Version de JWE3.exe non reconnue ; aucune modification. SHA-256 : $currentHash"
        }

        if (Test-Path -LiteralPath $BackupPath) {
            $backupHash = Get-Sha256 -LiteralPath $BackupPath
            if ($backupHash -cne $OfficialSha256) {
                throw "La sauvegarde existante n'est pas l'original attendu : $BackupPath"
            }
        }
        else {
            Copy-Item -LiteralPath $GameExe -Destination $BackupPath
            $backupHash = Get-Sha256 -LiteralPath $BackupPath
            if ($backupHash -cne $OfficialSha256) {
                throw "Échec de vérification de la sauvegarde : $BackupPath"
            }
        }

        $temporaryPath = Join-Path $GameDirectory (
            'JWE3.exe.clawlab-' + [System.Guid]::NewGuid().ToString('N') + '.tmp'
        )
        try {
            New-VerifiedPatchedFile -Destination $temporaryPath
            Move-Item -LiteralPath $temporaryPath -Destination $GameExe -Force
        }
        finally {
            if (Test-Path -LiteralPath $temporaryPath) {
                Remove-Item -LiteralPath $temporaryPath -Force
            }
        }

        if ((Get-Sha256 -LiteralPath $GameExe) -cne $PatchedSha256) {
            throw 'Le fichier installé ne correspond pas au correctif vérifié.'
        }
        Write-Host 'Fallback installé : JWE3 utilisera le pipeline classique VS/SM60.'
        Show-Status
    }

    'Uninstall' {
        Assert-GameStopped
        $currentHash = Get-Sha256 -LiteralPath $GameExe
        if ($currentHash -ceq $OfficialSha256) {
            Write-Host 'JWE3.exe est déjà officiel ; aucune restauration nécessaire.'
            Show-Status
            break
        }
        if ($currentHash -cne $PatchedSha256) {
            throw "Version de JWE3.exe non reconnue ; restauration automatique refusée. SHA-256 : $currentHash"
        }
        if (-not (Test-Path -LiteralPath $BackupPath -PathType Leaf)) {
            throw "Sauvegarde officielle introuvable : $BackupPath"
        }
        if ((Get-Sha256 -LiteralPath $BackupPath) -cne $OfficialSha256) {
            throw 'La sauvegarde officielle a un hash inattendu ; restauration refusée.'
        }

        $temporaryPath = Join-Path $GameDirectory (
            'JWE3.exe.restore-' + [System.Guid]::NewGuid().ToString('N') + '.tmp'
        )
        try {
            Copy-Item -LiteralPath $BackupPath -Destination $temporaryPath
            Move-Item -LiteralPath $temporaryPath -Destination $GameExe -Force
        }
        finally {
            if (Test-Path -LiteralPath $temporaryPath) {
                Remove-Item -LiteralPath $temporaryPath -Force
            }
        }

        if ((Get-Sha256 -LiteralPath $GameExe) -cne $OfficialSha256) {
            throw 'La restauration du JWE3.exe officiel a échoué.'
        }
        Write-Host 'JWE3.exe officiel restauré. La sauvegarde vérifiée est conservée.'
        Show-Status
    }
}
