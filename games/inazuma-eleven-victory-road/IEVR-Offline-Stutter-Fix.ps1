[CmdletBinding()]
param(
    [ValidateSet('Install', 'Uninstall', 'Status')]
    [string]$Action = 'Status',

    [string]$GameDirectory,

    [switch]$Elevated
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectName = 'IEVR Offline Stutter Fix'
$steamAppId = '2799860'
$defaultInstallDirectory = 'INAZUMA ELEVEN Victory Road'
$gameExecutableName = 'nie.exe'
$supportedOriginalSha256 = 'B1FA04EA365868E5C8933ACA393366F82D0D446187E2187F2737DC4FA2ACD40C'
$supportedPatchedSha256 = '4059F004915EC3462BB7E7348283A72C8738F9A3CCEB110C1475F2ADFBE2A3DF'
$supportedSize = 33918464L
$patchRva = 0x12EEC70L
$patchFileOffset = 0x12EE070L
$originalBytes = [byte[]](0x48, 0x85, 0xC0, 0x74)
$patchedBytes = [byte[]](0xB0, 0x01, 0xEB, 0x2F)
$firewallGroup = 'ClawLab - IEVR Offline Stutter Fix'
$stateRoot = Join-Path $env:LOCALAPPDATA 'ClawLab\IEVR-Offline-Stutter-Fix'
$backupPath = Join-Path $stateRoot "nie.exe-$supportedOriginalSha256.original.bak"
$elevationLogPath = Join-Path $stateRoot 'last-operation.log'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Format-ByteSequence {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    return (($Bytes | ForEach-Object { $_.ToString('X2') }) -join ' ')
}

function Test-ByteSequence {
    param(
        [Parameter(Mandatory)][byte[]]$Actual,
        [Parameter(Mandatory)][byte[]]$Expected
    )

    if ($Actual.Length -ne $Expected.Length) {
        return $false
    }
    for ($index = 0; $index -lt $Actual.Length; $index++) {
        if ($Actual[$index] -ne $Expected[$index]) {
            return $false
        }
    }
    return $true
}

function Get-Sha256 {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-BytesAtOffset {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][long]$Offset,
        [Parameter(Mandatory)][int]$Count
    )

    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $stream.Position = $Offset
        $bytes = New-Object byte[] $Count
        $read = $stream.Read($bytes, 0, $Count)
        if ($read -ne $Count) {
            throw "Could not read $Count bytes at file offset 0x$($Offset.ToString('X'))."
        }
        return $bytes
    }
    finally {
        $stream.Dispose()
    }
}

function Set-BytesAtOffset {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][long]$Offset,
        [Parameter(Mandatory)][byte[]]$Bytes
    )

    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $stream.Position = $Offset
        $stream.Write($Bytes, 0, $Bytes.Length)
        $stream.Flush($true)
    }
    finally {
        $stream.Dispose()
    }
}

