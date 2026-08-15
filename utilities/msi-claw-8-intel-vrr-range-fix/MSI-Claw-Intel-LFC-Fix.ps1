[CmdletBinding()]
param(
    [ValidateSet('Status', 'Apply', 'Restore', 'ApplyStartup')]
    [string]$Action = 'Status'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$toolVersion = '2.0.2'

# Intel LFC companion for every ClawLab-managed VRR mode. It
# disables Intel's low- and high-FPS VRR solutions as one tested combination,
# preventing the observed x2 refresh-rate multiplication inside the managed
# range. This is a global display-driver setting: no game process is opened,
# injected into, patched or monitored.

$physicalEdidHash = 'E49BC570225510B7C889ED292570F1345CAA07F5840DB57EA6998A403DB5CEF0'
$experimental30EdidHash = '14CDDC390CF69367C4B6821A46728518200446A33F708A1A87CA673B68B66918'
$experimental144EdidHash = '4CFB165CE96119BA37A07176F9D346691D447E0A40E8697777E499E1556A744E'
$experimental30_144EdidHash = '0B8E8A25325B4D9CAC2B6A03CF9B574688B1A6D2DEDF10401605C4898E0CAC05'
$validatedEdidHashes = @(
    $physicalEdidHash,
    $experimental30EdidHash,
    $experimental144EdidHash,
    $experimental30_144EdidHash
)
$vrrStateRoot = Join-Path $env:LOCALAPPDATA 'ClawLab\Intel-Arc-Sync-Full-Range'
$managedModePath = Join-Path $vrrStateRoot 'managed-mode.json'
$experimentalStatePath = Join-Path $vrrStateRoot 'experimental-edid.json'
$lfcStateRoot = Join-Path $env:LOCALAPPDATA 'ClawLab\Intel-LFC-Fix'
$lfcBackupPath = Join-Path $lfcStateRoot 'original-intel-vrr-solutions.json'
$installedToolPath = Join-Path $lfcStateRoot 'MSI-Claw-Intel-LFC-Fix.ps1'
$installedDriverInterfacePath = Join-Path $lfcStateRoot 'Intel-VRR-LFC-Driver-Interface.ps1'
$installedLauncherPath = Join-Path $lfcStateRoot 'ClawLab-LFC-Startup.vbs'
$startupTaskName = 'ClawLab MSI Claw Intel LFC Fix'

function Convert-WmiText {
    param([AllowNull()][object]$Values)

    if ($null -eq $Values) {
        return ''
    }
    return (-join @($Values | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }))
}

function Remove-FileIfPresent {
    param([Parameter(Mandatory)][string]$LiteralPath)

    if (Test-Path -LiteralPath $LiteralPath -PathType Leaf) {
        [IO.File]::Delete($LiteralPath)
    }
}

function Get-ByteArraySha256 {
    param([Parameter(Mandatory)][byte[]]$Bytes)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
}

$panels = @(
    Get-CimInstance -Namespace 'root\wmi' -ClassName 'WmiMonitorID' |
        ForEach-Object {
            [pscustomobject]@{
                InstanceName = [string]$_.InstanceName
                Manufacturer = Convert-WmiText -Values $_.ManufacturerName
                ProductCode = Convert-WmiText -Values $_.ProductCodeID
                Name = Convert-WmiText -Values $_.UserFriendlyName
            }
        } |
        Where-Object {
            $_.Manufacturer -eq 'CSW' -and
            $_.ProductCode -eq '0801' -and
            $_.Name -eq 'PN8007QB1-2'
        }
)
if ($panels.Count -ne 1) {
    throw 'The exact validated CSW0801 / PN8007QB1-2 panel was not found once.'
}
$panel = $panels[0]
$panelInstanceId = $panel.InstanceName -replace '_\d+$', ''
$panelDeviceParameters = "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\$panelInstanceId\Device Parameters"
$reportedEdid = [byte[]](Get-ItemPropertyValue -LiteralPath $panelDeviceParameters -Name 'EDID')
$reportedEdidSha256 = Get-ByteArraySha256 -Bytes $reportedEdid
if ($reportedEdidSha256 -notin $validatedEdidHashes) {
    throw "The active panel EDID is not an approved ClawLab state: $reportedEdidSha256"
}

