[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$packageRoot = $PSScriptRoot
$vrrTool = Join-Path $packageRoot 'MSI-Claw-VRR-Fix.ps1'
$lfcTool = Join-Path $packageRoot 'MSI-Claw-Intel-LFC-Fix.ps1'
$healthTool = Join-Path $packageRoot 'ClawLab-Health-Check.ps1'
$scheduledTaskTool = Join-Path $packageRoot 'Scheduled-Task-Persistence.ps1'
if (-not (Test-Path -LiteralPath $scheduledTaskTool -PathType Leaf)) {
    throw "Required task-query component is missing: $scheduledTaskTool"
}
. $scheduledTaskTool
$vrrStateRoot = Join-Path $env:LOCALAPPDATA 'ClawLab\Intel-Arc-Sync-Full-Range'
$lfcStateRoot = Join-Path $env:LOCALAPPDATA 'ClawLab\Intel-LFC-Fix'
$transactionStateRoot = Join-Path $env:LOCALAPPDATA 'ClawLab\VRR-Transaction'

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

function Get-ClawLabTaskRuntimeRecord {
    param([Parameter(Mandatory)][string]$Name)

    $service = $null
    $folder = $null
    $registeredTask = $null
    try {
        $service = New-Object -ComObject 'Schedule.Service'
        $service.Connect()
        $folder = $service.GetFolder('\')
        try {
            $registeredTask = $folder.GetTask($Name)
        }
        catch {
            $hresult = [BitConverter]::ToUInt32(
                [BitConverter]::GetBytes([int32]$_.Exception.HResult),
                0
            )
            if ($hresult -in @(
                [Convert]::ToUInt32('80070002', 16),
                [Convert]::ToUInt32('8004130F', 16)
            )) {
                return $null
            }
            throw ('Task Scheduler runtime query failed for "{0}" with HRESULT 0x{1:X8}: {2}' -f
                $Name, $hresult, $_.Exception.Message)
        }

        return [pscustomobject]@{
            LastRunTime = [datetime]$registeredTask.LastRunTime
            LastTaskResult = [int]$registeredTask.LastTaskResult
            NextRunTime = [datetime]$registeredTask.NextRunTime
        }
    }
    finally {
        foreach ($comObject in @($registeredTask, $folder, $service)) {
            if ($null -ne $comObject -and [Runtime.InteropServices.Marshal]::IsComObject($comObject)) {
                [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($comObject)
            }
        }
    }
}

function Get-TaskReport {
    param([Parameter(Mandatory)][string]$Name)

    try {
        $task = Get-ClawLabScheduledTaskRecord -TaskName $Name
        if ($null -eq $task) {
            return [pscustomobject]@{
                QueryState = 'ABSENT'
                Installed = $false
                State = $null
                LastRunTime = $null
                LastTaskResult = $null
                NextRunTime = $null
                Error = $null
            }
        }

        $runtime = Get-ClawLabTaskRuntimeRecord -Name $Name
        if ($null -eq $runtime) {
            throw "The task disappeared while its diagnostic state was being collected: $Name"
        }
        return [pscustomobject]@{
            QueryState = 'PRESENT'
            Installed = $true
            State = [string]$task.State
            Enabled = [bool]$task.Enabled
            LastRunTime = $runtime.LastRunTime
            LastTaskResult = $runtime.LastTaskResult
            NextRunTime = $runtime.NextRunTime
            Error = $null
        }
    }
    catch {
        return [pscustomobject]@{
            QueryState = 'TASK_QUERY_ERROR'
            Installed = $null
            State = $null
            LastRunTime = $null
            LastTaskResult = $null
            NextRunTime = $null
            Error = $_.Exception.Message
        }
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
        CursorRefresh = Get-TaskReport -Name 'ClawLab MSI Claw Cursor Refresh Engine'
        IntelLfc = Get-TaskReport -Name 'ClawLab MSI Claw Intel LFC Fix'
    }
    CursorRefreshRuntime = Invoke-ReadOnlyReport -Name 'Cursor Refresh runtime' -AllowEmpty -Operation {
        $path = Join-Path $env:LOCALAPPDATA 'ClawLab\Cursor-Refresh-Helper\runtime-state.txt'
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
        }
        else { $null }
    }
    LfcBackupMetadata = Get-LfcBackupMetadata
    RecoveryArtifacts = [ordered]@{
        NormalizationCompensationPresent = Test-Path -LiteralPath `
            (Join-Path $vrrStateRoot 'normalization-compensation.json') -PathType Leaf
        LfcRestoreCommittedPresent = Test-Path -LiteralPath `
            (Join-Path $lfcStateRoot 'restore-committed.json') -PathType Leaf
        LfcRestoreFinalizedPresent = Test-Path -LiteralPath `
            (Join-Path $lfcStateRoot 'restore-finalized.json') -PathType Leaf
        LfcFactoryIntentPresent = Test-Path -LiteralPath `
            (Join-Path $lfcStateRoot 'factory-default-intent.json') -PathType Leaf
        LfcFactoryFinalizedPresent = Test-Path -LiteralPath `
            (Join-Path $lfcStateRoot 'factory-finalized.json') -PathType Leaf
        TransactionJournalPresent = Test-Path -LiteralPath `
            (Join-Path $transactionStateRoot 'transaction.json') -PathType Leaf
    }
    TransactionJournal = Invoke-ReadOnlyReport -Name 'VRR transaction journal' -AllowEmpty -Operation {
        $path = Join-Path $transactionStateRoot 'transaction.json'
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json
        }
        else { $null }
    }
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
    LastExperimentalConfirmationError = Invoke-ReadOnlyReport -Name 'Last experimental confirmation error' -AllowEmpty -Operation {
        $path = Join-Path $vrrStateRoot 'experimental-confirmation-last-error.txt'
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
