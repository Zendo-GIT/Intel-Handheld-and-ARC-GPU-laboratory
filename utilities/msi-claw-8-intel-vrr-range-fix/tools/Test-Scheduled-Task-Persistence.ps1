[CmdletBinding()]
param(
    [switch]$RunTaskSchedulerIntegration
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot '..\Scheduled-Task-Persistence.ps1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    $modulePath = Join-Path $PSScriptRoot '..\scripts\Scheduled-Task-Persistence.ps1'
}
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    throw "Scheduled-Task-Persistence.ps1 was not found next to the source or packaged scripts."
}
. $modulePath
$moduleSource = [IO.File]::ReadAllText($modulePath, [Text.Encoding]::UTF8).Replace("`r`n", "`n")

function Assert-Equal {
    param(
        [AllowNull()][object]$Actual,
        [AllowNull()][object]$Expected,
        [Parameter(Mandatory)][string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message Expected '$Expected', got '$Actual'."
    }
}

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-False {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if ($Condition) {
        throw $Message
    }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory)][scriptblock]$Operation,
        [Parameter(Mandatory)][string]$ExpectedMessageFragment,
        [Parameter(Mandatory)][string]$Message
    )

    $thrownMessage = $null
    try {
        & $Operation
    }
    catch {
        $thrownMessage = $_.Exception.Message
    }
    if ([string]::IsNullOrWhiteSpace($thrownMessage)) {
        throw "$Message No exception was raised."
    }
    if ($thrownMessage.IndexOf($ExpectedMessageFragment, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw "$Message Expected an error containing '$ExpectedMessageFragment', got '$thrownMessage'."
    }
}