$managedMode = $null
if (Test-Path -LiteralPath $managedModePath -PathType Leaf) {
    $managedMode = [IO.File]::ReadAllText($managedModePath, [Text.Encoding]::UTF8) | ConvertFrom-Json
}
$managedModeName = if ($null -eq $managedMode) { 'UNMANAGED' } else { [string]$managedMode.Mode }
$managedProfiles = @{
    'OFFICIAL_48_120' = [pscustomobject]@{ MinimumHz = 48; MaximumHz = 120; EdidSha256 = $physicalEdidHash; UsesCustomEdid = $false }
    'CLAWLAB_30_120' = [pscustomobject]@{ MinimumHz = 30; MaximumHz = 120; EdidSha256 = $experimental30EdidHash; UsesCustomEdid = $true }
    'CLAWLAB_48_144' = [pscustomobject]@{ MinimumHz = 48; MaximumHz = 144; EdidSha256 = $experimental144EdidHash; UsesCustomEdid = $true }
    'CLAWLAB_30_144' = [pscustomobject]@{ MinimumHz = 30; MaximumHz = 144; EdidSha256 = $experimental30_144EdidHash; UsesCustomEdid = $true }
}
$managedProfile = if ($managedProfiles.ContainsKey($managedModeName)) { $managedProfiles[$managedModeName] } else { $null }
if ($Action -in @('Apply', 'ApplyStartup') -and $null -eq $managedProfile) {
    throw "The LFC fix requires one of the four ClawLab-managed profiles; current mode is $managedModeName."
}
if ($Action -in @('Apply', 'ApplyStartup') -and $managedModeName -in @('CLAWLAB_48_144', 'CLAWLAB_30_144')) {
    throw 'The installed 144 Hz profile is retired and cannot receive persistence updates. Run RESTORE_ORIGINAL_VRR.bat.'
}
$expectedMinimumHz = if ($null -eq $managedProfile) { 0 } else { [int]$managedProfile.MinimumHz }
$expectedMaximumHz = if ($null -eq $managedProfile) { 0 } else { [int]$managedProfile.MaximumHz }
$expectedEdidSha256 = if ($null -eq $managedProfile) { '' } else { [string]$managedProfile.EdidSha256 }
if ($Action -eq 'ApplyStartup' -and $reportedEdidSha256 -ne $expectedEdidSha256) {
    throw "The LFC fix requires the exact $managedModeName EDID; current hash is $reportedEdidSha256."
}
if ($Action -eq 'Apply' -and $reportedEdidSha256 -ne $expectedEdidSha256) {
    if (-not [bool]$managedProfile.UsesCustomEdid -or
        $reportedEdidSha256 -ne $physicalEdidHash -or
        -not (Test-Path -LiteralPath $experimentalStatePath -PathType Leaf)) {
        throw "The pending $managedModeName EDID state could not be verified."
    }
    $pendingEdidState = [IO.File]::ReadAllText($experimentalStatePath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if ([string]$pendingEdidState.Mode -ne $managedModeName -or
        [string]$pendingEdidState.ExperimentalEdidSha256 -ne $expectedEdidSha256) {
        throw "The pending custom EDID does not match $managedModeName."
    }
}

$intelGpus = @(
    Get-CimInstance Win32_VideoController |
        Where-Object { $_.PNPDeviceID -like 'PCI\VEN_8086&*' }
)
if ($intelGpus.Count -ne 1) {
    throw "Expected exactly one Intel graphics adapter; found $($intelGpus.Count)."
}
$intelGpu = $intelGpus[0]
$driverInterfacePath = Join-Path $PSScriptRoot 'Intel-VRR-LFC-Driver-Interface.ps1'
if (-not (Test-Path -LiteralPath $driverInterfacePath -PathType Leaf)) {
    throw 'The direct Intel VRR driver interface is missing from this package.'
}

function Convert-DirectVrrState {
    param([Parameter(Mandatory)][object]$RawState)

    [pscustomobject]@{
        Result = if ([uint32]$RawState.NtStatus -eq 0) { 'Success' } else { '0x{0:X8}' -f [uint32]$RawState.NtStatus }
        Supported = [bool]$RawState.Supported
        MinimumHz = [uint32]$RawState.MinimumHz
        MaximumHz = [uint32]$RawState.MaximumHz
        VrrEnabled = [bool]$RawState.Enabled
        LowFpsSolutionEnabled = [bool]$RawState.LowFpsSolutionEnabled
        HighFpsSolutionEnabled = [bool]$RawState.HighFpsSolutionEnabled
        TargetId = [uint32]$RawState.TargetId
        DisplayDeviceName = [string]$RawState.DisplayDeviceName
    }
}

function Invoke-DirectVrrDriverAction {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Status', 'EnableLowFps', 'DisableLowFps', 'EnableHighFps', 'DisableHighFps')]
        [string]$DriverAction
    )

    $raw = & $driverInterfacePath -Action $DriverAction
    if ($null -eq $raw) {
        throw "The direct Intel VRR driver action returned no state: $DriverAction"
    }
    return Convert-DirectVrrState -RawState $raw
}

