Set-StrictMode -Version Latest

function ConvertTo-ClawLabHResultUInt32 {
    param([Parameter(Mandatory)][int]$HResult)

    return [BitConverter]::ToUInt32([BitConverter]::GetBytes([int32]$HResult), 0)
}

function ConvertTo-ClawLabTaskSid {
    param([Parameter(Mandatory)][string]$Identity)

    if ($Identity -match '^S-\d-(?:\d+-){1,14}\d+$') {
        return ([Security.Principal.SecurityIdentifier]::new($Identity)).Value
    }
    try {
        return ([Security.Principal.NTAccount]::new($Identity)).Translate(
            [Security.Principal.SecurityIdentifier]
        ).Value
    }
    catch {
        throw "Task Scheduler returned an identity that could not be resolved to a SID: $Identity"
    }
}

function ConvertTo-ClawLabTaskAccountName {
    param([Parameter(Mandatory)][string]$Identity)

    try {
        if ($Identity -match '^S-\d-(?:\d+-){1,14}\d+$') {
            return ([Security.Principal.SecurityIdentifier]::new($Identity)).Translate(
                [Security.Principal.NTAccount]
            ).Value
        }
        $account = [Security.Principal.NTAccount]::new($Identity)
        [void]$account.Translate([Security.Principal.SecurityIdentifier])
        return $account.Value
    }
    catch {
        throw "The interactive task identity could not be resolved to a Windows account name: $Identity"
    }
}

function ConvertTo-ClawLabTaskPath {
    param([Parameter(Mandatory)][string]$LiteralPath)

    $expanded = [Environment]::ExpandEnvironmentVariables($LiteralPath.Trim().Trim('"'))
    return [IO.Path]::GetFullPath($expanded)
}

function ConvertTo-ClawLabTaskDurationSeconds {
    param([AllowEmptyString()][string]$Duration)

    if ([string]::IsNullOrWhiteSpace($Duration)) {
        return 0.0
    }
    try {
        return [Xml.XmlConvert]::ToTimeSpan($Duration).TotalSeconds
    }
    catch {
        throw "Task Scheduler returned an invalid ISO-8601 duration: $Duration"
    }
}