function Get-SteamRoots {
    $roots = [Collections.Generic.List[string]]::new()
    $registryLocations = @(
        @{ Path = 'HKCU:\Software\Valve\Steam'; Property = 'SteamPath' }
        @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam'; Property = 'InstallPath' }
    )

    foreach ($location in $registryLocations) {
        $value = Get-ItemPropertyValue `
            -LiteralPath $location.Path `
            -Name $location.Property `
            -ErrorAction SilentlyContinue
        if ($value -and (Test-Path -LiteralPath $value -PathType Container)) {
            $roots.Add([IO.Path]::GetFullPath($value))
        }
    }

    $defaultSteamRoot = 'C:\Program Files (x86)\Steam'
    if (Test-Path -LiteralPath $defaultSteamRoot -PathType Container) {
        $roots.Add($defaultSteamRoot)
    }

    $expandedRoots = [Collections.Generic.List[string]]::new()
    foreach ($root in @($roots | Sort-Object -Unique)) {
        $expandedRoots.Add($root)
        $libraryFile = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (-not (Test-Path -LiteralPath $libraryFile -PathType Leaf)) {
            continue
        }
        $libraryText = Get-Content -LiteralPath $libraryFile -Raw
        foreach ($match in [regex]::Matches($libraryText, '"path"\s+"(?<path>(?:\\\\|[^"])*)"')) {
            $libraryRoot = $match.Groups['path'].Value.Replace('\\', '\')
            if (Test-Path -LiteralPath $libraryRoot -PathType Container) {
                $expandedRoots.Add([IO.Path]::GetFullPath($libraryRoot))
            }
        }
    }

    return @($expandedRoots | Sort-Object -Unique)
}

function Resolve-GameDirectory {
    if ($GameDirectory) {
        $resolved = [IO.Path]::GetFullPath($GameDirectory)
        if (-not (Test-Path -LiteralPath (Join-Path $resolved $gameExecutableName) -PathType Leaf)) {
            throw "nie.exe was not found in the supplied game directory: $resolved"
        }
        return $resolved
    }

    foreach ($steamRoot in Get-SteamRoots) {
        $manifestPath = Join-Path $steamRoot "steamapps\appmanifest_$steamAppId.acf"
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            continue
        }

        $manifest = Get-Content -LiteralPath $manifestPath -Raw
        $installMatch = [regex]::Match($manifest, '"installdir"\s+"(?<dir>[^"]+)"')
        $installDirectory = if ($installMatch.Success) {
            $installMatch.Groups['dir'].Value
        }
        else {
            $defaultInstallDirectory
        }
        $candidate = Join-Path $steamRoot "steamapps\common\$installDirectory"
        if (Test-Path -LiteralPath (Join-Path $candidate $gameExecutableName) -PathType Leaf) {
            return [IO.Path]::GetFullPath($candidate)
        }
    }

    $fallback = "C:\Program Files (x86)\Steam\steamapps\common\$defaultInstallDirectory"
    if (Test-Path -LiteralPath (Join-Path $fallback $gameExecutableName) -PathType Leaf) {
        return $fallback
    }

    throw 'The Steam installation was not found. Run the PowerShell script with -GameDirectory followed by the full game folder.'
}

function Get-FileState {
    param([Parameter(Mandatory)][string]$ExecutablePath)

    $item = Get-Item -LiteralPath $ExecutablePath
    if ($item.Length -ne $supportedSize) {
        return [pscustomobject]@{
            State = 'UNSUPPORTED'
            Hash = Get-Sha256 -Path $ExecutablePath
            Bytes = Get-BytesAtOffset -Path $ExecutablePath -Offset $patchFileOffset -Count 4
        }
    }

    $hash = Get-Sha256 -Path $ExecutablePath
    $bytes = Get-BytesAtOffset -Path $ExecutablePath -Offset $patchFileOffset -Count 4
    $state = 'UNSUPPORTED'
    if ($hash -eq $supportedOriginalSha256 -and (Test-ByteSequence $bytes $originalBytes)) {
        $state = 'ORIGINAL'
    }
    elseif ($hash -eq $supportedPatchedSha256 -and (Test-ByteSequence $bytes $patchedBytes)) {
        $state = 'PATCHED'
    }

    return [pscustomobject]@{ State = $state; Hash = $hash; Bytes = $bytes }
}

function Get-IsolationRules {
    return @(Get-NetFirewallRule -Group $firewallGroup -ErrorAction SilentlyContinue)
}

function Test-GameOutboundBlock {
    param([Parameter(Mandatory)][string]$ExecutablePath)

    foreach ($rule in Get-IsolationRules) {
        if ($rule.Enabled -ne 'True' -or $rule.Direction -ne 'Outbound' -or $rule.Action -ne 'Block') {
            continue
        }
        $filter = $rule | Get-NetFirewallApplicationFilter
        if ($filter.Program -ieq $ExecutablePath) {
            return $true
        }
    }
    return $false
}

function Enable-OfflineIsolation {
    param([Parameter(Mandatory)][string]$ResolvedGameDirectory)

    Get-IsolationRules | Remove-NetFirewallRule
    $targets = @(
        Get-ChildItem -LiteralPath $ResolvedGameDirectory -Filter '*.exe' -File -Recurse |
            Sort-Object FullName -Unique |
            Select-Object -ExpandProperty FullName
    )
    if ($targets.Count -eq 0) {
        throw 'No executables were found in the game directory.'
    }

    $index = 0
    foreach ($target in $targets) {
        $index++
        $leaf = Split-Path -Leaf $target
        foreach ($direction in @('Inbound', 'Outbound')) {
            New-NetFirewallRule `
                -DisplayName "ClawLab IEVR Offline - $index - $leaf - $direction" `
                -Group $firewallGroup `
                -Direction $direction `
                -Program $target `
                -Action Block `
                -Profile Any `
                -InterfaceType Any `
                -Enabled True | Out-Null
        }
    }

    $gameExecutable = Join-Path $ResolvedGameDirectory $gameExecutableName
    if (-not (Test-GameOutboundBlock -ExecutablePath $gameExecutable)) {
        throw 'The required outbound firewall block for nie.exe could not be verified.'
    }
}

function Disable-OfflineIsolation {
    # PowerShell unwraps a single pipeline object. Force an array so strict
    # mode can always evaluate Count when exactly one firewall rule remains.
    $rules = @(Get-IsolationRules)
    if ($rules.Count -gt 0) {
        $rules | Remove-NetFirewallRule
    }
}

function Assert-GameProcessesClosed {
    $blockedProcessNames = @(
        'nie',
        'EACLauncher',
        'GameBootstrapper',
        'EasyAntiCheat_EOS',
        'start_protected_game'
    )
    $running = @(Get-Process -Name $blockedProcessNames -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        throw "Close the game and its launchers first: $($running.ProcessName -join ', ')"
    }
}

function Show-Status {
    $resolvedGameDirectory = Resolve-GameDirectory
    $gameExecutable = Join-Path $resolvedGameDirectory $gameExecutableName
    $fileState = Get-FileState -ExecutablePath $gameExecutable
    $outboundBlocked = Test-GameOutboundBlock -ExecutablePath $gameExecutable

    Write-Host "$projectName status"
    Write-Host "Game directory: $resolvedGameDirectory"
    Write-Host "Executable state: $($fileState.State)"
    Write-Host "SHA-256: $($fileState.Hash)"
    Write-Host "RVA 0x$($patchRva.ToString('X')): $(Format-ByteSequence $fileState.Bytes)"
    Write-Host "Offline firewall isolation: $(if ($outboundBlocked) { 'ENABLED' } else { 'DISABLED' })"
    Write-Host "Verified backup: $(if ((Test-Path -LiteralPath $backupPath) -and ((Get-Sha256 $backupPath) -eq $supportedOriginalSha256)) { $backupPath } else { 'NOT FOUND' })"

    if ($fileState.State -eq 'PATCHED' -and -not $outboundBlocked) {
        Write-Warning 'UNSAFE STATE: the executable is patched but its outbound firewall block is not active.'
    }
}

function Invoke-ElevatedAction {
    param([Parameter(Mandatory)][string]$RequestedAction)

    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    $escapedScriptPath = $PSCommandPath.Replace("'", "''")
    $escapedLogPath = $elevationLogPath.Replace("'", "''")
    $gameDirectoryArgument = if ($GameDirectory) {
        " -GameDirectory '$(($GameDirectory).Replace("'", "''"))'"
    }
    else {
        ''
    }
    $command = @"
`$ErrorActionPreference = 'Stop'
try {
    & '$escapedScriptPath' -Action '$RequestedAction'$gameDirectoryArgument -Elevated *>&1 | Out-File -LiteralPath '$escapedLogPath' -Encoding utf8
    exit 0
}
catch {
    `$_ | Format-List * -Force | Out-File -LiteralPath '$escapedLogPath' -Encoding utf8
    exit 1
}
"@
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))

    Write-Host 'Administrator rights are required for the executable and firewall changes.'
    Write-Host 'Approve the Windows UAC prompt to continue.'
    $process = Start-Process `
        -FilePath 'powershell.exe' `
        -Verb RunAs `
        -WindowStyle Hidden `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encodedCommand) `
        -Wait `
        -PassThru
    if (Test-Path -LiteralPath $elevationLogPath) {
        Get-Content -LiteralPath $elevationLogPath
    }
    if ($process.ExitCode -ne 0) {
        throw "The elevated operation failed with exit code $($process.ExitCode)."
    }
}

if ($Action -in @('Install', 'Uninstall') -and -not (Test-IsAdministrator)) {
    if ($Elevated) {
        throw 'Administrator elevation was requested but is not active.'
    }
    Invoke-ElevatedAction -RequestedAction $Action
    Show-Status
    return
}

switch ($Action) {
    'Install' {
        Assert-GameProcessesClosed
        $resolvedGameDirectory = Resolve-GameDirectory
        $gameExecutable = Join-Path $resolvedGameDirectory $gameExecutableName
        $fileState = Get-FileState -ExecutablePath $gameExecutable

        if ($fileState.State -eq 'UNSUPPORTED') {
            throw "Unsupported nie.exe build. Received SHA-256 $($fileState.Hash). No file or firewall change was made."
        }

        Enable-OfflineIsolation -ResolvedGameDirectory $resolvedGameDirectory
        if ($fileState.State -eq 'ORIGINAL') {
            New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
            [IO.File]::Copy($gameExecutable, $backupPath, $true)
            if ((Get-Sha256 $backupPath) -ne $supportedOriginalSha256) {
                Disable-OfflineIsolation
                throw 'Backup verification failed. The executable was not modified and the firewall rules were removed.'
            }

            Set-BytesAtOffset -Path $gameExecutable -Offset $patchFileOffset -Bytes $patchedBytes
            $patchedState = Get-FileState -ExecutablePath $gameExecutable
            if ($patchedState.State -ne 'PATCHED') {
                [IO.File]::Copy($backupPath, $gameExecutable, $true)
                Disable-OfflineIsolation
                throw 'Patch verification failed. The original executable was restored and the firewall rules were removed.'
            }
        }

        Write-Host 'Offline-only stutter fix installed and verified.'
        Write-Warning 'Do not launch this modified executable with Easy Anti-Cheat or use online features.'
        Show-Status
    }

    'Uninstall' {
        Assert-GameProcessesClosed
        $resolvedGameDirectory = Resolve-GameDirectory
        $gameExecutable = Join-Path $resolvedGameDirectory $gameExecutableName
        $fileState = Get-FileState -ExecutablePath $gameExecutable

        if ($fileState.State -eq 'UNSUPPORTED') {
            throw "The installed nie.exe is not the supported original or exact supported patch. It was not overwritten and the firewall rules remain active. Use Steam Verify Files, then run Uninstall again. SHA-256: $($fileState.Hash)"
        }

        if ($fileState.State -eq 'PATCHED') {
            if ((Test-Path -LiteralPath $backupPath) -and ((Get-Sha256 $backupPath) -eq $supportedOriginalSha256)) {
                [IO.File]::Copy($backupPath, $gameExecutable, $true)
            }
            else {
                Set-BytesAtOffset -Path $gameExecutable -Offset $patchFileOffset -Bytes $originalBytes
            }

            $restoredState = Get-FileState -ExecutablePath $gameExecutable
            if ($restoredState.State -ne 'ORIGINAL') {
                throw 'Original-file restoration failed verification. The firewall rules remain active.'
            }
        }

        Disable-OfflineIsolation
        Write-Host 'Original executable restored and offline firewall rules removed.'
        Show-Status
    }

    'Status' {
        Show-Status
    }
}
