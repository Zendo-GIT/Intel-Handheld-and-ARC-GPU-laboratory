[CmdletBinding()]
param(
    [ValidateSet('Status', 'Install', 'Uninstall', 'Launch', 'InstallSteamIntegration', 'RemoveSteamIntegration', 'SteamHandoffLaunch')]
    [string]$Action = 'Status',

    [string]$GameDirectory,

    [switch]$SteamWrapperMode,

    [int]$WrapperProcessId = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$fixVersion = '1.0.0'
$steamAppId = '1222140'
$gameFolderName = 'Detroit Become Human'
$gameExecutableName = 'DetroitBecomeHuman.exe'
$realExecutableName = 'DetroitBecomeHuman.ClawLab.real.exe'
$supportedBuildId = '12158144'
$vanillaSha256 = 'ECF52321921387E683904E089082D76B973326FC093AF14E524056715519C1CF'
$patchedSha256 = '1B31A15AC8AF8A236B3B7FB721DF439D03EB40ACAA5ECF59BC6BCF0CDF49D2AE'
$patchOffset = 0x661E57L
$vanillaBytes = [byte[]](0xFF, 0x15, 0x4B, 0x31, 0x25, 0x01)
$patchedBytes = [byte[]](0xB8, 0x01, 0x00, 0x00, 0x00, 0x90)
$stateRoot = Join-Path $env:LOCALAPPDATA 'ClawLab\Detroit-IntelArc-Stability-Fix'
$backupPath = Join-Path $stateRoot "DetroitBecomeHuman.exe-$vanillaSha256.original.bak"
$graphicsStatePath = Join-Path $stateRoot 'graphics-state.json'
$launchLogPath = Join-Path $stateRoot 'last-launch.log'
$steamIntegrationStatePath = Join-Path $stateRoot 'steam-integration.json'
$installedLauncherScriptPath = Join-Path $stateRoot 'Detroit-IntelArc-StabilityFix.installed.ps1'
$retiredWrapperPath = Join-Path $stateRoot 'DetroitBecomeHuman.ClawLab.wrapper.last.exe'
$retiredPayloadPath = Join-Path $stateRoot 'DetroitBecomeHuman.ClawLab.payload.last.exe'
$activeWrapperCopyPath = Join-Path $stateRoot 'DetroitBecomeHuman.ClawLab.active-wrapper.exe'
$handoffStatePath = Join-Path $stateRoot 'steam-handoff-active.json'

function Write-LaunchLog {
    param([Parameter(Mandatory)][string]$Message)
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Message
    Add-Content -LiteralPath $launchLogPath -Value $line -Encoding UTF8
    Write-Host $Message
}

function Get-Sha256 {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
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

function Get-BytesAtOffset {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][long]$Offset,
        [Parameter(Mandatory)][int]$Count
    )
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $stream.Position = $Offset
        $bytes = [byte[]]::new($Count)
        if ($stream.Read($bytes, 0, $Count) -ne $Count) {
            throw "Could not read $Count bytes at offset 0x$($Offset.ToString('X'))."
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
    $fullPath = [IO.Path]::GetFullPath($Path)
    if ($List -notcontains $fullPath) {
        $List.Add($fullPath)
    }
}

function Get-SteamLibraryRoots {
    $steamRoots = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in @(
        @('HKCU:\Software\Valve\Steam', 'SteamPath'),
        @('HKCU:\Software\Valve\Steam', 'InstallPath'),
        @('HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'InstallPath'),
        @('HKLM:\SOFTWARE\Valve\Steam', 'InstallPath')
    )) {
        try {
            Add-UniquePath -List $steamRoots -Path (Get-ItemPropertyValue -LiteralPath $entry[0] -Name $entry[1])
        }
        catch {
            # Optional registry location.
        }
    }
    if ($null -ne ${env:ProgramFiles(x86)}) {
        Add-UniquePath -List $steamRoots -Path (Join-Path ${env:ProgramFiles(x86)} 'Steam')
    }

    $libraryRoots = [System.Collections.Generic.List[string]]::new()
    foreach ($steamRoot in @($steamRoots)) {
        Add-UniquePath -List $libraryRoots -Path $steamRoot
        $libraryFile = Join-Path $steamRoot 'steamapps\libraryfolders.vdf'
        if (-not (Test-Path -LiteralPath $libraryFile -PathType Leaf)) {
            continue
        }
        foreach ($line in [IO.File]::ReadLines($libraryFile)) {
            if ($line -match '^\s*"path"\s+"([^"]+)"' -or $line -match '^\s*"\d+"\s+"([^"]+)"') {
                Add-UniquePath -List $libraryRoots -Path ($Matches[1] -replace '\\\\', '\')
            }
        }
    }
    return $libraryRoots
}

function Resolve-GameDirectory {
    param([string]$ExplicitDirectory)
    if (-not [string]::IsNullOrWhiteSpace($ExplicitDirectory)) {
        return [IO.Path]::GetFullPath($ExplicitDirectory)
    }

    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($libraryRoot in Get-SteamLibraryRoots) {
        $candidate = Join-Path $libraryRoot "steamapps\common\$gameFolderName"
        if (Test-Path -LiteralPath (Join-Path $candidate $gameExecutableName) -PathType Leaf) {
            Add-UniquePath -List $candidates -Path $candidate
        }
    }
    if ($candidates.Count -eq 0) {
        throw "Detroit: Become Human was not found. Pass -GameDirectory with the Steam game folder."
    }
    if ($candidates.Count -eq 1) {
        return $candidates[0]
    }

    $supported = @($candidates | Where-Object {
        $hash = Get-Sha256 -Path (Join-Path $_ $gameExecutableName)
        $hash -in @($vanillaSha256, $patchedSha256)
    })
    if ($supported.Count -eq 1) {
        return $supported[0]
    }
    throw "Multiple Detroit installations were found. Pass -GameDirectory explicitly.`n$($candidates -join "`n")"
}

function Assert-SafeGameDirectory {
    param([Parameter(Mandatory)][string]$Directory)
    if ([IO.Path]::GetFileName($Directory) -ine $gameFolderName) {
        throw "Safety check failed: the folder must be named exactly '$gameFolderName'."
    }
    $exePath = Join-Path $Directory $gameExecutableName
    if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
        throw "The game executable was not found: $exePath"
    }
}

function Assert-GameStopped {
    if (Get-Process -Name 'DetroitBecomeHuman', 'DetroitBecomeHuman.ClawLab.real' -ErrorAction SilentlyContinue) {
        throw 'Detroit: Become Human is running. Close it before installing or uninstalling.'
    }
}

function Get-SteamIntegrationInfo {
    param([Parameter(Mandatory)][string]$Directory)
    $wrapperPath = Join-Path $Directory $gameExecutableName
    $payloadPath = Join-Path $Directory $realExecutableName
    $wrapperExists = Test-Path -LiteralPath $wrapperPath -PathType Leaf
    $payloadExists = Test-Path -LiteralPath $payloadPath -PathType Leaf
    $wrapperHash = if ($wrapperExists) { Get-Sha256 -Path $wrapperPath } else { '' }
    $payloadHash = if ($payloadExists) { Get-Sha256 -Path $payloadPath } else { '' }
    $manifest = $null
    if (Test-Path -LiteralPath $steamIntegrationStatePath -PathType Leaf) {
        try {
            $manifest = Get-Content -LiteralPath $steamIntegrationStatePath -Raw | ConvertFrom-Json
        }
        catch {
            $manifest = $null
        }
    }

    $manifestMatches = $null -ne $manifest -and
        $manifest.GameDirectory -eq $Directory -and
        $manifest.WrapperSha256 -eq $wrapperHash -and
        $manifest.PayloadSha256 -eq $payloadHash

    $activeWrapperHash = if (Test-Path -LiteralPath $activeWrapperCopyPath -PathType Leaf) {
        Get-Sha256 -Path $activeWrapperCopyPath
    }
    else {
        ''
    }
    $handoffRecoverable = $null -ne $manifest -and
        (Test-Path -LiteralPath $handoffStatePath -PathType Leaf) -and
        $wrapperHash -eq $patchedSha256 -and
        $payloadHash -eq $patchedSha256 -and
        $activeWrapperHash -eq $manifest.WrapperSha256

    $state = if ($payloadExists -and $payloadHash -eq $patchedSha256 -and $manifestMatches) {
        'INSTALLED'
    }
    elseif ($handoffRecoverable) {
        'ACTIVE_OR_INTERRUPTED_HANDOFF'
    }
    elseif (-not $payloadExists -and $wrapperHash -in @($vanillaSha256, $patchedSha256)) {
        'NOT_INSTALLED'
    }
    elseif ($payloadExists -and $payloadHash -eq $patchedSha256 -and
        $wrapperHash -in @($vanillaSha256, $patchedSha256)) {
        'OVERWRITTEN_BY_STEAM'
    }
    else {
        'INCONSISTENT_REQUIRES_MANUAL_RECOVERY'
    }

    return [pscustomobject]@{
        State = $state
        WrapperPath = $wrapperPath
        PayloadPath = $payloadPath
        WrapperSha256 = $wrapperHash
        PayloadSha256 = $payloadHash
        Manifest = $manifest
        ManifestMatches = $manifestMatches
        ActiveWrapperSha256 = $activeWrapperHash
    }
}

function Copy-InstalledLauncherScript {
    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    $sourcePath = [IO.Path]::GetFullPath($PSCommandPath)
    $destinationPath = [IO.Path]::GetFullPath($installedLauncherScriptPath)
    if ($sourcePath -ne $destinationPath) {
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
    }
    if (-not (Test-Path -LiteralPath $destinationPath -PathType Leaf)) {
        throw 'Could not install the optimized launcher script.'
    }
}

function Build-SteamWrapper {
    param([Parameter(Mandatory)][string]$OutputPath)
    $source = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

namespace ClawLab.DetroitSteamLauncher
{
    internal static class Program
    {
        private static string Quote(string value)
        {
            return "\"" + value.Replace("\"", "\\\"") + "\"";
        }

        [STAThread]
        private static int Main()
        {
            string stateRoot = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "ClawLab", "Detroit-IntelArc-Stability-Fix");
            string scriptPath = Path.Combine(stateRoot, "Detroit-IntelArc-StabilityFix.installed.ps1");
            string gameDirectory = AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
            string powershell = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.System),
                "WindowsPowerShell", "v1.0", "powershell.exe");

            if (!File.Exists(scriptPath))
            {
                MessageBox.Show(
                    "The installed ClawLab launcher script is missing. Run INSTALL_STEAM_INTEGRATION.bat again.",
                    "Detroit Intel Arc Stability Fix",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return 2;
            }

            try
            {
                ProcessStartInfo startInfo = new ProcessStartInfo();
                startInfo.FileName = powershell;
                startInfo.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File " + Quote(scriptPath) +
                    " -Action SteamHandoffLaunch -GameDirectory " + Quote(gameDirectory) +
                    " -WrapperProcessId " + Process.GetCurrentProcess().Id;
                startInfo.WorkingDirectory = gameDirectory;
                startInfo.UseShellExecute = false;
                startInfo.CreateNoWindow = true;

                Process launcher = Process.Start(startInfo);
                return launcher == null ? 4 : 0;
            }
            catch (Exception exception)
            {
                MessageBox.Show(
                    "The optimized launcher could not start: " + exception.Message,
                    "Detroit Intel Arc Stability Fix",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return 3;
            }
        }
    }
}
'@
    if (Test-Path -LiteralPath $OutputPath) {
        Remove-Item -LiteralPath $OutputPath -Force
    }
    Add-Type -TypeDefinition $source -Language CSharp -OutputAssembly $OutputPath `
        -OutputType WindowsApplication -ReferencedAssemblies @('System.dll', 'System.Windows.Forms.dll')
    if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
        throw 'The local Steam wrapper compiler did not produce an executable.'
    }
}

function Get-StatusObject {
    param([Parameter(Mandatory)][string]$Directory)
    $exePath = Join-Path $Directory $gameExecutableName
    $integration = Get-SteamIntegrationInfo -Directory $Directory
    $hash = $integration.WrapperSha256
    $state = if ($integration.State -eq 'INSTALLED') {
        'FIX_INSTALLED_WITH_STEAM_INTEGRATION'
    }
    elseif ($integration.State -eq 'ACTIVE_OR_INTERRUPTED_HANDOFF') {
        'OPTIMIZED_STEAM_HANDOFF_ACTIVE_OR_RECOVERABLE'
    }
    elseif ($integration.State -eq 'OVERWRITTEN_BY_STEAM') {
        'STEAM_INTEGRATION_OVERWRITTEN_REPAIR_REQUIRED'
    }
    elseif ($integration.State -eq 'INCONSISTENT_REQUIRES_MANUAL_RECOVERY') {
        'INCONSISTENT_REQUIRES_MANUAL_RECOVERY'
    }
    elseif ($hash -eq $vanillaSha256) {
        'SUPPORTED_VANILLA_NOT_INSTALLED'
    }
    elseif ($hash -eq $patchedSha256) {
        'FIX_INSTALLED'
    }
    else {
        'UNSUPPORTED_BUILD_NO_CHANGES_ALLOWED'
    }
    [pscustomobject]@{
        FixVersion = $fixVersion
        SteamBuildId = $supportedBuildId
        State = $state
        GameDirectory = $Directory
        ExeSha256 = $hash
        GamePayloadSha256 = $integration.PayloadSha256
        SteamIntegration = $integration.State
        VerifiedBackup = (Test-Path -LiteralPath $backupPath -PathType Leaf) -and ((Get-Sha256 -Path $backupPath) -eq $vanillaSha256)
        DllInjection = $false
        RuntimeMemoryPatching = $false
        AntiCheatBypass = $false
    }
}

function Install-WarningPatch {
    param([Parameter(Mandatory)][string]$Directory)
    Assert-GameStopped
    $integration = Get-SteamIntegrationInfo -Directory $Directory
    if ($integration.State -eq 'INSTALLED') {
        Write-Host 'The warning patch is already installed inside the managed game payload.' -ForegroundColor Green
        return
    }
    if ($integration.State -ne 'NOT_INSTALLED') {
        throw "Steam integration state must be repaired before patching: $($integration.State)"
    }
    $exePath = Join-Path $Directory $gameExecutableName
    $currentHash = Get-Sha256 -Path $exePath
    if ($currentHash -eq $patchedSha256) {
        Write-Host 'The verified unsupported-GPU warning patch is already installed.' -ForegroundColor Green
        return
    }
    if ($currentHash -ne $vanillaSha256) {
        throw "Unsupported executable. Nothing was changed. SHA-256: $currentHash"
    }

    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
        if ((Get-Sha256 -Path $backupPath) -ne $vanillaSha256) {
            throw "The existing backup failed verification: $backupPath"
        }
    }
    else {
        Copy-Item -LiteralPath $exePath -Destination $backupPath
        if ((Get-Sha256 -Path $backupPath) -ne $vanillaSha256) {
            throw 'The vanilla executable backup failed verification.'
        }
    }

    $site = Get-BytesAtOffset -Path $exePath -Offset $patchOffset -Count $vanillaBytes.Length
    if (-not (Test-ByteSequence -Actual $site -Expected $vanillaBytes)) {
        throw "The warning-dialog call did not match at offset 0x$($patchOffset.ToString('X'))."
    }

    $temporaryPath = Join-Path $Directory ($gameExecutableName + '.clawlab-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        Copy-Item -LiteralPath $exePath -Destination $temporaryPath
        Set-BytesAtOffset -Path $temporaryPath -Offset $patchOffset -Bytes $patchedBytes
        if ((Get-Sha256 -Path $temporaryPath) -ne $patchedSha256) {
            throw 'The patched temporary executable failed SHA-256 verification.'
        }
        Move-Item -LiteralPath $temporaryPath -Destination $exePath -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
    if ((Get-Sha256 -Path $exePath) -ne $patchedSha256) {
        Copy-Item -LiteralPath $backupPath -Destination $exePath -Force
        throw 'Installed patch verification failed. The vanilla backup was restored.'
    }
    Write-Host 'Installed the verified unsupported-GPU warning patch.' -ForegroundColor Green
}

function Install-SteamIntegration {
    param([Parameter(Mandatory)][string]$Directory)
    Assert-GameStopped
    $integration = Get-SteamIntegrationInfo -Directory $Directory
    if ($integration.State -eq 'ACTIVE_OR_INTERRUPTED_HANDOFF') {
        Restore-SteamWrapperAfterHandoff -Directory $Directory
        $integration = Get-SteamIntegrationInfo -Directory $Directory
    }
    if ($integration.State -eq 'INSTALLED') {
        Copy-InstalledLauncherScript
        Remove-Item -LiteralPath $handoffStatePath -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $activeWrapperCopyPath -PathType Leaf) {
            Move-Item -LiteralPath $activeWrapperCopyPath -Destination $retiredWrapperPath -Force
        }
        Write-Host 'Steam integration is already installed; the managed launcher script was refreshed.' -ForegroundColor Green
        return
    }
    if ($integration.State -ne 'NOT_INSTALLED') {
        throw "Steam integration cannot be installed from state: $($integration.State)"
    }

    Install-WarningPatch -Directory $Directory
    $exePath = Join-Path $Directory $gameExecutableName
    $payloadPath = Join-Path $Directory $realExecutableName
    if ((Get-Sha256 -Path $exePath) -ne $patchedSha256) {
        throw 'The verified warning-patched game executable is required before Steam integration.'
    }
    if (Test-Path -LiteralPath $payloadPath) {
        throw "The managed payload path is already occupied: $payloadPath"
    }

    Copy-InstalledLauncherScript
    $temporaryWrapperPath = Join-Path $stateRoot ('DetroitSteamLauncher-' + [guid]::NewGuid().ToString('N') + '.exe')
    $manifestTemporaryPath = Join-Path $stateRoot ('steam-integration-' + [guid]::NewGuid().ToString('N') + '.json')
    try {
        Build-SteamWrapper -OutputPath $temporaryWrapperPath
        $wrapperHash = Get-Sha256 -Path $temporaryWrapperPath
        Copy-Item -LiteralPath $exePath -Destination $payloadPath
        if ((Get-Sha256 -Path $payloadPath) -ne $patchedSha256) {
            throw 'The managed game payload copy failed SHA-256 verification.'
        }

        [pscustomobject]@{
            Version = $fixVersion
            GameDirectory = $Directory
            WrapperSha256 = $wrapperHash
            PayloadSha256 = $patchedSha256
            InstalledScriptSha256 = Get-Sha256 -Path $installedLauncherScriptPath
            InstalledAtUtc = [datetime]::UtcNow.ToString('o')
        } | ConvertTo-Json | Set-Content -LiteralPath $manifestTemporaryPath -Encoding UTF8

        Move-Item -LiteralPath $manifestTemporaryPath -Destination $steamIntegrationStatePath -Force
        Move-Item -LiteralPath $temporaryWrapperPath -Destination $exePath -Force

        $installed = Get-SteamIntegrationInfo -Directory $Directory
        if ($installed.State -ne 'INSTALLED') {
            Copy-Item -LiteralPath $payloadPath -Destination $exePath -Force
            throw "Steam wrapper verification failed after installation: $($installed.State)"
        }
    }
    catch {
        if ((Test-Path -LiteralPath $payloadPath -PathType Leaf) -and
            (Get-Sha256 -Path $payloadPath) -eq $patchedSha256) {
            Copy-Item -LiteralPath $payloadPath -Destination $exePath -Force
            Move-Item -LiteralPath $payloadPath -Destination $retiredPayloadPath -Force
        }
        Remove-Item -LiteralPath $steamIntegrationStatePath -Force -ErrorAction SilentlyContinue
        throw
    }
    finally {
        Remove-Item -LiteralPath $temporaryWrapperPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $manifestTemporaryPath -Force -ErrorAction SilentlyContinue
    }
    Write-Host 'Installed the verified local Steam wrapper. Steam Play now starts the optimized launcher.' -ForegroundColor Green
}