function New-ClawLabLogonTaskSpec {
    param(
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][string]$ExecutePath,
        [Parameter(Mandatory)][string]$Arguments,
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][int]$ExecutionTimeLimitMinutes,
        [int]$TriggerDelaySeconds = 0,
        [ValidateRange(0, 10)][int]$TaskPriority = 7,
        [string]$UserSid = ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
    )

    if ([string]::IsNullOrWhiteSpace($TaskName) -or $TaskName.IndexOfAny(@('\', '/')) -ge 0) {
        throw "Invalid root Task Scheduler name: $TaskName"
    }
    if ($ExecutionTimeLimitMinutes -lt 0 -or $ExecutionTimeLimitMinutes -gt 60) {
        throw 'The ClawLab task execution limit must be zero (unlimited) or between 1 and 60 minutes.'
    }
    if ($TriggerDelaySeconds -lt 0 -or $TriggerDelaySeconds -gt 300) {
        throw 'The ClawLab logon trigger delay must be between 0 and 300 seconds.'
    }

    $resolvedSid = ConvertTo-ClawLabTaskSid -Identity $UserSid
    $resolvedAccount = ConvertTo-ClawLabTaskAccountName -Identity $resolvedSid
    return [pscustomobject]@{
        TaskName = $TaskName
        TaskPath = '\'
        UserSid = $resolvedSid
        # Task Scheduler accepts a SID when reading a task back, but some
        # Windows/account combinations reject a raw SID in the registration
        # XML Principal/UserId field with ERROR_INVALID_PARAMETER. Register
        # through the resolved NT account name and keep the immutable SID as
        # the ownership and readback-verification boundary.
        UserAccount = $resolvedAccount
        ExecutePath = ConvertTo-ClawLabTaskPath -LiteralPath $ExecutePath
        Arguments = $Arguments
        Description = $Description
        ExecutionTimeLimitSeconds = [double]($ExecutionTimeLimitMinutes * 60)
        TriggerDelaySeconds = [double]$TriggerDelaySeconds
        TaskPriority = [int]$TaskPriority
        StartWhenAvailable = $true
        AllowStartIfOnBatteries = $true
        DontStopIfGoingOnBatteries = $true
        MultipleInstancesPolicy = 2 # TASK_INSTANCES_IGNORE_NEW
    }
}

function Get-ClawLabScheduledTaskRecord {
    param([Parameter(Mandatory)][string]$TaskName)

    $service = $null
    $folder = $null
    $registeredTask = $null
    $definition = $null
    $action = $null
    $trigger = $null
    try {
        $service = New-Object -ComObject 'Schedule.Service'
        $service.Connect()
        $folder = $service.GetFolder('\')
        try {
            $registeredTask = $folder.GetTask($TaskName)
        }
        catch {
            $hresult = ConvertTo-ClawLabHResultUInt32 -HResult ([int]$_.Exception.HResult)
            if ($hresult -in @(
                    [Convert]::ToUInt32('80070002', 16),
                    [Convert]::ToUInt32('8004130F', 16)
                )) {
                return $null
            }
            throw ('Task Scheduler query failed for "{0}" with HRESULT 0x{1:X8}: {2}' -f
                $TaskName, $hresult, $_.Exception.Message)
        }

        $definition = $registeredTask.Definition
        $actionCount = [int]$definition.Actions.Count
        $triggerCount = [int]$definition.Triggers.Count
        if ($actionCount -ge 1) { $action = $definition.Actions.Item(1) }
        if ($triggerCount -ge 1) { $trigger = $definition.Triggers.Item(1) }

        $stateNames = @('Unknown', 'Disabled', 'Queued', 'Ready', 'Running')
        $stateNumber = [int]$registeredTask.State
        $stateName = if ($stateNumber -ge 0 -and $stateNumber -lt $stateNames.Count) {
            $stateNames[$stateNumber]
        }
        else {
            "Unknown_$stateNumber"
        }

        return [pscustomobject]@{
            TaskName = $TaskName
            TaskPath = [string]$registeredTask.Path
            State = $stateName
            Enabled = [bool]$registeredTask.Enabled -and [bool]$definition.Settings.Enabled
            Description = [string]$definition.RegistrationInfo.Description
            ActionCount = $actionCount
            ActionType = if ($null -eq $action) { -1 } else { [int]$action.Type }
            ExecutePath = if ($null -eq $action) { '' } else { [string]$action.Path }
            Arguments = if ($null -eq $action) { '' } else { [string]$action.Arguments }
            TriggerCount = $triggerCount
            TriggerType = if ($null -eq $trigger) { -1 } else { [int]$trigger.Type }
            TriggerUserId = if ($null -eq $trigger) { '' } else { [string]$trigger.UserId }
            TriggerDelay = if ($null -eq $trigger) { '' } else { [string]$trigger.Delay }
            PrincipalUserId = [string]$definition.Principal.UserId
            PrincipalLogonType = [int]$definition.Principal.LogonType
            PrincipalRunLevel = [int]$definition.Principal.RunLevel
            StartWhenAvailable = [bool]$definition.Settings.StartWhenAvailable
            AllowStartIfOnBatteries = -not [bool]$definition.Settings.DisallowStartIfOnBatteries
            DontStopIfGoingOnBatteries = -not [bool]$definition.Settings.StopIfGoingOnBatteries
            MultipleInstancesPolicy = [int]$definition.Settings.MultipleInstances
            ExecutionTimeLimit = [string]$definition.Settings.ExecutionTimeLimit
            TaskPriority = [int]$definition.Settings.Priority
        }
    }
    finally {
        foreach ($comObject in @($trigger, $action, $definition, $registeredTask, $folder, $service)) {
            if ($null -ne $comObject -and [Runtime.InteropServices.Marshal]::IsComObject($comObject)) {
                [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($comObject)
            }
        }
    }
}

function Test-ClawLabScheduledTaskRecord {
    param(
        [Parameter(Mandatory)][object]$Record,
        [Parameter(Mandatory)][object]$Spec
    )

    $reasons = [Collections.Generic.List[string]]::new()
    $expectedTaskPath = "\$($Spec.TaskName)"
    if (-not ([string]$Record.TaskPath).Equals($expectedTaskPath, [StringComparison]::OrdinalIgnoreCase)) {
        $reasons.Add("unexpected task path '$($Record.TaskPath)'")
    }
    if ([string]$Record.Description -cne [string]$Spec.Description) {
        $reasons.Add('unexpected task description')
    }
    if (-not [bool]$Record.Enabled) { $reasons.Add('task is disabled') }
    if ([int]$Record.ActionCount -ne 1 -or [int]$Record.ActionType -ne 0) {
        $reasons.Add('expected exactly one executable action')
    }
    else {
        try {
            $actualExecute = ConvertTo-ClawLabTaskPath -LiteralPath ([string]$Record.ExecutePath)
            if (-not $actualExecute.Equals([string]$Spec.ExecutePath, [StringComparison]::OrdinalIgnoreCase)) {
                $reasons.Add("unexpected executable '$actualExecute'")
            }
        }
        catch { $reasons.Add($_.Exception.Message) }
        if ([string]$Record.Arguments -cne [string]$Spec.Arguments) {
            $reasons.Add('unexpected action arguments')
        }
    }
    if ([int]$Record.TriggerCount -ne 1 -or [int]$Record.TriggerType -ne 9) {
        $reasons.Add('expected exactly one logon trigger')
    }
    else {
        try {
            if ((ConvertTo-ClawLabTaskSid -Identity ([string]$Record.TriggerUserId)) -ne [string]$Spec.UserSid) {
                $reasons.Add('logon trigger SID does not match the installing user')
            }
        }
        catch { $reasons.Add($_.Exception.Message) }
        $actualDelay = ConvertTo-ClawLabTaskDurationSeconds -Duration ([string]$Record.TriggerDelay)
        if ([Math]::Abs($actualDelay - [double]$Spec.TriggerDelaySeconds) -gt 0.1) {
            $reasons.Add("unexpected logon trigger delay '$($Record.TriggerDelay)'")
        }
    }
    try {
        if ((ConvertTo-ClawLabTaskSid -Identity ([string]$Record.PrincipalUserId)) -ne [string]$Spec.UserSid) {
            $reasons.Add('task principal SID does not match the installing user')
        }
    }
    catch { $reasons.Add($_.Exception.Message) }
    if ([int]$Record.PrincipalLogonType -ne 3) { $reasons.Add('principal is not InteractiveToken') }
    if ([int]$Record.PrincipalRunLevel -ne 0) { $reasons.Add('principal is not Limited/LUA') }
    if ([bool]$Record.StartWhenAvailable -ne [bool]$Spec.StartWhenAvailable) {
        $reasons.Add('StartWhenAvailable differs')
    }
    if ([bool]$Record.AllowStartIfOnBatteries -ne [bool]$Spec.AllowStartIfOnBatteries) {
        $reasons.Add('battery-start policy differs')
    }
    if ([bool]$Record.DontStopIfGoingOnBatteries -ne [bool]$Spec.DontStopIfGoingOnBatteries) {
        $reasons.Add('battery-stop policy differs')
    }
    if ([int]$Record.MultipleInstancesPolicy -ne [int]$Spec.MultipleInstancesPolicy) {
        $reasons.Add('multiple-instance policy differs')
    }
    if ([int]$Record.TaskPriority -ne [int]$Spec.TaskPriority) {
        $reasons.Add("task priority differs: '$($Record.TaskPriority)'")
    }
    $actualLimit = ConvertTo-ClawLabTaskDurationSeconds -Duration ([string]$Record.ExecutionTimeLimit)
    if ([Math]::Abs($actualLimit - [double]$Spec.ExecutionTimeLimitSeconds) -gt 0.1) {
        $reasons.Add("execution limit differs: '$($Record.ExecutionTimeLimit)'")
    }

    return [pscustomobject]@{
        Valid = $reasons.Count -eq 0
        Reasons = @($reasons)
    }
}

function Test-ClawLabScheduledTaskOwned {
    param(
        [Parameter(Mandatory)][object]$Record,
        [Parameter(Mandatory)][object]$Spec
    )

    $expectedTaskPath = "\$($Spec.TaskName)"
    if (-not ([string]$Record.TaskPath).Equals($expectedTaskPath, [StringComparison]::OrdinalIgnoreCase) -or
        [int]$Record.ActionCount -ne 1 -or [int]$Record.ActionType -ne 0 -or
        [int]$Record.TriggerCount -ne 1 -or [int]$Record.TriggerType -ne 9 -or
        [string]$Record.Arguments -cne [string]$Spec.Arguments) {
        return $false
    }
    try {
        $executeMatches = (ConvertTo-ClawLabTaskPath -LiteralPath ([string]$Record.ExecutePath)).Equals(
            [string]$Spec.ExecutePath, [StringComparison]::OrdinalIgnoreCase)
        $triggerSidMatches = (ConvertTo-ClawLabTaskSid -Identity ([string]$Record.TriggerUserId)) -eq
            [string]$Spec.UserSid
        $principalSidMatches = (ConvertTo-ClawLabTaskSid -Identity ([string]$Record.PrincipalUserId)) -eq
            [string]$Spec.UserSid
        return $executeMatches -and $triggerSidMatches -and $principalSidMatches
    }
    catch {
        return $false
    }
}

function Wait-ClawLabScheduledTaskState {
    param(
        [Parameter(Mandatory)][object]$Spec,
        [Parameter(Mandatory)][ValidateSet('Present', 'Absent')][string]$DesiredState,
        [scriptblock]$Query = { param($Name) Get-ClawLabScheduledTaskRecord -TaskName $Name },
        [scriptblock]$Delay = { param($Milliseconds) Start-Sleep -Milliseconds $Milliseconds }
    )

    $delays = @(0, 100, 200, 400, 800, 1000, 1000, 1000, 500)
    $lastRecord = $null
    foreach ($delayMilliseconds in $delays) {
        if ($delayMilliseconds -gt 0) { & $Delay $delayMilliseconds }
        $lastRecord = & $Query ([string]$Spec.TaskName)
        if ($DesiredState -eq 'Absent') {
            if ($null -eq $lastRecord) {
                return [pscustomobject]@{ State = 'ABSENT'; Record = $null; Validation = $null }
            }
            continue
        }
        if ($null -eq $lastRecord) { continue }
        $validation = Test-ClawLabScheduledTaskRecord -Record $lastRecord -Spec $Spec
        if (-not $validation.Valid) {
            return [pscustomobject]@{ State = 'PRESENT_INVALID'; Record = $lastRecord; Validation = $validation }
        }
        return [pscustomobject]@{ State = 'PRESENT_VALID'; Record = $lastRecord; Validation = $validation }
    }
    if ($DesiredState -eq 'Absent') {
        return [pscustomobject]@{ State = 'PRESENT_TIMEOUT'; Record = $lastRecord; Validation = $null }
    }
    return [pscustomobject]@{ State = 'ABSENT_TIMEOUT'; Record = $null; Validation = $null }
}

function Start-ClawLabScheduledTask {
    param([Parameter(Mandatory)][object]$Spec)

    # Revalidate the exact owned definition before asking Task Scheduler to
    # create an instance. In particular, this preserves InteractiveToken +
    # Limited even when the caller itself is elevated for installation.
    $record = Get-ClawLabScheduledTaskRecord -TaskName ([string]$Spec.TaskName)
    if ($null -eq $record) {
        throw "The ClawLab task '$($Spec.TaskName)' is not installed."
    }
    $validation = Test-ClawLabScheduledTaskRecord -Record $record -Spec $Spec
    if (-not $validation.Valid) {
        throw "The ClawLab task '$($Spec.TaskName)' cannot be started because its definition is invalid: $($validation.Reasons -join '; ')"
    }

    $service = $null
    $folder = $null
    $registeredTask = $null
    $runningTask = $null
    try {
        $service = New-Object -ComObject 'Schedule.Service'
        $service.Connect()
        $folder = $service.GetFolder('\')
        $registeredTask = $folder.GetTask([string]$Spec.TaskName)
        $runningTask = $registeredTask.Run($null)
        if ($null -eq $runningTask) {
            throw "Task Scheduler did not return a running instance for '$($Spec.TaskName)'."
        }
        return [pscustomobject]@{
            TaskName = [string]$Spec.TaskName
            InstanceGuid = [string]$runningTask.InstanceGuid
            EnginePid = [uint32]$runningTask.EnginePID
            State = [int]$runningTask.State
        }
    }
    finally {
        foreach ($comObject in @($runningTask, $registeredTask, $folder, $service)) {
            if ($null -ne $comObject -and [Runtime.InteropServices.Marshal]::IsComObject($comObject)) {
                [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($comObject)
            }
        }
    }
}

function Remove-ClawLabScheduledTask {
    param(
        [Parameter(Mandatory)][object]$Spec,
        [switch]$AllowAbsent
    )

    $current = Get-ClawLabScheduledTaskRecord -TaskName ([string]$Spec.TaskName)
    if ($null -eq $current) {
        if ($AllowAbsent) { return [pscustomobject]@{ Removed = $false; AlreadyAbsent = $true } }
        throw "The expected ClawLab task is already absent: $($Spec.TaskName)"
    }
    if (-not (Test-ClawLabScheduledTaskOwned -Record $current -Spec $Spec)) {
        throw "A task named '$($Spec.TaskName)' exists but its action is not owned by ClawLab. It was not removed."
    }

    $service = $null
    $folder = $null
    try {
        $service = New-Object -ComObject 'Schedule.Service'
        $service.Connect()
        $folder = $service.GetFolder('\')
        try {
            $folder.DeleteTask([string]$Spec.TaskName, 0)
        }
        catch {
            $hresult = ConvertTo-ClawLabHResultUInt32 -HResult ([int]$_.Exception.HResult)
            if ($hresult -notin @(
                    [Convert]::ToUInt32('80070002', 16),
                    [Convert]::ToUInt32('8004130F', 16)
                )) {
                throw ('Task Scheduler deletion failed for "{0}" with HRESULT 0x{1:X8}: {2}' -f
                    $Spec.TaskName, $hresult, $_.Exception.Message)
            }
        }
    }
    finally {
        foreach ($comObject in @($folder, $service)) {
            if ($null -ne $comObject -and [Runtime.InteropServices.Marshal]::IsComObject($comObject)) {
                [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($comObject)
            }
        }
    }

    $result = Wait-ClawLabScheduledTaskState -Spec $Spec -DesiredState Absent
    if ($result.State -ne 'ABSENT') {
        throw "The ClawLab task still exists after deletion: $($Spec.TaskName)"
    }
    return [pscustomobject]@{ Removed = $true; AlreadyAbsent = $false }
}

function Install-ClawLabScheduledTask {
    param([Parameter(Mandatory)][object]$Spec)

    $current = Get-ClawLabScheduledTaskRecord -TaskName ([string]$Spec.TaskName)
    if ($null -ne $current) {
        $validation = Test-ClawLabScheduledTaskRecord -Record $current -Spec $Spec
        if ($validation.Valid) {
            return [pscustomobject]@{ Installed = $false; Reused = $true; State = $current.State }
        }
        if (-not (Test-ClawLabScheduledTaskOwned -Record $current -Spec $Spec)) {
            throw "A task named '$($Spec.TaskName)' exists but is not the expected ClawLab task. It was not overwritten."
        }
        [void](Remove-ClawLabScheduledTask -Spec $Spec)
    }

    $registrationIdentity = if ('UserAccount' -in $Spec.PSObject.Properties.Name -and
        -not [string]::IsNullOrWhiteSpace([string]$Spec.UserAccount)) {
        [string]$Spec.UserAccount
    }
    else {
        [string]$Spec.UserSid
    }
    # Validate the registration identity immediately before it is embedded in
    # Task Scheduler XML. Readback remains SID-based, so a renamed account or a
    # different account can never satisfy the ownership checks accidentally.
    if ((ConvertTo-ClawLabTaskSid -Identity $registrationIdentity) -ne [string]$Spec.UserSid) {
        throw 'The task registration account no longer resolves to the installing user SID.'
    }

    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $registrationIdentity
    if ([double]$Spec.TriggerDelaySeconds -gt 0) {
        $trigger.Delay = [Xml.XmlConvert]::ToString([TimeSpan]::FromSeconds([double]$Spec.TriggerDelaySeconds))
    }
    $action = New-ScheduledTaskAction -Execute ([string]$Spec.ExecutePath) -Argument ([string]$Spec.Arguments)
    $principal = New-ScheduledTaskPrincipal -UserId $registrationIdentity -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -MultipleInstances IgnoreNew `
        -Priority ([int]$Spec.TaskPriority) `
        -ExecutionTimeLimit ([TimeSpan]::FromSeconds([double]$Spec.ExecutionTimeLimitSeconds))
    $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal `
        -Settings $settings -Description ([string]$Spec.Description)

    $registered = Register-ScheduledTask -TaskName ([string]$Spec.TaskName) -TaskPath '\' `
        -InputObject $task -ErrorAction Stop
    if ($null -eq $registered) {
        throw "Task Scheduler did not return the registered ClawLab task: $($Spec.TaskName)"
    }

    $readback = Wait-ClawLabScheduledTaskState -Spec $Spec -DesiredState Present
    if ($readback.State -ne 'PRESENT_VALID') {
        $details = if ($null -ne $readback.Validation) {
            $readback.Validation.Reasons -join '; '
        }
        else {
            $readback.State
        }
        $cleanupFailure = $null
        try {
            [void](Remove-ClawLabScheduledTask -Spec $Spec -AllowAbsent)
        }
        catch {
            $cleanupFailure = $_.Exception.Message
        }
        if (-not [string]::IsNullOrWhiteSpace($cleanupFailure)) {
            throw "The ClawLab task could not be verified after registration: $details. Cleanup also failed: $cleanupFailure"
        }
        throw "The ClawLab task could not be verified after registration: $details"
    }
    return [pscustomobject]@{ Installed = $true; Reused = $false; State = $readback.Record.State }
}
