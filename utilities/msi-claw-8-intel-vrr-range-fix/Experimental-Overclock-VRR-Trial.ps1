[CmdletBinding()]
param(
    [ValidateSet('Schedule', 'Run')]
    [string]$Action = 'Schedule',
    [ValidateSet(
        'CLAWLAB_48_144', 'CLAWLAB_48_165', 'CLAWLAB_48_180',
        'CLAWLAB_30_144', 'CLAWLAB_30_165', 'CLAWLAB_30_180'
    )]
    [string]$Mode = 'CLAWLAB_48_144'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$fixVersion = '2.2.0'
$stateRoot = Join-Path $env:LOCALAPPDATA 'ClawLab\Intel-Arc-Sync-Full-Range'
$managedModePath = Join-Path $stateRoot 'managed-mode.json'
$customEdidStatePath = Join-Path $stateRoot 'experimental-edid.json'
$originalProfilePath = Join-Path $stateRoot 'original-profile.json'
$trialStatePath = Join-Path $stateRoot 'experimental-overclock-trial.json'
$protectedRuntimeRoot = Join-Path $env:ProgramData 'ClawLab-VRR-Privileged\2.2.0'
$installedTrialPath = Join-Path $protectedRuntimeRoot 'Experimental-Overclock-VRR-Trial.ps1'
$installedTrialLauncherPath = Join-Path $protectedRuntimeRoot 'ClawLab-Experimental-Trial-Startup.vbs'
$installedVrrToolPath = Join-Path $protectedRuntimeRoot 'MSI-Claw-VRR-Fix.ps1'
$installedLocalVrrToolPath = Join-Path $stateRoot 'MSI-Claw-VRR-Fix.ps1'
$installedLfcToolPath = Join-Path $protectedRuntimeRoot 'MSI-Claw-Intel-LFC-Fix.ps1'
$trialTaskName = 'ClawLab MSI Claw Experimental Overclock Trial'
$lfcBackupPath = Join-Path $env:LOCALAPPDATA 'ClawLab\Intel-LFC-Fix\original-intel-vrr-solutions.json'

$profiles = @{
    'CLAWLAB_48_144' = [pscustomobject]@{ MinimumHz = 48; MaximumHz = 144; Stability = 'STABLE_EXPERIMENTAL' }
    'CLAWLAB_48_165' = [pscustomobject]@{ MinimumHz = 48; MaximumHz = 165; Stability = 'UNSTABLE_EXPERIMENTAL' }
    'CLAWLAB_48_180' = [pscustomobject]@{ MinimumHz = 48; MaximumHz = 180; Stability = 'UNSTABLE_EXPERIMENTAL' }
    'CLAWLAB_30_144' = [pscustomobject]@{ MinimumHz = 30; MaximumHz = 144; Stability = 'UNSTABLE_EXPERIMENTAL' }
    'CLAWLAB_30_165' = [pscustomobject]@{ MinimumHz = 30; MaximumHz = 165; Stability = 'UNSTABLE_EXPERIMENTAL' }
    'CLAWLAB_30_180' = [pscustomobject]@{ MinimumHz = 30; MaximumHz = 180; Stability = 'UNSTABLE_EXPERIMENTAL' }
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Confirm-AdministratorOrRelaunch {
    if (Test-Administrator) { return }

    $arguments = @(
        '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $PSCommandPath),
        '-Action', $Action,
        '-Mode', $Mode
    ) -join ' '
    try {
        $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs -Wait -PassThru
    }
    catch {
        throw 'Administrator approval is required to register the guarded one-time trial task.'
    }
    exit $process.ExitCode
}

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$LiteralPath)

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        throw "Required guarded-trial state is missing: $LiteralPath"
    }
    return [IO.File]::ReadAllText($LiteralPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
}

function Copy-VerifiedFile {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "A guarded-trial component is missing: $Source"
    }
    if (-not [IO.Path]::GetFullPath($Source).Equals(
            [IO.Path]::GetFullPath($Destination),
            [StringComparison]::OrdinalIgnoreCase)) {
        [IO.File]::Copy($Source, $Destination, $true)
    }
    if ((Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash) {
        throw "Guarded-trial copy verification failed: $Destination"
    }
}