function Remove-SteamIntegration {
    param([Parameter(Mandatory)][string]$Directory)
    Assert-GameStopped
    $integration = Get-SteamIntegrationInfo -Directory $Directory
    if ($integration.State -eq 'NOT_INSTALLED') {
        Write-Host 'Steam integration is not installed.'
        return
    }
    if ($integration.State -eq 'INCONSISTENT_REQUIRES_MANUAL_RECOVERY') {
        throw 'Steam integration files do not match their signed state. No file was changed; use Steam Verify integrity or recover manually.'
    }

    $exePath = $integration.WrapperPath
    $payloadPath = $integration.PayloadPath
    if ($integration.State -eq 'ACTIVE_OR_INTERRUPTED_HANDOFF') {
        Copy-Item -LiteralPath $activeWrapperCopyPath -Destination $retiredWrapperPath -Force
        Move-Item -LiteralPath $payloadPath -Destination $retiredPayloadPath -Force
        Remove-Item -LiteralPath $steamIntegrationStatePath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $handoffStatePath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $activeWrapperCopyPath -Force -ErrorAction SilentlyContinue
        Write-Host 'Removed interrupted Steam integration while preserving the verified patched game at its original path.' -ForegroundColor Yellow
        return
    }
    if ($integration.State -eq 'OVERWRITTEN_BY_STEAM') {
        Move-Item -LiteralPath $payloadPath -Destination $retiredPayloadPath -Force
        Remove-Item -LiteralPath $steamIntegrationStatePath -Force -ErrorAction SilentlyContinue
        Write-Host 'Steam had replaced the wrapper. The current Steam executable was preserved and the old managed payload was retired safely.' -ForegroundColor Yellow
        return
    }

    Copy-Item -LiteralPath $exePath -Destination $retiredWrapperPath -Force
    if ((Get-Sha256 -Path $retiredWrapperPath) -ne $integration.WrapperSha256) {
        throw 'The recoverable wrapper copy failed verification.'
    }
    $temporaryRestorePath = Join-Path $Directory ($gameExecutableName + '.clawlab-restore-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        Copy-Item -LiteralPath $payloadPath -Destination $temporaryRestorePath
        if ((Get-Sha256 -Path $temporaryRestorePath) -ne $patchedSha256) {
            throw 'The managed payload failed verification during restoration.'
        }
        Move-Item -LiteralPath $temporaryRestorePath -Destination $exePath -Force
        if ((Get-Sha256 -Path $exePath) -ne $patchedSha256) {
            Copy-Item -LiteralPath $retiredWrapperPath -Destination $exePath -Force
            throw 'The patched game executable could not be restored from Steam integration.'
        }
        Move-Item -LiteralPath $payloadPath -Destination $retiredPayloadPath -Force
        Remove-Item -LiteralPath $steamIntegrationStatePath -Force -ErrorAction SilentlyContinue
    }
    finally {
        Remove-Item -LiteralPath $temporaryRestorePath -Force -ErrorAction SilentlyContinue
    }
    Write-Host 'Removed Steam integration and restored the verified warning-patched game executable.' -ForegroundColor Green
}

