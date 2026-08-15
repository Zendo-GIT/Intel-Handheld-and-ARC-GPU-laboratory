[CmdletBinding()]
param(
    [string]$PackageDirectory = $PSScriptRoot,
    [string]$OutputRoot = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'ClawLab-VRR-Diagnostics')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-FileRecord {
    param([Parameter(Mandatory)][string]$LiteralPath)

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        return [pscustomobject]@{ Exists = $false; Path = $LiteralPath }
    }
    $item = Get-Item -LiteralPath $LiteralPath
    return [pscustomobject]@{
        Exists = $true
        Path = $item.FullName
        Length = $item.Length
        Version = [string]$item.VersionInfo.FileVersion
        Sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
    }
}

function Get-OptionalJsonRecord {
    param([Parameter(Mandatory)][string]$LiteralPath)

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        return [pscustomobject]@{ Exists = $false; Path = $LiteralPath; JsonValid = $null; Content = $null }
    }
    $raw = [IO.File]::ReadAllText($LiteralPath, [Text.Encoding]::UTF8)
    $valid = $true
    try { [void]($raw | ConvertFrom-Json) } catch { $valid = $false }
    return [pscustomobject]@{
        Exists = $true
        Path = $LiteralPath
        JsonValid = $valid
        Content = $raw
    }
}

function Get-RegistryValueRecord {
    param(
        [Parameter(Mandatory)][string]$RegistryPath,
        [Parameter(Mandatory)][string]$ValueName
    )

    try {
        $key = Get-Item -LiteralPath $RegistryPath -ErrorAction Stop
        if ($ValueName -notin @($key.GetValueNames())) {
            return [pscustomobject]@{ Present = $false; Value = $null }
        }
        return [pscustomobject]@{
            Present = $true
            Value = [string]$key.GetValue($ValueName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        }
    }
    catch {
        return [pscustomobject]@{ Present = $false; Value = $null; ReadError = $_.Exception.Message }
    }
}

function Get-TaskRecord {
    param([Parameter(Mandatory)][string]$TaskName)

    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        return [pscustomobject]@{
            Present = $true
            Name = $TaskName
            State = [string]$task.State
            Actions = @($task.Actions | ForEach-Object {
                [pscustomobject]@{ Execute = [string]$_.Execute; Arguments = [string]$_.Arguments }
            })
            LogonType = [string]$task.Principal.LogonType
            RunLevel = [string]$task.Principal.RunLevel
        }
    }
    catch [Microsoft.Management.Infrastructure.CimException] {
        return [pscustomobject]@{ Present = $false; Name = $TaskName }
    }
    catch {
        return [pscustomobject]@{ Present = $false; Name = $TaskName; ReadError = $_.Exception.Message }
    }
}

function Invoke-ReadOnlyStatus {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][string]$Action
    )

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        return [pscustomobject]@{ Available = $false; ExitCode = $null; Output = $null }
    }
    $output = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -Action $Action 2>&1 | Out-String
    return [pscustomobject]@{ Available = $true; ExitCode = $LASTEXITCODE; Output = $output.TrimEnd() }
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outputDirectory = Join-Path ([IO.Path]::GetFullPath($OutputRoot)) $timestamp
[IO.Directory]::CreateDirectory($outputDirectory) | Out-Null

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$computer = Get-CimInstance Win32_ComputerSystem
$operatingSystem = Get-CimInstance Win32_OperatingSystem
$bios = Get-CimInstance Win32_BIOS
$intelGpus = @(Get-CimInstance Win32_VideoController | Where-Object { $_.PNPDeviceID -like 'PCI\VEN_8086&*' })

$intelGraphicsPath = Join-Path $env:ProgramFiles 'Intel\Intel Graphics Software\IntelGraphicsSoftware.exe'
$intelGraphicsFile = Get-FileRecord -LiteralPath $intelGraphicsPath
$intelSignature = $null
if ($intelGraphicsFile.Exists) {
    $signature = Get-AuthenticodeSignature -LiteralPath $intelGraphicsPath
    $intelSignature = [pscustomobject]@{
        Status = [string]$signature.Status
        StatusMessage = [string]$signature.StatusMessage
        Subject = if ($null -eq $signature.SignerCertificate) { $null } else { [string]$signature.SignerCertificate.Subject }
        Thumbprint = if ($null -eq $signature.SignerCertificate) { $null } else { [string]$signature.SignerCertificate.Thumbprint }
    }
}

$intelStartupRegistryPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
$intelStartupValueName = 'Intel' + [char]0x00AE + ' Graphics Software'
$intelStartup = Get-RegistryValueRecord -RegistryPath $intelStartupRegistryPath -ValueName $intelStartupValueName

$stateRoot = Join-Path $env:LOCALAPPDATA 'ClawLab\Intel-Arc-Sync-Full-Range'
$lfcStateRoot = Join-Path $env:LOCALAPPDATA 'ClawLab\Intel-LFC-Fix'
$stateFiles = @(
    Get-OptionalJsonRecord -LiteralPath (Join-Path $stateRoot 'original-profile.json')
    Get-OptionalJsonRecord -LiteralPath (Join-Path $stateRoot 'experimental-edid.json')
    Get-OptionalJsonRecord -LiteralPath (Join-Path $stateRoot 'managed-mode.json')
    Get-OptionalJsonRecord -LiteralPath (Join-Path $stateRoot 'intel-graphics-startup.json')
    Get-OptionalJsonRecord -LiteralPath (Join-Path $stateRoot 'startup-last-run.json')
    Get-OptionalJsonRecord -LiteralPath (Join-Path $lfcStateRoot 'original-intel-vrr-solutions.json')
)