function Assert-ReasonsContain {
    param(
        [Parameter(Mandatory)][object]$Validation,
        [Parameter(Mandatory)][string]$ExpectedFragment,
        [Parameter(Mandatory)][string]$Message
    )

    $joined = @($Validation.Reasons) -join '; '
    if ($joined.IndexOf($ExpectedFragment, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw "$Message Expected '$ExpectedFragment' in '$joined'."
    }
}

foreach ($limitedLaunchMarker in @(
        'function Start-ClawLabScheduledTask {',
        'Test-ClawLabScheduledTaskRecord',
        '$registeredTask.Run($null)',
        'InteractiveToken +',
        'Limited'
    )) {
    Assert-True -Condition $moduleSource.Contains($limitedLaunchMarker) `
        -Message "The verified limited-user task launch contract is missing: $limitedLaunchMarker"
}

function New-TestTaskRecord {
    param(
        [Parameter(Mandatory)][object]$Spec,
        [hashtable]$Overrides = @{}
    )

    $properties = [ordered]@{
        TaskName = [string]$Spec.TaskName
        TaskPath = "\$($Spec.TaskName)"
        State = 'Ready'
        Enabled = $true
        Description = [string]$Spec.Description
        ActionCount = 1
        ActionType = 0
        ExecutePath = [string]$Spec.ExecutePath
        Arguments = [string]$Spec.Arguments
        TriggerCount = 1
        TriggerType = 9
        TriggerUserId = [string]$Spec.UserSid
        TriggerDelay = [Xml.XmlConvert]::ToString(
            [TimeSpan]::FromSeconds([double]$Spec.TriggerDelaySeconds)
        )
        PrincipalUserId = [string]$Spec.UserSid
        PrincipalLogonType = 3
        PrincipalRunLevel = 0
        StartWhenAvailable = [bool]$Spec.StartWhenAvailable
        AllowStartIfOnBatteries = [bool]$Spec.AllowStartIfOnBatteries
        DontStopIfGoingOnBatteries = [bool]$Spec.DontStopIfGoingOnBatteries
        MultipleInstancesPolicy = [int]$Spec.MultipleInstancesPolicy
        TaskPriority = [int]$Spec.TaskPriority
        ExecutionTimeLimit = [Xml.XmlConvert]::ToString(
            [TimeSpan]::FromSeconds([double]$Spec.ExecutionTimeLimitSeconds)
        )
    }
    foreach ($entry in $Overrides.GetEnumerator()) {
        $properties[[string]$entry.Key] = $entry.Value
    }
    return [pscustomobject]$properties
}

function Invoke-OfflineWaitSequence {
    param(
        [Parameter(Mandatory)][object]$Spec,
        [Parameter(Mandatory)][ValidateSet('Present', 'Absent')][string]$DesiredState,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$Records
    )

    $sequence = [pscustomobject]@{
        Index = 0
        Records = @($Records)
        QueryCount = 0
        Delays = [Collections.Generic.List[int]]::new()
    }
    $query = {
        param($TaskName)
        $sequence.QueryCount = $sequence.QueryCount + 1
        if ($sequence.Index -ge $sequence.Records.Count) {
            return $null
        }
        $record = $sequence.Records[$sequence.Index]
        $sequence.Index = $sequence.Index + 1
        return $record
    }
    $delay = {
        param($Milliseconds)
        [void]$sequence.Delays.Add([int]$Milliseconds)
    }
    $result = Wait-ClawLabScheduledTaskState -Spec $Spec -DesiredState $DesiredState `
        -Query $query -Delay $delay
    return [pscustomobject]@{
        Result = $result
        QueryCount = $sequence.QueryCount
        Delays = @($sequence.Delays)
    }
}

$testUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$testExecutable = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$spec = New-ClawLabLogonTaskSpec `
    -TaskName 'ClawLab Offline Scheduled Task Test' `
    -ExecutePath ('"{0}"' -f $testExecutable) `
    -Arguments '-NoProfile -NonInteractive -Command "exit 0"' `
    -Description 'ClawLab offline scheduled-task semantic test' `
    -ExecutionTimeLimitMinutes 2 `
    -TriggerDelaySeconds 5 `
    -UserSid $testUserSid

Assert-Equal $spec.TaskName 'ClawLab Offline Scheduled Task Test' 'The task name changed.'
Assert-Equal $spec.TaskPath '\' 'The task was not constrained to the Task Scheduler root.'
Assert-Equal $spec.UserSid $testUserSid 'The task user SID changed.'
Assert-True (-not [string]::IsNullOrWhiteSpace([string]$spec.UserAccount)) `
    'The task registration account name was not resolved.'
Assert-Equal (ConvertTo-ClawLabTaskSid -Identity ([string]$spec.UserAccount)) $testUserSid `
    'The task registration account name does not resolve back to the installing SID.'
Assert-True `
    ([string]$spec.ExecutePath).Equals($testExecutable, [StringComparison]::OrdinalIgnoreCase) `
    'The executable path was not normalized correctly.'
Assert-Equal $spec.ExecutionTimeLimitSeconds 120.0 'The execution limit was not converted to seconds.'
Assert-Equal $spec.TriggerDelaySeconds 5.0 'The trigger delay was not converted to seconds.'
Assert-Equal $spec.TaskPriority 7 'The default task priority must remain the Windows background default.'
Assert-True $spec.StartWhenAvailable 'StartWhenAvailable was not enabled.'
Assert-True $spec.AllowStartIfOnBatteries 'Battery start was not enabled.'
Assert-True $spec.DontStopIfGoingOnBatteries 'Battery stop protection was not enabled.'
Assert-Equal $spec.MultipleInstancesPolicy 2 'IgnoreNew was not selected.'

Assert-Throws `
    { New-ClawLabLogonTaskSpec -TaskName 'Folder\Task' -ExecutePath $testExecutable `
        -Arguments 'x' -Description 'x' -ExecutionTimeLimitMinutes 1 -UserSid $testUserSid } `
    'Invalid root Task Scheduler name' 'A nested backslash task name was accepted.'
Assert-Throws `
    { New-ClawLabLogonTaskSpec -TaskName 'Folder/Task' -ExecutePath $testExecutable `
        -Arguments 'x' -Description 'x' -ExecutionTimeLimitMinutes 1 -UserSid $testUserSid } `
    'Invalid root Task Scheduler name' 'A nested slash task name was accepted.'
Assert-Throws `
    { New-ClawLabLogonTaskSpec -TaskName ' ' -ExecutePath $testExecutable `
        -Arguments 'x' -Description 'x' -ExecutionTimeLimitMinutes 1 -UserSid $testUserSid } `
    'Invalid root Task Scheduler name' 'A blank task name was accepted.'
foreach ($invalidLimit in @(-1, 61)) {
    Assert-Throws `
        { New-ClawLabLogonTaskSpec -TaskName 'ClawLab Test' -ExecutePath $testExecutable `
            -Arguments 'x' -Description 'x' -ExecutionTimeLimitMinutes $invalidLimit `
            -UserSid $testUserSid } `
        'zero (unlimited) or between 1 and 60 minutes' "Invalid execution limit $invalidLimit was accepted."
}
$unlimitedSpec = New-ClawLabLogonTaskSpec `
    -TaskName 'ClawLab Unlimited Runtime Test' -ExecutePath $testExecutable `
    -Arguments 'x' -Description 'x' -ExecutionTimeLimitMinutes 0 `
    -UserSid $testUserSid
Assert-Equal $unlimitedSpec.ExecutionTimeLimitSeconds 0.0 `
    'An unlimited long-running helper task did not map to the scheduler PT0S policy.'
foreach ($invalidDelay in @(-1, 301)) {
    Assert-Throws `
        { New-ClawLabLogonTaskSpec -TaskName 'ClawLab Test' -ExecutePath $testExecutable `
            -Arguments 'x' -Description 'x' -ExecutionTimeLimitMinutes 1 `
            -TriggerDelaySeconds $invalidDelay -UserSid $testUserSid } `
        'between 0 and 300 seconds' "Invalid trigger delay $invalidDelay was accepted."
}
Assert-Throws `
    { ConvertTo-ClawLabTaskDurationSeconds -Duration 'not-an-iso-duration' } `
    'invalid ISO-8601 duration' 'An invalid scheduler duration was accepted.'

$validRecord = New-TestTaskRecord -Spec $spec
$validResult = Test-ClawLabScheduledTaskRecord -Record $validRecord -Spec $spec
Assert-True $validResult.Valid 'A record matching the complete task specification was rejected.'
Assert-Equal @($validResult.Reasons).Count 0 'A valid record produced validation reasons.'
Assert-True `
    (Test-ClawLabScheduledTaskOwned -Record $validRecord -Spec $spec) `
    'A matching ClawLab task was not recognized as owned.'

$accountNameReadback = New-TestTaskRecord -Spec $spec -Overrides @{
    TriggerUserId = [string]$spec.UserAccount
    PrincipalUserId = [string]$spec.UserAccount
}
$accountNameReadbackResult = Test-ClawLabScheduledTaskRecord `
    -Record $accountNameReadback -Spec $spec
Assert-True $accountNameReadbackResult.Valid `
    'A Task Scheduler readback using the equivalent NT account name was rejected.'

foreach ($registrationMarker in @(
        'ConvertTo-ClawLabTaskAccountName',
        '$registrationIdentity',
        'New-ScheduledTaskTrigger -AtLogOn -User $registrationIdentity',
        'New-ScheduledTaskPrincipal -UserId $registrationIdentity'
    )) {
    Assert-True -Condition $moduleSource.Contains($registrationMarker) `
        -Message "The portable Task Scheduler registration contract is missing: $registrationMarker"
}

$semanticallyInvalidRecord = New-TestTaskRecord -Spec $spec -Overrides @{
    TaskPath = '\Unexpected Task'
    Description = 'Foreign description'
    Enabled = $false
    TriggerType = 8
    PrincipalLogonType = 1
    PrincipalRunLevel = 1
    StartWhenAvailable = $false
    AllowStartIfOnBatteries = $false
    DontStopIfGoingOnBatteries = $false
    MultipleInstancesPolicy = 0
    TaskPriority = 2
    ExecutionTimeLimit = 'PT3M'
}
$invalidResult = Test-ClawLabScheduledTaskRecord -Record $semanticallyInvalidRecord -Spec $spec
Assert-False $invalidResult.Valid 'A semantically different task record was accepted.'
foreach ($reason in @(
    'unexpected task path',
    'unexpected task description',
    'task is disabled',
    'exactly one logon trigger',
    'principal is not InteractiveToken',
    'principal is not Limited/LUA',
    'StartWhenAvailable differs',
    'battery-start policy differs',
    'battery-stop policy differs',
    'multiple-instance policy differs',
    'task priority differs',
    'execution limit differs'
)) {
    Assert-ReasonsContain $invalidResult $reason "The invalid task record did not report '$reason'."
}
Assert-False `
    (Test-ClawLabScheduledTaskOwned -Record $semanticallyInvalidRecord -Spec $spec) `
    'A task outside the exact path/trigger ownership boundary was treated as ClawLab-owned.'

$repairableOwnedRecord = New-TestTaskRecord -Spec $spec -Overrides @{
    Description = 'Old ClawLab description'
    Enabled = $false
    PrincipalLogonType = 1
    PrincipalRunLevel = 1
    StartWhenAvailable = $false
    ExecutionTimeLimit = 'PT3M'
}
Assert-True `
    (Test-ClawLabScheduledTaskOwned -Record $repairableOwnedRecord -Spec $spec) `
    'A same-SID ClawLab task with repairable settings drift was treated as foreign.'

$foreignSid = 'S-1-5-21-111111111-222222222-333333333-1001'
foreach ($sidField in @('PrincipalUserId', 'TriggerUserId')) {
    $foreignSidRecord = New-TestTaskRecord -Spec $spec -Overrides @{ $sidField = $foreignSid }
    Assert-False `
        (Test-ClawLabScheduledTaskOwned -Record $foreignSidRecord -Spec $spec) `
        "A task owned by another Windows SID through $sidField was treated as ClawLab-owned."
}

$foreignActionRecord = New-TestTaskRecord -Spec $spec -Overrides @{
    ExecutePath = (Join-Path $env:SystemRoot 'System32\cmd.exe')
    Arguments = '/c exit 0'
}
Assert-False `
    (Test-ClawLabScheduledTaskOwned -Record $foreignActionRecord -Spec $spec) `
    'A task with a foreign action was incorrectly treated as ClawLab-owned.'
Assert-False `
    (Test-ClawLabScheduledTaskOwned `
        -Record (New-TestTaskRecord -Spec $spec -Overrides @{ ActionCount = 2 }) -Spec $spec) `
    'A task with multiple actions was incorrectly treated as ClawLab-owned.'
Assert-False `
    (Test-ClawLabScheduledTaskOwned `
        -Record (New-TestTaskRecord -Spec $spec -Overrides @{ Arguments = '-Foreign' }) -Spec $spec) `
    'A task with foreign arguments was incorrectly treated as ClawLab-owned.'

$presentSequence = Invoke-OfflineWaitSequence -Spec $spec -DesiredState Present `
    -Records @($null, $null, $validRecord)
Assert-Equal $presentSequence.Result.State 'PRESENT_VALID' 'Present polling did not accept the delayed valid record.'
Assert-Equal $presentSequence.QueryCount 3 'Present polling made an unexpected number of queries.'
Assert-Equal ($presentSequence.Delays -join ',') '100,200' 'Present polling used unexpected delays.'

$invalidPresentSequence = Invoke-OfflineWaitSequence -Spec $spec -DesiredState Present `
    -Records @($semanticallyInvalidRecord)
Assert-Equal $invalidPresentSequence.Result.State 'PRESENT_INVALID' `
    'Present polling did not stop on a semantically invalid task.'
Assert-Equal $invalidPresentSequence.QueryCount 1 'Invalid-task polling did not fail immediately.'

$absentSequence = Invoke-OfflineWaitSequence -Spec $spec -DesiredState Absent `
    -Records @($validRecord, $validRecord, $null)
Assert-Equal $absentSequence.Result.State 'ABSENT' 'Absent polling did not accept delayed disappearance.'
Assert-Equal $absentSequence.QueryCount 3 'Absent polling made an unexpected number of queries.'
Assert-Equal ($absentSequence.Delays -join ',') '100,200' 'Absent polling used unexpected delays.'

$presentTimeout = Invoke-OfflineWaitSequence -Spec $spec -DesiredState Present `
    -Records @($null, $null, $null, $null, $null, $null, $null, $null, $null)
Assert-Equal $presentTimeout.Result.State 'ABSENT_TIMEOUT' 'Present polling did not time out while absent.'
Assert-Equal $presentTimeout.QueryCount 9 'Present timeout did not exhaust the bounded query sequence.'
Assert-Equal ($presentTimeout.Delays -join ',') '100,200,400,800,1000,1000,1000,500' `
    'Present timeout used an unexpected bounded delay sequence.'

$absentTimeout = Invoke-OfflineWaitSequence -Spec $spec -DesiredState Absent `
    -Records @(
        $validRecord, $validRecord, $validRecord, $validRecord, $validRecord,
        $validRecord, $validRecord, $validRecord, $validRecord
    )
Assert-Equal $absentTimeout.Result.State 'PRESENT_TIMEOUT' 'Absent polling did not time out while present.'
Assert-Equal $absentTimeout.QueryCount 9 'Absent timeout did not exhaust the bounded query sequence.'
Assert-True ($null -ne $absentTimeout.Result.Record) 'Absent timeout discarded the last observed record.'

# The Task Scheduler records only the exit status returned by wscript.exe. The
# invisible VBS launcher must therefore wait for its PowerShell child and
# propagate that exact child status instead of silently returning success.
$projectRoot = Split-Path $PSScriptRoot -Parent
$lfcLauncherPath = Join-Path $projectRoot 'ClawLab-LFC-Startup.vbs'
if (-not (Test-Path -LiteralPath $lfcLauncherPath -PathType Leaf)) {
    $lfcLauncherPath = Join-Path $projectRoot 'scripts\ClawLab-LFC-Startup.vbs'
}
if (-not (Test-Path -LiteralPath $lfcLauncherPath -PathType Leaf)) {
    throw 'ClawLab-LFC-Startup.vbs was not found next to the source or packaged scripts.'
}
$lfcLauncher = [IO.File]::ReadAllText($lfcLauncherPath).Replace("`r`n", "`n")
foreach ($requiredLauncherMarker in @(
        'Dim exitCode',
        'exitCode = shell.Run(command, 0, True)',
        'WScript.Quit exitCode'
    )) {
    Assert-True -Condition ($lfcLauncher.Contains($requiredLauncherMarker)) `
        -Message "The LFC launcher does not propagate its child exit status: $requiredLauncherMarker"
}

$launcherProbeRoot = Join-Path ([IO.Path]::GetTempPath()) `
    ('ClawLab-VbsExitProbe-{0}' -f [Guid]::NewGuid().ToString('N'))
$launcherProbeChild = Join-Path $launcherProbeRoot 'child-exit-37.ps1'
$launcherProbeVbs = Join-Path $launcherProbeRoot 'probe.vbs'
try {
    [IO.Directory]::CreateDirectory($launcherProbeRoot) | Out-Null
    [IO.File]::WriteAllText(
        $launcherProbeChild,
        "exit 37`r`n",
        [Text.UTF8Encoding]::new($false)
    )
    $probeSource = @'
Option Explicit
Dim shell
Dim powerShellPath
Dim command
Dim exitCode
Set shell = CreateObject("WScript.Shell")
powerShellPath = shell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")
command = Chr(34) & powerShellPath & Chr(34) & " -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " & Chr(34) & "__CHILD_PATH__" & Chr(34)
exitCode = shell.Run(command, 0, True)
WScript.Quit exitCode
'@
    $probeSource = $probeSource.Replace('__CHILD_PATH__', $launcherProbeChild)
    [IO.File]::WriteAllText($launcherProbeVbs, $probeSource, [Text.UTF8Encoding]::new($false))
    $wscriptPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
    $probeProcess = Start-Process -FilePath $wscriptPath `
        -ArgumentList @('//B', '//Nologo', ('"{0}"' -f $launcherProbeVbs)) `
        -Wait -PassThru
    $probeExitCode = $probeProcess.ExitCode
    Assert-Equal $probeExitCode 37 `
        'The invisible VBS launcher did not return its PowerShell child exit status.'
}
finally {
    foreach ($probeFile in @($launcherProbeChild, $launcherProbeVbs)) {
        if (Test-Path -LiteralPath $probeFile -PathType Leaf) {
            [IO.File]::Delete($probeFile)
        }
    }
    if (Test-Path -LiteralPath $launcherProbeRoot -PathType Container) {
        [IO.Directory]::Delete($launcherProbeRoot, $false)
    }
}

$integrationResult = 'NOT_REQUESTED'
if ($RunTaskSchedulerIntegration) {
    $integrationTaskName = 'ClawLab Manual Persistence Test {0}' -f ([Guid]::NewGuid().ToString('N'))
    $integrationSpec = New-ClawLabLogonTaskSpec `
        -TaskName $integrationTaskName `
        -ExecutePath $testExecutable `
        -Arguments '-NoProfile -NonInteractive -Command "exit 0"' `
        -Description 'Temporary ClawLab manual Task Scheduler integration test' `
        -ExecutionTimeLimitMinutes 1 `
        -TriggerDelaySeconds 1 `
        -UserSid $testUserSid
    try {
        $installed = Install-ClawLabScheduledTask -Spec $integrationSpec
        if (-not $installed.Installed) {
            throw 'The unique manual integration task was unexpectedly reused.'
        }
        $record = Get-ClawLabScheduledTaskRecord -TaskName $integrationTaskName
        $validation = Test-ClawLabScheduledTaskRecord -Record $record -Spec $integrationSpec
        if (-not $validation.Valid) {
            throw "The manually registered task failed semantic validation: $($validation.Reasons -join '; ')"
        }
        $integrationResult = 'PASS'
    }
    finally {
        $recordToRemove = Get-ClawLabScheduledTaskRecord -TaskName $integrationTaskName
        if ($null -ne $recordToRemove) {
            [void](Remove-ClawLabScheduledTask -Spec $integrationSpec)
        }
    }
}

[pscustomobject]@{
    Result = 'PASS'
    SchedulerMutated = [bool]$RunTaskSchedulerIntegration
    ManualIntegration = $integrationResult
    SpecValidation = 'PASS'
    InvalidSpecGuards = 'PASS'
    SemanticValidation = 'PASS'
    OwnershipCollisionGuard = 'PASS'
    PollingSequences = 'PASS'
    PollingTimeouts = 'PASS'
    LauncherExitPropagation = 'PASS'
}