function Restore-SteamWrapperAfterHandoff {
    param([Parameter(Mandatory)][string]$Directory)
    $integration = Get-SteamIntegrationInfo -Directory $Directory
    if ($integration.State -eq 'INSTALLED') {
        Remove-Item -LiteralPath $handoffStatePath -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $activeWrapperCopyPath -PathType Leaf) {
            Move-Item -LiteralPath $activeWrapperCopyPath -Destination $retiredWrapperPath -Force
        }
        return
    }
    if ($integration.State -ne 'ACTIVE_OR_INTERRUPTED_HANDOFF') {
        throw "The Steam wrapper cannot be restored from handoff state: $($integration.State)"
    }
    $exePath = Join-Path $Directory $gameExecutableName
    $temporaryWrapperPath = Join-Path $Directory ($gameExecutableName + '.clawlab-wrapper-restore-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        Copy-Item -LiteralPath $activeWrapperCopyPath -Destination $temporaryWrapperPath
        if ((Get-Sha256 -Path $temporaryWrapperPath) -ne $integration.Manifest.WrapperSha256) {
            throw 'The active Steam wrapper recovery copy failed SHA-256 verification.'
        }
        Move-Item -LiteralPath $temporaryWrapperPath -Destination $exePath -Force
        $restored = Get-SteamIntegrationInfo -Directory $Directory
        if ($restored.State -ne 'INSTALLED') {
            throw "Steam wrapper restoration failed verification: $($restored.State)"
        }
        Move-Item -LiteralPath $activeWrapperCopyPath -Destination $retiredWrapperPath -Force
        Remove-Item -LiteralPath $handoffStatePath -Force -ErrorAction SilentlyContinue
    }
    finally {
        Remove-Item -LiteralPath $temporaryWrapperPath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-SteamHandoffLaunch {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][int]$ParentWrapperProcessId
    )
    $integration = Get-SteamIntegrationInfo -Directory $Directory
    if ($integration.State -ne 'INSTALLED') {
        throw "Steam handoff requires a verified installed wrapper: $($integration.State)"
    }
    if ($ParentWrapperProcessId -le 0) {
        throw 'Steam handoff did not receive a valid wrapper process ID.'
    }

    $wrapperProcess = Get-Process -Id $ParentWrapperProcessId -ErrorAction SilentlyContinue
    if ($null -ne $wrapperProcess) {
        if (-not $wrapperProcess.WaitForExit(15000)) {
            throw 'The Steam wrapper did not exit in time for the executable handoff.'
        }
    }

    Assert-GameStopped
    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    $exePath = Join-Path $Directory $gameExecutableName
    $payloadPath = Join-Path $Directory $realExecutableName
    $temporaryPayloadPath = Join-Path $Directory ($gameExecutableName + '.clawlab-payload-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $handoffPrepared = $false
    try {
        Copy-Item -LiteralPath $exePath -Destination $activeWrapperCopyPath -Force
        if ((Get-Sha256 -Path $activeWrapperCopyPath) -ne $integration.WrapperSha256) {
            throw 'The active wrapper recovery copy failed SHA-256 verification.'
        }
        [pscustomobject]@{
            Version = $fixVersion
            GameDirectory = $Directory
            WrapperSha256 = $integration.WrapperSha256
            PayloadSha256 = $patchedSha256
            StartedAtUtc = [datetime]::UtcNow.ToString('o')
        } | ConvertTo-Json | Set-Content -LiteralPath $handoffStatePath -Encoding UTF8
        $handoffPrepared = $true

        Copy-Item -LiteralPath $payloadPath -Destination $temporaryPayloadPath
        if ((Get-Sha256 -Path $temporaryPayloadPath) -ne $patchedSha256) {
            throw 'The temporary handoff payload failed SHA-256 verification.'
        }
        Move-Item -LiteralPath $temporaryPayloadPath -Destination $exePath -Force
        if ((Get-Sha256 -Path $exePath) -ne $patchedSha256) {
            throw 'The game executable handoff failed verification.'
        }

        Invoke-OptimizedLaunch -Directory $Directory
    }
    finally {
        Remove-Item -LiteralPath $temporaryPayloadPath -Force -ErrorAction SilentlyContinue
        if ($handoffPrepared) {
            Restore-SteamWrapperAfterHandoff -Directory $Directory
        }
        else {
            Remove-Item -LiteralPath $activeWrapperCopyPath -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $handoffStatePath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Save-AndApplyGraphicsSafety {
    param([Parameter(Mandatory)][string]$Directory)
    $graphicsPath = Join-Path $Directory 'GraphicOptions.JSON'
    if (-not (Test-Path -LiteralPath $graphicsPath -PathType Leaf)) {
        Write-LaunchLog 'GraphicOptions.JSON was not found; graphics safety values were not changed.'
        return
    }

    $graphics = Get-Content -LiteralPath $graphicsPath -Raw | ConvertFrom-Json
    $video = $graphics.GRAPHIC_OPTIONS.VIDEO_OPTIONS
    if (-not (Test-Path -LiteralPath $graphicsStatePath -PathType Leaf)) {
        [pscustomobject]@{
            ResolutionScaling = [double]$video.RESOLUTION_SCALING
            Hdr = [bool]$video.HDR
        } | ConvertTo-Json | Set-Content -LiteralPath $graphicsStatePath -Encoding UTF8
    }

    $changed = $false
    if ([double]$video.RESOLUTION_SCALING -ne 1.0) {
        $video.RESOLUTION_SCALING = 1.0
        $changed = $true
    }
    if ([bool]$video.HDR) {
        $video.HDR = $false
        $changed = $true
    }
    if ($changed) {
        $graphics | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $graphicsPath -Encoding UTF8
        Write-LaunchLog 'Applied the validated graphics safety profile: 100% internal scale and in-game HDR off.'
    }
    else {
        Write-LaunchLog 'Graphics safety profile is already active: 100% internal scale and in-game HDR off.'
    }
}

function Restore-GraphicsValues {
    param([Parameter(Mandatory)][string]$Directory)
    $graphicsPath = Join-Path $Directory 'GraphicOptions.JSON'
    if (-not (Test-Path -LiteralPath $graphicsStatePath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $graphicsPath -PathType Leaf)) {
        return
    }
    $saved = Get-Content -LiteralPath $graphicsStatePath -Raw | ConvertFrom-Json
    $graphics = Get-Content -LiteralPath $graphicsPath -Raw | ConvertFrom-Json
    $graphics.GRAPHIC_OPTIONS.VIDEO_OPTIONS.RESOLUTION_SCALING = [double]$saved.ResolutionScaling
    $graphics.GRAPHIC_OPTIONS.VIDEO_OPTIONS.HDR = [bool]$saved.Hdr
    $graphics | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $graphicsPath -Encoding UTF8
    Remove-Item -LiteralPath $graphicsStatePath -Force
}

function Test-PipelineCache {
    param([Parameter(Mandatory)][string]$Directory)
    $cachePath = Join-Path $Directory 'ShaderCache\VkPipelineCache.bin'
    if (-not (Test-Path -LiteralPath $cachePath -PathType Leaf)) {
        return [pscustomobject]@{ Valid = $false; Path = $cachePath; Detail = 'missing' }
    }

    $stream = [IO.File]::Open($cachePath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $header = [byte[]]::new([Math]::Min(4096, [int]$stream.Length))
        [void]$stream.Read($header, 0, $header.Length)
    }
    finally {
        $stream.Dispose()
    }

    $qdMagic = [Text.Encoding]::ASCII.GetString($header, 0, [Math]::Min(4, $header.Length)) -eq 'HCDQ'
    $intelHeaderFound = $false
    for ($offset = 0; $offset -le ($header.Length - 16); $offset++) {
        if ([BitConverter]::ToUInt32($header, $offset) -eq 32 -and
            [BitConverter]::ToUInt32($header, $offset + 4) -eq 1 -and
            [BitConverter]::ToUInt32($header, $offset + 8) -eq 0x8086) {
            $intelHeaderFound = $true
            break
        }
    }
    return [pscustomobject]@{
        Valid = $qdMagic -and $intelHeaderFound
        Path = $cachePath
        Detail = if ($qdMagic -and $intelHeaderFound) { 'QD container with Intel Vulkan pipeline header' } else { 'unexpected cache header' }
    }
}

function Add-NativeMethods {
    if ('ClawLabDetroitNative' -as [type]) {
        return
    }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class ClawLabDetroitNative
{
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool ShowWindowAsync(IntPtr window, int command);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SetForegroundWindow(IntPtr window);

    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int virtualKey);
}
'@
}

function Invoke-PresentationReset {
    param(
        [Parameter(Mandatory)][IntPtr]$Window,
        [Parameter(Mandatory)][string]$Reason
    )
    Write-LaunchLog "Presentation recovery triggered: $Reason"
    [void][ClawLabDetroitNative]::ShowWindowAsync($Window, 6)
    Start-Sleep -Milliseconds 180
    [void][ClawLabDetroitNative]::ShowWindowAsync($Window, 9)
    Start-Sleep -Milliseconds 100
    [void][ClawLabDetroitNative]::SetForegroundWindow($Window)
}

function Get-ChapterProgressRoots {
    $saveRoot = Join-Path $env:USERPROFILE 'Saved Games\Quantic Dream\Detroit Become Human'
    if (-not (Test-Path -LiteralPath $saveRoot -PathType Container)) {
        return @()
    }
    return @(Get-ChildItem -LiteralPath $saveRoot -Directory -Recurse -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -eq 'Chapters' -and
            $_.Parent.Name -eq 'Game' -and
            $_.Parent.Parent.Name -like 'Default-*'
        } |
        Select-Object -ExpandProperty FullName)
}

function Get-ChapterProgressSignature {
    param([AllowEmptyCollection()][string[]]$Roots)
    $entries = foreach ($root in $Roots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) {
            continue
        }
        Get-ChildItem -LiteralPath $root -File -Filter '*.qdsav' -ErrorAction SilentlyContinue |
            Sort-Object FullName |
            ForEach-Object {
                '{0}|{1}|{2}' -f $_.FullName, $_.LastWriteTimeUtc.Ticks, $_.Length
            }
    }
    return ($entries -join "`n")
}