$packagePath = [IO.Path]::GetFullPath($PackageDirectory)
$packageFiles = @(
    'MSI-Claw-VRR-Fix.ps1',
    'MSI-Claw-Intel-LFC-Fix.ps1',
    'Intel-VRR-LFC-Driver-Interface.ps1',
    'ClawLab-VRR-Startup.vbs',
    'ClawLab-LFC-Startup.vbs',
    'INSTALL_30_120_VRR.bat',
    'INSTALL_48_120_VRR.bat',
    'RESTORE_ORIGINAL_VRR.bat'
) | ForEach-Object { Get-FileRecord -LiteralPath (Join-Path $packagePath $_) }

$uacPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
$uac = Get-ItemProperty -LiteralPath $uacPath -ErrorAction SilentlyContinue
$taskService = Get-Service -Name Schedule -ErrorAction SilentlyContinue

$report = [ordered]@{
    SchemaVersion = 1
    CollectorVersion = '1.0.1'
    CollectedAt = (Get-Date).ToString('o')
    ReadOnlyCollection = $true
    UserContext = [ordered]@{
        IsAdministrator = $isAdministrator
        IsSystem = $identity.IsSystem
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        LanguageMode = [string]$ExecutionContext.SessionState.LanguageMode
        ExecutionPolicies = @(Get-ExecutionPolicy -List | ForEach-Object {
            [pscustomobject]@{ Scope = [string]$_.Scope; Policy = [string]$_.ExecutionPolicy }
        })
    }
    Computer = [ordered]@{
        Manufacturer = [string]$computer.Manufacturer
        Model = [string]$computer.Model
        BiosVersion = @($bios.BIOSVersion)
        WindowsCaption = [string]$operatingSystem.Caption
        WindowsVersion = [string]$operatingSystem.Version
        WindowsBuild = [string]$operatingSystem.BuildNumber
        Culture = [Globalization.CultureInfo]::CurrentCulture.Name
        UiCulture = [Globalization.CultureInfo]::CurrentUICulture.Name
    }
    IntelGpus = @($intelGpus | ForEach-Object {
        [pscustomobject]@{
            Name = [string]$_.Name
            DriverVersion = [string]$_.DriverVersion
            PnpDeviceId = [string]$_.PNPDeviceID
        }
    })
    IntelGraphicsSoftware = [ordered]@{
        CanonicalFile = $intelGraphicsFile
        Signature = $intelSignature
        StartupEntry = $intelStartup
        Running = $null -ne (Get-Process -Name IntelGraphicsSoftware -ErrorAction SilentlyContinue)
    }
    TaskScheduler = [ordered]@{
        ServiceStatus = if ($null -eq $taskService) { 'NOT_FOUND' } else { [string]$taskService.Status }
        Tasks = @(
            Get-TaskRecord -TaskName 'ClawLab MSI Claw 8 VRR Range'
            Get-TaskRecord -TaskName 'ClawLab MSI Claw Intel LFC Fix'
            Get-TaskRecord -TaskName 'ClawLab MSI Claw 144 Hz Trial Confirmation'
        )
    }
    Uac = [ordered]@{
        EnableLUA = if ($null -eq $uac) { $null } else { $uac.EnableLUA }
        ConsentPromptBehaviorAdmin = if ($null -eq $uac) { $null } else { $uac.ConsentPromptBehaviorAdmin }
        PromptOnSecureDesktop = if ($null -eq $uac) { $null } else { $uac.PromptOnSecureDesktop }
    }
    ClawLabStateDirectories = [ordered]@{
        VrrExists = Test-Path -LiteralPath $stateRoot -PathType Container
        LfcExists = Test-Path -LiteralPath $lfcStateRoot -PathType Container
        Files = $stateFiles
    }
    PackageDirectory = $packagePath
    PackageFiles = $packageFiles
    VrrStatus = Invoke-ReadOnlyStatus -ScriptPath (Join-Path $packagePath 'MSI-Claw-VRR-Fix.ps1') -Action Status
    LfcStatus = Invoke-ReadOnlyStatus -ScriptPath (Join-Path $packagePath 'MSI-Claw-Intel-LFC-Fix.ps1') -Action Status
}

$reportPath = Join-Path $outputDirectory 'ClawLab-VRR-install-diagnostics.json'
[IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))

$summary = @(
    'ClawLab VRR install diagnostics'
    "Collected: $($report.CollectedAt)"
    'Read-only: True'
    "Model: $($report.Computer.Manufacturer) $($report.Computer.Model)"
    "Windows: $($report.Computer.WindowsCaption) $($report.Computer.WindowsVersion)"
    "Administrator: $($report.UserContext.IsAdministrator)"
    "Intel Graphics Software canonical file: $($intelGraphicsFile.Exists)"
    "Intel Graphics Software signature: $(if ($null -eq $intelSignature) { 'NOT_AVAILABLE' } else { $intelSignature.Status })"
    "Intel Graphics Software Run entry: $($intelStartup.Present)"
    "VRR state directory: $(Test-Path -LiteralPath $stateRoot -PathType Container)"
    "LFC state directory: $(Test-Path -LiteralPath $lfcStateRoot -PathType Container)"
    "Package directory: $packagePath"
    'See the JSON file for exact read-only details.'
)
[IO.File]::WriteAllLines((Join-Path $outputDirectory 'SUMMARY.txt'), $summary, [Text.UTF8Encoding]::new($false))

$zipPath = "$outputDirectory.zip"
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($outputDirectory, $zipPath, [IO.Compression.CompressionLevel]::Optimal, $false)

Write-Host 'ClawLab VRR diagnostics collected without changing the display, driver, registry or tasks.' -ForegroundColor Green
Write-Host "Share this ZIP privately: $zipPath" -ForegroundColor Cyan
Write-Host 'Review the JSON before public sharing; it contains hardware and local path information.' -ForegroundColor Yellow