if ($Action -eq 'ApplyStartup') {
    $clawTweaksTask = Get-ScheduledTask -TaskPath '\ClawTweaks\' -TaskName 'ClawTweaksHelper' -ErrorAction SilentlyContinue
    if ($null -ne $clawTweaksTask) {
        for ($attempt = 1; $attempt -le 30; $attempt++) {
            $clawTweaksTask = Get-ScheduledTask -TaskPath '\ClawTweaks\' -TaskName 'ClawTweaksHelper' -ErrorAction SilentlyContinue
            if ($null -ne $clawTweaksTask -and [string]$clawTweaksTask.State -eq 'Running') {
                break
            }
            Start-Sleep -Seconds 2
        }
        # ClawTweaks may restore its saved display profile during helper
        # initialization. Wait once for that initialization to settle; this is
        # deliberately not a persistent watcher.
        Start-Sleep -Seconds 8
    }

    $installedVrrToolPath = Join-Path $vrrStateRoot 'MSI-Claw-VRR-Fix.ps1'
    if (-not (Test-Path -LiteralPath $installedVrrToolPath -PathType Leaf)) {
        throw 'The installed ClawLab VRR startup tool is missing.'
    }
    # Run the range reapply in a child host. Its successful ApplyStartup path
    # deliberately calls exit 0; invoking it in this host would terminate the
    # LFC script before the Intel solution flags are reapplied.
    $rangeArguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$installedVrrToolPath`" -Action ApplyStartup"
    $rangeProcess = Start-Process -FilePath 'powershell.exe' -ArgumentList $rangeArguments `
        -WindowStyle Hidden -Wait -PassThru
    if ($rangeProcess.ExitCode -ne 0) {
        throw "The installed ClawLab VRR startup reapply failed with exit code $($rangeProcess.ExitCode)."
    }
}
$current = Invoke-DirectVrrDriverAction -DriverAction Status
if ($Action -eq 'ApplyStartup') {
    for ($attempt = 1; $attempt -le 90; $attempt++) {
        if ($current.Supported -and $current.VrrEnabled -and
            $current.MinimumHz -eq $expectedMinimumHz -and $current.MaximumHz -eq $expectedMaximumHz) {
            break
        }
        Start-Sleep -Seconds 2
        $current = Invoke-DirectVrrDriverAction -DriverAction Status
    }
}
if ($Action -eq 'ApplyStartup' -and
    (-not $current.Supported -or -not $current.VrrEnabled -or
        $current.MinimumHz -ne $expectedMinimumHz -or $current.MaximumHz -ne $expectedMaximumHz)) {
    throw "Unexpected active VRR state for ${managedModeName}: supported=$($current.Supported), enabled=$($current.VrrEnabled), range=$($current.MinimumHz)-$($current.MaximumHz)."
}
if ($Action -eq 'Apply' -and (-not $current.Supported -or $current.Result -ne 'Success')) {
    throw 'The Intel VRR driver interface is unavailable, so the LFC state cannot be backed up safely.'
}
if ($Action -eq 'Restore' -and (-not $current.Supported -or $current.Result -ne 'Success')) {
    throw 'The signed Intel driver escape is unavailable, so the saved LFC state cannot be restored safely.'
}

function Get-CurrentIntelVrrState {
    Invoke-DirectVrrDriverAction -DriverAction Status
}

function Set-LowFpsSolution {
    param([Parameter(Mandatory)][bool]$Enabled)

    $driverAction = if ($Enabled) { 'EnableLowFps' } else { 'DisableLowFps' }
    $result = Invoke-DirectVrrDriverAction -DriverAction $driverAction
    if ($result.Result -ne 'Success') {
        throw "The direct Intel low-FPS driver action failed: $($result.Result)"
    }
}