function Watch-GameAndRecoverPresentation {
    param([Parameter(Mandatory)][Diagnostics.Process]$Process)
    $lastReset = [datetime]::MinValue
    $hotkeyLatched = $false
    $chapterRoots = @(Get-ChapterProgressRoots)
    $chapterSignature = Get-ChapterProgressSignature -Roots $chapterRoots
    $lastChapterCheck = [datetime]::MinValue
    $chapterResetPending = $false
    $chapterChangeDetectedAt = $null

    if ($chapterRoots.Count -gt 0) {
        Write-LaunchLog "Chapter-only guard found $($chapterRoots.Count) progress directory/directories."
    }
    else {
        Write-LaunchLog 'Chapter-only guard found no progress directory; automatic recovery is disabled for this session.'
    }

    while (-not $Process.HasExited) {
        Start-Sleep -Milliseconds 500
        $Process.Refresh()
        if ($Process.HasExited) {
            break
        }

        $now = Get-Date
        $window = $Process.MainWindowHandle
        if ($window -eq [IntPtr]::Zero) {
            continue
        }

        $control = [ClawLabDetroitNative]::GetAsyncKeyState(0x11) -lt 0
        $alt = [ClawLabDetroitNative]::GetAsyncKeyState(0x12) -lt 0
        $f11 = [ClawLabDetroitNative]::GetAsyncKeyState(0x7A) -lt 0
        $hotkeyPressed = $control -and $alt -and $f11
        if ($hotkeyPressed -and -not $hotkeyLatched -and ($now - $lastReset).TotalSeconds -ge 2) {
            Invoke-PresentationReset -Window $window -Reason 'manual Ctrl+Alt+F11 request'
            $lastReset = Get-Date
        }
        $hotkeyLatched = $hotkeyPressed

        $isForeground = [ClawLabDetroitNative]::GetForegroundWindow() -eq $window
        if ($chapterRoots.Count -gt 0 -and ($now - $lastChapterCheck).TotalSeconds -ge 1) {
            $newChapterSignature = Get-ChapterProgressSignature -Roots $chapterRoots
            if (-not [string]::IsNullOrEmpty($chapterSignature) -and
                $newChapterSignature -ne $chapterSignature) {
                $chapterResetPending = $true
                $chapterChangeDetectedAt = $now
                Write-LaunchLog 'Chapter progress changed; one between-chapter presentation reset is armed.'
            }
            $chapterSignature = $newChapterSignature
            $lastChapterCheck = $now
        }

        if ($chapterResetPending -and $isForeground -and
            ($now - $chapterChangeDetectedAt).TotalSeconds -ge 3 -and
            ($now - $lastReset).TotalSeconds -ge 60) {
            Invoke-PresentationReset -Window $window -Reason 'between-chapter progress transition'
            $lastReset = Get-Date
            $chapterResetPending = $false
            $chapterChangeDetectedAt = $null
        }
        elseif ($chapterResetPending -and
            ($now - $chapterChangeDetectedAt).TotalSeconds -ge 30) {
            Write-LaunchLog 'Chapter reset expired because the game did not return to the foreground in time.'
            $chapterResetPending = $false
            $chapterChangeDetectedAt = $null
        }
    }
}

