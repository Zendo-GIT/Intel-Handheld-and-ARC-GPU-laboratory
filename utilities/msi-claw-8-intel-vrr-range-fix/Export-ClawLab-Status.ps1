[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$packageRoot = $PSScriptRoot
$vrrTool = Join-Path $packageRoot 'MSI-Claw-VRR-Fix.ps1'
$lfcTool = Join-Path $packageRoot 'MSI-Claw-Intel-LFC-Fix.ps1'
$healthTool = Join-Path $packageRoot 'ClawLab-Health-Check.ps1'
$vrrStateRoot = Join-Path $env:LOCALAPPDATA 'ClawLab\Intel-Arc-Sync-Full-Range'
$lfcStateRoot = Join-Path $env:LOCALAPPDATA 'ClawLab\Intel-LFC-Fix'

function Invoke-ReadOnlyReport {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Operation,
        [switch]$AllowEmpty
    )
    try {
        $data = @(& $Operation)
        $operationSucceeded = $?
        if (-not $operationSucceeded) {
            throw "$Name query returned a failure exit code."
        }
        if (-not $AllowEmpty -and ($data.Count -ne 1 -or $null -eq $data[0])) {
            throw "$Name query did not return exactly one valid object."
        }
        $value = if ($data.Count -eq 1) { $data[0] } else { $data }
        return [pscustomobject]@{ Success = $true; Data = $value; Error = $null }
    }
    catch {
        return [pscustomobject]@{ Success = $false; Data = $null; Error = $_.Exception.Message }
    }
}

function Get-TaskReport {
    param([Parameter(Mandatory)][string]$Name)
    $task = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
    if ($null -eq $task) { return [pscustomobject]@{ Installed = $false } }
    $info = Get-ScheduledTaskInfo -TaskName $Name -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Installed = $true
        State = [string]$task.State
        LastRunTime = if ($null -ne $info) { $info.LastRunTime } else { $null }
        LastTaskResult = if ($null -ne $info) { $info.LastTaskResult } else { $null }
        NextRunTime = if ($null -ne $info) { $info.NextRunTime } else { $null }
    }
}

function Get-LfcBackupMetadata {
    $path = Join-Path $lfcStateRoot 'original-intel-vrr-solutions.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [pscustomobject]@{ Present = $false }
    }
    try {
        $record = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $value = { param($name) if ($name -in $record.PSObject.Properties.Name) { $record.$name } else { $null } }
        return [pscustomobject]@{
            Present = $true
            SchemaVersion = & $value 'SchemaVersion'
            SavedAt = & $value 'SavedAt'
            ManagedVrrMode = & $value 'ManagedVrrMode'
            PanelManufacturer = & $value 'PanelManufacturer'
            PanelProductCode = & $value 'PanelProductCode'
            PanelName = & $value 'PanelName'
            PhysicalEdidSha256 = & $value 'PhysicalEdidSha256'
            PanelInstanceNameAtSave = & $value 'PanelInstanceNameAtSave'
            LastValidatedPanelInstanceName = & $value 'LastValidatedPanelInstanceName'
            PanelEdidSha256AtSave = & $value 'PanelEdidSha256AtSave'
            InstanceMigrationCount = & $value 'InstanceMigrationCount'
            LastInstanceMigrationAt = & $value 'LastInstanceMigrationAt'
            IntelDriverVersionAtSave = & $value 'IntelDriverVersion'
        }
    }
    catch {
        return [pscustomobject]@{ Present = $true; ReadError = $_.Exception.Message }
    }
}

$health = Invoke-ReadOnlyReport -Name 'Health' -Operation { & $healthTool }
$vrr = Invoke-ReadOnlyReport -Name 'VRR' -Operation { & $vrrTool -Action Status }
$lfc = Invoke-ReadOnlyReport -Name 'Intel LFC' -Operation { & $lfcTool -Action Status }
$report = [ordered]@{
    SchemaVersion = 1
    CollectedAt = (Get-Date).ToString('o')
    ReadOnlyCollection = $true
    Health = $health
    VRR = $vrr
    LFC = $lfc
    Tasks = [ordered]@{
        VrrRange = Get-TaskReport -Name 'ClawLab MSI Claw 8 VRR Range'
        IntelLfc = Get-TaskReport -Name 'ClawLab MSI Claw Intel LFC Fix'
    }
    LfcBackupMetadata = Get-LfcBackupMetadata
    StartupLastRun = Invoke-ReadOnlyReport -Name 'Startup last run' -AllowEmpty -Operation {
        $path = Join-Path $vrrStateRoot 'startup-last-run.json'
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json
        }
        else { $null }
    }
    LastVrrError = Invoke-ReadOnlyReport -Name 'Last VRR error' -AllowEmpty -Operation {
        $path = Join-Path $vrrStateRoot 'last-error.txt'
        if (Test-Path -LiteralPath $path -PathType Leaf) { [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) } else { $null }
    }
}

$desktop = [Environment]::GetFolderPath('Desktop')
if ([string]::IsNullOrWhiteSpace($desktop) -or -not (Test-Path -LiteralPath $desktop -PathType Container)) {
    $desktop = [Environment]::GetFolderPath('MyDocuments')
}
$outputPath = Join-Path $desktop ('ClawLab-Status-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
[IO.File]::WriteAllText($outputPath, ($report | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))

Write-Host 'ClawLab status was collected without changing the display configuration.' -ForegroundColor Green
Write-Host "Share this file: $outputPath" -ForegroundColor Cyan
[pscustomobject]@{ Result = 'PASS'; Output = $outputPath }
