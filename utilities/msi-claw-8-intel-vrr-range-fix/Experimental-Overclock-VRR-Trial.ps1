[CmdletBinding()]
param(
    [ValidateSet('Schedule', 'Run')]
    [string]$Action = 'Schedule',
    [ValidateSet(
        'CLAWLAB_48_144', 'CLAWLAB_48_165', 'CLAWLAB_48_180', 'CLAWLAB_48_192',
        'CLAWLAB_30_144', 'CLAWLAB_30_165', 'CLAWLAB_30_180', 'CLAWLAB_30_192'
    )]
    [string]$Mode = 'CLAWLAB_48_144',

    [switch]$LibraryOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$fixVersion = '2.3.0'
$stateRoot = Join-Path $env:LOCALAPPDATA 'ClawLab\Intel-Arc-Sync-Full-Range'
$managedModePath = Join-Path $stateRoot 'managed-mode.json'
$customEdidStatePath = Join-Path $stateRoot 'experimental-edid.json'
$originalProfilePath = Join-Path $stateRoot 'original-profile.json'
$trialStatePath = Join-Path $stateRoot 'experimental-overclock-trial.json'
$confirmationErrorPath = Join-Path $stateRoot 'experimental-confirmation-last-error.txt'
$protectedRuntimeRoot = Join-Path $env:ProgramData 'ClawLab-VRR-Privileged\2.3.0'
$installedTrialPath = Join-Path $protectedRuntimeRoot 'Experimental-Overclock-VRR-Trial.ps1'
$installedTrialLauncherPath = Join-Path $protectedRuntimeRoot 'ClawLab-Experimental-Trial-Startup.vbs'
$installedVrrToolPath = Join-Path $protectedRuntimeRoot 'MSI-Claw-VRR-Fix.ps1'
$installedLocalVrrToolPath = Join-Path $stateRoot 'MSI-Claw-VRR-Fix.ps1'
$installedLfcToolPath = Join-Path $protectedRuntimeRoot 'MSI-Claw-Intel-LFC-Fix.ps1'
$trialTaskName = 'ClawLab MSI Claw Experimental Overclock Trial'
$lfcTaskName = 'ClawLab MSI Claw Intel LFC Fix'
$lfcBackupPath = Join-Path $env:LOCALAPPDATA 'ClawLab\Intel-LFC-Fix\original-intel-vrr-solutions.json'
$windowsPowerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$scheduledTaskPersistenceModuleName = 'Scheduled-Task-Persistence.ps1'
$scheduledTaskPersistenceModulePath = Join-Path $PSScriptRoot $scheduledTaskPersistenceModuleName
$localizationModuleName = 'ClawLab-Localization.ps1'
$localizationModulePath = Join-Path $PSScriptRoot $localizationModuleName
$script:trialTransactionMutex = $null
$script:trialStartupMutex = $null
$trialObservationSeconds = 30
$trialReadyTimeoutSeconds = 120

if (-not (Test-Path -LiteralPath $windowsPowerShellPath -PathType Leaf)) {
    throw "The trusted Windows PowerShell host is missing: $windowsPowerShellPath"
}
if (-not (Test-Path -LiteralPath $scheduledTaskPersistenceModulePath -PathType Leaf)) {
    throw "The guarded-trial Task Scheduler module is missing: $scheduledTaskPersistenceModulePath"
}
. $scheduledTaskPersistenceModulePath
if (-not (Test-Path -LiteralPath $localizationModulePath -PathType Leaf)) {
    throw "The guarded-trial localization module is missing: $localizationModulePath"
}
. $localizationModulePath
[void](Initialize-ClawLabLocalization)

$profiles = @{
    'CLAWLAB_48_144' = [pscustomobject]@{ MinimumHz = 48; MaximumHz = 144; Stability = 'STABLE_EXPERIMENTAL' }
    'CLAWLAB_48_165' = [pscustomobject]@{ MinimumHz = 48; MaximumHz = 165; Stability = 'UNSTABLE_EXPERIMENTAL' }
    'CLAWLAB_48_180' = [pscustomobject]@{ MinimumHz = 48; MaximumHz = 180; Stability = 'UNSTABLE_EXPERIMENTAL' }
    'CLAWLAB_48_192' = [pscustomobject]@{ MinimumHz = 48; MaximumHz = 192; Stability = 'UNSTABLE_EXPERIMENTAL' }
    'CLAWLAB_30_144' = [pscustomobject]@{ MinimumHz = 30; MaximumHz = 144; Stability = 'UNSTABLE_EXPERIMENTAL' }
    'CLAWLAB_30_165' = [pscustomobject]@{ MinimumHz = 30; MaximumHz = 165; Stability = 'UNSTABLE_EXPERIMENTAL' }
    'CLAWLAB_30_180' = [pscustomobject]@{ MinimumHz = 30; MaximumHz = 180; Stability = 'UNSTABLE_EXPERIMENTAL' }
    'CLAWLAB_30_192' = [pscustomobject]@{ MinimumHz = 30; MaximumHz = 192; Stability = 'UNSTABLE_EXPERIMENTAL' }
}

function Get-TrialExecutionDisposition {
    param(
        [Parameter(Mandatory)][string]$LifecycleState,
        [Parameter(Mandatory)][bool]$AttemptConsumed
    )

    if ($LifecycleState -eq 'SCHEDULED' -and -not $AttemptConsumed) {
        return 'FIRST_ATTEMPT'
    }
    if ($LifecycleState -eq 'COMMIT_VERIFIED') {
        return 'COMMITTED_NO_REAPPLY'
    }
    return 'RECOVERY_ONLY'
}

function Get-TrialRollbackDisposition {
    param(
        [Parameter(Mandatory)][bool]$LfcBackupPresent,
        [Parameter(Mandatory)][bool]$LfcRestoreTombstonePresent,
        [Parameter(Mandatory)][bool]$LfcRestoreFinalizedPresent,
        [Parameter(Mandatory)][bool]$LfcFactoryFinalizedPresent,
        [Parameter(Mandatory)][bool]$FreshLfcProofValid
    )

    if ($LfcBackupPresent) {
        return 'PREPARE_LFC_THEN_VRR_THEN_COMMIT'
    }
    if ($LfcRestoreTombstonePresent) {
        return 'RESUME_COMMITTED_LFC_THEN_VRR_THEN_FINALIZE'
    }
    if ($LfcRestoreFinalizedPresent) {
        return 'VERIFY_FINALIZED_LFC_THEN_RESTORE_VRR'
    }
    if ($LfcFactoryFinalizedPresent) {
        return 'VERIFY_FACTORY_FINALIZED_LFC_THEN_RESTORE_VRR'
    }
    if ($FreshLfcProofValid) {
        return 'PROVE_FRESH_LFC_THEN_RESTORE_VRR'
    }
    return 'FAIL_CLOSED_LFC_DIVERGED'
}

function Enter-TrialTransactionLocks {
    $transaction = [Threading.Mutex]::new($false, 'Global\ClawLab.VRR.DisplayTransaction')
    $startup = $null
    $transactionAcquired = $false
    $startupAcquired = $false
    try {
        try { $transactionAcquired = $transaction.WaitOne(180000) }
        catch [Threading.AbandonedMutexException] { $transactionAcquired = $true }
        if (-not $transactionAcquired) {
            throw 'Another ClawLab VRR transaction did not finish within three minutes.'
        }

        # Lock ordering is global and deliberate: transaction, then startup.
        # The guarded trial keeps both until its commit or rollback is final.
        $startup = [Threading.Mutex]::new($false, 'Global\ClawLab.MSIClaw.VrrApplyStartup')
        try { $startupAcquired = $startup.WaitOne(180000) }
        catch [Threading.AbandonedMutexException] { $startupAcquired = $true }
        if (-not $startupAcquired) {
            throw 'Another ClawLab startup operation did not finish within three minutes.'
        }
        $script:trialTransactionMutex = $transaction
        $script:trialStartupMutex = $startup
    }
    catch {
        if ($startupAcquired -and $null -ne $startup) {
            try { $startup.ReleaseMutex() } catch {}
        }
        if ($transactionAcquired) {
            try { $transaction.ReleaseMutex() } catch {}
        }
        if ($null -ne $startup) { $startup.Dispose() }
        $transaction.Dispose()
        throw
    }
}

function Exit-TrialTransactionLocks {
    if ($null -ne $script:trialStartupMutex) {
        try { $script:trialStartupMutex.ReleaseMutex() }
        finally {
            $script:trialStartupMutex.Dispose()
            $script:trialStartupMutex = $null
        }
    }
    if ($null -ne $script:trialTransactionMutex) {
        try { $script:trialTransactionMutex.ReleaseMutex() }
        finally {
            $script:trialTransactionMutex.Dispose()
            $script:trialTransactionMutex = $null
        }
    }
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Confirm-AdministratorOrRelaunch {
    if (Test-Administrator) { return }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if ($null -eq $identity.User) {
        throw 'The guarded trial could not bind elevation to the current Windows SID.'
    }
    $encode = {
        param([string]$Value)
        [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))
    }
    $script64 = & $encode ([IO.Path]::GetFullPath($PSCommandPath))
    $sid64 = & $encode ([string]$identity.User.Value)
    $local64 = & $encode ([IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd('\'))
    $mode64 = & $encode $Mode
    $sessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId
    $command = @'
$ErrorActionPreference = 'Stop'
$decode = { param($value) [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($value)) }
$scriptPath = & $decode '__SCRIPT64__'
$expectedSid = & $decode '__SID64__'
$expectedLocal = & $decode '__LOCAL64__'
$mode = & $decode '__MODE64__'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$actualSid = if ($null -eq $identity.User) { '' } else { [string]$identity.User.Value }
$actualSession = [Diagnostics.Process]::GetCurrentProcess().SessionId
$actualLocal = [IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd('\')
$canonicalExpectedLocal = [IO.Path]::GetFullPath($expectedLocal).TrimEnd('\')
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -or
    -not $actualSid.Equals($expectedSid, [StringComparison]::OrdinalIgnoreCase) -or
    $actualSession -ne __SESSION__ -or
    -not $actualLocal.Equals($canonicalExpectedLocal, [StringComparison]::OrdinalIgnoreCase)) {
    exit 31
}
if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { exit 32 }
try {
    & $scriptPath -Action Schedule -Mode $mode
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 41
}
exit 0
'@
    $command = $command.Replace('__SCRIPT64__', $script64).
        Replace('__SID64__', $sid64).
        Replace('__LOCAL64__', $local64).
        Replace('__MODE64__', $mode64).
        Replace('__SESSION__', ([string]$sessionId))
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    try {
        $process = Start-Process -FilePath $windowsPowerShellPath -Verb RunAs `
            -ArgumentList @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded) `
            -Wait -PassThru
    }
    catch {
        throw 'Administrator approval is required to register the guarded one-time trial task.'
    }
    if ([int]$process.ExitCode -eq 31) {
        throw 'Administrator approval used a different Windows identity, session or LOCALAPPDATA; guarded trial registration was refused.'
    }
    exit $process.ExitCode
}

function Get-TrialTaskSpec {
    $wscriptPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
    New-ClawLabLogonTaskSpec -TaskName $trialTaskName -ExecutePath $wscriptPath `
        -Arguments ("//B //Nologo `"$installedTrialLauncherPath`"") `
        -Description 'Runs one user-started MSI Claw display-overclock trial with a visible 30-second observation, automatic safe-120 restoration and explicit confirmation.' `
        -ExecutionTimeLimitMinutes 5 -TriggerDelaySeconds 10
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
    $sourceItem = Get-Item -LiteralPath $Source -Force
    if (($sourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "A guarded-trial source component is a reparse point: $Source"
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

function Get-ProtectedRuntimePayload {
    return @(
        'MSI-Claw-VRR-Fix.ps1',
        'Edid-Normalization.ps1',
        'ArcSync-Range-Policy.ps1',
        'ClawLab-VRR-Startup.vbs',
        'ClawLab-Cursor-Refresh-Helper.exe',
        'MSI-Claw-Intel-LFC-Fix.ps1',
        'Intel-VRR-LFC-Driver-Interface.ps1',
        'Lfc-Backup-Identity.ps1',
        'ClawLab-LFC-Startup.vbs',
        'Scheduled-Task-Persistence.ps1',
        'ClawLab-Localization.ps1',
        'locales\messages.json',
        'Experimental-Overclock-VRR-Trial.ps1',
        'ClawLab-Experimental-Trial-Startup.vbs'
    )
}

function Assert-ProtectedRuntimeDirectoryAcl {
    param([Parameter(Mandatory)][string]$LiteralPath)

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
    # GetOwner() only returns a value when the Owner section was requested.
    # Loading Access alone produces a null owner on Windows and StrictMode then
    # reports the misleading "property Value was not found" scheduling error.
    $verifiedAcl = ([IO.DirectoryInfo]$LiteralPath).GetAccessControl(
        [Security.AccessControl.AccessControlSections]::Access -bor
        [Security.AccessControl.AccessControlSections]::Owner)
    $verifiedOwner = $verifiedAcl.GetOwner(
        [Security.Principal.SecurityIdentifier]).Value
    if (-not $verifiedAcl.AreAccessRulesProtected -or
        $verifiedOwner -ne $administratorsSid.Value) {
        throw "The protected runtime owner or inheritance boundary is invalid: $LiteralPath"
    }
    $rules = @($verifiedAcl.GetAccessRules(
            $true, $false, [Security.Principal.SecurityIdentifier]))
    $usersAllowRights = [Security.AccessControl.FileSystemRights]0
    $systemAllowRights = [Security.AccessControl.FileSystemRights]0
    $administratorsAllowRights = [Security.AccessControl.FileSystemRights]0
    foreach ($rule in $rules) {
        if ($rule.IsInherited -or
            $rule.IdentityReference.Value -notin $allowedSids -or
            $rule.AccessControlType -ne $allow) {
            throw "The protected runtime ACL contains an unexpected rule: $LiteralPath"
        }
        if ($rule.IdentityReference.Value -eq $usersSid.Value) {
            $usersAllowRights = $usersAllowRights -bor $rule.FileSystemRights
            if (($rule.FileSystemRights -band $writeRights) -ne 0) {
                throw 'The protected trial runtime unexpectedly grants write access to standard users.'
            }
        }
        elseif ($rule.IdentityReference.Value -eq $systemSid.Value) {
            $systemAllowRights = $systemAllowRights -bor $rule.FileSystemRights
        }
        elseif ($rule.IdentityReference.Value -eq $administratorsSid.Value) {
            $administratorsAllowRights = $administratorsAllowRights -bor $rule.FileSystemRights
        }
    }
    if (($usersAllowRights -band $requiredReadRights) -ne $requiredReadRights) {
        throw "The protected runtime ACL does not grant standard-user read access: $LiteralPath"
    }
    $fullControl = [Security.AccessControl.FileSystemRights]::FullControl
    if (($systemAllowRights -band $fullControl) -ne $fullControl -or
        ($administratorsAllowRights -band $fullControl) -ne $fullControl) {
        throw "The protected runtime ACL does not retain SYSTEM/Administrators full control: $LiteralPath"
    }
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
    Assert-ProtectedRuntimeDirectoryAcl -LiteralPath $parentRoot

    if (Test-Path -LiteralPath $runtimeRoot) {
        $runtimeItem = Get-Item -LiteralPath $runtimeRoot -Force
        if (-not $runtimeItem.PSIsContainer -or
            ($runtimeItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "The protected runtime path is not a normal directory: $runtimeRoot"
        }
        $existingEntries = @([IO.Directory]::EnumerateFileSystemEntries($runtimeRoot))
        if ($existingEntries.Count -ne 0) {
            throw 'The final protected runtime already exists and is not empty. ClawLab refused to trust or overwrite it.'
        }
        # Atomic publication requires the final name to be absent. Only a
        # verified empty, non-reparse directory may be removed here.
        [IO.Directory]::Delete($runtimeRoot, $false)
    }

    $stagingRoot = Join-Path $parentRoot ('.staging-' + [Guid]::NewGuid().ToString('N'))
    if (Test-Path -LiteralPath $stagingRoot) {
        throw "The fresh protected-runtime staging path unexpectedly exists: $stagingRoot"
    }
    [IO.Directory]::CreateDirectory($stagingRoot) | Out-Null
    $stagingItem = Get-Item -LiteralPath $stagingRoot -Force
    if (-not $stagingItem.PSIsContainer -or
        ($stagingItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "The protected-runtime staging path is not a normal directory: $stagingRoot"
    }
    ([IO.DirectoryInfo]$stagingRoot).SetAccessControl((New-ProtectedRuntimeAcl))
    Assert-ProtectedRuntimeDirectoryAcl -LiteralPath $stagingRoot
    return $stagingRoot
}

function Get-ProtectedRuntimeStagingDestination {
    param(
        [Parameter(Mandatory)][string]$StagingRoot,
        [Parameter(Mandatory)][string]$RelativeFileName
    )

    if ([IO.Path]::IsPathRooted($RelativeFileName)) {
        throw "A protected payload path is rooted: $RelativeFileName"
    }
    $segments = @($RelativeFileName -split '[\\/]')
    if ($segments.Count -lt 1 -or @($segments | Where-Object {
                [string]::IsNullOrWhiteSpace($_) -or $_ -in @('.', '..')
            }).Count -gt 0) {
        throw "A protected payload path is unsafe: $RelativeFileName"
    }

    $canonicalRoot = [IO.Path]::GetFullPath($StagingRoot).TrimEnd('\')
    $current = $canonicalRoot
    for ($index = 0; $index -lt ($segments.Count - 1); $index++) {
        $current = [IO.Path]::GetFullPath((Join-Path $current $segments[$index]))
        if (-not $current.StartsWith(
                $canonicalRoot + [IO.Path]::DirectorySeparatorChar,
                [StringComparison]::OrdinalIgnoreCase)) {
            throw "A protected payload directory escaped staging: $RelativeFileName"
        }
        if (-not (Test-Path -LiteralPath $current)) {
            [IO.Directory]::CreateDirectory($current) | Out-Null
        }
        $directory = Get-Item -LiteralPath $current -Force
        if (-not $directory.PSIsContainer -or
            ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "A protected payload directory is not a normal directory: $current"
        }
    }

    $destination = [IO.Path]::GetFullPath((Join-Path $current $segments[-1]))
    if (-not $destination.StartsWith(
            $canonicalRoot + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase) -or
        (Test-Path -LiteralPath $destination)) {
        throw "A protected payload destination is unsafe or already exists: $destination"
    }
    return $destination
}

function Assert-ProtectedRuntimeTree {
    param(
        [Parameter(Mandatory)][string]$RuntimeRoot,
        [Parameter(Mandatory)][string[]]$FileNames
    )

    $canonicalRoot = [IO.Path]::GetFullPath($RuntimeRoot).TrimEnd('\')
    $prefix = $canonicalRoot + [IO.Path]::DirectorySeparatorChar
    $expectedFiles = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $expectedDirectories = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($fileName in @($FileNames) + @('protected-runtime.json')) {
        [void]$expectedFiles.Add($fileName.Replace('/', '\'))
        $parent = Split-Path $fileName -Parent
        while (-not [string]::IsNullOrWhiteSpace($parent)) {
            [void]$expectedDirectories.Add($parent.Replace('/', '\'))
            $parent = Split-Path $parent -Parent
        }
    }

    $actualFileCount = 0
    foreach ($entry in @(Get-ChildItem -LiteralPath $canonicalRoot -Force -Recurse)) {
        $fullName = [IO.Path]::GetFullPath($entry.FullName)
        if (-not $fullName.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or
            ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "The protected runtime tree contains an unsafe entry: $fullName"
        }
        $relative = $fullName.Substring($prefix.Length)
        if ($entry.PSIsContainer) {
            if (-not $expectedDirectories.Contains($relative)) {
                throw "The protected runtime contains an unexpected directory: $relative"
            }
        }
        else {
            $actualFileCount++
            if (-not $expectedFiles.Contains($relative)) {
                throw "The protected runtime contains an unexpected file: $relative"
            }
        }
    }
    if ($actualFileCount -ne $expectedFiles.Count) {
        throw 'The protected runtime tree is incomplete.'
    }
}

function Publish-ProtectedRuntimeStaging {
    param(
        [Parameter(Mandatory)][string]$StagingRoot,
        [Parameter(Mandatory)][string[]]$FileNames
    )

    Assert-ProtectedRuntimeTree -RuntimeRoot $StagingRoot -FileNames $FileNames
    if (Test-Path -LiteralPath $protectedRuntimeRoot) {
        throw 'The final protected runtime appeared during staging; atomic publication was refused.'
    }
    [IO.Directory]::Move(
        [IO.Path]::GetFullPath($StagingRoot),
        [IO.Path]::GetFullPath($protectedRuntimeRoot))
    Assert-ProtectedRuntimeDirectoryAcl -LiteralPath $protectedRuntimeRoot
    Assert-ProtectedRuntimeTree -RuntimeRoot $protectedRuntimeRoot -FileNames $FileNames
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
    if (Test-Path -LiteralPath $manifestPath) {
        throw 'The protected runtime manifest destination already exists.'
    }
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
    $expectedFiles = @(Get-ProtectedRuntimePayload)
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
    Assert-ProtectedRuntimeTree -RuntimeRoot $protectedRuntimeRoot -FileNames $expectedFiles
}

function Invoke-ToolAction {
    param(
        [Parameter(Mandatory)][string]$ToolPath,
        [Parameter(Mandatory)][string]$ToolAction,
        [int]$TimeoutSeconds = 0
    )

    $arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$ToolPath`" -Action $ToolAction"
    $process = Start-Process -FilePath $windowsPowerShellPath -ArgumentList $arguments -WindowStyle Hidden -PassThru
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

function ConvertTo-TrialUtf8Base64 {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))
}

function Invoke-BoundElevatedTrialConfirmation {
    param(
        [Parameter(Mandatory)][object]$Trial,
        [Parameter(Mandatory)][int]$ExpectedSessionId
    )

    $path64 = ConvertTo-TrialUtf8Base64 -Value ([IO.Path]::GetFullPath($installedVrrToolPath))
    $sid64 = ConvertTo-TrialUtf8Base64 -Value ([string]$Trial.OwnerSid)
    $local64 = ConvertTo-TrialUtf8Base64 -Value ([string]$Trial.OwnerLocalAppData)
    $error64 = ConvertTo-TrialUtf8Base64 -Value ([IO.Path]::GetFullPath($confirmationErrorPath))
    if (Test-Path -LiteralPath $confirmationErrorPath -PathType Leaf) {
        [IO.File]::Delete($confirmationErrorPath)
    }
    $command = @'
$ErrorActionPreference = 'Stop'
$decode = { param($value) [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($value)) }
$toolPath = & $decode '__PATH64__'
$expectedSid = & $decode '__SID64__'
$expectedLocal = & $decode '__LOCAL64__'
$confirmationErrorPath = & $decode '__ERROR64__'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$actualSid = if ($null -eq $identity.User) { '' } else { [string]$identity.User.Value }
$actualSession = [Diagnostics.Process]::GetCurrentProcess().SessionId
$actualLocal = [IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd('\')
$canonicalExpectedLocal = [IO.Path]::GetFullPath($expectedLocal).TrimEnd('\')
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -or
    -not $actualSid.Equals($expectedSid, [StringComparison]::OrdinalIgnoreCase) -or
    $actualSession -ne __SESSION__ -or
    -not $actualLocal.Equals($canonicalExpectedLocal, [StringComparison]::OrdinalIgnoreCase)) {
    exit 31
}
if (-not (Test-Path -LiteralPath $toolPath -PathType Leaf)) { exit 32 }
try {
    $global:LASTEXITCODE = 0
    & $toolPath -Action ConfirmExperimentalTrial | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "The protected confirmation core returned exit code $LASTEXITCODE."
    }
}
catch {
    $details = $_.Exception.Message
    $toolErrorPath = Join-Path $expectedLocal 'ClawLab\Intel-Arc-Sync-Full-Range\last-error.txt'
    if (Test-Path -LiteralPath $toolErrorPath -PathType Leaf) {
        try {
            $toolDetails = [IO.File]::ReadAllText($toolErrorPath, [Text.Encoding]::UTF8).Trim()
            if (-not [string]::IsNullOrWhiteSpace($toolDetails)) { $details = $toolDetails }
        }
        catch {}
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$_.ScriptStackTrace)) {
        $details += "`r`nScriptStackTrace: $($_.ScriptStackTrace)"
    }
    try {
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($confirmationErrorPath)) | Out-Null
        [IO.File]::WriteAllText($confirmationErrorPath, $details, [Text.UTF8Encoding]::new($false))
    }
    catch {}
    [Console]::Error.WriteLine($details)
    exit 41
}
exit 0
'@
    $command = $command.Replace('__PATH64__', $path64).
        Replace('__SID64__', $sid64).
        Replace('__LOCAL64__', $local64).
        Replace('__ERROR64__', $error64).
        Replace('__SESSION__', ([string]$ExpectedSessionId))
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    try {
        $process = Start-Process -FilePath $windowsPowerShellPath -Verb RunAs `
            -ArgumentList @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded) `
            -Wait -PassThru
    }
    catch {
        throw 'The bound administrator confirmation was cancelled or could not start.'
    }
    if ([int]$process.ExitCode -eq 31) {
        throw 'The administrator confirmation identity, session or LOCALAPPDATA did not match the guarded trial owner.'
    }
    if ([int]$process.ExitCode -ne 0) {
        $details = $null
        if (Test-Path -LiteralPath $confirmationErrorPath -PathType Leaf) {
            try { $details = [IO.File]::ReadAllText($confirmationErrorPath, [Text.Encoding]::UTF8).Trim() }
            catch {}
        }
        if ([string]::IsNullOrWhiteSpace([string]$details)) {
            throw "The bound administrator confirmation failed with exit code $($process.ExitCode)."
        }
        throw "The bound administrator confirmation failed with exit code $($process.ExitCode): $details"
    }
    if (Test-Path -LiteralPath $confirmationErrorPath -PathType Leaf) {
        [IO.File]::Delete($confirmationErrorPath)
    }
}

function Invoke-BoundElevatedTrialRollback {
    param(
        [Parameter(Mandatory)][object]$Trial,
        [Parameter(Mandatory)][int]$ExpectedSessionId,
        [Parameter(Mandatory)][ValidateSet('Fresh', 'Prepare', 'Resume')]
        [string]$LfcRollbackPhase
    )

    $vrrPath64 = ConvertTo-TrialUtf8Base64 -Value ([IO.Path]::GetFullPath($installedVrrToolPath))
    $lfcPath64 = ConvertTo-TrialUtf8Base64 -Value ([IO.Path]::GetFullPath($installedLfcToolPath))
    $sid64 = ConvertTo-TrialUtf8Base64 -Value ([string]$Trial.OwnerSid)
    $local64 = ConvertTo-TrialUtf8Base64 -Value ([string]$Trial.OwnerLocalAppData)
    $command = @'
$ErrorActionPreference = 'Stop'
$decode = { param($value) [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($value)) }
$vrrToolPath = & $decode '__VRR_PATH64__'
$lfcToolPath = & $decode '__LFC_PATH64__'
$expectedSid = & $decode '__SID64__'
$expectedLocal = & $decode '__LOCAL64__'
$lfcRollbackPhase = '__LFC_PHASE__'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$actualSid = if ($null -eq $identity.User) { '' } else { [string]$identity.User.Value }
$actualSession = [Diagnostics.Process]::GetCurrentProcess().SessionId
$actualLocal = [IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd('\')
$canonicalExpectedLocal = [IO.Path]::GetFullPath($expectedLocal).TrimEnd('\')
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -or
    -not $actualSid.Equals($expectedSid, [StringComparison]::OrdinalIgnoreCase) -or
    $actualSession -ne __SESSION__ -or
    -not $actualLocal.Equals($canonicalExpectedLocal, [StringComparison]::OrdinalIgnoreCase)) {
    exit 31
}
if (-not (Test-Path -LiteralPath $vrrToolPath -PathType Leaf)) { exit 32 }
if ($lfcRollbackPhase -ne 'Fresh' -and -not (Test-Path -LiteralPath $lfcToolPath -PathType Leaf)) { exit 33 }
try {
    if ($lfcRollbackPhase -eq 'Prepare') {
        $prepareResults = @(& $lfcToolPath -Action PrepareRestore)
        $prepareResult = if ($prepareResults.Count -gt 0) { $prepareResults[-1] } else { $null }
        if ($null -eq $prepareResult -or
            [string]$prepareResult.LfcTransition.State -ne 'ORIGINAL_LFC_STATE_PREPARED_BACKUP_RETAINED' -or
            -not [bool]$prepareResult.LfcTransition.BackupPresent) {
            throw 'The bound Intel LFC restore preparation did not verify.'
        }
    }
    if ($lfcRollbackPhase -eq 'Fresh') {
        & $vrrToolPath -Action Restore | Out-Null
    }
    else {
        & $vrrToolPath -Action RestoreGuardedTrial | Out-Null
    }
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 41
}
exit 0
'@
    $command = $command.Replace('__VRR_PATH64__', $vrrPath64).
        Replace('__LFC_PATH64__', $lfcPath64).
        Replace('__SID64__', $sid64).
        Replace('__LOCAL64__', $local64).
        Replace('__SESSION__', ([string]$ExpectedSessionId)).
        Replace('__LFC_PHASE__', $LfcRollbackPhase)
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    try {
        $process = Start-Process -FilePath $windowsPowerShellPath -Verb RunAs `
            -ArgumentList @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded) `
            -Wait -PassThru
    }
    catch {
        throw 'The bound administrator rollback was cancelled or could not start.'
    }
    if ([int]$process.ExitCode -eq 31) {
        throw 'The administrator rollback identity, session or LOCALAPPDATA did not match the guarded trial owner.'
    }
    if ([int]$process.ExitCode -ne 0) {
        throw "The bound administrator rollback failed with exit code $($process.ExitCode)."
    }
}

function Get-LfcStatusObject {
    param([string]$ToolPath = $installedLfcToolPath)

    if (-not (Test-Path -LiteralPath $ToolPath -PathType Leaf)) {
        throw 'The protected Intel LFC status component is missing.'
    }
    $results = @(& $ToolPath -Action Status)
    if ($results.Count -lt 1 -or $null -eq $results[-1]) {
        throw 'The protected Intel LFC status component returned no verifiable state.'
    }
    return $results[-1]
}

function New-PreTrialLfcSnapshot {
    param([Parameter(Mandatory)][object]$Status)

    $current = $Status.CurrentState
    if ($null -eq $current -or [string]$current.Result -ne 'Success') {
        throw 'The guarded trial could not read the direct Intel LFC state.'
    }
    $task = Get-ClawLabScheduledTaskRecord -TaskName $lfcTaskName
    return [ordered]@{
        SchemaVersion = 1
        CapturedAt = (Get-Date).ToString('o')
        DriverInterface = [string]$Status.DriverInterface
        IntelGpu = [string]$Status.IntelGpu
        IntelDriverVersion = [string]$Status.IntelDriverVersion
        PanelEdidSha256 = [string]$Status.PanelEdidSha256
        ManagedVrrMode = [string]$Status.ManagedVrrMode
        ExpectedRange = [string]$Status.ExpectedRange
        StartupPersistence = [string]$Status.StartupPersistence
        LfcFixActive = [bool]$Status.LfcFixActive
        TransitionState = [string]$Status.LfcTransition.State
        BackupPresent = [bool]$Status.LfcTransition.BackupPresent
        BackupFilePresent = [bool](Test-Path -LiteralPath $lfcBackupPath -PathType Leaf)
        RestoreTombstonePresent = [bool]$Status.LfcTransition.RestoreTombstonePresent
        RestoreFinalizedPresent = [bool]$Status.LfcTransition.RestoreFinalizedPresent
        RestoreFinalizedVerified = [bool]$Status.LfcTransition.RestoreFinalizedVerified
        FactoryIntentPresent = [bool]$Status.LfcTransition.FactoryIntentPresent
        FactoryFinalizedPresent = [bool]$Status.LfcTransition.FactoryFinalizedPresent
        FactoryFinalizedVerified = [bool]$Status.LfcTransition.FactoryFinalizedVerified
        TaskInstalled = [bool]($null -ne $task)
        CurrentResult = [string]$current.Result
        Supported = [bool]$current.Supported
        MinimumHz = [int]$current.MinimumHz
        MaximumHz = [int]$current.MaximumHz
        VrrEnabled = [bool]$current.VrrEnabled
        LowFpsSolutionEnabled = [bool]$current.LowFpsSolutionEnabled
        HighFpsSolutionEnabled = [bool]$current.HighFpsSolutionEnabled
        TargetId = [uint32]$current.TargetId
        DisplayDeviceName = [string]$current.DisplayDeviceName
    }
}

function Assert-FreshPreTrialLfcState {
    param(
        [Parameter(Mandatory)][object]$Snapshot,
        [Parameter(Mandatory)][string]$ExpectedManagedMode,
        [Parameter(Mandatory)][int]$ExpectedMinimumHz,
        [Parameter(Mandatory)][int]$ExpectedMaximumHz
    )

    $failures = [Collections.Generic.List[string]]::new()
    if ([string]$Snapshot.ManagedVrrMode -ne $ExpectedManagedMode) { $failures.Add('ManagedVrrMode does not match the guarded profile.') }
    if ([string]$Snapshot.ExpectedRange -ne "$ExpectedMinimumHz-$ExpectedMaximumHz Hz") { $failures.Add('ExpectedRange does not match the guarded profile.') }
    if ([string]$Snapshot.StartupPersistence -ne 'NOT_INSTALLED') { $failures.Add('LFC startup persistence is installed.') }
    if ([bool]$Snapshot.LfcFixActive) { $failures.Add('The Intel LFC correction is already active.') }
    if ([bool]$Snapshot.BackupPresent -or [bool]$Snapshot.BackupFilePresent) { $failures.Add('An Intel LFC backup is present.') }
    if ([bool]$Snapshot.TaskInstalled) { $failures.Add('The Intel LFC startup task is installed.') }
    if ([string]$Snapshot.CurrentResult -ne 'Success') { $failures.Add('The direct Intel LFC read failed.') }
    if ([bool]$Snapshot.RestoreTombstonePresent) { $failures.Add('An Intel LFC restore transaction is still pending finalization.') }
    if ([bool]$Snapshot.FactoryIntentPresent) { $failures.Add('An Intel LFC factory-default transaction is still pending.') }

    $terminalMarkerCount = @(
        [bool]$Snapshot.RestoreFinalizedPresent,
        [bool]$Snapshot.FactoryFinalizedPresent
    ) | Where-Object { $_ }
    if (@($terminalMarkerCount).Count -gt 1) {
        $failures.Add('Multiple mutually exclusive Intel LFC terminal provenance markers are present.')
    }

    $baselineDisposition = 'INVALID'
    if ([string]$Snapshot.TransitionState -eq 'INTEL_VRR_SOLUTIONS_NOT_PATCHED' -and
        -not [bool]$Snapshot.RestoreFinalizedPresent -and
        -not [bool]$Snapshot.FactoryFinalizedPresent -and
        [bool]$Snapshot.LowFpsSolutionEnabled -and
        [bool]$Snapshot.HighFpsSolutionEnabled) {
        $baselineDisposition = 'CLEAN_NO_BACKUP'
    }
    elseif ([string]$Snapshot.TransitionState -eq 'ORIGINAL_LFC_RESTORE_FINALIZED' -and
        [bool]$Snapshot.RestoreFinalizedPresent -and
        [bool]$Snapshot.RestoreFinalizedVerified -and
        -not [bool]$Snapshot.FactoryFinalizedPresent) {
        # A normal Restore may legitimately restore either Intel solution flag
        # to false. The LFC status component has already verified this durable
        # provenance against the exact current driver/panel/EDID state.
        $baselineDisposition = 'VERIFIED_RESTORE_FINALIZED_NO_BACKUP'
    }
    elseif ([string]$Snapshot.TransitionState -eq 'INTEL_VRR_SOLUTIONS_FACTORY_DEFAULTS_FINALIZED' -and
        [bool]$Snapshot.FactoryFinalizedPresent -and
        [bool]$Snapshot.FactoryFinalizedVerified -and
        -not [bool]$Snapshot.RestoreFinalizedPresent -and
        [bool]$Snapshot.LowFpsSolutionEnabled -and
        [bool]$Snapshot.HighFpsSolutionEnabled) {
        $baselineDisposition = 'VERIFIED_FACTORY_FINALIZED_NO_BACKUP'
    }
    else {
        $failures.Add('The Intel LFC transition has no verified clean or finalized-original provenance.')
    }
    if ($failures.Count -gt 0) {
        throw ('A fresh guarded trial requires an unchanged, unpatched Intel LFC baseline: ' + ($failures -join ' | '))
    }
    return $baselineDisposition
}

function Assert-FreshLfcStillUnchanged {
    param(
        [Parameter(Mandatory)][object]$Trial,
        [Parameter(Mandatory)][object]$Status
    )

    if ($null -eq $Trial.PreTrialLfc -or
        [string]$Trial.PreTrialLfcDisposition -ne 'CLEAN_NO_BACKUP') {
        throw 'The fresh guarded trial has no exact pre-trial Intel LFC proof.'
    }
    $before = $Trial.PreTrialLfc
    $current = New-PreTrialLfcSnapshot -Status $Status
    try {
        [void](Assert-FreshPreTrialLfcState -Snapshot $current `
            -ExpectedManagedMode ([string]$Trial.Mode) `
            -ExpectedMinimumHz ([int]$Trial.MinimumHz) `
            -ExpectedMaximumHz ([int]$Trial.MaximumHz))
    }
    catch {
        throw ('Intel LFC changed without a restorable backup; rollback stopped before VRR restore: ' +
            $_.Exception.Message)
    }

    $failures = [Collections.Generic.List[string]]::new()
    foreach ($property in @(
            'DriverInterface', 'IntelGpu', 'IntelDriverVersion',
            'CurrentResult', 'Supported', 'VrrEnabled',
            'LowFpsSolutionEnabled', 'HighFpsSolutionEnabled',
            'TargetId', 'DisplayDeviceName'
        )) {
        if ([string]$current.$property -cne [string]$before.$property) {
            $failures.Add("Direct Intel LFC identity/flag drifted: $property.")
        }
    }

    # The guarded Arc Sync profile deliberately changes the active range; it
    # must be either the exact pre-trial pair or this trial's exact pair. No
    # mixed or third range is accepted as an unchanged LFC baseline.
    $rangeIsOriginal = [int]$current.MinimumHz -eq [int]$before.MinimumHz -and
        [int]$current.MaximumHz -eq [int]$before.MaximumHz
    $rangeIsTrial = [int]$current.MinimumHz -eq [int]$Trial.MinimumHz -and
        [int]$current.MaximumHz -eq [int]$Trial.MaximumHz
    if (-not $rangeIsOriginal -and -not $rangeIsTrial) {
        $failures.Add("Direct Intel range drifted to $($current.MinimumHz)-$($current.MaximumHz) Hz.")
    }

    $allowedPanelHashes = @(
        [string]$before.PanelEdidSha256,
        [string]$Trial.PhysicalEdidSha256,
        [string]$Trial.ExperimentalEdidSha256
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
    if ([string]$current.PanelEdidSha256 -notin $allowedPanelHashes) {
        $failures.Add('The active panel EDID identity no longer belongs to the guarded trial.')
    }
    if ($failures.Count -gt 0) {
        throw ('Intel LFC changed without a restorable backup; rollback stopped before VRR restore: ' + ($failures -join ' | '))
    }
}

function Write-TrialStateAtomic {
    param([Parameter(Mandatory)][object]$Trial)

    [IO.Directory]::CreateDirectory($stateRoot) | Out-Null
    if (Test-Path -LiteralPath $confirmationErrorPath -PathType Leaf) {
        [IO.File]::Delete($confirmationErrorPath)
    }
    $temporaryPath = Join-Path $stateRoot ('.experimental-trial-{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
    $rollbackPath = Join-Path $stateRoot ('.experimental-trial-previous-{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText($temporaryPath, ($Trial | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $trialStatePath -PathType Leaf) {
            [IO.File]::Replace($temporaryPath, $trialStatePath, $rollbackPath, $true)
        }
        else {
            [IO.File]::Move($temporaryPath, $trialStatePath)
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            [IO.File]::Delete($temporaryPath)
        }
        if (Test-Path -LiteralPath $rollbackPath -PathType Leaf) {
            [IO.File]::Delete($rollbackPath)
        }
    }
}

function Set-TrialConfirmation {
    param([Parameter(Mandatory)][bool]$Confirmed)

    $trial = Read-JsonFile -LiteralPath $trialStatePath
    $trial.UserConfirmed = $Confirmed
    Write-TrialStateAtomic -Trial $trial
}

function Set-TrialLifecycleState {
    param(
        [Parameter(Mandatory)][object]$Trial,
        [Parameter(Mandatory)][ValidateSet(
            'SCHEDULED', 'RUNNING', 'ATTEMPT_CONSUMED',
            'AWAITING_CONFIRMATION', 'CONFIRMING', 'PERSISTENCE_APPLIED',
            'COMMIT_VERIFIED', 'RECOVERY_REQUIRED'
        )][string]$LifecycleState
    )

    $Trial | Add-Member -NotePropertyName LifecycleState -NotePropertyValue $LifecycleState -Force
    $Trial | Add-Member -NotePropertyName LifecycleUpdatedAt `
        -NotePropertyValue (Get-Date).ToString('o') -Force
    Write-TrialStateAtomic -Trial $Trial
}

function Consume-TrialAttemptAndTask {
    param([Parameter(Mandatory)][object]$Trial)

    if ((Get-TrialExecutionDisposition -LifecycleState ([string]$Trial.LifecycleState) `
            -AttemptConsumed ([bool]$Trial.AttemptConsumed)) -ne 'FIRST_ATTEMPT') {
        throw 'The guarded display-overclock attempt was already consumed.'
    }

    # The durable state transition is committed before the overclock can be
    # applied. A power loss from this point can only enter the recovery path.
    $Trial | Add-Member -NotePropertyName AttemptConsumed -NotePropertyValue $true -Force
    $Trial | Add-Member -NotePropertyName AttemptStartedAt `
        -NotePropertyValue (Get-Date).ToString('o') -Force
    $Trial | Add-Member -NotePropertyName TaskConsumed -NotePropertyValue $false -Force
    Set-TrialLifecycleState -Trial $Trial -LifecycleState 'RUNNING'

    # Keep the already-running AtLogOn definition only as a power-loss
    # recovery watchdog. The atomic AttemptConsumed state above makes every
    # later invocation recovery-only; it can never reapply the overclock.
    $taskRecord = Get-ClawLabScheduledTaskRecord -TaskName $trialTaskName
    if ($null -eq $taskRecord -or
        -not [bool](Test-ClawLabScheduledTaskRecord -Record $taskRecord `
                -Spec (Get-TrialTaskSpec)).Valid) {
        throw 'The one-time guarded trial task could not be verified before consumption.'
    }
    $Trial | Add-Member -NotePropertyName TaskConsumed -NotePropertyValue $true -Force
    $Trial | Add-Member -NotePropertyName TaskConsumedAt `
        -NotePropertyValue (Get-Date).ToString('o') -Force
    Set-TrialLifecycleState -Trial $Trial -LifecycleState 'ATTEMPT_CONSUMED'
    return $Trial
}

function Set-TrialRecoveryRequired {
    param(
        [Parameter(Mandatory)][object]$Trial,
        [Parameter(Mandatory)][string]$Reason,
        [Parameter(Mandatory)][string[]]$Errors
    )

    $Trial | Add-Member -NotePropertyName RecoveryRequired -NotePropertyValue $true -Force
    $Trial | Add-Member -NotePropertyName RecoveryReason -NotePropertyValue $Reason -Force
    $Trial | Add-Member -NotePropertyName RecoveryErrors -NotePropertyValue @($Errors) -Force
    $Trial | Add-Member -NotePropertyName RecoveryRecordedAt `
        -NotePropertyValue (Get-Date).ToString('o') -Force
    $Trial | Add-Member -NotePropertyName LifecycleState -NotePropertyValue 'RECOVERY_REQUIRED' -Force
    Write-TrialStateAtomic -Trial $Trial
}

function Remove-TrialTaskOnly {
    [void](Remove-ClawLabScheduledTask -Spec (Get-TrialTaskSpec) -AllowAbsent)
    if ($null -ne (Get-ClawLabScheduledTaskRecord -TaskName $trialTaskName)) {
        throw 'The guarded trial task could not be consumed or removed completely.'
    }
}

function Remove-TrialArtifacts {
    Remove-TrialTaskOnly
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

function Invoke-ExperimentalObservationUi {
    param([Parameter(Mandatory)][object]$Trial)

    $title64 = ConvertTo-TrialUtf8Base64 -Value `
        (Get-ClawLabString -Key 'experimental_trial_title')
    $warning64 = ConvertTo-TrialUtf8Base64 -Value `
        (Get-ClawLabString -Key 'experimental_warning')
    $wait64 = ConvertTo-TrialUtf8Base64 -Value `
        (Get-ClawLabString -Key 'experimental_wait_warning')
    $waiting64 = ConvertTo-TrialUtf8Base64 -Value `
        (Get-ClawLabString -Key 'wait_please')
    $command = @'
$ErrorActionPreference = 'Stop'
$decode = { param($value) [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($value)) }
$title = & $decode '__TITLE64__'
$warning = & $decode '__WARNING64__'
$waitWarning = & $decode '__WAIT64__'
$waiting = & $decode '__WAITING64__'
$minimumHz = __MINIMUM__
$maximumHz = __MAXIMUM__
$seconds = __SECONDS__

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object Windows.Forms.Form
$form.Text = $title
$form.StartPosition = [Windows.Forms.FormStartPosition]::CenterScreen
$form.FormBorderStyle = [Windows.Forms.FormBorderStyle]::FixedDialog
$form.ClientSize = New-Object Drawing.Size(760, 430)
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.ControlBox = $false
$form.ShowInTaskbar = $true
$form.TopMost = $true
$form.BackColor = [Drawing.Color]::FromArgb(12, 14, 22)
$form.ForeColor = [Drawing.Color]::White

$heading = New-Object Windows.Forms.Label
$heading.SetBounds(30, 24, 700, 58)
$heading.TextAlign = [Drawing.ContentAlignment]::MiddleCenter
$heading.Font = New-Object Drawing.Font('Segoe UI', 26, [Drawing.FontStyle]::Bold)
$heading.ForeColor = [Drawing.Color]::FromArgb(70, 170, 255)
$heading.Text = ('{0}-{1} Hz' -f $minimumHz, $maximumHz)
$form.Controls.Add($heading)

$state = New-Object Windows.Forms.Label
$state.SetBounds(30, 88, 700, 44)
$state.TextAlign = [Drawing.ContentAlignment]::MiddleCenter
$state.Font = New-Object Drawing.Font('Segoe UI', 18, [Drawing.FontStyle]::Bold)
$state.ForeColor = [Drawing.Color]::FromArgb(95, 230, 145)
$state.Text = ('{0} Hz' -f $maximumHz)
$form.Controls.Add($state)

$body = New-Object Windows.Forms.Label
$body.SetBounds(42, 146, 676, 118)
$body.TextAlign = [Drawing.ContentAlignment]::MiddleCenter
$body.Font = New-Object Drawing.Font('Segoe UI', 11)
$body.ForeColor = [Drawing.Color]::FromArgb(255, 210, 95)
$body.Text = $warning + [Environment]::NewLine + [Environment]::NewLine + $waitWarning
$form.Controls.Add($body)

$countdown = New-Object Windows.Forms.Label
$countdown.SetBounds(30, 278, 700, 48)
$countdown.TextAlign = [Drawing.ContentAlignment]::MiddleCenter
$countdown.Font = New-Object Drawing.Font('Segoe UI', 18, [Drawing.FontStyle]::Bold)
$countdown.ForeColor = [Drawing.Color]::White
$countdown.Text = ('{0} {1}s' -f $waiting, $seconds)
$form.Controls.Add($countdown)

$track = New-Object Windows.Forms.Panel
$track.SetBounds(54, 350, 652, 22)
$track.BackColor = [Drawing.Color]::FromArgb(32, 40, 58)
$form.Controls.Add($track)

$marker = New-Object Windows.Forms.Panel
$marker.SetBounds(0, 0, 88, 22)
$marker.BackColor = [Drawing.Color]::FromArgb(220, 60, 235)
$track.Controls.Add($marker)

$footer = New-Object Windows.Forms.Label
$footer.SetBounds(30, 386, 700, 24)
$footer.TextAlign = [Drawing.ContentAlignment]::MiddleCenter
$footer.Font = New-Object Drawing.Font('Segoe UI', 9)
$footer.ForeColor = [Drawing.Color]::FromArgb(165, 175, 195)
$footer.Text = $title
$form.Controls.Add($footer)

$script:clawLabTrialCanClose = $false
$direction = 1
$stopwatch = [Diagnostics.Stopwatch]::StartNew()
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 16
$timer.Add_Tick({
    $elapsed = $stopwatch.Elapsed.TotalSeconds
    $remaining = [Math]::Max(0, $seconds - [int][Math]::Floor($elapsed))
    $countdown.Text = ('{0} {1}s' -f $waiting, $remaining)

    $next = $marker.Left + (8 * $direction)
    $maximumLeft = $track.ClientSize.Width - $marker.Width
    if ($next -ge $maximumLeft) {
        $next = $maximumLeft
        $direction = -1
        $marker.BackColor = [Drawing.Color]::FromArgb(65, 220, 245)
    }
    elseif ($next -le 0) {
        $next = 0
        $direction = 1
        $marker.BackColor = [Drawing.Color]::FromArgb(220, 60, 235)
    }
    $marker.Left = $next

    if ($elapsed -ge $seconds) {
        $timer.Stop()
        $script:clawLabTrialCanClose = $true
        $form.Close()
    }
})
$form.Add_FormClosing({
    param($sender, $eventArgs)
    if (-not $script:clawLabTrialCanClose) {
        $eventArgs.Cancel = $true
    }
})
$form.Add_Shown({
    $form.Activate()
    $timer.Start()
})
try {
    [void]$form.ShowDialog()
}
finally {
    $timer.Stop()
    $timer.Dispose()
    $form.Dispose()
}
exit 0
'@
    $command = $command.Replace('__TITLE64__', $title64).
        Replace('__WARNING64__', $warning64).
        Replace('__WAIT64__', $wait64).
        Replace('__WAITING64__', $waiting64).
        Replace('__MINIMUM__', ([string][int]$Trial.MinimumHz)).
        Replace('__MAXIMUM__', ([string][int]$Trial.MaximumHz)).
        Replace('__SECONDS__', ([string][int]$Trial.ObservationSeconds))
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $process = Start-Process -FilePath $windowsPowerShellPath -ArgumentList @(
        '-NoLogo', '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass',
        '-EncodedCommand', $encoded
    ) -WindowStyle Hidden -PassThru
    $timeoutSeconds = [int]$Trial.ObservationSeconds + 10
    if (-not $process.WaitForExit($timeoutSeconds * 1000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        try { $process.WaitForExit(3000) | Out-Null } catch {}
        throw 'The visible experimental observation did not close inside its guarded time limit.'
    }
    if ([int]$process.ExitCode -ne 0) {
        throw "The visible experimental observation failed with exit code $($process.ExitCode)."
    }
}

function Restart-AfterTrial {
    Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\shutdown.exe') `
        -ArgumentList '/r /t 5 /c "ClawLab guarded VRR trial completed"' -WindowStyle Hidden
}

if ($LibraryOnly) { return }

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

    # Complete every user/profile/LFC preflight before creating or publishing
    # a machine-wide protected runtime.
    $sourceLfcToolPath = Join-Path $PSScriptRoot 'MSI-Claw-Intel-LFC-Fix.ps1'
    $preTrialLfcStatus = Get-LfcStatusObject -ToolPath $sourceLfcToolPath
    $preTrialLfc = New-PreTrialLfcSnapshot -Status $preTrialLfcStatus
    $lfcBackupPresent = [bool](Test-Path -LiteralPath $lfcBackupPath -PathType Leaf)
    if ($lfcBackupPresent -ne [bool]$preTrialLfc.BackupPresent) {
        throw 'The Intel LFC backup file and direct LFC status disagree; the guarded trial was not scheduled.'
    }
    $preTrialLfcDisposition = if ($lfcBackupPresent) {
        'VERIFIED_BACKUP_PRESENT'
    }
    else {
        $verifiedBaselineDisposition = Assert-FreshPreTrialLfcState -Snapshot $preTrialLfc `
            -ExpectedManagedMode $Mode `
            -ExpectedMinimumHz ([int]$profile.MinimumHz) `
            -ExpectedMaximumHz ([int]$profile.MaximumHz)
        [string]$verifiedBaselineDisposition
    }
    $ownerIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if ($null -eq $ownerIdentity.User) {
        throw 'The guarded trial could not bind its state to the current Windows SID.'
    }
    $ownerLocalAppData = [IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd('\')

    $trial = [ordered]@{
        SchemaVersion = 2
        FixVersion = $fixVersion
        ScheduledAt = (Get-Date).ToString('o')
        LifecycleState = 'SCHEDULED'
        LifecycleUpdatedAt = (Get-Date).ToString('o')
        AttemptConsumed = $false
        TaskConsumed = $false
        OwnerSid = [string]$ownerIdentity.User.Value
        OwnerLocalAppData = $ownerLocalAppData
        Mode = $Mode
        MinimumHz = [int]$profile.MinimumHz
        MaximumHz = [int]$profile.MaximumHz
        Stability = [string]$profile.Stability
        PanelKey = [string]$custom.PanelKey
        PhysicalEdidSha256 = [string]$custom.PhysicalEdidSha256
        ExperimentalEdidSha256 = [string]$custom.ExperimentalEdidSha256
        ObservationSeconds = $trialObservationSeconds
        UserConfirmed = $false
        PreTrialLfcDisposition = $preTrialLfcDisposition
        PreTrialLfc = $preTrialLfc
    }

    $protectedPayload = @(Get-ProtectedRuntimePayload)
    $stagingRoot = $null
    $trialStateWritten = $false
    try {
        $stagingRoot = Initialize-ProtectedRuntimeDirectory
        foreach ($fileName in $protectedPayload) {
            $protectedDestination = Get-ProtectedRuntimeStagingDestination `
                -StagingRoot $stagingRoot -RelativeFileName $fileName
            Copy-VerifiedFile -Source (Join-Path $PSScriptRoot $fileName) `
                -Destination $protectedDestination
        }
        Write-ProtectedRuntimeManifest -RuntimeRoot $stagingRoot -FileNames $protectedPayload
        Assert-ProtectedRuntimeTree -RuntimeRoot $stagingRoot -FileNames $protectedPayload

        Write-TrialStateAtomic -Trial $trial
        $trialStateWritten = $true
        Publish-ProtectedRuntimeStaging -StagingRoot $stagingRoot -FileNames $protectedPayload
        Assert-ProtectedRuntimeIntegrity

        # Register last, after the immutable final runtime and durable trial
        # state both verify. The task itself remains Limited privilege and
        # never executes a user-writable script as administrator.
        [void](Install-ClawLabScheduledTask -Spec (Get-TrialTaskSpec))
    }
    catch {
        $scheduleFailureRecord = $_
        $scheduleFailure = $scheduleFailureRecord.Exception.Message
        $cleanupErrors = [Collections.Generic.List[string]]::new()
        try { Remove-TrialTaskOnly }
        catch { $cleanupErrors.Add("Trial task cleanup failed: $($_.Exception.Message)") }

        $publishedByThisTransaction = (Test-Path -LiteralPath $protectedRuntimeRoot) -and
            ($null -ne $stagingRoot) -and -not (Test-Path -LiteralPath $stagingRoot)
        if ($publishedByThisTransaction) {
            try {
                # Delete only the exact, hash-verified, non-reparse tree this
                # transaction just published. Any identity drift is retained
                # for manual recovery rather than recursively followed.
                Assert-ProtectedRuntimeIntegrity
                Assert-ProtectedRuntimeDirectoryAcl -LiteralPath $protectedRuntimeRoot
                [IO.Directory]::Delete(
                    [IO.Path]::GetFullPath($protectedRuntimeRoot), $true)
            }
            catch { $cleanupErrors.Add("Published runtime cleanup failed: $($_.Exception.Message)") }
        }
        elseif ($null -ne $stagingRoot -and (Test-Path -LiteralPath $stagingRoot)) {
            try {
                $stagingItem = Get-Item -LiteralPath $stagingRoot -Force
                $parentRoot = [IO.Path]::GetDirectoryName(
                    [IO.Path]::GetFullPath($protectedRuntimeRoot))
                $canonicalStaging = [IO.Path]::GetFullPath($stagingRoot)
                if (-not $stagingItem.PSIsContainer -or
                    ($stagingItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
                    -not $canonicalStaging.StartsWith(
                        $parentRoot + [IO.Path]::DirectorySeparatorChar + '.staging-',
                        [StringComparison]::OrdinalIgnoreCase) -or
                    @($stagingItem.GetFileSystemInfos('*',
                            [IO.SearchOption]::AllDirectories) | Where-Object {
                            ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
                        }).Count -gt 0) {
                    throw 'The staging runtime changed identity and was retained for manual recovery.'
                }
                [IO.Directory]::Delete($canonicalStaging, $true)
            }
            catch { $cleanupErrors.Add("Staging runtime cleanup failed: $($_.Exception.Message)") }
        }
        if ($trialStateWritten -and (Test-Path -LiteralPath $trialStatePath -PathType Leaf)) {
            try { [IO.File]::Delete($trialStatePath) }
            catch { $cleanupErrors.Add("Trial state cleanup failed: $($_.Exception.Message)") }
        }
        if ($cleanupErrors.Count -gt 0) {
            throw "$scheduleFailure Cleanup also reported: $($cleanupErrors -join ' | ')"
        }
        throw $scheduleFailureRecord
    }

    Write-Host (Get-ClawLabString -Key 'experimental_schedule_details' `
        -Arguments @([int]$profile.MinimumHz, [int]$profile.MaximumHz)) -ForegroundColor Yellow
    Write-Host (Get-ClawLabString -Key 'experimental_wait_warning') -ForegroundColor Yellow
    Write-Host (Get-ClawLabString -Key 'restart_required') -ForegroundColor Green
    return
}

function Invoke-GuardedTrialRun {
    # Run is launched once and interactively with normal user rights.
    # Persistence still requires one visible UAC approval after an explicit
    # Yes answer. The task attempt is durably consumed before any OC write.
    Assert-ProtectedRuntimeIntegrity
    $trial = Read-JsonFile -LiteralPath $trialStatePath
    if ([int]$trial.SchemaVersion -ne 2 -or
        [string]$trial.FixVersion -ne $fixVersion -or
        -not $profiles.ContainsKey([string]$trial.Mode) -or
        $null -eq $trial.PreTrialLfc) {
        throw 'The guarded trial state has an unsupported version, mode or pre-trial proof.'
    }
    $profile = $profiles[[string]$trial.Mode]
    if ([int]$trial.MinimumHz -ne [int]$profile.MinimumHz -or
        [int]$trial.MaximumHz -ne [int]$profile.MaximumHz -or
        [string]$trial.Stability -ne [string]$profile.Stability -or
        [int]$trial.ObservationSeconds -ne $trialObservationSeconds) {
        throw 'The guarded trial state has unexpected range, classification or timing values.'
    }

    $runIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $runSid = if ($null -eq $runIdentity.User) { '' } else { [string]$runIdentity.User.Value }
    $runLocalAppData = [IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd('\')
    $runSessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId
    $ownerLocalAppData = [IO.Path]::GetFullPath([string]$trial.OwnerLocalAppData).TrimEnd('\')
    if ([string]::IsNullOrWhiteSpace($runSid) -or
        -not $runSid.Equals([string]$trial.OwnerSid, [StringComparison]::OrdinalIgnoreCase) -or
        -not $runLocalAppData.Equals($ownerLocalAppData, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The guarded trial owner SID or canonical LOCALAPPDATA does not match the current interactive user.'
    }
    # Session identity is captured per Run, after reboot. It is never frozen
    # when Schedule is created and is rebound for recovery-only invocations.
    $trial | Add-Member -NotePropertyName RunSessionId -NotePropertyValue ([int]$runSessionId) -Force
    $trial | Add-Member -NotePropertyName RunIdentityVerifiedAt `
        -NotePropertyValue (Get-Date).ToString('o') -Force
    Write-TrialStateAtomic -Trial $trial

    $disposition = Get-TrialExecutionDisposition `
        -LifecycleState ([string]$trial.LifecycleState) `
        -AttemptConsumed ([bool]$trial.AttemptConsumed)
    if ($disposition -eq 'COMMITTED_NO_REAPPLY') {
        Remove-TrialTaskOnly
        return 0
    }

    $trialSucceeded = $false
    $rollbackReason = $null
    if ($disposition -eq 'FIRST_ATTEMPT') {
        $trial = Consume-TrialAttemptAndTask -Trial $trial
        $trial.UserConfirmed = $false
        Write-TrialStateAtomic -Trial $trial
        $readyText = ('{0}-{1} Hz' -f
                [int]$profile.MinimumHz, [int]$profile.MaximumHz) +
            "`n`n" + (Get-ClawLabString -Key 'experimental_warning') +
            "`n`n" + (Get-ClawLabString -Key 'experimental_wait_warning') +
            "`n`n" + (Get-ClawLabString -Key 'experimental_consent_prompt')
        $readyAnswer = Show-Message -Text $readyText `
            -Title (Get-ClawLabString -Key 'experimental_trial_title') `
            -Flags 0x24 -TimeoutSeconds $trialReadyTimeoutSeconds
        if ($readyAnswer -ne 6) {
            $rollbackReason = Get-ClawLabString -Key 'experimental_declined'
        }
        else {
            $displayTrialAttempted = $false
            try {
                # The user starts the test only when the desktop is visible and
                # they are ready to watch it. Apply and verify the exact same
                # Windows maximum + Intel EXCELLENT range used by persistence.
                $displayTrialAttempted = $true
                Invoke-ToolAction -ToolPath $installedVrrToolPath `
                    -ToolAction 'ApplyExperimentalTrial' -TimeoutSeconds 15
                Invoke-ExperimentalObservationUi -Trial $trial
                Invoke-ToolAction -ToolPath $installedVrrToolPath `
                    -ToolAction 'VerifyExperimentalTrial' -TimeoutSeconds 15
                $trialSucceeded = $true
            }
            catch {
                $rollbackReason = $_.Exception.Message
            }
            finally {
                if ($displayTrialAttempted) {
                    try {
                        # Always leave the temporary high-refresh state before
                        # asking whether it should become persistent. A black
                        # or unstable panel therefore needs no user input to
                        # return to the validated 120 Hz safety mode.
                        Invoke-ToolAction -ToolPath $installedVrrToolPath `
                            -ToolAction 'SetSafe120ForTrial' -TimeoutSeconds 15
                    }
                    catch {
                        $safeFailure = "Automatic 120 Hz safety restoration failed: $($_.Exception.Message)"
                        if ([string]::IsNullOrWhiteSpace($rollbackReason)) {
                            $rollbackReason = $safeFailure
                        }
                        else {
                            $rollbackReason += " $safeFailure"
                        }
                        $trialSucceeded = $false
                    }
                }
            }
        }
    }
    else {
        # Power loss, a killed process or a second logon can reach only this
        # branch. It never invokes ApplyExperimentalTrial again.
        $rollbackReason = 'The one-time guarded trial attempt was already consumed; recovery was resumed without reapplying the overclock.'
        try {
            Invoke-ToolAction -ToolPath $installedVrrToolPath `
                -ToolAction 'SetSafe120ForTrial' -TimeoutSeconds 15
        }
        catch {
            $rollbackReason += " Automatic safe-120 preparation reported: $($_.Exception.Message)"
        }
        try { Remove-TrialTaskOnly }
        catch { $rollbackReason += " Task consumption reported: $($_.Exception.Message)" }
    }

    if ($trialSucceeded) {
        Set-TrialLifecycleState -Trial $trial -LifecycleState 'AWAITING_CONFIRMATION'
        $question = Get-ClawLabString -Key 'experimental_trial_confirmation' `
            -Arguments @([int]$profile.MaximumHz)
        $answer = Show-Message -Text $question `
            -Title (Get-ClawLabString -Key 'experimental_trial_title') -Flags 0x24 -TimeoutSeconds 30
        if ($answer -eq 6) {
            try {
                $trial.UserConfirmed = $true
                Set-TrialLifecycleState -Trial $trial -LifecycleState 'CONFIRMING'
                # Never force-kill a process that may be waiting on UAC: doing
                # so could detach its elevated child and race rollback.
                Invoke-BoundElevatedTrialConfirmation -Trial $trial `
                    -ExpectedSessionId $runSessionId
                $keptMessage = (Get-ClawLabString -Key 'experimental_keep_success' `
                        -Arguments @([int]$profile.MinimumHz, [int]$profile.MaximumHz)) +
                    "`n`n" + (Get-ClawLabString -Key 'restart_required')
                [void](Show-Message -Text $keptMessage `
                    -Title (Get-ClawLabString -Key 'experimental_trial_title') `
                    -Flags 0x40 -TimeoutSeconds 0)
                Restart-AfterTrial
                return 0
            }
            catch {
                $rollbackReason = "Final verification failed: $($_.Exception.Message)"
            }
        }
        else {
            $rollbackReason = Get-ClawLabString -Key 'experimental_declined'
        }
    }

    # Any failure, No, timeout, UAC cancellation or interrupted second run
    # restores LFC first when a backup exists. A genuinely fresh trial has no
    # LFC backup, so it must prove the exact clean pre-trial LFC identity and
    # flags before VRR Restore is allowed to run.
    $rollbackErrors = [Collections.Generic.List[string]]::new()
    $lfcBackupPresent = Test-Path -LiteralPath $lfcBackupPath -PathType Leaf
    $lfcRestoreTombstonePresent = $false
    $lfcRestoreFinalizedPresent = $false
    $lfcFactoryFinalizedPresent = $false
    $freshProofValid = $false
    try {
        $lfcStatus = Get-LfcStatusObject
        if ($lfcBackupPresent -ne [bool]$lfcStatus.LfcTransition.BackupPresent) {
            throw 'The Intel LFC backup file and direct status disagree during guarded rollback.'
        }
        $lfcRestoreTombstonePresent = [bool]$lfcStatus.RestoreTombstonePresent
        $lfcRestoreFinalizedPresent = [bool]$lfcStatus.RestoreFinalizedPresent
        $lfcFactoryFinalizedPresent = [bool]$lfcStatus.FactoryFinalizedPresent
        $lfcArtifactCount = @(
            $lfcBackupPresent,
            $lfcRestoreTombstonePresent,
            $lfcRestoreFinalizedPresent,
            $lfcFactoryFinalizedPresent
        ) | Where-Object { $_ }
        if (@($lfcArtifactCount).Count -gt 1) {
            throw 'The Intel LFC rollback contains multiple mutually exclusive recovery artifacts.'
        }
        if (-not $lfcBackupPresent -and
            -not $lfcRestoreTombstonePresent -and
            -not $lfcRestoreFinalizedPresent -and
            -not $lfcFactoryFinalizedPresent) {
            Assert-FreshLfcStillUnchanged -Trial $trial -Status $lfcStatus
            $freshProofValid = $true
        }
    }
    catch {
        $rollbackErrors.Add($_.Exception.Message)
    }
    $rollbackDisposition = Get-TrialRollbackDisposition `
        -LfcBackupPresent ([bool]$lfcBackupPresent) `
        -LfcRestoreTombstonePresent $lfcRestoreTombstonePresent `
        -LfcRestoreFinalizedPresent $lfcRestoreFinalizedPresent `
        -LfcFactoryFinalizedPresent $lfcFactoryFinalizedPresent `
        -FreshLfcProofValid $freshProofValid

    if ($rollbackDisposition -eq 'FAIL_CLOSED_LFC_DIVERGED' -and
        $rollbackErrors.Count -eq 0) {
        $rollbackErrors.Add('Intel LFC diverged without a restorable backup; VRR Restore was refused.')
    }

    # One bound UAC process validates the trial owner SID, this logon session
    # and canonical LOCALAPPDATA before loading any protected core. It then
    # completes the complete rollback transaction without detached generic
    # RunAs children. With a backup this is Prepare LFC -> Restore/verify VRR
    # -> Commit/finalize LFC. A committed or finalized provenance marker
    # resumes idempotently without Prepare; a proven-fresh trial invokes only
    # VRR Restore.
    if ($rollbackErrors.Count -eq 0) {
        try {
            $lfcRollbackPhase = switch ($rollbackDisposition) {
                'PREPARE_LFC_THEN_VRR_THEN_COMMIT' { 'Prepare' }
                'RESUME_COMMITTED_LFC_THEN_VRR_THEN_FINALIZE' { 'Resume' }
                'VERIFY_FINALIZED_LFC_THEN_RESTORE_VRR' { 'Resume' }
                'VERIFY_FACTORY_FINALIZED_LFC_THEN_RESTORE_VRR' { 'Resume' }
                'PROVE_FRESH_LFC_THEN_RESTORE_VRR' { 'Fresh' }
                default { throw "Unsupported guarded rollback disposition: $rollbackDisposition" }
            }
            Invoke-BoundElevatedTrialRollback -Trial $trial `
                -ExpectedSessionId $runSessionId `
                -LfcRollbackPhase $lfcRollbackPhase
        }
        catch { $rollbackErrors.Add($_.Exception.Message) }
    }
    if ($rollbackErrors.Count -eq 0) {
        try { Remove-TrialArtifacts }
        catch { $rollbackErrors.Add($_.Exception.Message) }
    }
    if ($rollbackErrors.Count -gt 0) {
        # The task stays consumed. Preserve the atomic state and protected
        # payload as durable recovery evidence, and never reboot automatically.
        try { Remove-TrialTaskOnly }
        catch { $rollbackErrors.Add("Trial task removal failed: $($_.Exception.Message)") }
    }

    $message = $rollbackReason
    if ([string]::IsNullOrWhiteSpace($message)) {
        $message = 'The guarded experimental profile was not kept.'
    }
    if ($rollbackErrors.Count -gt 0) {
        try {
            Set-TrialRecoveryRequired -Trial $trial -Reason $message `
                -Errors @($rollbackErrors)
        }
        catch {
            $rollbackErrors.Add("Recovery-state recording failed: $($_.Exception.Message)")
        }
        $message += "`n`n" + (Get-ClawLabString -Key 'technical_error_envelope')
        $message += "`n" + (Get-ClawLabString -Key 'experimental_recovery_reported' `
            -Arguments @(($rollbackErrors -join ' | ')))
        $message += "`n`n" + (Get-ClawLabString -Key 'transaction_rollback_failed')
    }
    else {
        $message += "`n`n" + (Get-ClawLabString -Key 'experimental_recovery_success')
        $message += "`n`n" + (Get-ClawLabString -Key 'restart_required')
    }
    [void](Show-Message -Text $message `
        -Title (Get-ClawLabString -Key 'recovery_title') `
        -Flags $(if ($rollbackErrors.Count -gt 0) { 0x10 } else { 0x40 }) `
        -TimeoutSeconds 0)
    if ($rollbackErrors.Count -gt 0) {
        return 1
    }
    Restart-AfterTrial
    return 0
}

$trialExitCode = 1
Enter-TrialTransactionLocks
try {
    $trialExitCode = Invoke-GuardedTrialRun
}
finally {
    Exit-TrialTransactionLocks
}
exit $trialExitCode