function Invoke-OptimizedLaunch {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [switch]$FromSteamWrapper
    )
    $integration = Get-SteamIntegrationInfo -Directory $Directory
    if ($FromSteamWrapper -and $integration.State -ne 'INSTALLED') {
        throw "Steam wrapper launch was requested from an invalid integration state: $($integration.State)"
    }
    if ($integration.State -eq 'INCONSISTENT_REQUIRES_MANUAL_RECOVERY') {
        throw 'Steam integration is inconsistent. The game launch was refused to protect the original files.'
    }
    $exePath = if ($integration.State -eq 'INSTALLED') {
        $integration.PayloadPath
    }
    else {
        Join-Path $Directory $gameExecutableName
    }
    $payloadProcessName = [IO.Path]::GetFileNameWithoutExtension($exePath)
    if (Get-Process -Name $payloadProcessName -ErrorAction SilentlyContinue) {
        throw 'Detroit: Become Human is already running.'
    }
    if ((Get-Sha256 -Path $exePath) -ne $patchedSha256) {
        throw 'Install the fix before using LAUNCH_OPTIMIZED.bat.'
    }

    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    Set-Content -LiteralPath $launchLogPath -Value '' -Encoding UTF8
    Save-AndApplyGraphicsSafety -Directory $Directory

    $cache = Test-PipelineCache -Directory $Directory
    Write-LaunchLog "Pipeline cache: $($cache.Detail)."
    Write-LaunchLog 'Shader and pipeline caches are left to the game and Windows; forced prefetch is disabled.'

    $steamAppIdPath = Join-Path $Directory 'steam_appid.txt'
    $steamAppIdExisted = Test-Path -LiteralPath $steamAppIdPath -PathType Leaf
    $steamAppIdOriginalBytes = if ($steamAppIdExisted) { [IO.File]::ReadAllBytes($steamAppIdPath) } else { $null }
    $steamAppIdPrepared = $false
    $game = $null

    try {
        $env:SteamAppId = $steamAppId
        $env:SteamGameId = $steamAppId

        [IO.File]::WriteAllText($steamAppIdPath, $steamAppId, [Text.Encoding]::ASCII)
        $steamAppIdPrepared = $true
        Write-LaunchLog 'Prepared the temporary Steam AppID context required by the controlled direct launch.'

        Add-NativeMethods
        $game = Start-Process -FilePath $exePath -WorkingDirectory $Directory -PassThru
        Write-LaunchLog "Detroit started with PID $($game.Id)."
        Start-Sleep -Seconds 2
        $game.Refresh()
        if ($game.HasExited) {
            throw "Detroit exited during startup with code $($game.ExitCode)."
        }
        Write-LaunchLog 'Automatic recovery is restricted to chapter-progress transitions. No automatic reset occurs during gameplay. Manual hotkey: Ctrl+Alt+F11.'
        Watch-GameAndRecoverPresentation -Process $game
        Write-LaunchLog "Detroit exited with code $($game.ExitCode)."
    }
    finally {
        if ($steamAppIdPrepared) {
            if ($steamAppIdExisted) {
                [IO.File]::WriteAllBytes($steamAppIdPath, $steamAppIdOriginalBytes)
                Write-LaunchLog 'Restored the pre-existing steam_appid.txt exactly.'
            }
            elseif (Test-Path -LiteralPath $steamAppIdPath -PathType Leaf) {
                if ([IO.File]::ReadAllText($steamAppIdPath).Trim() -eq $steamAppId) {
                    Remove-Item -LiteralPath $steamAppIdPath -Force
                    Write-LaunchLog 'Removed the temporary steam_appid.txt.'
                }
                else {
                    Write-LaunchLog 'WARNING: steam_appid.txt changed during the session and was left untouched.'
                }
            }
        }
    }
}