function New-ProtectedRuntimeAcl {
    $inheritance = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
        [Security.AccessControl.InheritanceFlags]::ObjectInherit
    $propagation = [Security.AccessControl.PropagationFlags]::None
    $allow = [Security.AccessControl.AccessControlType]::Allow
    $systemSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
    $administratorsSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
    $usersSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-545')
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true, $false)
    $acl.SetOwner($administratorsSid)
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
            $systemSid, [Security.AccessControl.FileSystemRights]::FullControl,
            $inheritance, $propagation, $allow))
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
            $administratorsSid, [Security.AccessControl.FileSystemRights]::FullControl,
            $inheritance, $propagation, $allow))
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
            $usersSid, [Security.AccessControl.FileSystemRights]::ReadAndExecute,
            $inheritance, $propagation, $allow))
    return $acl
}

function Initialize-ProtectedRuntimeDirectory {
    if (-not (Test-Administrator)) {
        throw 'Administrator rights are required to create the protected trial runtime.'
    }

    $programDataRoot = [IO.Path]::GetFullPath($env:ProgramData).TrimEnd('\')
    $runtimeRoot = [IO.Path]::GetFullPath($protectedRuntimeRoot).TrimEnd('\')
    if (-not $runtimeRoot.StartsWith(
            $programDataRoot + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe protected runtime path: $runtimeRoot"
    }
    $parentRoot = [IO.Path]::GetDirectoryName($runtimeRoot)
    if (Test-Path -LiteralPath $parentRoot) {
        $parentItem = Get-Item -LiteralPath $parentRoot -Force
        if (-not $parentItem.PSIsContainer -or
            ($parentItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "The protected runtime parent is not a normal directory: $parentRoot"
        }
    }
    else {
        [IO.Directory]::CreateDirectory($parentRoot) | Out-Null
    }
    # DirectorySecurity tracks which sections were modified and clears those
    # flags after persistence. Never reuse one instance for two paths: a fresh
    # child can otherwise retain inherited rules instead of receiving the
    # intended protected explicit DACL.
    ([IO.DirectoryInfo]$parentRoot).SetAccessControl((New-ProtectedRuntimeAcl))

    if (Test-Path -LiteralPath $runtimeRoot) {
        $runtimeItem = Get-Item -LiteralPath $runtimeRoot -Force
        if (-not $runtimeItem.PSIsContainer -or
            ($runtimeItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "The protected runtime path is not a normal directory: $runtimeRoot"
        }
    }
    else {
        [IO.Directory]::CreateDirectory($runtimeRoot) | Out-Null
    }
    ([IO.DirectoryInfo]$runtimeRoot).SetAccessControl((New-ProtectedRuntimeAcl))

    $writeRights =
        [Security.AccessControl.FileSystemRights]::WriteData -bor
        [Security.AccessControl.FileSystemRights]::AppendData -bor
        [Security.AccessControl.FileSystemRights]::WriteExtendedAttributes -bor
        [Security.AccessControl.FileSystemRights]::WriteAttributes -bor
        [Security.AccessControl.FileSystemRights]::Delete -bor
        [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
        [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
        [Security.AccessControl.FileSystemRights]::TakeOwnership
    $requiredReadRights = [Security.AccessControl.FileSystemRights]::ReadAndExecute
    $allow = [Security.AccessControl.AccessControlType]::Allow
    $systemSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
    $administratorsSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
    $usersSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-545')
    $allowedSids = @($systemSid.Value, $administratorsSid.Value, $usersSid.Value)
    foreach ($securedPath in @($parentRoot, $runtimeRoot)) {
        $verifiedAcl = ([IO.DirectoryInfo]$securedPath).GetAccessControl([Security.AccessControl.AccessControlSections]::Access)
        $rules = @($verifiedAcl.GetAccessRules($true, $false, [Security.Principal.SecurityIdentifier]))
        $usersAllowRights = [Security.AccessControl.FileSystemRights]0
        foreach ($rule in $rules) {
            if ($rule.IsInherited -or
                $rule.IdentityReference.Value -notin $allowedSids -or
                $rule.AccessControlType -ne $allow) {
                throw "The protected runtime ACL contains an unexpected rule: $securedPath"
            }
            if ($rule.IdentityReference.Value -eq $usersSid.Value) {
                $usersAllowRights = $usersAllowRights -bor $rule.FileSystemRights
                if (($rule.FileSystemRights -band $writeRights) -ne 0) {
                    throw 'The protected trial runtime unexpectedly grants write access to standard users.'
                }
            }
        }
        if (($usersAllowRights -band $requiredReadRights) -ne $requiredReadRights) {
            throw "The protected runtime ACL does not grant standard-user read access: $securedPath"
        }
    }
    return $runtimeRoot
}

function Write-ProtectedRuntimeManifest {
    param(
        [Parameter(Mandatory)][string]$RuntimeRoot,
        [Parameter(Mandatory)][string[]]$FileNames
    )

    $entries = foreach ($fileName in $FileNames) {
        $filePath = Join-Path $RuntimeRoot $fileName
        if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
            throw "Protected runtime payload is missing: $fileName"
        }
        [ordered]@{
            Name = $fileName
            Sha256 = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash
        }
    }
    $manifest = [ordered]@{
        SchemaVersion = 1
        FixVersion = $fixVersion
        CreatedAt = (Get-Date).ToString('o')
        Files = @($entries)
    }
    $manifestPath = Join-Path $RuntimeRoot 'protected-runtime.json'
    [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    $verified = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if ([int]$verified.SchemaVersion -ne 1 -or [string]$verified.FixVersion -ne $fixVersion -or
        @($verified.Files).Count -ne $FileNames.Count) {
        throw 'The protected runtime manifest failed readback verification.'
    }
}

function Assert-ProtectedRuntimeIntegrity {
    $manifestPath = Join-Path $protectedRuntimeRoot 'protected-runtime.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw 'The protected experimental runtime manifest is missing.'
    }
    $manifest = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $expectedFiles = @(
        'MSI-Claw-VRR-Fix.ps1',
        'Edid-Normalization.ps1',
        'ArcSync-Range-Policy.ps1',
        'ClawLab-VRR-Startup.vbs',
        'ClawLab-Cursor-Refresh-Helper.exe',
        'MSI-Claw-Intel-LFC-Fix.ps1',
        'Intel-VRR-LFC-Driver-Interface.ps1',
        'Lfc-Backup-Identity.ps1',
        'ClawLab-LFC-Startup.vbs',
        'Experimental-Overclock-VRR-Trial.ps1',
        'ClawLab-Experimental-Trial-Startup.vbs'
    )
    if ([int]$manifest.SchemaVersion -ne 1 -or [string]$manifest.FixVersion -ne $fixVersion -or
        @($manifest.Files).Count -ne $expectedFiles.Count) {
        throw 'The protected experimental runtime manifest has an invalid identity.'
    }
    foreach ($fileName in $expectedFiles) {
        $entry = @($manifest.Files | Where-Object { [string]$_.Name -ceq $fileName })
        $filePath = Join-Path $protectedRuntimeRoot $fileName
        if ($entry.Count -ne 1 -or [string]$entry[0].Sha256 -notmatch '^[A-F0-9]{64}$' -or
            -not (Test-Path -LiteralPath $filePath -PathType Leaf) -or
            (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash -cne [string]$entry[0].Sha256) {
            throw "Protected experimental runtime integrity failed for $fileName."
        }
    }
}

function Invoke-ToolAction {
    param(
        [Parameter(Mandatory)][string]$ToolPath,
        [Parameter(Mandatory)][string]$ToolAction,
        [int]$TimeoutSeconds = 0
    )

    $arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$ToolPath`" -Action $ToolAction"
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden -PassThru
    if ($TimeoutSeconds -gt 0) {
        $finished = $process.WaitForExit($TimeoutSeconds * 1000)
        if (-not $finished) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            try { $process.WaitForExit(3000) | Out-Null } catch {}
            throw "$ToolAction exceeded the guarded $TimeoutSeconds-second display-test window."
        }
    }
    else {
        $process.WaitForExit()
    }
    if ($process.ExitCode -ne 0) {
        throw "$ToolAction failed with exit code $($process.ExitCode)."
    }
}

function Set-TrialConfirmation {
    param([Parameter(Mandatory)][bool]$Confirmed)

    $trial = Read-JsonFile -LiteralPath $trialStatePath
    $trial.UserConfirmed = $Confirmed
    $temporaryPath = Join-Path $stateRoot ('.experimental-trial-{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText($temporaryPath, ($trial | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
        [IO.File]::Copy($temporaryPath, $trialStatePath, $true)
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            [IO.File]::Delete($temporaryPath)
        }
    }
}

function Remove-TrialArtifacts {
    $task = Get-ScheduledTask -TaskName $trialTaskName -ErrorAction SilentlyContinue
    if ($null -ne $task) {
        Unregister-ScheduledTask -TaskName $trialTaskName -Confirm:$false -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $trialStatePath -PathType Leaf) {
        [IO.File]::Delete($trialStatePath)
    }
}

function Show-Message {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Title,
        [int]$Flags = 0,
        [int]$TimeoutSeconds = 0
    )

    $shell = New-Object -ComObject WScript.Shell
    try {
        return $shell.Popup($Text, $TimeoutSeconds, $Title, $Flags)
    }
    finally {
        [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) | Out-Null
    }
}

function Restart-AfterTrial {
    Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\shutdown.exe') `
        -ArgumentList '/r /t 5 /c "ClawLab guarded VRR trial completed"' -WindowStyle Hidden
}

if ($Action -eq 'Schedule') {
    # Registration is elevated for reliability, but the registered task itself
    # deliberately runs at Limited privilege. A user-writable script is never
    # executed by Task Scheduler with administrator rights.
    Confirm-AdministratorOrRelaunch
    $profile = $profiles[$Mode]
    $managed = Read-JsonFile -LiteralPath $managedModePath
    $custom = Read-JsonFile -LiteralPath $customEdidStatePath
    [void](Read-JsonFile -LiteralPath $originalProfilePath)
    if ([string]$managed.Mode -ne $Mode -or
    [string]$custom.Mode -ne $Mode -or
        [string]$custom.FixVersion -ne $fixVersion -or
        [bool]$custom.RequiresGuardedTrial -ne $true -or
        [int]$custom.ExperimentalMinimumHz -ne [int]$profile.MinimumHz -or
        [int]$custom.MaximumHz -ne [int]$profile.MaximumHz -or
        [string]$custom.Classification -ne [string]$profile.Stability -or
        [string]::IsNullOrWhiteSpace([string]$custom.PanelKey) -or
        [string]::IsNullOrWhiteSpace([string]$custom.PhysicalEdidSha256) -or
        [string]::IsNullOrWhiteSpace([string]$custom.ExperimentalEdidSha256)) {
        throw 'The installed EDID, managed profile and guarded-trial request do not share one exact identity.'
    }

    [IO.Directory]::CreateDirectory($stateRoot) | Out-Null
    Copy-VerifiedFile -Source (Join-Path $PSScriptRoot 'MSI-Claw-VRR-Fix.ps1') `
        -Destination $installedLocalVrrToolPath

    $securedRuntimeRoot = Initialize-ProtectedRuntimeDirectory
    $protectedPayload = @(
            'MSI-Claw-VRR-Fix.ps1',
            'Edid-Normalization.ps1',
            'ArcSync-Range-Policy.ps1',
            'ClawLab-VRR-Startup.vbs',
            'ClawLab-Cursor-Refresh-Helper.exe',
            'MSI-Claw-Intel-LFC-Fix.ps1',
            'Intel-VRR-LFC-Driver-Interface.ps1',
            'Lfc-Backup-Identity.ps1',
            'ClawLab-LFC-Startup.vbs',
            'Experimental-Overclock-VRR-Trial.ps1',
            'ClawLab-Experimental-Trial-Startup.vbs'
        )
    foreach ($fileName in $protectedPayload) {
        Copy-VerifiedFile -Source (Join-Path $PSScriptRoot $fileName) `
            -Destination (Join-Path $securedRuntimeRoot $fileName)
    }
    Write-ProtectedRuntimeManifest -RuntimeRoot $securedRuntimeRoot -FileNames $protectedPayload

    $trial = [ordered]@{
        SchemaVersion = 1
        FixVersion = $fixVersion
        ScheduledAt = (Get-Date).ToString('o')
        Mode = $Mode
        MinimumHz = [int]$profile.MinimumHz
        MaximumHz = [int]$profile.MaximumHz
        Stability = [string]$profile.Stability
        PanelKey = [string]$custom.PanelKey
        PhysicalEdidSha256 = [string]$custom.PhysicalEdidSha256
        ExperimentalEdidSha256 = [string]$custom.ExperimentalEdidSha256
        ObservationSeconds = 15
        UserConfirmed = $false
    }
    [IO.File]::WriteAllText($trialStatePath, ($trial | ConvertTo-Json), [Text.UTF8Encoding]::new($false))

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $wscriptPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
    $taskAction = New-ScheduledTaskAction -Execute $wscriptPath `
        -Argument ("//B //Nologo `"$installedTrialLauncherPath`"")
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $identity.Name
    $trigger.Delay = 'PT10S'
    # Never execute a user-writable script as an elevated scheduled task. The
    # display-only trial runs with normal user rights. If the user later keeps
    # the profile, MSI-Claw-VRR-Fix.ps1 presents the standard UAC prompt for
    # the persistent machine-level installation.
    $principal = New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -MultipleInstances IgnoreNew
    $task = New-ScheduledTask -Action $taskAction -Trigger $trigger -Principal $principal -Settings $settings `
        -Description 'Runs one guarded MSI Claw display-overclock trial, restores 120 Hz after 15 seconds, and requires explicit confirmation.'
    Register-ScheduledTask -TaskName $trialTaskName -InputObject $task -Force | Out-Null
    if ($null -eq (Get-ScheduledTask -TaskName $trialTaskName -ErrorAction SilentlyContinue)) {
        throw 'The guarded overclock trial task could not be verified.'
    }

    Write-Host "Guarded $($profile.MinimumHz)-$($profile.MaximumHz) Hz trial scheduled." -ForegroundColor Yellow
    Write-Host 'Restart the PC. After sign-in, wait patiently if the screen flickers or goes black.' -ForegroundColor Yellow
    Write-Host 'The test returns to 120 Hz automatically after no more than 15 seconds.' -ForegroundColor Green
    return
}

# Run is launched once and interactively with normal user rights. Persistence
# still requires a separate, visible UAC approval after an explicit Yes answer.
Assert-ProtectedRuntimeIntegrity
$trial = Read-JsonFile -LiteralPath $trialStatePath
if ([string]$trial.FixVersion -ne $fixVersion -or -not $profiles.ContainsKey([string]$trial.Mode)) {
    throw 'The guarded trial state has an unsupported version or mode.'
}
$profile = $profiles[[string]$trial.Mode]
if ([int]$trial.MinimumHz -ne [int]$profile.MinimumHz -or
    [int]$trial.MaximumHz -ne [int]$profile.MaximumHz -or
    [string]$trial.Stability -ne [string]$profile.Stability -or
    [int]$trial.ObservationSeconds -ne 15) {
    throw 'The guarded trial state has unexpected range, classification or timing values.'
}
# A stale confirmation can exist only if Windows was interrupted between the
# user's Yes answer and final persistence. Never reuse it across task runs.
Set-TrialConfirmation -Confirmed $false
$trialSucceeded = $false
$rollbackReason = $null
try {
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    Invoke-ToolAction -ToolPath $installedVrrToolPath -ToolAction 'ApplyExperimentalTrial' -TimeoutSeconds 15
    $remaining = 15 - [int][Math]::Ceiling($stopwatch.Elapsed.TotalSeconds)
    if ($remaining -gt 0) { Start-Sleep -Seconds $remaining }
    $trialSucceeded = $true
}
catch {
    $rollbackReason = $_.Exception.Message
}
finally {
    try {
        Invoke-ToolAction -ToolPath $installedVrrToolPath -ToolAction 'SetSafe120ForTrial' -TimeoutSeconds 15
    }
    catch {
        if ([string]::IsNullOrWhiteSpace($rollbackReason)) {
            $rollbackReason = "Automatic 120 Hz safety restoration failed: $($_.Exception.Message)"
        }
        $trialSucceeded = $false
    }
}

if ($trialSucceeded) {
    $question = @"
The guarded $($profile.MinimumHz)-$($profile.MaximumHz) Hz display-overclock test is complete.

Windows has already returned to the safe 120 Hz mode.

Did the screen visibly reach $($profile.MaximumHz) Hz and remain stable, without persistent artifacts, flicker or signal loss?

Choose Yes only if the test was conclusively successful. No or no answer within 30 seconds restores the original VRR profile.
"@
    $answer = Show-Message -Text $question -Title 'ClawLab display-overclock confirmation' -Flags 0x24 -TimeoutSeconds 30
    if ($answer -eq 6) {
        try {
            Set-TrialConfirmation -Confirmed $true
            # Never force-kill a process that may be waiting on UAC: doing so
            # could detach its elevated child and race the rollback path.
            Invoke-ToolAction -ToolPath $installedVrrToolPath -ToolAction 'ConfirmExperimentalTrial'
            Remove-TrialArtifacts
            [void](Show-Message -Text "The $($profile.MinimumHz)-$($profile.MaximumHz) Hz profile and Intel LFC patch were verified and kept. Windows will restart now." `
                -Title 'ClawLab experimental profile kept' -Flags 0x40 -TimeoutSeconds 0)
            Restart-AfterTrial
            exit 0
        }
        catch {
            $rollbackReason = "Final verification failed: $($_.Exception.Message)"
        }
    }
    else {
        $rollbackReason = 'The user declined or did not confirm the display-overclock trial.'
    }
}

# Any failure, No, or prompt timeout restores the saved Intel/LFC state and
# removes the exact ClawLab EDID override. Fail closed if either restore fails.
$rollbackErrors = [Collections.Generic.List[string]]::new()
if (Test-Path -LiteralPath $lfcBackupPath -PathType Leaf) {
    # LFC restore does not elevate or spawn a privileged child. Keep it bounded
    # so a stuck driver call cannot prevent the subsequent VRR rollback.
    try { Invoke-ToolAction -ToolPath $installedLfcToolPath -ToolAction 'Restore' -TimeoutSeconds 30 }
    catch { $rollbackErrors.Add($_.Exception.Message) }
}
# Restore may also require UAC. Wait for its definitive result rather than
# timing out and risking a detached elevated restore racing the restart.
try { Invoke-ToolAction -ToolPath $installedVrrToolPath -ToolAction 'Restore' }
catch { $rollbackErrors.Add($_.Exception.Message) }
try { Remove-TrialArtifacts } catch { $rollbackErrors.Add($_.Exception.Message) }

$message = "The experimental profile was not kept. Reason: $rollbackReason"
if ($rollbackErrors.Count -gt 0) {
    $message += "`n`nRecovery reported: " + ($rollbackErrors -join ' | ') + "`n`nUse the RECOVERY folder after Windows restarts."
}
else {
    $message += "`n`nThe original VRR and Intel LFC states were restored. Windows will restart now."
}
[void](Show-Message -Text $message -Title 'ClawLab experimental profile restored' `
    -Flags $(if ($rollbackErrors.Count -gt 0) { 0x10 } else { 0x40 }) -TimeoutSeconds 0)
Restart-AfterTrial
exit $(if ($rollbackErrors.Count -gt 0) { 1 } else { 0 })