function Set-HighFpsSolution {
    param([Parameter(Mandatory)][bool]$Enabled)

    $driverAction = if ($Enabled) { 'EnableHighFps' } else { 'DisableHighFps' }
    $result = Invoke-DirectVrrDriverAction -DriverAction $driverAction
    if ($result.Result -ne 'Success') {
        throw "The direct Intel high-FPS driver action failed: $($result.Result)"
    }
}

function Get-LfcBackup {
    if (-not (Test-Path -LiteralPath $lfcBackupPath -PathType Leaf)) {
        return $null
    }
    $backup = [IO.File]::ReadAllText($lfcBackupPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($property in @('SchemaVersion', 'PanelInstanceName', 'OriginalLowFpsSolutionEnabled')) {
        if ($property -notin $backup.PSObject.Properties.Name) {
            throw "The LFC backup is invalid: missing $property."
        }
    }
    if ([int]$backup.SchemaVersion -notin @(1, 2, 3) -or
        [string]$backup.PanelInstanceName -ne [string]$panel.InstanceName) {
        throw 'The LFC backup does not match the current validated panel.'
    }
    if ([int]$backup.SchemaVersion -eq 1 -and $Action -ne 'Restore') {
        throw 'A legacy low-FPS-only experiment is still active. Restore it before applying this release.'
    }
    if ([int]$backup.SchemaVersion -in @(2, 3) -and
        'OriginalHighFpsSolutionEnabled' -notin $backup.PSObject.Properties.Name) {
        throw 'The Intel VRR solution backup is invalid.'
    }
    if ([int]$backup.SchemaVersion -eq 3 -and
        'ManagedVrrMode' -notin $backup.PSObject.Properties.Name) {
        throw 'The Intel VRR solution backup has no managed-profile identity.'
    }
    if ($Action -in @('Apply', 'ApplyStartup') -and
        [int]$backup.SchemaVersion -eq 3 -and
        [string]$backup.ManagedVrrMode -ne $managedModeName) {
        throw "The saved LFC state belongs to $($backup.ManagedVrrMode), not $managedModeName. Run RESTORE_ORIGINAL_VRR.bat before switching profiles."
    }
    return $backup
}

function Get-StartupPersistenceState {
    $task = Get-ScheduledTask -TaskName $startupTaskName -ErrorAction SilentlyContinue
    if ($null -eq $task) {
        return 'NOT_INSTALLED'
    }
    if (-not (Test-Path -LiteralPath $installedToolPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $installedDriverInterfacePath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $installedLauncherPath -PathType Leaf)) {
        return 'INCOMPLETE'
    }
    return 'INSTALLED_ONE_SHOT_AT_LOGON'
}

function Install-StartupPersistence {
    $sourceLauncherPath = Join-Path $PSScriptRoot 'ClawLab-LFC-Startup.vbs'
    if (-not (Test-Path -LiteralPath $sourceLauncherPath -PathType Leaf)) {
        throw 'The windowless one-shot startup launcher is missing from this package.'
    }
    [IO.Directory]::CreateDirectory($lfcStateRoot) | Out-Null
    [IO.File]::Copy($PSCommandPath, $installedToolPath, $true)
    [IO.File]::Copy($driverInterfacePath, $installedDriverInterfacePath, $true)
    [IO.File]::Copy($sourceLauncherPath, $installedLauncherPath, $true)

    foreach ($pair in @(
        @($PSCommandPath, $installedToolPath),
        @($driverInterfacePath, $installedDriverInterfacePath),
        @($sourceLauncherPath, $installedLauncherPath)
    )) {
        if ((Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash -ne
            (Get-FileHash -LiteralPath $pair[1] -Algorithm SHA256).Hash) {
            throw "Startup persistence copy verification failed: $($pair[1])"
        }
    }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $wscriptPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
    $arguments = "//B //Nologo `"$installedLauncherPath`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $identity.Name
    $taskAction = New-ScheduledTaskAction -Execute $wscriptPath -Argument $arguments
    $principal = New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 4)
    $task = New-ScheduledTask -Action $taskAction -Trigger $trigger -Principal $principal `
        -Settings $settings -Description 'Silently reapplies the selected ClawLab VRR range and Intel LFC state once at logon, then exits.'
    Register-ScheduledTask -TaskName $startupTaskName -InputObject $task -Force | Out-Null
    if ((Get-StartupPersistenceState) -ne 'INSTALLED_ONE_SHOT_AT_LOGON') {
        throw 'The one-shot startup persistence task could not be verified.'
    }
}

function Remove-StartupPersistence {
    $task = Get-ScheduledTask -TaskName $startupTaskName -ErrorAction SilentlyContinue
    if ($null -ne $task) {
        Unregister-ScheduledTask -TaskName $startupTaskName -Confirm:$false -ErrorAction Stop
    }
    Remove-FileIfPresent -LiteralPath $installedToolPath
    Remove-FileIfPresent -LiteralPath $installedDriverInterfacePath
    Remove-FileIfPresent -LiteralPath $installedLauncherPath
    if ((Get-StartupPersistenceState) -ne 'NOT_INSTALLED') {
        throw 'The one-shot startup persistence task was not fully removed.'
    }
}

$state = switch ($Action) {
    'Status' {
        $now = Get-CurrentIntelVrrState
        [pscustomobject]@{
            State = if ($null -ne $managedProfile -and
                (Test-Path -LiteralPath $lfcBackupPath -PathType Leaf) -and
                $now.MinimumHz -eq $expectedMinimumHz -and
                $now.MaximumHz -eq $expectedMaximumHz -and
                -not $now.LowFpsSolutionEnabled -and -not $now.HighFpsSolutionEnabled) {
                'CLAWLAB_LFC_FIX_ACTIVE'
            }
            elseif (-not $now.LowFpsSolutionEnabled) {
                'INTEL_LOW_FPS_SOLUTION_DISABLED_OUTSIDE_MANAGED_FIX'
            }
            elseif ($null -ne $managedProfile -and
                (Test-Path -LiteralPath $lfcBackupPath -PathType Leaf) -and
                (Get-StartupPersistenceState) -eq 'INSTALLED_ONE_SHOT_AT_LOGON') {
                'CLAWLAB_LFC_FIX_PENDING_RESTART'
            }
            else {
                'INTEL_VRR_SOLUTIONS_NOT_PATCHED'
            }
            Current = $now
            BackupPresent = Test-Path -LiteralPath $lfcBackupPath -PathType Leaf
        }
    }

    { $_ -in @('Apply', 'ApplyStartup') } {
        $startupApplication = $Action -eq 'ApplyStartup'
        $before = Get-CurrentIntelVrrState
        $backup = Get-LfcBackup
        if ($null -eq $backup) {
            if ($startupApplication) {
                throw 'Startup reapply refused to run without a saved original LFC state.'
            }
            [IO.Directory]::CreateDirectory($lfcStateRoot) | Out-Null
            $backup = [ordered]@{
                SchemaVersion = 3
                SavedAt = (Get-Date).ToString('o')
                PanelInstanceName = [string]$panel.InstanceName
                PanelEdidSha256 = $reportedEdidSha256
                ManagedVrrMode = $managedModeName
                IntelDriverVersion = [string](Get-CimInstance Win32_VideoController | Where-Object { $_.PNPDeviceID -like 'PCI\VEN_8086&*' } | Select-Object -First 1).DriverVersion
                DriverInterface = 'DIRECT_D3DKMT_INTEL_PRIVATE_ESCAPE'
                OriginalLowFpsSolutionEnabled = [bool]$before.LowFpsSolutionEnabled
                OriginalHighFpsSolutionEnabled = [bool]$before.HighFpsSolutionEnabled
            }
            [IO.File]::WriteAllText(
                $lfcBackupPath,
                ($backup | ConvertTo-Json),
                [Text.UTF8Encoding]::new($false)
            )
            $backup = Get-LfcBackup
        }

        $rangeReady = $before.Supported -and $before.VrrEnabled -and
            $before.MinimumHz -eq $expectedMinimumHz -and
            $before.MaximumHz -eq $expectedMaximumHz
        if (-not $startupApplication -and -not $rangeReady) {
            Install-StartupPersistence
            [pscustomobject]@{
                State = 'CLAWLAB_LFC_FIX_PENDING_RESTART'
                Before = $before
                Current = $before
                BackupPresent = $true
                StartupPersistence = Get-StartupPersistenceState
            }
            break
        }

        if ($before.LowFpsSolutionEnabled -or $before.HighFpsSolutionEnabled) {
            try {
                Set-LowFpsSolution -Enabled $false
                Set-HighFpsSolution -Enabled $false
                Start-Sleep -Milliseconds 750
                $after = Get-CurrentIntelVrrState
                if ($after.Result -ne 'Success' -or
                    $after.LowFpsSolutionEnabled -or
                    $after.HighFpsSolutionEnabled -or
                    -not $after.VrrEnabled -or
                    $after.MinimumHz -ne $before.MinimumHz -or
                    $after.MaximumHz -ne $before.MaximumHz) {
                    throw "The post-apply Intel state is invalid: $($after | ConvertTo-Json -Compress)"
                }
                if (-not $startupApplication) {
                    Install-StartupPersistence
                }
            }
            catch {
                Set-LowFpsSolution -Enabled ([bool]$backup.OriginalLowFpsSolutionEnabled)
                Set-HighFpsSolution -Enabled ([bool]$backup.OriginalHighFpsSolutionEnabled)
                if (-not $startupApplication) {
                    try { Remove-StartupPersistence } catch {}
                }
                throw
            }
        }
        else {
            $after = $before
            if (-not $startupApplication) {
                Install-StartupPersistence
            }
        }

        [pscustomobject]@{
            State = 'CLAWLAB_LFC_FIX_ACTIVE'
            Before = $before
            Current = $after
            BackupPresent = $true
            StartupPersistence = Get-StartupPersistenceState
        }
        break
    }

    'Restore' {
        $backup = Get-LfcBackup
        if ($null -eq $backup) {
            Remove-StartupPersistence
            $after = Get-CurrentIntelVrrState
            [pscustomobject]@{
                State = 'ALREADY_RESTORED'
                Current = $after
                BackupPresent = $false
            }
            break
        }
        Remove-StartupPersistence
        Set-LowFpsSolution -Enabled ([bool]$backup.OriginalLowFpsSolutionEnabled)
        if ([int]$backup.SchemaVersion -in @(2, 3)) {
            Set-HighFpsSolution -Enabled ([bool]$backup.OriginalHighFpsSolutionEnabled)
        }
        Start-Sleep -Milliseconds 750
        $after = Get-CurrentIntelVrrState
        if ($after.Result -ne 'Success' -or
            $after.LowFpsSolutionEnabled -ne [bool]$backup.OriginalLowFpsSolutionEnabled -or
            ([int]$backup.SchemaVersion -in @(2, 3) -and
                $after.HighFpsSolutionEnabled -ne [bool]$backup.OriginalHighFpsSolutionEnabled)) {
            throw "The restored Intel state did not verify: $($after | ConvertTo-Json -Compress)"
        }
        Remove-FileIfPresent -LiteralPath $lfcBackupPath
        [pscustomobject]@{
            State = 'ORIGINAL_LFC_STATE_RESTORED'
            Current = $after
            BackupPresent = $false
        }
    }
}

[pscustomobject]@{
    ToolVersion = $toolVersion
    DriverInterface = 'DIRECT_D3DKMT_INTEL_PRIVATE_ESCAPE'
    IntelGpu = [string]$intelGpu.Name
    IntelDriverVersion = [string]$intelGpu.DriverVersion
    CurrentState = $current
    ManagedVrrMode = $managedModeName
    ExpectedRange = if ($null -eq $managedProfile) { 'UNMANAGED' } else { "$expectedMinimumHz-$expectedMaximumHz Hz" }
    PanelEdidSha256 = $reportedEdidSha256
    LfcTransition = $state
    StartupPersistence = Get-StartupPersistenceState
    LfcFixActive = $null -ne $managedProfile -and
        (Test-Path -LiteralPath $lfcBackupPath -PathType Leaf) -and
        (Get-StartupPersistenceState) -eq 'INSTALLED_ONE_SHOT_AT_LOGON' -and
        [int]$state.Current.MinimumHz -eq $expectedMinimumHz -and
        [int]$state.Current.MaximumHz -eq $expectedMaximumHz -and
        (-not [bool]$state.Current.LowFpsSolutionEnabled) -and
        (-not [bool]$state.Current.HighFpsSolutionEnabled)
}