$GameDirectory = Resolve-GameDirectory -ExplicitDirectory $GameDirectory
Assert-SafeGameDirectory -Directory $GameDirectory
$exePath = Join-Path $GameDirectory $gameExecutableName

switch ($Action) {
    'Status' {
        Get-StatusObject -Directory $GameDirectory
    }
    'Install' {
        Install-WarningPatch -Directory $GameDirectory
        Get-StatusObject -Directory $GameDirectory
    }
    'Uninstall' {
        Assert-GameStopped
        $integration = Get-SteamIntegrationInfo -Directory $GameDirectory
        if ($integration.State -ne 'NOT_INSTALLED') {
            Remove-SteamIntegration -Directory $GameDirectory
        }
        $currentHash = Get-Sha256 -Path $exePath
        if ($currentHash -eq $patchedSha256) {
            if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf) -or
                (Get-Sha256 -Path $backupPath) -ne $vanillaSha256) {
                throw 'A verified vanilla backup is unavailable. Use Steam Verify integrity of game files.'
            }
            Copy-Item -LiteralPath $backupPath -Destination $exePath -Force
            if ((Get-Sha256 -Path $exePath) -ne $vanillaSha256) {
                throw 'Vanilla restore failed verification.'
            }
        }
        elseif ($currentHash -ne $vanillaSha256) {
            throw "Unsupported or updated executable. Automatic restore was refused: $currentHash"
        }
        Restore-GraphicsValues -Directory $GameDirectory
        Write-Host 'Restored the verified vanilla executable and saved graphics values.' -ForegroundColor Green
        Get-StatusObject -Directory $GameDirectory
    }
    'Launch' {
        Invoke-OptimizedLaunch -Directory $GameDirectory -FromSteamWrapper:$SteamWrapperMode
    }
    'InstallSteamIntegration' {
        Install-SteamIntegration -Directory $GameDirectory
        Get-StatusObject -Directory $GameDirectory
    }
    'RemoveSteamIntegration' {
        Remove-SteamIntegration -Directory $GameDirectory
        Get-StatusObject -Directory $GameDirectory
    }
    'SteamHandoffLaunch' {
        Invoke-SteamHandoffLaunch -Directory $GameDirectory -ParentWrapperProcessId $WrapperProcessId
    }
}
