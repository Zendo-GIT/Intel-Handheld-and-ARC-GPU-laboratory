[CmdletBinding()]
param(
    [ValidateSet('Status', 'Install', 'Uninstall')]
    [string]$Action = 'Status',

    [string]$GameExe
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$FixVersion = '1.0.0'
$SupportedGameVersion = '1.4.2.0'
$OfficialSha256 = '04FA75D84683DE73AAFF7C0D5C28D8FDC5B4E900E5968022995CF84039F0A79F'
$PatchedSha256 = '3A172D9261075017974897A2F4EB89F16232B5E5D711B2EA77A524394BD7FAA8'
$PatchOffset = 0x1CB666D
[byte[]]$OfficialBytes = 0x0F, 0x9D, 0xC0 # setge al
[byte[]]$PatchedBytes = 0x31, 0xC0, 0x90  # xor eax,eax; nop
$PublicBackupName = 'JWE3.exe.intel-arc-water-fix.original.1.4.2.0.bak'
$LegacyBackupName = 'JWE3.exe.clawlab-original-1.4.2.0.bak'

function Get-Sha256 {
    param([Parameter(Mandatory)][string]$LiteralPath)
    return (Get-FileHash -LiteralPath $LiteralPath -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Add-UniquePath {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$List,
        [string]$Path
    )
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if ($List -notcontains $fullPath) {
        $List.Add($fullPath)
    }
}

function Get-SteamLibraryRoots {
    $steamRoots = [System.Collections.Generic.List[string]]::new()
    $registryValues = @(
        @('HKCU:\Software\Valve\Steam', 'SteamPath'),
        @('HKCU:\Software\Valve\Steam', 'InstallPath'),
        @('HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'InstallPath'),
        @('HKLM:\SOFTWARE\Valve\Steam', 'InstallPath')
    )

    foreach ($entry in $registryValues) {
        try {
            $value = Get-ItemPropertyValue -LiteralPath $entry[0] -Name $entry[1]
            Add-UniquePath -List $steamRoots -Path $value
        }
        catch {
            # This registry location is optional.
        }
    }

    if ($null -ne ${env:ProgramFiles(x86)}) {
        Add-UniquePath -List $steamRoots -Path (Join-Path ${env:ProgramFiles(x86)} 'Steam')
    }
    if ($null -ne $env:ProgramFiles) {
        Add-UniquePath -List $steamRoots -Path (Join-Path $env:ProgramFiles 'Steam')
    }

    $libraryRoots = [System.Collections.Generic.List[string]]::new()
    foreach ($steamRoot in @($steamRoots)) {
        Add-UniquePath -List $libraryRoots -Path $steamRoot
        $libraryFile = Join-Path $steamRoot 'steamapps\libraryfolders.vdf'
        if (-not (Test-Path -LiteralPath $libraryFile -PathType Leaf)) {
            continue
        }

        foreach ($line in [System.IO.File]::ReadLines($libraryFile)) {
            $candidate = $null
            if ($line -match '^\s*"path"\s+"([^"]+)"') {
                $candidate = $Matches[1]
            }
            elseif ($line -match '^\s*"\d+"\s+"([^"]+)"') {
                $candidate = $Matches[1]
            }
            if ($null -ne $candidate) {
                $candidate = $candidate -replace '\\\\', '\'
                Add-UniquePath -List $libraryRoots -Path $candidate
            }
        }
    }
    return $libraryRoots
}

function Resolve-GameExe {
    param([string]$ExplicitPath)

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        return [System.IO.Path]::GetFullPath($ExplicitPath)
    }

    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($libraryRoot in Get-SteamLibraryRoots) {
        $candidate = Join-Path $libraryRoot 'steamapps\common\Jurassic World Evolution 3\JWE3.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            Add-UniquePath -List $candidates -Path $candidate
        }
    }

    if ($candidates.Count -eq 0) {
        throw @'
Jurassic World Evolution 3 was not found in the registered Steam libraries.
Run the PowerShell script with:
  -GameExe "D:\SteamLibrary\steamapps\common\Jurassic World Evolution 3\JWE3.exe"
'@
    }
    if ($candidates.Count -eq 1) {
        return $candidates[0]
    }

    $supported = @(
        $candidates | Where-Object {
            $hash = Get-Sha256 -LiteralPath $_
            $hash -ceq $OfficialSha256 -or $hash -ceq $PatchedSha256
        }
    )
    if ($supported.Count -eq 1) {
        return $supported[0]
    }

    throw "Multiple JWE3 installations were found. Use -GameExe to select one:`n$($candidates -join "`n")"
}

function Assert-SafeTarget {
    param([Parameter(Mandatory)][string]$LiteralPath)

    if ([System.IO.Path]::GetFileName($LiteralPath) -ine 'JWE3.exe') {
        throw 'Safety check failed: the target file must be named exactly JWE3.exe.'
    }
    if ([System.IO.Path]::GetFileName([System.IO.Path]::GetDirectoryName($LiteralPath)) -ine 'Jurassic World Evolution 3') {
        throw 'Safety check failed: JWE3.exe is not inside a Jurassic World Evolution 3 folder.'
    }
    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        throw "JWE3.exe does not exist: $LiteralPath"
    }
}

function Assert-GameStopped {
    if ($null -ne (Get-Process -Name 'JWE3' -ErrorAction SilentlyContinue)) {
        throw 'JWE3 is currently running. Close the game completely and try again.'
    }
}

function Assert-PatchBytes {
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
            throw "Unexpected bytes at offset 0x$($PatchOffset.ToString('X')) in ${Label}: $actual"
        }
    }
}

function Get-ValidBackup {
    param([Parameter(Mandatory)][string]$GameDirectory)

    foreach ($name in @($PublicBackupName, $LegacyBackupName)) {
        $candidate = Join-Path $GameDirectory $name
        if ((Test-Path -LiteralPath $candidate -PathType Leaf) -and
            (Get-Sha256 -LiteralPath $candidate) -ceq $OfficialSha256) {
            return $candidate
        }
    }
    return $null
}

function Show-Status {
    param([Parameter(Mandatory)][string]$LiteralPath)

    $hash = Get-Sha256 -LiteralPath $LiteralPath
    $state = if ($hash -ceq $OfficialSha256) {
        'SUPPORTED_ORIGINAL_NOT_INSTALLED'
    }
    elseif ($hash -ceq $PatchedSha256) {
        'FIX_INSTALLED'
    }
    else {
        'UNSUPPORTED_GAME_VERSION_NO_CHANGES_ALLOWED'
    }
    $gameDirectory = [System.IO.Path]::GetDirectoryName($LiteralPath)

    [pscustomobject]@{
        FixVersion = $FixVersion
        SupportedGameVersion = $SupportedGameVersion
        State = $state
        GameExe = $LiteralPath
        CurrentSha256 = $hash
        ValidBackup = Get-ValidBackup -GameDirectory $gameDirectory
        DllInjection = $false
        RuntimeMemoryPatching = $false
    }
}

$GameExe = Resolve-GameExe -ExplicitPath $GameExe
Assert-SafeTarget -LiteralPath $GameExe
$GameDirectory = [System.IO.Path]::GetDirectoryName($GameExe)
$PublicBackupPath = Join-Path $GameDirectory $PublicBackupName

switch ($Action) {
    'Status' {
        Show-Status -LiteralPath $GameExe
    }

    'Install' {
        Assert-GameStopped
        $currentHash = Get-Sha256 -LiteralPath $GameExe
        if ($currentHash -ceq $PatchedSha256) {
            Write-Host 'Intel Arc Water Fix is already installed.' -ForegroundColor Green
            Show-Status -LiteralPath $GameExe
            break
        }
        if ($currentHash -cne $OfficialSha256) {
            throw "Unsupported JWE3.exe. Nothing was changed. SHA-256: $currentHash"
        }

        if (Test-Path -LiteralPath $PublicBackupPath) {
            if ((Get-Sha256 -LiteralPath $PublicBackupPath) -cne $OfficialSha256) {
                throw "The existing backup is not the supported original: $PublicBackupPath"
            }
        }
        else {
            Copy-Item -LiteralPath $GameExe -Destination $PublicBackupPath
            if ((Get-Sha256 -LiteralPath $PublicBackupPath) -cne $OfficialSha256) {
                throw 'Backup verification failed. The game executable was not modified.'
            }
        }

        [byte[]]$data = [System.IO.File]::ReadAllBytes($GameExe)
        Assert-PatchBytes -Data $data -Expected $OfficialBytes -Label 'supported original JWE3.exe'
        [System.Array]::Copy($PatchedBytes, 0, $data, $PatchOffset, $PatchedBytes.Length)

        $temporaryPath = Join-Path $GameDirectory (
            'JWE3.exe.intel-arc-water-fix-' + [System.Guid]::NewGuid().ToString('N') + '.tmp'
        )
        try {
            [System.IO.File]::WriteAllBytes($temporaryPath, $data)
            if ((Get-Sha256 -LiteralPath $temporaryPath) -cne $PatchedSha256) {
                throw 'Patched-copy verification failed. The game executable was not modified.'
            }
            Move-Item -LiteralPath $temporaryPath -Destination $GameExe -Force
        }
        finally {
            if (Test-Path -LiteralPath $temporaryPath) {
                Remove-Item -LiteralPath $temporaryPath -Force
            }
        }

        if ((Get-Sha256 -LiteralPath $GameExe) -cne $PatchedSha256) {
            throw 'Installed-file verification failed. Restore the verified backup before launching.'
        }
        Write-Host 'Installed successfully. JWE3 will use its classic VS/SM60 rendering path.' -ForegroundColor Green
        Show-Status -LiteralPath $GameExe
    }

    'Uninstall' {
        Assert-GameStopped
        $currentHash = Get-Sha256 -LiteralPath $GameExe
        if ($currentHash -ceq $OfficialSha256) {
            Write-Host 'JWE3.exe is already the supported original.' -ForegroundColor Green
            Show-Status -LiteralPath $GameExe
            break
        }
        if ($currentHash -cne $PatchedSha256) {
            throw "Unsupported or updated JWE3.exe. Automatic restore was refused. SHA-256: $currentHash"
        }

        $backupPath = Get-ValidBackup -GameDirectory $GameDirectory
        if ($null -eq $backupPath) {
            throw 'No verified original backup was found. Use Steam Verify integrity instead.'
        }

        $temporaryPath = Join-Path $GameDirectory (
            'JWE3.exe.restore-' + [System.Guid]::NewGuid().ToString('N') + '.tmp'
        )
        try {
            Copy-Item -LiteralPath $backupPath -Destination $temporaryPath
            Move-Item -LiteralPath $temporaryPath -Destination $GameExe -Force
        }
        finally {
            if (Test-Path -LiteralPath $temporaryPath) {
                Remove-Item -LiteralPath $temporaryPath -Force
            }
        }

        if ((Get-Sha256 -LiteralPath $GameExe) -cne $OfficialSha256) {
            throw 'Restore verification failed. Use Steam Verify integrity before launching.'
        }
        Write-Host 'Uninstalled successfully. The supported original JWE3.exe was restored.' -ForegroundColor Green
        Show-Status -LiteralPath $GameExe
    }
}
