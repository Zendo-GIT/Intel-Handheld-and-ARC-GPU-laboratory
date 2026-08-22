[CmdletBinding()]
param(
    [ValidateSet(
        'CheckStatus', 'ExportStatus', 'CollectDiagnostics',
        'Install30', 'Install48',
        'Install48_144', 'Install48_165', 'Install48_180', 'Install48_192',
        'Install30_144', 'Install30_165', 'Install30_180', 'Install30_192',
        'Restore', 'RestoreLfcOnly', 'FactoryReset', 'EmergencyRestoreEdid',
        'FactoryLfcDefaults', 'UpdateCursorHelper'
    )]
    [string]$Action = 'CheckStatus',

    [AllowNull()]
    [AllowEmptyString()]
    [string]$Language,

    [switch]$Elevated,
    [AllowNull()][AllowEmptyString()][string]$ExpectedCallerSid,
    [int]$ExpectedCallerSessionId = -1,
    [AllowNull()][AllowEmptyString()][string]$ExpectedCallerLocalAppData,
    [AllowNull()][AllowEmptyString()][string]$TransactionId,

    # Used only by the static/pure helper tests. Public launchers never pass it.
    [switch]$LibraryOnly,
    [switch]$NonInteractive
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:CoordinatorVersion = '2.3.0'
$script:ExpectedLfcToolVersion = '2.0.7'
$script:LocalizationPath = Join-Path $PSScriptRoot 'ClawLab-Localization.ps1'
$script:VrrToolPath = Join-Path $PSScriptRoot 'MSI-Claw-VRR-Fix.ps1'
$script:LfcToolPath = Join-Path $PSScriptRoot 'MSI-Claw-Intel-LFC-Fix.ps1'
$script:HealthToolPath = Join-Path $PSScriptRoot 'ClawLab-Health-Check.ps1'
$script:ExportToolPath = Join-Path $PSScriptRoot 'Export-ClawLab-Status.ps1'
$script:DiagnosticsToolPath = Join-Path $PSScriptRoot 'Collect-Claw-Display-Diagnostics.ps1'
$script:TaskPersistencePath = Join-Path $PSScriptRoot 'Scheduled-Task-Persistence.ps1'
$script:RangePolicyPath = Join-Path $PSScriptRoot 'ArcSync-Range-Policy.ps1'
$script:PowerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$script:SelectedLanguage = $null
$script:ElevationLaunchError = $null

foreach ($requiredCoordinatorModule in @($script:TaskPersistencePath, $script:RangePolicyPath)) {
    if (-not (Test-Path -LiteralPath $requiredCoordinatorModule -PathType Leaf)) {
        throw "Required coordinator safety module is missing: $requiredCoordinatorModule"
    }
    . $requiredCoordinatorModule
}

$script:StableActions = @('Install30', 'Install48')
$script:ExperimentalActions = @(
    'Install48_144', 'Install48_165', 'Install48_180', 'Install48_192',
    'Install30_144', 'Install30_165', 'Install30_180', 'Install30_192'
)
$script:InstallActions = @($script:StableActions + $script:ExperimentalActions)
$script:MaintenanceActions = @('UpdateCursorHelper')
$script:NonMutatingActions = @('CheckStatus', 'ExportStatus', 'CollectDiagnostics')
$script:RecoveryActions = @('Restore', 'FactoryReset', 'EmergencyRestoreEdid', 'FactoryLfcDefaults')
$script:RestartActions = @($script:InstallActions + @('Restore', 'FactoryReset', 'EmergencyRestoreEdid'))

function Get-CoordinatorText {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [AllowNull()][object[]]$Arguments
    )

    return Get-ClawLabString -Key $Key -Arguments $Arguments -Language $script:SelectedLanguage
}

function Write-CoordinatorText {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [AllowNull()][object[]]$Arguments,
        [ConsoleColor]$ForegroundColor = [Console]::ForegroundColor
    )

    Write-Host (Get-CoordinatorText -Key $Key -Arguments $Arguments) -ForegroundColor $ForegroundColor
}

function Resolve-CoordinatorYesNoAnswer {
    param(
        [AllowNull()][AllowEmptyString()][string]$Answer,
        [Parameter(Mandatory = $true)][string]$YesLabel,
        [Parameter(Mandatory = $true)][string]$NoLabel,
        [Parameter(Mandatory = $true)][string]$YesKey,
        [Parameter(Mandatory = $true)][string]$NoKey
    )

    $normalized = ([string]$Answer).Trim()
    if ($normalized.Equals($YesLabel, [StringComparison]::CurrentCultureIgnoreCase) -or
        $normalized.Equals($YesKey, [StringComparison]::CurrentCultureIgnoreCase)) {
        return 'YES'
    }
    if ($normalized.Equals($NoLabel, [StringComparison]::CurrentCultureIgnoreCase) -or
        $normalized.Equals($NoKey, [StringComparison]::CurrentCultureIgnoreCase)) {
        return 'NO'
    }
    return 'INVALID'
}

function Read-CoordinatorYesNo {
    param([Parameter(Mandatory = $true)][string]$QuestionKey)

    if ($NonInteractive) {
        throw 'An interactive confirmation is required.'
    }

    $yes = Get-CoordinatorText -Key 'common_yes'
    $no = Get-CoordinatorText -Key 'common_no'
    $yesKey = Get-CoordinatorText -Key 'common_yes_key'
    $noKey = Get-CoordinatorText -Key 'common_no_key'
    while ($true) {
        $prompt = ('{0} [{1}/{2}] ' -f
            (Get-CoordinatorText -Key $QuestionKey), $yesKey, $noKey)
        $answer = $null
        $keyInfo = $null
        try {
            if ([Console]::IsInputRedirected) {
                throw [InvalidOperationException]::new('Console input is redirected.')
            }
            Write-Host $prompt -NoNewline
            $keyInfo = [Console]::ReadKey($true)
        }
        catch {
            # ReadKey is unavailable in hosts without a real console. Keep a
            # compatibility fallback there, while normal BAT/Terminal usage
            # remains a genuine one-key choice with no Enter key required.
            if ($null -eq $keyInfo) {
                if (-not [Console]::IsInputRedirected) { Write-Host }
                $answer = Read-Host $prompt
            }
        }
        if ($null -ne $keyInfo) {
            if (($keyInfo.Modifiers -band [ConsoleModifiers]::Control) -ne 0 -and
                $keyInfo.Key -eq [ConsoleKey]::C) {
                Write-Host '^C'
                throw [OperationCanceledException]::new('The interactive confirmation was cancelled.')
            }
            $answer = [string]$keyInfo.KeyChar
            Write-Host $answer
        }
        switch (Resolve-CoordinatorYesNoAnswer -Answer $answer `
                -YesLabel $yes -NoLabel $no -YesKey $yesKey -NoKey $noKey) {
            'YES' { return $true }
            'NO' { return $false }
        }
        Write-CoordinatorText -Key 'prompt_yes_no' -ForegroundColor Yellow
    }
}

function Wait-CoordinatorEnter {
    if ($NonInteractive) { return }
    [void](Read-Host (Get-CoordinatorText -Key 'press_enter'))
}

function Test-ClawLabOverclockConsentValue {
    param([AllowNull()][AllowEmptyString()][string]$Value)

    return [string]$Value -ceq 'I ACCEPT THE OVERCLOCK RISK'
}

function Read-ClawLabOverclockConsent {
    if ($NonInteractive) {
        throw 'The guarded display-overclock trial requires interactive consent.'
    }
    $token = 'I ACCEPT THE OVERCLOCK RISK'
    $answer = Read-Host (('{0} [{1}]' -f
            (Get-CoordinatorText -Key 'experimental_consent_prompt'), $token))
    return Test-ClawLabOverclockConsentValue -Value ([string]$answer)
}

function Show-ClawLabOverclockRiskReadingPeriod {
    param([Parameter(Mandatory = $true)][string]$RequestedAction)

    if ($RequestedAction -notmatch '^Install(30|48)_(144|165|180|192)$') {
        throw "The experimental warning cannot resolve profile '$RequestedAction'."
    }
    $minimumHz = [int]$Matches[1]
    $maximumHz = [int]$Matches[2]
    $readingSeconds = 10

    Write-CoordinatorText -Key 'experimental_warning' -ForegroundColor Red
    Write-CoordinatorText -Key 'experimental_schedule_details' `
        -Arguments @($minimumHz, $maximumHz) -ForegroundColor Yellow
    Write-CoordinatorText -Key 'experimental_wait_warning' -ForegroundColor Yellow
    for ($remaining = $readingSeconds; $remaining -gt 0; $remaining--) {
        Write-Host ("`r{0} {1}s   " -f
            (Get-CoordinatorText -Key 'wait_please'), $remaining) `
            -ForegroundColor Yellow -NoNewline
        Start-Sleep -Seconds 1
    }
    Write-Host ("`r{0}      " -f (Get-CoordinatorText -Key 'wait_please')) `
        -ForegroundColor Yellow
}

function Get-ClawLabIdentityContext {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $localAppData = [IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd('\')
    return [pscustomobject]@{
        Sid = [string]$identity.User.Value
        SessionId = [int][Diagnostics.Process]::GetCurrentProcess().SessionId
        LocalAppData = $localAppData
        IsAdministrator = $principal.IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)
    }
}

function Assert-ClawLabElevatedIdentity {
    param(
        [Parameter(Mandatory = $true)][object]$Actual,
        [Parameter(Mandatory = $true)][string]$CallerSid,
        [Parameter(Mandatory = $true)][int]$CallerSessionId,
        [Parameter(Mandatory = $true)][string]$CallerLocalAppData
    )

    $expectedPath = [IO.Path]::GetFullPath($CallerLocalAppData).TrimEnd('\')
    if (-not [bool]$Actual.IsAdministrator -or
        -not ([string]$Actual.Sid).Equals($CallerSid, [StringComparison]::OrdinalIgnoreCase) -or
        [int]$Actual.SessionId -ne $CallerSessionId -or
        -not ([string]$Actual.LocalAppData).Equals($expectedPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'CLAWLAB_ELEVATED_IDENTITY_MISMATCH'
    }
    return $true
}

function ConvertTo-ClawLabEncodedCommand {
    param([Parameter(Mandatory = $true)][string]$Command)

    return [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Command))
}

function ConvertTo-ClawLabUtf8Base64 {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))
}

function ConvertFrom-ClawLabEnvelopeText {
    param([Parameter(Mandatory = $true)][string]$Text)

    $prefix = 'CLAWLAB64:'
    if (-not $Text.StartsWith($prefix, [StringComparison]::Ordinal)) {
        throw 'Component returned an invalid ASCII envelope marker.'
    }
    try {
        $json = [Text.Encoding]::UTF8.GetString(
            [Convert]::FromBase64String($Text.Substring($prefix.Length)))
        return $json | ConvertFrom-Json
    }
    catch {
        throw "Component returned an invalid Base64/JSON envelope: $($_.Exception.Message)"
    }
}

function Write-ClawLabJsonAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][object]$Value
    )

    $parent = Split-Path -Parent $LiteralPath
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    $temporary = Join-Path $parent ('.clawlab-transaction-{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
    $previous = Join-Path $parent ('.clawlab-transaction-{0}.bak' -f [Guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText(
            $temporary,
            ($Value | ConvertTo-Json -Depth 12),
            [Text.UTF8Encoding]::new($false)
        )
        if (Test-Path -LiteralPath $LiteralPath -PathType Leaf) {
            [IO.File]::Replace($temporary, $LiteralPath, $previous)
            if (Test-Path -LiteralPath $previous -PathType Leaf) {
                [IO.File]::Delete($previous)
            }
        }
        else {
            [IO.File]::Move($temporary, $LiteralPath)
        }
    }
    finally {
        foreach ($path in @($temporary, $previous)) {
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                [IO.File]::Delete($path)
            }
        }
    }
}

function Read-ClawLabJsonFile {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) { return $null }
    return [IO.File]::ReadAllText($LiteralPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
}

function New-ClawLabTransactionPaths {
    param([Parameter(Mandatory = $true)][string]$LocalAppData)

    $root = Join-Path ([IO.Path]::GetFullPath($LocalAppData).TrimEnd('\')) 'ClawLab\VRR-Transaction'
    $vrrStateRoot = Join-Path $LocalAppData 'ClawLab\Intel-Arc-Sync-Full-Range'
    $lfcStateRoot = Join-Path $LocalAppData 'ClawLab\Intel-LFC-Fix'
    $protectedRuntimeBaseRoot = Join-Path $env:ProgramData 'ClawLab-VRR-Privileged'
    $protectedRuntimeRoot = Join-Path $protectedRuntimeBaseRoot '2.3.0'
    $vrrArtifacts = @(
        'original-profile.json',
        'normalization-compensation.json',
        'experimental-edid.json',
        'managed-mode.json',
        'MSI-Claw-VRR-Fix.ps1',
        'Edid-Normalization.ps1',
        'ArcSync-Range-Policy.ps1',
        'Scheduled-Task-Persistence.ps1',
        'ClawLab-VRR-Startup.vbs',
        'startup-last-run.json',
        'ClawLab-Cursor-Refresh-Helper.exe',
        'cursor-refresh-helper.json',
        'experimental-overclock-trial.json',
        'Experimental-Overclock-VRR-Trial.ps1',
        'ClawLab-Experimental-Trial-Startup.vbs',
        'intel-graphics-startup.json'
    ) | ForEach-Object { Join-Path $vrrStateRoot $_ }
    $lfcArtifacts = @(
        'original-intel-vrr-solutions.json',
        'restore-committed.json',
        'restore-finalized.json',
        'factory-default-intent.json',
        'factory-finalized.json',
        'MSI-Claw-Intel-LFC-Fix.ps1',
        'Intel-VRR-LFC-Driver-Interface.ps1',
        'Lfc-Backup-Identity.ps1',
        'Edid-Normalization.ps1',
        'ArcSync-Range-Policy.ps1',
        'Scheduled-Task-Persistence.ps1',
        'ClawLab-LFC-Startup.vbs'
    ) | ForEach-Object { Join-Path $lfcStateRoot $_ }
    return [pscustomobject]@{
        Root = $root
        Journal = Join-Path $root 'transaction.json'
        Result = Join-Path $root 'last-result.json'
        VrrStateRoot = $vrrStateRoot
        LfcStateRoot = $lfcStateRoot
        VrrBackup = Join-Path $vrrStateRoot 'original-profile.json'
        VrrNormalizationCompensation = Join-Path $vrrStateRoot 'normalization-compensation.json'
        VrrManaged = Join-Path $vrrStateRoot 'managed-mode.json'
        VrrEdid = Join-Path $vrrStateRoot 'experimental-edid.json'
        TrialState = Join-Path $vrrStateRoot 'experimental-overclock-trial.json'
        TrialLocalScript = Join-Path $vrrStateRoot 'Experimental-Overclock-VRR-Trial.ps1'
        TrialLocalLauncher = Join-Path $vrrStateRoot 'ClawLab-Experimental-Trial-Startup.vbs'
        LfcBackup = Join-Path $lfcStateRoot 'original-intel-vrr-solutions.json'
        LfcRestoreCommitted = Join-Path $lfcStateRoot 'restore-committed.json'
        LfcRestoreFinalized = Join-Path $lfcStateRoot 'restore-finalized.json'
        LfcFactoryIntent = Join-Path $lfcStateRoot 'factory-default-intent.json'
        LfcFactoryFinalized = Join-Path $lfcStateRoot 'factory-finalized.json'
        VrrArtifacts = @($vrrArtifacts)
        LfcArtifacts = @($lfcArtifacts)
        ProtectedRuntimeBaseRoot = $protectedRuntimeBaseRoot
        ProtectedRuntimeRoot = $protectedRuntimeRoot
        VrrTaskName = 'ClawLab MSI Claw 8 VRR Range'
        CursorTaskName = 'ClawLab MSI Claw Cursor Refresh Engine'
        LfcTaskName = 'ClawLab MSI Claw Intel LFC Fix'
        TrialTaskName = 'ClawLab MSI Claw Experimental Overclock Trial'
    }
}

function Assert-ClawLabLocalStateRootsSafe {
    param(
        [Parameter(Mandatory = $true)][string]$LocalAppData,
        [Parameter(Mandatory = $true)][object]$Paths
    )

    $localRoot = [IO.Path]::GetFullPath($LocalAppData).TrimEnd('\')
    $clawRoot = [IO.Path]::GetFullPath((Join-Path $localRoot 'ClawLab')).TrimEnd('\')
    $candidates = @($clawRoot, $Paths.Root, $Paths.VrrStateRoot, $Paths.LfcStateRoot)
    foreach ($candidate in $candidates) {
        $full = [IO.Path]::GetFullPath([string]$candidate).TrimEnd('\')
        if ($full -ne $clawRoot -and -not $full.StartsWith(
                $clawRoot + [IO.Path]::DirectorySeparatorChar,
                [StringComparison]::OrdinalIgnoreCase)) {
            throw "Unsafe ClawLab LocalAppData state path: $full"
        }
    }

    # Create only the coordinator-owned roots here. VRR/LFC roots remain under
    # the ownership of their core components. Existing roots are never followed
    # through junctions or symbolic links by an elevated coordinator.
    foreach ($directory in @($clawRoot, $Paths.Root)) {
        if (Test-Path -LiteralPath $directory) {
            $item = Get-Item -LiteralPath $directory -Force
            if (-not $item.PSIsContainer -or
                ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing an unsafe ClawLab LocalAppData reparse point: $directory"
            }
        }
        else {
            [IO.Directory]::CreateDirectory($directory) | Out-Null
            $item = Get-Item -LiteralPath $directory -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing a newly resolved ClawLab LocalAppData reparse point: $directory"
            }
        }
    }
    foreach ($directory in @($Paths.VrrStateRoot, $Paths.LfcStateRoot)) {
        if (Test-Path -LiteralPath $directory) {
            $item = Get-Item -LiteralPath $directory -Force
            if (-not $item.PSIsContainer -or
                ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing an unsafe managed-state reparse point: $directory"
            }
        }
    }
}

function Set-ClawLabTransactionPhase {
    param(
        [Parameter(Mandatory = $true)][object]$Journal,
        [Parameter(Mandatory = $true)][string]$Phase,
        [Parameter(Mandatory = $true)][string]$JournalPath,
        [AllowNull()][string]$Detail
    )

    $Journal.Phase = $Phase
    $Journal.UpdatedAt = (Get-Date).ToString('o')
    $Journal.Detail = $Detail
    Write-ClawLabJsonAtomic -LiteralPath $JournalPath -Value $Journal
}

function New-ClawLabTransactionJournal {
    param(
        [Parameter(Mandatory = $true)][string]$RequestedAction,
        [Parameter(Mandatory = $true)][object]$Identity,
        [Parameter(Mandatory = $true)][string]$Id,
        [AllowNull()][object]$Previous
    )

    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        CoordinatorVersion = $script:CoordinatorVersion
        TransactionId = $Id
        Action = $RequestedAction
        CallerSid = [string]$Identity.Sid
        CallerSessionId = [int]$Identity.SessionId
        StartedAt = (Get-Date).ToString('o')
        UpdatedAt = (Get-Date).ToString('o')
        Phase = 'STARTED'
        Detail = $null
        PreviousInterruptedTransaction = $Previous
    }
}

function Invoke-ClawLabCoreAction {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$CoreAction,
        [Parameter(Mandatory = $true)][string]$CallerSid,
        [Parameter(Mandatory = $true)][string]$CallerLocalAppData,
        [switch]$AllowEmptySuccess
    )

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        throw "Required core component is missing: $ScriptPath"
    }
    if (-not (Test-Path -LiteralPath $script:PowerShellPath -PathType Leaf)) {
        throw "Windows PowerShell is missing: $($script:PowerShellPath)"
    }

    $path64 = ConvertTo-ClawLabUtf8Base64 -Value ([IO.Path]::GetFullPath($ScriptPath))
    $action64 = ConvertTo-ClawLabUtf8Base64 -Value $CoreAction
    $sid64 = ConvertTo-ClawLabUtf8Base64 -Value $CallerSid
    $local64 = ConvertTo-ClawLabUtf8Base64 -Value ([IO.Path]::GetFullPath($CallerLocalAppData).TrimEnd('\'))
    if ($ExpectedCallerSessionId -lt 0) {
        throw 'The coordinator did not receive a valid caller session identifier.'
    }
    $template = @'
$ErrorActionPreference = 'Stop'
$path = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PATH64__'))
$action = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__ACTION64__'))
$expectedSid = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__SID64__'))
$expectedLocal = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__LOCAL64__'))
$expectedSession = __SESSION__
try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $actualLocal = [IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd('\')
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -or
        -not $identity.User.Value.Equals($expectedSid, [StringComparison]::OrdinalIgnoreCase) -or
        [int][Diagnostics.Process]::GetCurrentProcess().SessionId -ne [int]$expectedSession -or
        -not $actualLocal.Equals($expectedLocal, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'CLAWLAB_CORE_PROCESS_IDENTITY_MISMATCH'
    }
    $items = @(& $path -Action $action 3>$null 4>$null 5>$null 6>$null)
    $result = if ($items.Count -gt 0) { $items[-1] } else { $null }
    $envelope = [ordered]@{ Success = $true; Result = $result; Message = $null; ErrorId = $null }
    $json = $envelope | ConvertTo-Json -Depth 16 -Compress
    [Console]::Out.WriteLine('CLAWLAB64:' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json)))
    exit 0
}
catch {
    $envelope = [ordered]@{
        Success = $false
        Result = $null
        Message = [string]$_.Exception.Message
        ErrorId = [string]$_.FullyQualifiedErrorId
    }
    $json = $envelope | ConvertTo-Json -Depth 8 -Compress
    [Console]::Out.WriteLine('CLAWLAB64:' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json)))
    exit 1
}
'@
    $command = $template.Replace('__PATH64__', $path64).
        Replace('__ACTION64__', $action64).
        Replace('__SID64__', $sid64).
        Replace('__LOCAL64__', $local64).
        Replace('__SESSION__', ([string][int]$ExpectedCallerSessionId))
    $encoded = ConvertTo-ClawLabEncodedCommand -Command $command
    $raw = @(& $script:PowerShellPath -NoLogo -NoProfile -NonInteractive `
            -ExecutionPolicy Bypass -EncodedCommand $encoded 2>$null)
    $exitCode = $LASTEXITCODE
    $text = (@($raw | ForEach-Object { [string]$_ }) -join "`n").Trim()

    if ([string]::IsNullOrWhiteSpace($text)) {
        if ($AllowEmptySuccess -and $exitCode -eq 0) {
            return [pscustomobject]@{ Success = $true; Result = $null; Message = $null; ErrorId = $null }
        }
        throw "Core component returned no result: $([IO.Path]::GetFileName($ScriptPath)) / $CoreAction (exit $exitCode)"
    }
    $envelope = ConvertFrom-ClawLabEnvelopeText -Text $text
    if ($exitCode -ne 0 -or -not [bool]$envelope.Success) {
        throw "Core action $CoreAction failed: $([string]$envelope.Message)"
    }
    return $envelope
}

function Invoke-ClawLabReadOnlyObject {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [AllowNull()][AllowEmptyString()][string]$CoreAction,
        [switch]$AllowEmptySuccess
    )

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        throw "Required read-only component is missing: $ScriptPath"
    }
    $path64 = ConvertTo-ClawLabUtf8Base64 -Value ([IO.Path]::GetFullPath($ScriptPath))
    $action64 = ConvertTo-ClawLabUtf8Base64 -Value ([string]$CoreAction)
    $template = @'
$ErrorActionPreference = 'Stop'
$path = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PATH64__'))
$action = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__ACTION64__'))
try {
    $items = @(if ([string]::IsNullOrWhiteSpace($action)) {
            & $path 3>$null 4>$null 5>$null 6>$null
        }
        else {
            & $path -Action $action 3>$null 4>$null 5>$null 6>$null
        })
    $result = if ($items.Count -gt 0) { $items[-1] } else { $null }
    $json = (([ordered]@{
        Success = $true; Result = $result; Message = $null; ErrorId = $null
    }) | ConvertTo-Json -Depth 16 -Compress)
    [Console]::Out.WriteLine('CLAWLAB64:' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json)))
    exit 0
}
catch {
    $json = (([ordered]@{
        Success = $false; Result = $null; Message = [string]$_.Exception.Message
        ErrorId = [string]$_.FullyQualifiedErrorId
    }) | ConvertTo-Json -Depth 8 -Compress)
    [Console]::Out.WriteLine('CLAWLAB64:' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json)))
    exit 1
}
'@
    $command = $template.Replace('__PATH64__', $path64).Replace('__ACTION64__', $action64)
    $raw = @(& $script:PowerShellPath -NoLogo -NoProfile -NonInteractive `
            -ExecutionPolicy Bypass -EncodedCommand (ConvertTo-ClawLabEncodedCommand -Command $command) 2>$null)
    $exitCode = $LASTEXITCODE
    $text = (@($raw | ForEach-Object { [string]$_ }) -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "Read-only component returned no result: $([IO.Path]::GetFileName($ScriptPath))"
    }
    $envelope = ConvertFrom-ClawLabEnvelopeText -Text $text
    if ($exitCode -ne 0 -or -not [bool]$envelope.Success) {
        throw "Read-only component failed: $([string]$envelope.Message)"
    }
    if (-not $AllowEmptySuccess -and $null -eq $envelope.Result) {
        throw "Read-only component returned no state object: $([IO.Path]::GetFileName($ScriptPath))"
    }
    return $envelope
}

function Get-ClawLabProfileLabel {
    param([Parameter(Mandatory = $true)][string]$RequestedAction)

    if ($RequestedAction -match '^Install(30|48)_(144|165|180|192)$') {
        return ('{0}-{1} Hz' -f $Matches[1], $Matches[2])
    }
    if ($RequestedAction -eq 'Install30') { return '30-120 Hz' }
    if ($RequestedAction -eq 'Install48') { return '48-120 Hz' }
    return $RequestedAction
}

function Invoke-ClawLabPublicPreflight {
    param([Parameter(Mandatory = $true)][string]$RequestedAction)

    if ($RequestedAction -in $script:InstallActions) {
        Write-CoordinatorText -Key 'preflight_title' -ForegroundColor Cyan
        Write-CoordinatorText -Key 'cru_warning' -ForegroundColor Yellow
        if (-not (Read-CoordinatorYesNo -QuestionKey 'cru_question')) {
            return $false
        }
        Write-CoordinatorText -Key 'vrr_ownership_title' -ForegroundColor Cyan
        Write-CoordinatorText -Key 'vrr_ownership_warning' -ForegroundColor Yellow
        Write-CoordinatorText -Key 'clawtweaks_note'
        if (-not (Read-CoordinatorYesNo -QuestionKey 'vrr_ownership_question')) {
            return $false
        }
        if ($RequestedAction -in $script:ExperimentalActions) {
            Show-ClawLabOverclockRiskReadingPeriod -RequestedAction $RequestedAction
            if (-not (Read-ClawLabOverclockConsent)) {
                return $false
            }
        }
        return $true
    }

    switch ($RequestedAction) {
        'FactoryReset' {
            Write-CoordinatorText -Key 'factory_reset_title' -ForegroundColor Red
            return Read-CoordinatorYesNo -QuestionKey 'factory_reset_confirm'
        }
        'EmergencyRestoreEdid' {
            Write-CoordinatorText -Key 'emergency_title' -ForegroundColor Red
            return Read-CoordinatorYesNo -QuestionKey 'emergency_confirm'
        }
        'RestoreLfcOnly' {
            Write-CoordinatorText -Key 'lfc_restore_title' -ForegroundColor Cyan
            return Read-CoordinatorYesNo -QuestionKey 'lfc_restore_confirm'
        }
        'FactoryLfcDefaults' {
            Write-CoordinatorText -Key 'emergency_title' -ForegroundColor Red
            return Read-CoordinatorYesNo -QuestionKey 'emergency_confirm'
        }
        default { return $true }
    }
}

function Test-ClawLabVrrOriginalBackupVerified {
    param(
        [Parameter(Mandatory = $true)][object]$Paths,
        [Parameter(Mandatory = $true)][object]$Vrr,
        [Parameter(Mandatory = $true)][object]$Lfc
    )

    try {
        if (-not [bool]$Vrr.OriginalProfileSaved -or
            -not (Test-Path -LiteralPath $Paths.VrrBackup -PathType Leaf) -or
            'BackupPath' -notin $Vrr.PSObject.Properties.Name -or
            [string]::IsNullOrWhiteSpace([string]$Vrr.BackupPath)) {
            return $false
        }
        $reportedPath = [IO.Path]::GetFullPath([string]$Vrr.BackupPath)
        $expectedPath = [IO.Path]::GetFullPath([string]$Paths.VrrBackup)
        if (-not $reportedPath.Equals($expectedPath, [StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }

        $backup = Read-ClawLabJsonFile -LiteralPath $Paths.VrrBackup
        if ($null -eq $backup) { return $false }
        $required = @(
            'SchemaVersion', 'FixVersion', 'BaselinePolicy', 'PanelKey',
            'PhysicalEdidSha256', 'EdidOverrideStateAtSave', 'ProfileId',
            'ProfileName', 'MinRefreshRateInHz', 'MaxRefreshRateInHz',
            'MaxFrameTimeIncreaseInUs', 'MaxFrameTimeDecreaseInUs'
        )
        foreach ($property in $required) {
            if ($property -notin $backup.PSObject.Properties.Name) { return $false }
        }
        $knownPanelIdentity = switch ([string]$backup.PanelKey) {
            'CLAW_8_AI_PLUS' {
                [pscustomobject]@{
                    PanelId = 'CSW0801'
                    PhysicalEdidSha256 = 'E49BC570225510B7C889ED292570F1345CAA07F5840DB57EA6998A403DB5CEF0'
                    StableActiveEdidSha256 = @(
                        'E49BC570225510B7C889ED292570F1345CAA07F5840DB57EA6998A403DB5CEF0',
                        '14CDDC390CF69367C4B6821A46728518200446A33F708A1A87CA673B68B66918'
                    )
                }
            }
            'CLAW_A1M_CLAW_7_AI_PLUS' {
                [pscustomobject]@{
                    PanelId = 'TMA2027'
                    PhysicalEdidSha256 = '3518AB4456669D12A7B8D254F63005EAE143C784DCE02EC56C3753C41A664CA1'
                    StableActiveEdidSha256 = @(
                        '3518AB4456669D12A7B8D254F63005EAE143C784DCE02EC56C3753C41A664CA1',
                        '7B5EE7D96BC91E83EBD2419B3A4F12771035D76303F77EEB0E356C996BFA4647'
                    )
                }
            }
            default { $null }
        }
        $activeEdidSha256 = [string]$Lfc.PanelEdidSha256
        if ([int]$backup.SchemaVersion -ne 2 -or
            [string]$backup.FixVersion -ne $script:CoordinatorVersion -or
            [string]$backup.EdidOverrideStateAtSave -ne 'NONE' -or
            $null -eq $knownPanelIdentity -or
            [string]$backup.PhysicalEdidSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or
            -not ([string]$backup.PhysicalEdidSha256).Equals(
                [string]$knownPanelIdentity.PhysicalEdidSha256,
                [StringComparison]::OrdinalIgnoreCase) -or
            'PanelId' -notin $Vrr.PSObject.Properties.Name -or
            -not ([string]$Vrr.PanelId).Equals(
                [string]$knownPanelIdentity.PanelId,
                [StringComparison]::OrdinalIgnoreCase) -or
            'PanelEdidSha256' -notin $Lfc.PSObject.Properties.Name -or
            $activeEdidSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or
            $activeEdidSha256.ToUpperInvariant() -notin
                @($knownPanelIdentity.StableActiveEdidSha256)) {
            return $false
        }

        switch ([string]$backup.BaselinePolicy) {
            'INTEL_STANDARD_BASELINE' {
                return [int]$backup.ProfileId -in @(1, 2)
            }
            'TMA2027_VERIFIED_CUSTOM_30_120' {
                return [string]$backup.PanelKey -eq 'CLAW_A1M_CLAW_7_AI_PLUS' -and
                    [int]$backup.ProfileId -eq 7 -and
                    (Test-ClawLabFrequencyEqual -Left ([float]$backup.MinRefreshRateInHz) -Right 30.0) -and
                    (Test-ClawLabFrequencyEqual -Left ([float]$backup.MaxRefreshRateInHz) -Right 120.0) -and
                    [uint32]$backup.MaxFrameTimeIncreaseInUs -eq 8333 -and
                    [uint32]$backup.MaxFrameTimeDecreaseInUs -eq 8333
            }
            default { return $false }
        }
    }
    catch {
        return $false
    }
}

function Test-ClawLabStableManagedIdentity {
    param(
        [Parameter(Mandatory = $true)][string]$RequestedAction,
        [Parameter(Mandatory = $true)][object]$Vrr,
        [Parameter(Mandatory = $true)][object]$Lfc
    )

    $expected = switch ($RequestedAction) {
        'Install30' {
            [pscustomobject]@{
                Mode = 'CLAWLAB_30_120'; Override = 'CLAWLAB_30_120'
                State = 'CLAWLAB_30_120_ACTIVE'; Range = '30-120 Hz'; MinimumHz = 30.0
                DriftStates = @('CLAWLAB_30_120_PENDING_RESTART', 'DRIVER_PROFILE_CONSTRAINED')
                DriftRanges = @('30-120 Hz', '48-120 Hz', '60-120 Hz')
                DriftMinimumHz = @(30.0, 48.0, 60.0)
            }
        }
        'Install48' {
            [pscustomobject]@{
                Mode = 'OFFICIAL_48_120'; Override = 'NONE'
                State = 'OFFICIAL_48_120_ACTIVE'; Range = '48-120 Hz'; MinimumHz = 48.0
                DriftStates = @('DRIVER_PROFILE_CONSTRAINED')
                DriftRanges = @('48-120 Hz', '60-120 Hz')
                DriftMinimumHz = @(48.0, 60.0)
            }
        }
        default { return $false }
    }

    $arcSyncIdentity = if ($RequestedAction -eq 'Install30' -and
        [string]$Vrr.ArcSyncPolicy -eq 'TMA2027_PRESERVE_EXACT_CUSTOM_30_120') {
        [string]$Vrr.ArcSyncVerification -eq 'TMA2027_CUSTOM_EXACT' -and
            [string]$Vrr.State -eq [string]$expected.State -and
            [string]$Vrr.DriverProfile -eq 'CUSTOM' -and
            [string]$Vrr.DriverActiveRange -eq [string]$expected.Range -and
            (Test-ClawLabFrequencyEqual -Left ([float]$Lfc.CurrentState.MinimumHz) `
                -Right ([float]$expected.MinimumHz)) -and
            (Test-ClawLabFrequencyEqual -Left ([float]$Lfc.CurrentState.MaximumHz) -Right 120.0)
    }
    else {
        $exactHealthyOutput =
            [string]$Vrr.State -eq [string]$expected.State -and
            [string]$Vrr.DriverProfile -eq 'EXCELLENT' -and
            [string]$Vrr.DriverActiveRange -eq [string]$expected.Range -and
            [string]$Vrr.ArcSyncVerification -eq 'EXCELLENT_EXACT' -and
            (Test-ClawLabFrequencyEqual -Left ([float]$Lfc.CurrentState.MinimumHz) `
                -Right ([float]$expected.MinimumHz)) -and
            (Test-ClawLabFrequencyEqual -Left ([float]$Lfc.CurrentState.MaximumHz) -Right 120.0)
        $knownIntelDriverDrift =
            [string]$Vrr.State -in @($expected.DriftStates) -and
            [string]$Vrr.DriverProfile -in @('RECOMMENDED', 'EXCELLENT') -and
            [string]$Vrr.DriverActiveRange -in @($expected.DriftRanges) -and
            [string]$Vrr.ArcSyncVerification -eq 'NOT_VERIFIED' -and
            @($expected.DriftMinimumHz | Where-Object {
                    Test-ClawLabFrequencyEqual -Left ([float]$Lfc.CurrentState.MinimumHz) `
                        -Right ([float]$_)
                }).Count -eq 1 -and
            (Test-ClawLabFrequencyEqual -Left ([float]$Lfc.CurrentState.MaximumHz) -Right 120.0)
        [string]$Vrr.ArcSyncPolicy -eq 'INTEL_EXCELLENT_REQUIRED' -and
            ($exactHealthyOutput -or $knownIntelDriverDrift)
    }

    return (
        [string]$Vrr.ManagedMode -eq [string]$expected.Mode -and
        [string]$Vrr.EdidOverride -eq [string]$expected.Override -and
        [string]$Vrr.ProfileSwitchGuard -in @('CONSISTENT', 'INCONSISTENT_RESTORE_REQUIRED') -and
        $arcSyncIdentity -and
        -not [bool]$Vrr.RecoveryRequired -and
        [string]$Lfc.DriverInterface -eq 'DIRECT_D3DKMT_INTEL_PRIVATE_ESCAPE' -and
        [string]$Lfc.ManagedVrrMode -eq [string]$expected.Mode -and
        [string]$Lfc.ExpectedRange -eq [string]$expected.Range -and
        [string]$Lfc.ThirdPartyEdidOverrideValues -eq 'NONE' -and
        [bool]$Lfc.CurrentState.Supported -and
        [bool]$Lfc.CurrentState.VrrEnabled
    )
}

function Test-ClawLabTrialArtifactsAbsent {
    param([Parameter(Mandatory = $true)][object]$Paths)

    foreach ($path in @(
            $Paths.TrialState, $Paths.TrialLocalScript,
            $Paths.TrialLocalLauncher, $Paths.ProtectedRuntimeRoot
        )) {
        if (Test-Path -LiteralPath $path) { return $false }
    }
    return $null -eq (Get-ClawLabScheduledTaskRecord -TaskName $Paths.TrialTaskName)
}

function Get-ClawLabFreshLfcOriginalStateDisposition {
    param([Parameter(Mandatory = $true)][object]$Lfc)

    $commonCleanState =
        [string]$Lfc.ManagedVrrMode -in @('', 'NONE', 'UNMANAGED') -and
        [string]$Lfc.ExpectedRange -eq 'UNMANAGED' -and
        -not [bool]$Lfc.LfcTransition.BackupPresent -and
        [string]$Lfc.StartupPersistence -eq 'NOT_INSTALLED' -and
        -not [bool]$Lfc.LfcFixActive -and
        [string]$Lfc.ThirdPartyEdidOverrideValues -eq 'NONE' -and
        -not [bool]$Lfc.RestoreTombstonePresent -and
        -not [bool]$Lfc.LfcTransition.RestoreTombstonePresent -and
        -not [bool]$Lfc.FactoryIntentPresent -and
        -not [bool]$Lfc.LfcTransition.FactoryIntentPresent -and
        [bool]$Lfc.LfcBackupIdentity.Accepted -and
        [string]$Lfc.LfcBackupIdentity.State -eq 'NO_BACKUP'
    if (-not $commonCleanState) { return 'INVALID' }

    $factoryDefaults =
        [string]$Lfc.LfcTransition.State -eq 'INTEL_VRR_SOLUTIONS_NOT_PATCHED' -and
        -not [bool]$Lfc.RestoreFinalizedPresent -and
        -not [bool]$Lfc.LfcTransition.RestoreFinalizedPresent -and
        -not [bool]$Lfc.FactoryFinalizedPresent -and
        -not [bool]$Lfc.LfcTransition.FactoryFinalizedPresent -and
        [bool]$Lfc.CurrentState.LowFpsSolutionEnabled -and
        [bool]$Lfc.CurrentState.HighFpsSolutionEnabled
    if ($factoryDefaults) { return 'FACTORY_DEFAULTS' }

    # Restore may legitimately return either Intel solution flag to false. The
    # durable restore-finalized record is the only safe proof that those values
    # are original rather than an unknown modified state. Status construction
    # verifies the record against the current direct-driver state before these
    # fields can be returned.
    $verifiedFinalized =
        [string]$Lfc.LfcTransition.State -eq 'ORIGINAL_LFC_RESTORE_FINALIZED' -and
        [bool]$Lfc.RestoreFinalizedPresent -and
        [bool]$Lfc.LfcTransition.RestoreFinalizedPresent -and
        [bool]$Lfc.LfcTransition.RestoreFinalizedVerified
    if ($verifiedFinalized) { return 'VERIFIED_FINALIZED_PROVENANCE' }

    # The emergency factory-default transaction also keeps a durable, exact
    # terminal provenance record. Status verifies its driver/panel/EDID/target
    # identity and the true/true flags before exposing this state. A future
    # Apply consumes that provenance atomically into a normal LFC backup.
    $verifiedFactoryFinalized =
        [string]$Lfc.LfcTransition.State -eq 'INTEL_VRR_SOLUTIONS_FACTORY_DEFAULTS_FINALIZED' -and
        [bool]$Lfc.FactoryFinalizedPresent -and
        [bool]$Lfc.LfcTransition.FactoryFinalizedPresent -and
        [bool]$Lfc.LfcTransition.FactoryFinalizedVerified -and
        [bool]$Lfc.CurrentState.LowFpsSolutionEnabled -and
        [bool]$Lfc.CurrentState.HighFpsSolutionEnabled
    if ($verifiedFactoryFinalized) { return 'VERIFIED_FACTORY_FINALIZED_PROVENANCE' }

    return 'INVALID'
}

function Get-ClawLabInstallDispositionFromState {
    param(
        [Parameter(Mandatory = $true)][string]$RequestedAction,
        [Parameter(Mandatory = $true)][object]$Vrr,
        [Parameter(Mandatory = $true)][object]$Lfc,
        [bool]$VrrOriginalBackupVerified = $false,
        [bool]$TrialArtifactsAbsent = $false,
        [bool]$RecoveryClear = $false
    )

    $vrrGuard = [string]$Vrr.ProfileSwitchGuard
    $vrrManagedMode = [string]$Vrr.ManagedMode
    $vrrBackupPresent = [bool]$Vrr.OriginalProfileSaved
    $lfcManagedMode = [string]$Lfc.ManagedVrrMode
    $lfcBackupPresent = [bool]$Lfc.LfcTransition.BackupPresent
    $lfcTransitionState = [string]$Lfc.LfcTransition.State
    $expectedCoreVersions = [string]$Vrr.FixVersion -eq $script:CoordinatorVersion -and
        [string]$Lfc.ToolVersion -eq $script:ExpectedLfcToolVersion
    $lfcOriginalStateDisposition = Get-ClawLabFreshLfcOriginalStateDisposition -Lfc $Lfc

    $freshInstall = $expectedCoreVersions -and
        $RecoveryClear -and
        $TrialArtifactsAbsent -and
        $vrrGuard -eq 'CLEAN' -and
        -not $vrrBackupPresent -and
        $vrrManagedMode -in @('', 'NONE', 'UNMANAGED') -and
        [string]$Vrr.EdidOverride -eq 'NONE' -and
        [string]$Vrr.StartupReapply -eq 'NOT_INSTALLED' -and
        [string]$Vrr.CursorRefreshHelper -eq 'NOT_INSTALLED' -and
        [string]$Vrr.IntelGraphicsStartup -in @('INTEL_DEFAULT', 'MISSING_WITHOUT_BACKUP') -and
        -not [bool]$Vrr.RecoveryRequired -and
        -not [bool]$Vrr.RegistryModified -and
        $lfcOriginalStateDisposition -ne 'INVALID'
    if ($freshInstall) {
        return [pscustomobject]@{
            Disposition = 'FRESH_INSTALL'
            ExpectedManagedMode = $null
            LfcOriginalStateDisposition = $lfcOriginalStateDisposition
        }
    }

    # A same-profile repair is intentionally narrower than the core transition
    # policy. It is allowed only for the two stable profiles and only when both
    # exact original-state backups already form one verified 2.3.0 identity.
    # Experimental profiles must complete a normal Restore before another
    # guarded trial; otherwise the coordinator could confuse a confirmed trial
    # with a newly scheduled one.
    $expectedManagedMode = switch ($RequestedAction) {
        'Install30' { 'CLAWLAB_30_120' }
        'Install48' { 'OFFICIAL_48_120' }
        default { $null }
    }
    if ([string]::IsNullOrWhiteSpace($expectedManagedMode)) {
        throw 'CLAWLAB_RESTORE_REQUIRED_BEFORE_INSTALL'
    }
    $lfcIdentityAccepted = $null -ne $Lfc.LfcBackupIdentity -and
        [bool]$Lfc.LfcBackupIdentity.Accepted
    $managedIdentityVerified = $expectedCoreVersions -and
        -not [string]::IsNullOrWhiteSpace($expectedManagedMode) -and
        (Test-ClawLabStableManagedIdentity -RequestedAction $RequestedAction -Vrr $Vrr -Lfc $Lfc)
    $lfcOriginalBackupVerified = $lfcManagedMode -eq $expectedManagedMode -and
        $lfcBackupPresent -and $lfcIdentityAccepted -and
        $lfcTransitionState -ne 'ORIGINAL_LFC_BACKUP_MISSING_CANNOT_RESTORE'
    $repairDisposition = Get-ClawLabStableProfileRepairDisposition `
        -CurrentMode $vrrManagedMode -CurrentState $vrrGuard `
        -DesiredMode $expectedManagedMode -CurrentOverrideState ([string]$Vrr.EdidOverride) `
        -ManagedIdentityVerified $managedIdentityVerified `
        -VrrOriginalBackupVerified $VrrOriginalBackupVerified `
        -LfcOriginalBackupVerified $lfcOriginalBackupVerified `
        -TrialArtifactsAbsent $TrialArtifactsAbsent -RecoveryClear $RecoveryClear
    if ($repairDisposition -eq 'REPAIRABLE_SAME_MODE') {
        return [pscustomobject]@{
            Disposition = 'REPAIRABLE_SAME_MODE'
            ExpectedManagedMode = $expectedManagedMode
        }
    }

    throw 'CLAWLAB_RESTORE_REQUIRED_BEFORE_INSTALL'
}

function Get-ClawLabInstallInitialDisposition {
    param(
        [Parameter(Mandatory = $true)][string]$RequestedAction,
        [Parameter(Mandatory = $true)][string]$CallerSid,
        [Parameter(Mandatory = $true)][string]$CallerLocalAppData,
        [Parameter(Mandatory = $true)][object]$Paths
    )

    # Compensation may consume only backups created by this transaction. A
    # pre-existing managed install must be restored explicitly, never mistaken
    # for a partial write made by the new request.
    $vrr = Invoke-ClawLabCoreAction -ScriptPath $script:VrrToolPath -CoreAction Status `
        -CallerSid $CallerSid -CallerLocalAppData $CallerLocalAppData
    $lfc = Invoke-ClawLabCoreAction -ScriptPath $script:LfcToolPath -CoreAction Status `
        -CallerSid $CallerSid -CallerLocalAppData $CallerLocalAppData
    if ([string]$vrr.Result.FixVersion -ne $script:CoordinatorVersion -or
        [string]$lfc.Result.ToolVersion -ne $script:ExpectedLfcToolVersion) {
        throw "The VRR/LFC core version pair is not the expected 2.3.0 / $($script:ExpectedLfcToolVersion) release identity."
    }
    if ([string]$lfc.Result.LfcTransition.State -eq
        'ORIGINAL_LFC_BACKUP_MISSING_CANNOT_RESTORE') {
        throw 'The Intel LFC state is modified but its exact original backup is missing. Installation was refused before the VRR profile changed.'
    }
    $vrrBackupVerified = Test-ClawLabVrrOriginalBackupVerified -Paths $Paths `
        -Vrr $vrr.Result -Lfc $lfc.Result
    $trialArtifactsAbsent = Test-ClawLabTrialArtifactsAbsent -Paths $Paths
    $recoveryClear = -not [bool]$vrr.Result.RecoveryRequired -and
        -not (Test-Path -LiteralPath $Paths.Journal -PathType Leaf)
    return Get-ClawLabInstallDispositionFromState -RequestedAction $RequestedAction `
        -Vrr $vrr.Result -Lfc $lfc.Result `
        -VrrOriginalBackupVerified $vrrBackupVerified `
        -TrialArtifactsAbsent $trialArtifactsAbsent -RecoveryClear $recoveryClear
}

function Test-ClawLabExperimentalRecoveryJournalEligibleForCleanReconciliation {
    param(
        [AllowNull()][object]$Journal,
        [Parameter(Mandatory = $true)][string]$CallerSid
    )

    if ($null -eq $Journal) { return $false }
    foreach ($property in @(
            'SchemaVersion', 'CoordinatorVersion', 'TransactionId',
            'Action', 'CallerSid', 'Phase'
        )) {
        if ($property -notin $Journal.PSObject.Properties.Name) { return $false }
    }
    $transactionGuid = [Guid]::Empty
    return [int]$Journal.SchemaVersion -eq 1 -and
        [string]$Journal.CoordinatorVersion -eq $script:CoordinatorVersion -and
        [Guid]::TryParse([string]$Journal.TransactionId, [ref]$transactionGuid) -and
        [string]$Journal.Action -in $script:ExperimentalActions -and
        [string]$Journal.Phase -eq 'RECOVERY_REQUIRED' -and
        [string]$Journal.CallerSid -eq $CallerSid
}

function Resolve-ClawLabCleanExperimentalRecoveryJournal {
    param(
        [Parameter(Mandatory = $true)][object]$Journal,
        [Parameter(Mandatory = $true)][object]$Paths,
        [Parameter(Mandatory = $true)][string]$CallerSid,
        [Parameter(Mandatory = $true)][string]$CallerLocalAppData
    )

    if (-not (Test-ClawLabExperimentalRecoveryJournalEligibleForCleanReconciliation `
            -Journal $Journal -CallerSid $CallerSid)) {
        return $false
    }

    # Reconcile only a false recovery journal left by a guarded-scheduling
    # failure whose complete machine state is independently proven clean. No
    # file is removed merely because CHECK_STATUS looks clean: task absence,
    # protected-runtime absence, exact VRR state and verified LFC provenance
    # must all agree first.
    if (-not (Test-ClawLabTrialArtifactsAbsent -Paths $Paths)) { return $false }
    $vrr = Invoke-ClawLabCoreAction -ScriptPath $script:VrrToolPath -CoreAction Status `
        -CallerSid $CallerSid -CallerLocalAppData $CallerLocalAppData
    $lfc = Invoke-ClawLabCoreAction -ScriptPath $script:LfcToolPath -CoreAction Status `
        -CallerSid $CallerSid -CallerLocalAppData $CallerLocalAppData
    $lfcDisposition = Get-ClawLabFreshLfcOriginalStateDisposition -Lfc $lfc.Result
    if ($lfcDisposition -eq 'INVALID') { return $false }

    try {
        [void](Assert-ClawLabFullyRestoredState -Paths $Paths `
                -CallerSid $CallerSid -CallerLocalAppData $CallerLocalAppData `
                -AllowLfcFinalizedProvenance:($lfcDisposition -eq 'VERIFIED_FINALIZED_PROVENANCE') `
                -AllowLfcFactoryFinalizedProvenance:($lfcDisposition -eq 'VERIFIED_FACTORY_FINALIZED_PROVENANCE'))
    }
    catch {
        return $false
    }

    [IO.File]::Delete($Paths.Journal)
    if (Test-Path -LiteralPath $Paths.Journal -PathType Leaf) {
        throw 'The independently clean experimental recovery journal could not be reconciled.'
    }
    return $true
}

function Get-ClawLabStableStatePairDecision {
    param(
        [Parameter(Mandatory = $true)][string]$RequestedAction,
        [Parameter(Mandatory = $true)][object]$Vrr,
        [Parameter(Mandatory = $true)][object]$Lfc
    )

    $vrrState = [string]$Vrr.State
    $lfcState = [string]$Lfc.LfcTransition.State
    if ($RequestedAction -eq 'Install48') {
        if ($vrrState -ne 'OFFICIAL_48_120_ACTIVE') {
            throw "Final VRR verification failed: $vrrState"
        }
        if ($lfcState -ne 'CLAWLAB_LFC_FIX_ACTIVE') {
            throw "The active VRR profile was verified, but Intel LFC is not active: $lfcState"
        }
        return [pscustomobject]@{ RestartVerificationPending = $false; Tma2027Exception = $false }
    }

    if ($RequestedAction -ne 'Install30' -or
        $vrrState -notin @('CLAWLAB_30_120_ACTIVE', 'CLAWLAB_30_120_PENDING_RESTART')) {
        throw "Final VRR verification failed: $vrrState"
    }
    if ($vrrState -eq 'CLAWLAB_30_120_PENDING_RESTART') {
        if ($lfcState -ne 'CLAWLAB_LFC_FIX_PENDING_RESTART') {
            throw "The custom VRR profile requires a restart, but Intel LFC did not enter the matching pending state: $lfcState"
        }
        return [pscustomobject]@{ RestartVerificationPending = $true; Tma2027Exception = $false }
    }
    if ($lfcState -eq 'CLAWLAB_LFC_FIX_ACTIVE') {
        return [pscustomobject]@{ RestartVerificationPending = $false; Tma2027Exception = $false }
    }

    # The exact TMA2027 OEM CUSTOM 30-120 baseline is already active before its
    # EDID restart, while the direct Intel LFC interface correctly remains at
    # physical 48-120 until that restart. Accept this one mixed pair only when
    # every independent TMA policy marker still verifies.
    $verifiedTmaPending = $lfcState -eq 'CLAWLAB_LFC_FIX_PENDING_RESTART' -and
        [string]$Vrr.ArcSyncPolicy -eq 'TMA2027_PRESERVE_EXACT_CUSTOM_30_120' -and
        [string]$Vrr.ArcSyncVerification -eq 'TMA2027_CUSTOM_EXACT' -and
        [string]$Vrr.ManagedMode -eq 'CLAWLAB_30_120' -and
        [string]$Lfc.ManagedVrrMode -eq 'CLAWLAB_30_120'
    if (-not $verifiedTmaPending) {
        throw "The active VRR profile was verified, but Intel LFC is not active: $lfcState"
    }
    return [pscustomobject]@{ RestartVerificationPending = $true; Tma2027Exception = $true }
}

function Assert-ClawLabStableInstallVerified {
    param(
        [Parameter(Mandatory = $true)][string]$RequestedAction,
        [Parameter(Mandatory = $true)][string]$CallerSid,
        [Parameter(Mandatory = $true)][string]$CallerLocalAppData
    )

    $vrr = Invoke-ClawLabCoreAction -ScriptPath $script:VrrToolPath -CoreAction Status `
        -CallerSid $CallerSid -CallerLocalAppData $CallerLocalAppData
    $lfc = Invoke-ClawLabCoreAction -ScriptPath $script:LfcToolPath -CoreAction Status `
        -CallerSid $CallerSid -CallerLocalAppData $CallerLocalAppData
    $vrrState = [string]$vrr.Result.State
    $vrrGuard = [string]$vrr.Result.ProfileSwitchGuard
    $vrrStartup = [string]$vrr.Result.StartupReapply
    $lfcState = [string]$lfc.Result.LfcTransition.State
    if ($vrrGuard -ne 'CONSISTENT') {
        throw "Final VRR managed-state verification failed: $vrrGuard"
    }
    if (-not [bool]$vrr.Result.OriginalProfileSaved) {
        throw 'Final VRR verification found no exact original-profile backup.'
    }
    if ($vrrStartup -in @('', 'NOT_INSTALLED', 'TASK_INVALID', 'TASK_WITHOUT_FILES')) {
        throw "Final VRR startup-persistence verification failed: $vrrStartup"
    }
    if ($lfcState -notin @('CLAWLAB_LFC_FIX_ACTIVE', 'CLAWLAB_LFC_FIX_PENDING_RESTART')) {
        throw "Final Intel LFC verification failed: $lfcState"
    }
    if (-not [bool]$lfc.Result.LfcTransition.BackupPresent) {
        throw 'Final Intel LFC verification found no original-state backup.'
    }
    if ($null -eq $lfc.Result.LfcBackupIdentity -or
        -not [bool]$lfc.Result.LfcBackupIdentity.Accepted) {
        throw 'Final Intel LFC backup identity verification failed.'
    }
    if ([string]$lfc.Result.StartupPersistence -ne 'INSTALLED_ONE_SHOT_AT_LOGON') {
        throw "Final Intel LFC startup-persistence verification failed: $([string]$lfc.Result.StartupPersistence)"
    }
    $pairDecision = Get-ClawLabStableStatePairDecision -RequestedAction $RequestedAction `
        -Vrr $vrr.Result -Lfc $lfc.Result

    return [pscustomobject]@{
        VrrState = $vrrState
        LfcState = $lfcState
        RestartVerificationPending = [bool]$pairDecision.RestartVerificationPending
        Tma2027PendingException = [bool]$pairDecision.Tma2027Exception
    }
}

function Assert-ClawLabExperimentalScheduleVerified {
    param(
        [Parameter(Mandatory = $true)][string]$CallerSid,
        [Parameter(Mandatory = $true)][string]$CallerLocalAppData
    )

    $vrr = Invoke-ClawLabCoreAction -ScriptPath $script:VrrToolPath -CoreAction Status `
        -CallerSid $CallerSid -CallerLocalAppData $CallerLocalAppData
    if ([string]$vrr.Result.ProfileSwitchGuard -ne 'EXPERIMENTAL_TRIAL_PENDING') {
        throw "The guarded experimental trial task was not verified: $([string]$vrr.Result.ProfileSwitchGuard)"
    }
    if (-not [bool]$vrr.Result.OriginalProfileSaved) {
        throw 'The guarded experimental trial has no exact original-profile backup.'
    }
}

function Get-ClawLabRecoveryCleanDecision {
    param(
        [Parameter(Mandatory = $true)][object]$Vrr,
        [Parameter(Mandatory = $true)][object]$Lfc,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$PresentTasks,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$RemainingArtifacts,
        [switch]$AllowLfcRestoreTombstone,
        [switch]$AllowLfcFinalizedProvenance,
        [switch]$AllowLfcFactoryFinalizedProvenance
    )

    $reasons = New-Object 'System.Collections.Generic.List[string]'
    $allowedIntelStartup = @('INTEL_DEFAULT', 'MISSING_WITHOUT_BACKUP')

    if ([string]$Vrr.ManagedMode -ne 'NONE') {
        $reasons.Add("VRR ManagedMode is $([string]$Vrr.ManagedMode), expected NONE.")
    }
    if ([string]$Vrr.ProfileSwitchGuard -ne 'CLEAN') {
        $reasons.Add("VRR ProfileSwitchGuard is $([string]$Vrr.ProfileSwitchGuard), expected CLEAN.")
    }
    if ([bool]$Vrr.OriginalProfileSaved) {
        $reasons.Add('The original VRR profile backup is still present.')
    }
    if ([string]$Vrr.EdidOverride -ne 'NONE') {
        $reasons.Add("The EDID override state is $([string]$Vrr.EdidOverride), expected NONE.")
    }
    if ([string]$Vrr.StartupReapply -ne 'NOT_INSTALLED') {
        $reasons.Add("VRR startup persistence is $([string]$Vrr.StartupReapply), expected NOT_INSTALLED.")
    }
    if ([string]$Vrr.CursorRefreshHelper -ne 'NOT_INSTALLED') {
        $reasons.Add("Cursor Refresh Helper is $([string]$Vrr.CursorRefreshHelper), expected NOT_INSTALLED.")
    }
    if ([string]$Vrr.IntelGraphicsStartup -notin $allowedIntelStartup) {
        $reasons.Add("Intel Graphics Software startup is $([string]$Vrr.IntelGraphicsStartup), not an unmanaged original state.")
    }
    if ([bool]$Vrr.RegistryModified) {
        $reasons.Add('VRR status still reports registry modifications.')
    }
    if ([bool]$Vrr.RecoveryRequired) {
        $reasons.Add('VRR status still reports recovery required.')
    }
    if ([string]$Lfc.ManagedVrrMode -ne 'UNMANAGED') {
        $reasons.Add("Intel LFC ManagedVrrMode is $([string]$Lfc.ManagedVrrMode), expected UNMANAGED.")
    }
    if ([string]$Lfc.ExpectedRange -ne 'UNMANAGED') {
        $reasons.Add("Intel LFC ExpectedRange is $([string]$Lfc.ExpectedRange), expected UNMANAGED.")
    }
    if ([string]$Lfc.StartupPersistence -ne 'NOT_INSTALLED') {
        $reasons.Add("Intel LFC startup persistence is $([string]$Lfc.StartupPersistence), expected NOT_INSTALLED.")
    }
    if ([bool]$Lfc.LfcFixActive) {
        $reasons.Add('Intel LFC still reports the ClawLab correction as active.')
    }
    if ([bool]$Lfc.LfcTransition.BackupPresent) {
        $reasons.Add('The original Intel LFC backup is still present.')
    }
    $lfcCommittedPendingFinalize = $AllowLfcRestoreTombstone -and
        [string]$Lfc.LfcTransition.State -eq 'ORIGINAL_LFC_RESTORE_COMMITTED_PENDING_FINALIZE' -and
        [bool]$Lfc.RestoreTombstonePresent
    $lfcFinalizedProvenance = $AllowLfcFinalizedProvenance -and
        [string]$Lfc.LfcTransition.State -eq 'ORIGINAL_LFC_RESTORE_FINALIZED' -and
        [bool]$Lfc.RestoreFinalizedPresent -and
        [bool]$Lfc.LfcTransition.RestoreFinalizedVerified
    $lfcFactoryFinalizedProvenance = $AllowLfcFactoryFinalizedProvenance -and
        [string]$Lfc.LfcTransition.State -eq 'INTEL_VRR_SOLUTIONS_FACTORY_DEFAULTS_FINALIZED' -and
        -not [bool]$Lfc.FactoryIntentPresent -and
        -not [bool]$Lfc.LfcTransition.FactoryIntentPresent -and
        [bool]$Lfc.FactoryFinalizedPresent -and
        [bool]$Lfc.LfcTransition.FactoryFinalizedPresent -and
        [bool]$Lfc.LfcTransition.FactoryFinalizedVerified -and
        [bool]$Lfc.CurrentState.LowFpsSolutionEnabled -and
        [bool]$Lfc.CurrentState.HighFpsSolutionEnabled
    if ([bool]$Lfc.FactoryIntentPresent -or [bool]$Lfc.LfcTransition.FactoryIntentPresent) {
        $reasons.Add('An Intel LFC factory-default transaction intent is still pending recovery.')
    }
    if ([string]$Lfc.LfcTransition.State -ne 'INTEL_VRR_SOLUTIONS_NOT_PATCHED' -and
        -not $lfcCommittedPendingFinalize -and -not $lfcFinalizedProvenance -and
        -not $lfcFactoryFinalizedProvenance) {
        $reasons.Add("Intel LFC transition is $([string]$Lfc.LfcTransition.State), expected INTEL_VRR_SOLUTIONS_NOT_PATCHED.")
    }
    foreach ($taskName in @($PresentTasks)) {
        $reasons.Add("Scheduled task remains installed: $taskName")
    }
    foreach ($artifactPath in @($RemainingArtifacts)) {
        $reasons.Add("Managed artifact remains: $artifactPath")
    }

    return [pscustomobject]@{
        Clean = $reasons.Count -eq 0
        Reasons = @($reasons)
    }
}

function Get-ClawLabRemainingManagedArtifacts {
    param(
        [Parameter(Mandatory = $true)][object]$Paths,
        [switch]$VrrOnly
    )

    $remaining = New-Object 'System.Collections.Generic.List[string]'
    $artifactPaths = @($Paths.VrrArtifacts)
    if (-not $VrrOnly) { $artifactPaths += @($Paths.LfcArtifacts) }
    foreach ($path in $artifactPaths) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $remaining.Add([string]$path)
        }
    }
    if (Test-Path -LiteralPath $Paths.ProtectedRuntimeBaseRoot) {
        $runtimeBase = Get-Item -LiteralPath $Paths.ProtectedRuntimeBaseRoot -Force
        if (-not $runtimeBase.PSIsContainer -or
            ($runtimeBase.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            $remaining.Add([string]$Paths.ProtectedRuntimeBaseRoot)
        }
        else {
            foreach ($entry in @([IO.Directory]::EnumerateFileSystemEntries(
                        [string]$Paths.ProtectedRuntimeBaseRoot))) {
                $remaining.Add([string]$entry)
            }
        }
    }
    return @($remaining)
}

function Assert-ClawLabVrrRestoredState {
    param(
        [Parameter(Mandatory = $true)][object]$Paths,
        [Parameter(Mandatory = $true)][string]$CallerSid,
        [Parameter(Mandatory = $true)][string]$CallerLocalAppData
    )

    $vrr = Invoke-ClawLabCoreAction -ScriptPath $script:VrrToolPath -CoreAction Status `
        -CallerSid $CallerSid -CallerLocalAppData $CallerLocalAppData
    $presentTasks = New-Object 'System.Collections.Generic.List[string]'
    foreach ($taskName in @($Paths.VrrTaskName, $Paths.CursorTaskName, $Paths.TrialTaskName)) {
        if ($null -ne (Get-ClawLabScheduledTaskRecord -TaskName $taskName)) {
            $presentTasks.Add([string]$taskName)
        }
    }
    $knownCleanLfc = [pscustomobject]@{
        ManagedVrrMode = 'UNMANAGED'
        ExpectedRange = 'UNMANAGED'
        StartupPersistence = 'NOT_INSTALLED'
        LfcFixActive = $false
        RestoreFinalizedPresent = $false
        FactoryIntentPresent = $false
        FactoryFinalizedPresent = $false
        CurrentState = [pscustomobject]@{
            LowFpsSolutionEnabled = $true
            HighFpsSolutionEnabled = $true
        }
        LfcTransition = [pscustomobject]@{
            State = 'INTEL_VRR_SOLUTIONS_NOT_PATCHED'
            BackupPresent = $false
            RestoreTombstonePresent = $false
            RestoreFinalizedPresent = $false
            RestoreFinalizedVerified = $false
            FactoryIntentPresent = $false
            FactoryFinalizedPresent = $false
            FactoryFinalizedVerified = $false
        }
    }
    $decision = Get-ClawLabRecoveryCleanDecision -Vrr $vrr.Result -Lfc $knownCleanLfc `
        -PresentTasks @($presentTasks) `
        -RemainingArtifacts @(Get-ClawLabRemainingManagedArtifacts -Paths $Paths -VrrOnly)
    if (-not $decision.Clean) {
        throw ('The VRR restore backup is absent and the VRR state is not fully clean: ' +
            ($decision.Reasons -join ' | '))
    }
    return $decision
}

function Resolve-ClawLabVrrStateWithoutBackup {
    param(
        [Parameter(Mandatory = $true)][object]$Paths,
        [Parameter(Mandatory = $true)][string]$CallerSid,
        [Parameter(Mandatory = $true)][string]$CallerLocalAppData,
        [AllowNull()][object]$Journal
    )

    $uncleanReason = $null
    try {
        [void](Assert-ClawLabVrrRestoredState -Paths $Paths -CallerSid $CallerSid `
                -CallerLocalAppData $CallerLocalAppData)
        return [pscustomobject]@{
            Disposition = 'ALREADY_CLEAN_WITHOUT_BACKUP'
            RecoveryApplied = $false
        }
    }
    catch {
        $uncleanReason = [string]$_.Exception.Message
    }

    try {
        [void](Invoke-ClawLabCoreAction -ScriptPath $script:VrrToolPath `
                -CoreAction RecoverOrphanedDefaultState -CallerSid $CallerSid `
                -CallerLocalAppData $CallerLocalAppData)
        if ($null -ne $Journal) {
            Set-ClawLabTransactionPhase -Journal $Journal `
                -Phase 'ORPHANED_DEFAULT_VRR_SHELL_CLEANED' `
                -JournalPath $Paths.Journal
        }
        [void](Assert-ClawLabVrrRestoredState -Paths $Paths -CallerSid $CallerSid `
                -CallerLocalAppData $CallerLocalAppData)
        return [pscustomobject]@{
            Disposition = 'ORPHANED_DEFAULT_VRR_SHELL_CLEANED'
            RecoveryApplied = $true
        }
    }
    catch {
        throw ('The VRR restore backup is absent. The state was not already clean, ' +
            'and bounded orphaned-default recovery was refused: ' + $uncleanReason +
            ' | ' + [string]$_.Exception.Message)
    }
}

function Assert-ClawLabFullyRestoredState {
    param(
        [Parameter(Mandatory = $true)][object]$Paths,
        [Parameter(Mandatory = $true)][string]$CallerSid,
        [Parameter(Mandatory = $true)][string]$CallerLocalAppData,
        [switch]$AllowLfcRestoreTombstone,
        [switch]$AllowLfcFinalizedProvenance,
        [switch]$AllowLfcFactoryFinalizedProvenance
    )

    $vrr = Invoke-ClawLabCoreAction -ScriptPath $script:VrrToolPath -CoreAction Status `
        -CallerSid $CallerSid -CallerLocalAppData $CallerLocalAppData
    $lfc = Invoke-ClawLabCoreAction -ScriptPath $script:LfcToolPath -CoreAction Status `
        -CallerSid $CallerSid -CallerLocalAppData $CallerLocalAppData

    $presentTasks = New-Object 'System.Collections.Generic.List[string]'
    foreach ($taskName in @(
            $Paths.VrrTaskName,
            $Paths.CursorTaskName,
            $Paths.LfcTaskName,
            $Paths.TrialTaskName
        )) {
        if ($null -ne (Get-ClawLabScheduledTaskRecord -TaskName $taskName)) {
            $presentTasks.Add([string]$taskName)
        }
    }
    $remainingArtifacts = Get-ClawLabRemainingManagedArtifacts -Paths $Paths
    if ($AllowLfcRestoreTombstone) {
        $remainingArtifacts = @($remainingArtifacts | Where-Object {
                -not ([string]$_).Equals([string]$Paths.LfcRestoreCommitted,
                    [StringComparison]::OrdinalIgnoreCase)
            })
    }
    if ($AllowLfcFinalizedProvenance) {
        $remainingArtifacts = @($remainingArtifacts | Where-Object {
                -not ([string]$_).Equals([string]$Paths.LfcRestoreFinalized,
                    [StringComparison]::OrdinalIgnoreCase)
            })
    }
    if ($AllowLfcFactoryFinalizedProvenance) {
        $remainingArtifacts = @($remainingArtifacts | Where-Object {
                -not ([string]$_).Equals([string]$Paths.LfcFactoryFinalized,
                    [StringComparison]::OrdinalIgnoreCase)
            })
    }
    $decision = Get-ClawLabRecoveryCleanDecision -Vrr $vrr.Result -Lfc $lfc.Result `
        -PresentTasks @($presentTasks) -RemainingArtifacts @($remainingArtifacts) `
        -AllowLfcRestoreTombstone:$AllowLfcRestoreTombstone `
        -AllowLfcFinalizedProvenance:$AllowLfcFinalizedProvenance `
        -AllowLfcFactoryFinalizedProvenance:$AllowLfcFactoryFinalizedProvenance
    if (-not $decision.Clean) {
        throw ('Complete restoration could not be verified: ' + ($decision.Reasons -join ' | '))
    }
    return $decision
}

function Assert-ClawLabLfcFactoryFinalizedState {
    param(
        [Parameter(Mandatory = $true)][string]$CallerSid,
        [Parameter(Mandatory = $true)][string]$CallerLocalAppData
    )

    $status = Invoke-ClawLabCoreAction -ScriptPath $script:LfcToolPath -CoreAction Status `
        -CallerSid $CallerSid -CallerLocalAppData $CallerLocalAppData
    $lfc = $status.Result
    $verified =
        [string]$lfc.ManagedVrrMode -eq 'UNMANAGED' -and
        [string]$lfc.ExpectedRange -eq 'UNMANAGED' -and
        [string]$lfc.StartupPersistence -eq 'NOT_INSTALLED' -and
        -not [bool]$lfc.LfcFixActive -and
        -not [bool]$lfc.LfcTransition.BackupPresent -and
        -not [bool]$lfc.FactoryIntentPresent -and
        -not [bool]$lfc.LfcTransition.FactoryIntentPresent -and
        [bool]$lfc.FactoryFinalizedPresent -and
        [bool]$lfc.LfcTransition.FactoryFinalizedPresent -and
        [bool]$lfc.LfcTransition.FactoryFinalizedVerified -and
        [string]$lfc.LfcTransition.State -eq 'INTEL_VRR_SOLUTIONS_FACTORY_DEFAULTS_FINALIZED' -and
        [bool]$lfc.CurrentState.LowFpsSolutionEnabled -and
        [bool]$lfc.CurrentState.HighFpsSolutionEnabled
    if (-not $verified) {
        throw 'Intel LFC factory-default finalization could not be independently verified.'
    }
    return $lfc
}

function Invoke-ClawLabExactRestore {
    param(
        [Parameter(Mandatory = $true)][object]$Paths,
        [Parameter(Mandatory = $true)][string]$CallerSid,
        [Parameter(Mandatory = $true)][string]$CallerLocalAppData,
        [Parameter(Mandatory = $true)][object]$Journal
    )

    # TMA2027 recovery validates the restored Intel low/high-FPS solution flags
    # before it permits Arc Sync/EDID cleanup. Therefore LFC must be restored
    # first. PrepareRestore applies and verifies the saved flags while retaining
    # their exact backup. Only after VRR/EDID restoration verifies does Commit
    # convert that backup into durable recovery provenance, making every stage
    # restartable after an interruption.
    [void](Invoke-ClawLabCoreAction -ScriptPath $script:LfcToolPath -CoreAction PrepareRestore `
            -CallerSid $CallerSid -CallerLocalAppData $CallerLocalAppData)
    Set-ClawLabTransactionPhase -Journal $Journal -Phase 'LFC_RESTORE_PREPARED' `
        -JournalPath $Paths.Journal

    if (Test-Path -LiteralPath $Paths.VrrBackup -PathType Leaf) {
        [void](Invoke-ClawLabCoreAction -ScriptPath $script:VrrToolPath -CoreAction Restore `
                -CallerSid $CallerSid -CallerLocalAppData $CallerLocalAppData)
    }
    else {
        # A missing original backup is normally only an idempotent success when
        # every independent state is clean. One additional bounded path accepts
        # the exact known Intel factory profile plus one owned stale legacy task
        # and removes only that ClawLab shell, without writing display state.
        [void](Resolve-ClawLabVrrStateWithoutBackup -Paths $Paths `
                -CallerSid $CallerSid -CallerLocalAppData $CallerLocalAppData `
                -Journal $Journal)
    }
    Set-ClawLabTransactionPhase -Journal $Journal -Phase 'VRR_RESTORED' `
        -JournalPath $Paths.Journal

    [void](Invoke-ClawLabCoreAction -ScriptPath $script:LfcToolPath -CoreAction CommitRestore `
            -CallerSid $CallerSid -CallerLocalAppData $CallerLocalAppData)
    Set-ClawLabTransactionPhase -Journal $Journal -Phase 'LFC_RESTORE_COMMITTED' `
        -JournalPath $Paths.Journal

    # CommitRestore atomically converts the exact backup into a tombstone. The
    # tombstone survives a power loss until the complete VRR/LFC cleanup has
    # been independently verified; FinalizeRestore then converts it atomically
    # into durable finalized provenance rather than discarding the evidence.
    [void](Assert-ClawLabFullyRestoredState -Paths $Paths -CallerSid $CallerSid `
            -CallerLocalAppData $CallerLocalAppData -AllowLfcRestoreTombstone `
            -AllowLfcFinalizedProvenance `
            -AllowLfcFactoryFinalizedProvenance)
    [void](Invoke-ClawLabCoreAction -ScriptPath $script:LfcToolPath -CoreAction FinalizeRestore `
            -CallerSid $CallerSid -CallerLocalAppData $CallerLocalAppData)
    Set-ClawLabTransactionPhase -Journal $Journal -Phase 'LFC_RESTORE_FINALIZED' `
        -JournalPath $Paths.Journal

    [void](Assert-ClawLabFullyRestoredState -Paths $Paths -CallerSid $CallerSid `
            -CallerLocalAppData $CallerLocalAppData -AllowLfcFinalizedProvenance `
            -AllowLfcFactoryFinalizedProvenance)
}

function Invoke-ClawLabInstallRollback {
    param(
        [Parameter(Mandatory = $true)][object]$Paths,
        [Parameter(Mandatory = $true)][string]$CallerSid,
        [Parameter(Mandatory = $true)][string]$CallerLocalAppData
    )

    Write-CoordinatorText -Key 'transaction_rollback_started' -ForegroundColor Yellow
    $failures = New-Object 'System.Collections.Generic.List[string]'

    # TMA2027 requires the exact Intel low/high-FPS flags to be restored before
    # the VRR/EDID state can be accepted for cleanup. If the later VRR stage
    # fails, the journal remains and Restore can safely resume that stage.
    try {
        # Restore is intentionally called even when the backup is absent: the
        # LFC core then removes any orphaned persistence and verifies that both
        # Intel solution flags are already at their safe original defaults.
        [void](Invoke-ClawLabCoreAction -ScriptPath $script:LfcToolPath -CoreAction PrepareRestore `
                -CallerSid $CallerSid -CallerLocalAppData $CallerLocalAppData)
    }
    catch { $failures.Add($_.Exception.Message) }

    if ($failures.Count -eq 0 -and (Test-Path -LiteralPath $Paths.VrrBackup -PathType Leaf)) {
        try {
            [void](Invoke-ClawLabCoreAction -ScriptPath $script:VrrToolPath -CoreAction Restore `
                    -CallerSid $CallerSid -CallerLocalAppData $CallerLocalAppData)
        }
        catch { $failures.Add($_.Exception.Message) }
    }

    if ($failures.Count -eq 0 -and -not (Test-Path -LiteralPath $Paths.VrrBackup -PathType Leaf)) {
        try {
            [void](Resolve-ClawLabVrrStateWithoutBackup -Paths $Paths `
                    -CallerSid $CallerSid -CallerLocalAppData $CallerLocalAppData)
        }
        catch { $failures.Add($_.Exception.Message) }
    }

    if ($failures.Count -eq 0) {
        try {
            [void](Invoke-ClawLabCoreAction -ScriptPath $script:LfcToolPath -CoreAction CommitRestore `
                    -CallerSid $CallerSid -CallerLocalAppData $CallerLocalAppData)
        }
        catch { $failures.Add($_.Exception.Message) }
    }

    if ($failures.Count -eq 0) {
        try {
            [void](Assert-ClawLabFullyRestoredState -Paths $Paths -CallerSid $CallerSid `
                    -CallerLocalAppData $CallerLocalAppData -AllowLfcRestoreTombstone `
                    -AllowLfcFinalizedProvenance `
                    -AllowLfcFactoryFinalizedProvenance)
            [void](Invoke-ClawLabCoreAction -ScriptPath $script:LfcToolPath -CoreAction FinalizeRestore `
                    -CallerSid $CallerSid -CallerLocalAppData $CallerLocalAppData)
            [void](Assert-ClawLabFullyRestoredState -Paths $Paths -CallerSid $CallerSid `
                    -CallerLocalAppData $CallerLocalAppData -AllowLfcFinalizedProvenance `
                    -AllowLfcFactoryFinalizedProvenance)
            Write-CoordinatorText -Key 'transaction_rollback_success' -ForegroundColor Green
            return [pscustomobject]@{ Verified = $true; Details = $null }
        }
        catch { $failures.Add($_.Exception.Message) }
    }

    if ($failures.Count -eq 0) {
        $failures.Add('The complete original state could not be verified after rollback.')
    }
    Write-CoordinatorText -Key 'transaction_rollback_failed' -ForegroundColor Red
    return [pscustomobject]@{ Verified = $false; Details = ($failures -join ' | ') }
}

function Invoke-ClawLabElevatedOperation {
    param(
        [Parameter(Mandatory = $true)][object]$Identity,
        [Parameter(Mandatory = $true)][object]$Paths,
        [Parameter(Mandatory = $true)][string]$RequestedAction,
        [Parameter(Mandatory = $true)][string]$Id
    )

    $transactionMutex = $null
    $startupMutex = $null
    $transactionAcquired = $false
    $startupAcquired = $false
    $journal = $null
    $result = $null
    $installDisposition = $null
    $identityVerified = $false
    try {
        [void](Assert-ClawLabElevatedIdentity -Actual $Identity `
                -CallerSid $ExpectedCallerSid -CallerSessionId $ExpectedCallerSessionId `
                -CallerLocalAppData $ExpectedCallerLocalAppData)
        $identityVerified = $true

        # Display/driver state is machine-global, so these locks must cross
        # Fast User Switching and RDP sessions as well as process boundaries.
        # A different account that cannot open the creator ACL fails closed.
        $transactionMutex = [Threading.Mutex]::new($false, 'Global\ClawLab.VRR.DisplayTransaction')
        $startupMutex = [Threading.Mutex]::new($false, 'Global\ClawLab.MSIClaw.VrrApplyStartup')
        try { $transactionAcquired = $transactionMutex.WaitOne(0) }
        catch [Threading.AbandonedMutexException] { $transactionAcquired = $true }
        if (-not $transactionAcquired) { throw 'CLAWLAB_TRANSACTION_BUSY' }
        try { $startupAcquired = $startupMutex.WaitOne(0) }
        catch [Threading.AbandonedMutexException] { $startupAcquired = $true }
        if (-not $startupAcquired) { throw 'CLAWLAB_TRANSACTION_BUSY' }

        [void](Assert-ClawLabLocalStateRootsSafe -LocalAppData $Identity.LocalAppData `
                -Paths $Paths)

        $previous = Read-ClawLabJsonFile -LiteralPath $Paths.Journal
        if ($null -ne $previous -and $RequestedAction -notin $script:RecoveryActions) {
            $reconciled = $RequestedAction -in $script:InstallActions -and
                (Resolve-ClawLabCleanExperimentalRecoveryJournal -Journal $previous `
                    -Paths $Paths -CallerSid $Identity.Sid `
                    -CallerLocalAppData $Identity.LocalAppData)
            if (-not $reconciled) {
                throw 'CLAWLAB_INTERRUPTED_TRANSACTION'
            }
        }
        if ($RequestedAction -in $script:InstallActions) {
            $installDisposition = Get-ClawLabInstallInitialDisposition `
                -RequestedAction $RequestedAction -CallerSid $Identity.Sid `
                -CallerLocalAppData $Identity.LocalAppData -Paths $Paths
            if ([string]$installDisposition.Disposition -eq 'FRESH_INSTALL') {
                [void](Assert-ClawLabFullyRestoredState -Paths $Paths `
                        -CallerSid $Identity.Sid -CallerLocalAppData $Identity.LocalAppData `
                        -AllowLfcFinalizedProvenance:(
                            [string]$installDisposition.LfcOriginalStateDisposition -eq
                            'VERIFIED_FINALIZED_PROVENANCE') `
                        -AllowLfcFactoryFinalizedProvenance:(
                            [string]$installDisposition.LfcOriginalStateDisposition -eq
                            'VERIFIED_FACTORY_FINALIZED_PROVENANCE'))
            }
        }
        $journal = New-ClawLabTransactionJournal -RequestedAction $RequestedAction `
            -Identity $Identity -Id $Id -Previous $previous
        Write-ClawLabJsonAtomic -LiteralPath $Paths.Journal -Value $journal

        if ($RequestedAction -in $script:StableActions) {
            $label = Get-ClawLabProfileLabel -RequestedAction $RequestedAction
            Write-CoordinatorText -Key 'install_started' -Arguments @($label) -ForegroundColor Cyan
            Set-ClawLabTransactionPhase -Journal $journal -Phase 'PREFLIGHT_VERIFIED' `
                -JournalPath $Paths.Journal
            try {
                $vrrCoreAction = if ([string]$installDisposition.Disposition -eq 'REPAIRABLE_SAME_MODE') {
                    if ($RequestedAction -eq 'Install30') { 'Repair30' } else { 'Repair48' }
                }
                else {
                    $RequestedAction
                }
                [void](Invoke-ClawLabCoreAction -ScriptPath $script:VrrToolPath `
                        -CoreAction $vrrCoreAction -CallerSid $Identity.Sid `
                        -CallerLocalAppData $Identity.LocalAppData)
                Set-ClawLabTransactionPhase -Journal $journal -Phase 'VRR_APPLIED' `
                    -JournalPath $Paths.Journal
                [void](Invoke-ClawLabCoreAction -ScriptPath $script:LfcToolPath `
                        -CoreAction Apply -CallerSid $Identity.Sid `
                        -CallerLocalAppData $Identity.LocalAppData)
                Set-ClawLabTransactionPhase -Journal $journal -Phase 'LFC_APPLIED' `
                    -JournalPath $Paths.Journal
                $stableVerification = Assert-ClawLabStableInstallVerified -RequestedAction $RequestedAction `
                    -CallerSid $Identity.Sid -CallerLocalAppData $Identity.LocalAppData
                Set-ClawLabTransactionPhase -Journal $journal -Phase 'VRR_AND_LFC_VERIFIED' `
                    -JournalPath $Paths.Journal -Detail ($stableVerification | ConvertTo-Json -Compress)
            }
            catch {
                $failure = $_.Exception.Message
                if ([string]$installDisposition.Disposition -eq 'REPAIRABLE_SAME_MODE') {
                    # Never consume a pre-existing verified backup to compensate
                    # a repair attempt. Preserve it and require explicit Restore
                    # if the repair cannot be jointly verified.
                    Set-ClawLabTransactionPhase -Journal $journal -Phase 'REPAIR_INCOMPLETE' `
                        -JournalPath $Paths.Journal -Detail $failure
                    throw "Same-profile repair failed. The existing original-state backups were preserved; run Restore before another install attempt. $failure"
                }
                Set-ClawLabTransactionPhase -Journal $journal -Phase 'ROLLBACK_STARTED' `
                    -JournalPath $Paths.Journal -Detail $failure
                $rollback = Invoke-ClawLabInstallRollback -Paths $Paths `
                    -CallerSid $Identity.Sid -CallerLocalAppData $Identity.LocalAppData
                if (-not $rollback.Verified) {
                    Set-ClawLabTransactionPhase -Journal $journal -Phase 'RECOVERY_REQUIRED' `
                        -JournalPath $Paths.Journal -Detail ("$failure | $($rollback.Details)")
                    throw "Installation failed and verified rollback was not possible: $failure | $($rollback.Details)"
                }
                Set-ClawLabTransactionPhase -Journal $journal -Phase 'ROLLED_BACK' `
                    -JournalPath $Paths.Journal -Detail $failure
                [IO.File]::Delete($Paths.Journal)
                throw "Installation failed; incomplete changes were rolled back: $failure"
            }
        }
        elseif ($RequestedAction -in $script:ExperimentalActions) {
            $label = Get-ClawLabProfileLabel -RequestedAction $RequestedAction
            Write-CoordinatorText -Key 'install_started' -Arguments @($label) -ForegroundColor Cyan
            try {
                [void](Invoke-ClawLabCoreAction -ScriptPath $script:VrrToolPath `
                        -CoreAction $RequestedAction -CallerSid $Identity.Sid `
                        -CallerLocalAppData $Identity.LocalAppData)
                Assert-ClawLabExperimentalScheduleVerified -CallerSid $Identity.Sid `
                    -CallerLocalAppData $Identity.LocalAppData
                Set-ClawLabTransactionPhase -Journal $journal -Phase 'GUARDED_TRIAL_SCHEDULED' `
                    -JournalPath $Paths.Journal
            }
            catch {
                $failure = $_.Exception.Message
                Set-ClawLabTransactionPhase -Journal $journal -Phase 'ROLLBACK_STARTED' `
                    -JournalPath $Paths.Journal -Detail $failure
                $rollback = Invoke-ClawLabInstallRollback -Paths $Paths `
                    -CallerSid $Identity.Sid -CallerLocalAppData $Identity.LocalAppData
                if (-not $rollback.Verified) {
                    Set-ClawLabTransactionPhase -Journal $journal -Phase 'RECOVERY_REQUIRED' `
                        -JournalPath $Paths.Journal -Detail ("$failure | $($rollback.Details)")
                    throw "Experimental scheduling failed and rollback was not verified: $failure | $($rollback.Details)"
                }
                [IO.File]::Delete($Paths.Journal)
                throw "Experimental scheduling failed; incomplete changes were rolled back: $failure"
            }
        }
        elseif ($RequestedAction -eq 'UpdateCursorHelper') {
            Write-CoordinatorText -Key 'install_started' `
                -Arguments @('Cursor Refresh Engine') -ForegroundColor Cyan
            [void](Invoke-ClawLabCoreAction -ScriptPath $script:VrrToolPath `
                    -CoreAction UpdateCursorRefresh -CallerSid $Identity.Sid `
                    -CallerLocalAppData $Identity.LocalAppData)
            Set-ClawLabTransactionPhase -Journal $journal -Phase 'CURSOR_ENGINE_UPDATED' `
                -JournalPath $Paths.Journal
        }
        elseif ($RequestedAction -eq 'Restore') {
            Write-CoordinatorText -Key 'restore_started' -ForegroundColor Cyan
            Invoke-ClawLabExactRestore -Paths $Paths -CallerSid $Identity.Sid `
                -CallerLocalAppData $Identity.LocalAppData -Journal $journal
        }
        elseif ($RequestedAction -eq 'FactoryReset') {
            # Same TMA2027 contract as exact restore: restore LFC before the
            # VRR factory-reset proof is evaluated.
            [void](Invoke-ClawLabCoreAction -ScriptPath $script:LfcToolPath -CoreAction PrepareRestore `
                    -CallerSid $Identity.Sid -CallerLocalAppData $Identity.LocalAppData)
            Set-ClawLabTransactionPhase -Journal $journal -Phase 'LFC_RESTORE_PREPARED' `
                -JournalPath $Paths.Journal
            [void](Invoke-ClawLabCoreAction -ScriptPath $script:VrrToolPath -CoreAction FactoryReset `
                    -CallerSid $Identity.Sid -CallerLocalAppData $Identity.LocalAppData)
            [void](Invoke-ClawLabCoreAction -ScriptPath $script:LfcToolPath -CoreAction CommitRestore `
                    -CallerSid $Identity.Sid -CallerLocalAppData $Identity.LocalAppData)
            [void](Assert-ClawLabFullyRestoredState -Paths $Paths `
                    -CallerSid $Identity.Sid -CallerLocalAppData $Identity.LocalAppData `
                    -AllowLfcRestoreTombstone -AllowLfcFactoryFinalizedProvenance)
            [void](Invoke-ClawLabCoreAction -ScriptPath $script:LfcToolPath -CoreAction FinalizeRestore `
                    -CallerSid $Identity.Sid -CallerLocalAppData $Identity.LocalAppData)
            [void](Assert-ClawLabFullyRestoredState -Paths $Paths `
                    -CallerSid $Identity.Sid -CallerLocalAppData $Identity.LocalAppData `
                    -AllowLfcFinalizedProvenance -AllowLfcFactoryFinalizedProvenance)
            Set-ClawLabTransactionPhase -Journal $journal -Phase 'VRR_FACTORY_RESET' `
                -JournalPath $Paths.Journal
        }
        elseif ($RequestedAction -eq 'RestoreLfcOnly') {
            [void](Invoke-ClawLabCoreAction -ScriptPath $script:LfcToolPath -CoreAction PrepareRestore `
                    -CallerSid $Identity.Sid -CallerLocalAppData $Identity.LocalAppData)
            Set-ClawLabTransactionPhase -Journal $journal -Phase 'LFC_RESTORED_BACKUP_RETAINED' `
                -JournalPath $Paths.Journal
        }
        elseif ($RequestedAction -eq 'FactoryLfcDefaults') {
            [void](Invoke-ClawLabCoreAction -ScriptPath $script:LfcToolPath -CoreAction FactoryDefaults `
                    -CallerSid $Identity.Sid -CallerLocalAppData $Identity.LocalAppData)
            [void](Assert-ClawLabLfcFactoryFinalizedState -CallerSid $Identity.Sid `
                    -CallerLocalAppData $Identity.LocalAppData)
            $vrrCleanFailure = $null
            try {
                [void](Assert-ClawLabVrrRestoredState -Paths $Paths -CallerSid $Identity.Sid `
                        -CallerLocalAppData $Identity.LocalAppData)
            }
            catch {
                $vrrCleanFailure = $_.Exception.Message
            }
            if (-not [string]::IsNullOrWhiteSpace($vrrCleanFailure)) {
                Set-ClawLabTransactionPhase -Journal $journal `
                    -Phase 'LFC_FACTORY_DEFAULTS_RECOVERY_REQUIRED' -JournalPath $Paths.Journal `
                    -Detail $vrrCleanFailure
                $result = [pscustomobject]@{
                    SchemaVersion = 1; CoordinatorVersion = $script:CoordinatorVersion
                    TransactionId = $Id; Action = $RequestedAction; Success = $true
                    RestartRequired = $false; RecoveryRequired = $true
                    Message = $vrrCleanFailure
                }
                Write-ClawLabJsonAtomic -LiteralPath $Paths.Result -Value $result
                return $result
            }
            Set-ClawLabTransactionPhase -Journal $journal -Phase 'LFC_FACTORY_DEFAULTS' `
                -JournalPath $Paths.Journal
        }
        elseif ($RequestedAction -eq 'EmergencyRestoreEdid') {
            [void](Invoke-ClawLabCoreAction -ScriptPath $script:VrrToolPath `
                    -CoreAction EmergencyRestoreEdid -CallerSid $Identity.Sid `
                    -CallerLocalAppData $Identity.LocalAppData -AllowEmptySuccess)
            Set-ClawLabTransactionPhase -Journal $journal -Phase 'EMERGENCY_EDID_REMOVED_RECOVERY_REQUIRED' `
                -JournalPath $Paths.Journal
            $result = [pscustomobject]@{
                SchemaVersion = 1; CoordinatorVersion = $script:CoordinatorVersion
                TransactionId = $Id; Action = $RequestedAction; Success = $true
                RestartRequired = $true; RecoveryRequired = $true; Message = $null
            }
            Write-ClawLabJsonAtomic -LiteralPath $Paths.Result -Value $result
            return $result
        }

        Set-ClawLabTransactionPhase -Journal $journal -Phase 'COMMITTED' `
            -JournalPath $Paths.Journal
        [IO.File]::Delete($Paths.Journal)
        $result = [pscustomobject]@{
            SchemaVersion = 1
            CoordinatorVersion = $script:CoordinatorVersion
            TransactionId = $Id
            Action = $RequestedAction
            Success = $true
            RestartRequired = $RequestedAction -in $script:RestartActions
            RecoveryRequired = $false
            Message = $null
        }
        Write-ClawLabJsonAtomic -LiteralPath $Paths.Result -Value $result
        return $result
    }
    catch {
        $message = $_.Exception.Message
        if ($RequestedAction -in $script:MaintenanceActions -and
            (Test-Path -LiteralPath $Paths.Journal -PathType Leaf)) {
            # Cursor-engine maintenance never writes EDID, Arc Sync or LFC.
            # A failed helper update therefore must not falsely force display
            # recovery or block a later verified profile operation.
            try { [IO.File]::Delete($Paths.Journal) } catch {}
        }
        elseif ($null -ne $journal -and (Test-Path -LiteralPath $Paths.Journal -PathType Leaf)) {
            try {
                Set-ClawLabTransactionPhase -Journal $journal -Phase 'RECOVERY_REQUIRED' `
                    -JournalPath $Paths.Journal -Detail $message
            }
            catch {}
        }
        $result = [pscustomobject]@{
            SchemaVersion = 1
            CoordinatorVersion = $script:CoordinatorVersion
            TransactionId = $Id
            Action = $RequestedAction
            Success = $false
            RestartRequired = $false
            RecoveryRequired = $RequestedAction -notin $script:MaintenanceActions -and
                (Test-Path -LiteralPath $Paths.Journal -PathType Leaf)
            Message = $message
        }
        # An over-the-shoulder elevation must be completely read-only. The
        # unelevated caller detects the missing transaction-scoped result and
        # reports the localized identity error itself.
        if ($identityVerified) {
            try { Write-ClawLabJsonAtomic -LiteralPath $Paths.Result -Value $result } catch {}
        }
        return $result
    }
    finally {
        if ($startupAcquired -and $null -ne $startupMutex) {
            try { $startupMutex.ReleaseMutex() } catch {}
        }
        if ($transactionAcquired -and $null -ne $transactionMutex) {
            try { $transactionMutex.ReleaseMutex() } catch {}
        }
        if ($null -ne $startupMutex) { $startupMutex.Dispose() }
        if ($null -ne $transactionMutex) { $transactionMutex.Dispose() }
    }
}

function Start-ClawLabElevatedCoordinator {
    param(
        [Parameter(Mandatory = $true)][object]$Identity,
        [Parameter(Mandatory = $true)][string]$RequestedAction,
        [Parameter(Mandatory = $true)][string]$Id
    )

    $path64 = ConvertTo-ClawLabUtf8Base64 -Value ([IO.Path]::GetFullPath($PSCommandPath))
    $action64 = ConvertTo-ClawLabUtf8Base64 -Value $RequestedAction
    $language64 = ConvertTo-ClawLabUtf8Base64 -Value ([string]$script:SelectedLanguage)
    $sid64 = ConvertTo-ClawLabUtf8Base64 -Value ([string]$Identity.Sid)
    $local64 = ConvertTo-ClawLabUtf8Base64 -Value ([string]$Identity.LocalAppData)
    $id64 = ConvertTo-ClawLabUtf8Base64 -Value $Id
    $template = @'
$decode = { param($value) [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($value)) }
$scriptPath = & $decode '__PATH64__'
$requestedAction = & $decode '__ACTION64__'
$language = & $decode '__LANGUAGE64__'
$callerSid = & $decode '__SID64__'
$callerLocal = & $decode '__LOCAL64__'
$transactionId = & $decode '__ID64__'
$actualIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$actualPrincipal = [Security.Principal.WindowsPrincipal]::new($actualIdentity)
$actualSid = $actualIdentity.User.Value
$actualSession = [Diagnostics.Process]::GetCurrentProcess().SessionId
$actualLocal = [IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd('\')
$expectedLocal = [IO.Path]::GetFullPath($callerLocal).TrimEnd('\')
if (-not $actualPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -or
    -not $actualSid.Equals($callerSid, [StringComparison]::OrdinalIgnoreCase) -or
    $actualSession -ne __SESSION__ -or
    -not $actualLocal.Equals($expectedLocal, [StringComparison]::OrdinalIgnoreCase)) {
    exit 31
}
& $scriptPath -Action $requestedAction -Language $language -Elevated `
    -ExpectedCallerSid $callerSid -ExpectedCallerSessionId __SESSION__ `
    -ExpectedCallerLocalAppData $callerLocal -TransactionId $transactionId
exit $LASTEXITCODE
'@
    $command = $template.Replace('__PATH64__', $path64).
        Replace('__ACTION64__', $action64).
        Replace('__LANGUAGE64__', $language64).
        Replace('__SID64__', $sid64).
        Replace('__LOCAL64__', $local64).
        Replace('__ID64__', $id64).
        Replace('__SESSION__', ([string][int]$Identity.SessionId))
    $encoded = ConvertTo-ClawLabEncodedCommand -Command $command

    # A launcher that was explicitly started as administrator already owns the
    # required elevated token. Reusing that token in a bound child avoids a
    # second UAC boundary, which can be rejected or misreported on locked-down
    # Windows installations. The child still verifies the initiating SID,
    # session and LOCALAPPDATA before loading any mutable core component.
    if ([bool]$Identity.IsAdministrator) {
        & $script:PowerShellPath -NoLogo -NoProfile -ExecutionPolicy Bypass `
            -EncodedCommand $encoded | Out-Host
        $inheritedTokenExitCode = [int]$LASTEXITCODE
        return $inheritedTokenExitCode
    }

    try {
        $process = Start-Process -FilePath $script:PowerShellPath -Verb RunAs `
            -ArgumentList @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded) `
            -Wait -PassThru
        return [int]$process.ExitCode
    }
    catch {
        $script:ElevationLaunchError = [string]$_.Exception.Message
        return 30
    }
}

function Show-ClawLabOperationResult {
    param(
        [Parameter(Mandatory = $true)][string]$RequestedAction,
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][object]$Paths,
        [Parameter(Mandatory = $true)][int]$ExitCode
    )

    $result = Read-ClawLabJsonFile -LiteralPath $Paths.Result
    if ($ExitCode -eq 30) {
        Write-CoordinatorText -Key 'administrator_required' -ForegroundColor Red
        if (-not [string]::IsNullOrWhiteSpace($script:ElevationLaunchError)) {
            Write-CoordinatorText -Key 'technical_details' -ForegroundColor Yellow
            Write-Host $script:ElevationLaunchError -ForegroundColor Red
        }
        return [pscustomobject]@{ Success = $false; RestartRequired = $false; ExitCode = 30 }
    }
    $resultMatches = $null -ne $result -and
        [string]$result.TransactionId -eq $Id -and [string]$result.Action -eq $RequestedAction
    if ($ExitCode -in @(20, 31) -and -not $resultMatches) {
        Write-CoordinatorText -Key 'transaction_identity_mismatch' -ForegroundColor Red
        return [pscustomobject]@{ Success = $false; RestartRequired = $false; ExitCode = 31 }
    }
    if (-not $resultMatches) {
        Write-CoordinatorText -Key 'technical_error_envelope' -ForegroundColor Red
        Write-CoordinatorText -Key 'technical_details' -ForegroundColor Yellow
        Write-Host "Elevated coordinator exited without a transaction result (exit $ExitCode)." -ForegroundColor Red
        return [pscustomobject]@{ Success = $false; RestartRequired = $false; ExitCode = 20 }
    }
    if (-not [bool]$result.Success) {
        if ([string]$result.Message -eq 'CLAWLAB_TRANSACTION_BUSY') {
            Write-CoordinatorText -Key 'transaction_busy' -ForegroundColor Red
        }
        elseif ([string]$result.Message -eq 'CLAWLAB_INTERRUPTED_TRANSACTION') {
            Write-CoordinatorText -Key 'transaction_incomplete' -ForegroundColor Red
        }
        elseif ([string]$result.Message -eq 'CLAWLAB_ELEVATED_IDENTITY_MISMATCH') {
            Write-CoordinatorText -Key 'transaction_identity_mismatch' -ForegroundColor Red
        }
        elseif ([string]$result.Message -eq 'CLAWLAB_RESTORE_REQUIRED_BEFORE_INSTALL') {
            Write-CoordinatorText -Key 'restore_before_switch' -ForegroundColor Red
        }
        else {
            Write-CoordinatorText -Key 'technical_error_envelope' -ForegroundColor Red
            Write-CoordinatorText -Key 'technical_details' -ForegroundColor Yellow
            Write-Host ([string]$result.Message) -ForegroundColor Red
        }
        if ([bool]$result.RecoveryRequired) {
            if ($RequestedAction -in $script:InstallActions) {
                Write-CoordinatorText -Key 'transaction_rollback_failed' -ForegroundColor Red
            }
            else {
                Write-CoordinatorText -Key 'transaction_incomplete' -ForegroundColor Red
            }
        }
        return [pscustomobject]@{ Success = $false; RestartRequired = $false; ExitCode = 20 }
    }

    if ($RequestedAction -in $script:InstallActions) {
        $label = Get-ClawLabProfileLabel -RequestedAction $RequestedAction
        Write-CoordinatorText -Key 'install_success' -Arguments @($label) -ForegroundColor Green
        if ($RequestedAction -match '^Install(30|48)_(144|165|180|192)$') {
            Write-CoordinatorText -Key 'experimental_schedule_details' `
                -Arguments @([int]$Matches[1], [int]$Matches[2]) -ForegroundColor Yellow
        }
    }
    elseif ($RequestedAction -eq 'UpdateCursorHelper') {
        Write-CoordinatorText -Key 'status_healthy' -ForegroundColor Green
    }
    elseif ($RequestedAction -in @('Restore', 'FactoryReset')) {
        Write-CoordinatorText -Key 'restore_success' -ForegroundColor Green
    }
    else {
        Write-CoordinatorText -Key 'restored_safe' -ForegroundColor Green
    }
    if ([bool]$result.RecoveryRequired) {
        Write-CoordinatorText -Key 'transaction_incomplete' -ForegroundColor Yellow
    }
    return [pscustomobject]@{
        Success = $true
        RestartRequired = [bool]$result.RestartRequired
        RecoveryRequired = [bool]$result.RecoveryRequired
        ExitCode = 0
    }
}

function Invoke-ClawLabNonMutatingAction {
    param([Parameter(Mandatory = $true)][string]$RequestedAction)

    $exitCode = 0
    try {
        switch ($RequestedAction) {
            'CheckStatus' {
                Write-CoordinatorText -Key 'status_title' -ForegroundColor Cyan
                $health = Invoke-ClawLabReadOnlyObject -ScriptPath $script:HealthToolPath
                $vrr = Invoke-ClawLabReadOnlyObject -ScriptPath $script:VrrToolPath -CoreAction Status
                $lfc = Invoke-ClawLabReadOnlyObject -ScriptPath $script:LfcToolPath -CoreAction Status
                $overall = [string]$health.Result.OverallHealth
                if ($overall -eq 'HEALTHY') {
                    Write-CoordinatorText -Key 'status_healthy' -ForegroundColor Green
                }
                else {
                    Write-CoordinatorText -Key 'status_attention' -ForegroundColor Yellow
                }
                Write-CoordinatorText -Key 'technical_details' -ForegroundColor DarkGray
                $health.Result | Format-List | Out-Host
                $vrr.Result | Format-List | Out-Host
                $lfc.Result | Format-List | Out-Host
            }
            'ExportStatus' {
                Write-CoordinatorText -Key 'diagnostics_prompt' -ForegroundColor Cyan
                $export = Invoke-ClawLabReadOnlyObject -ScriptPath $script:ExportToolPath
                Write-CoordinatorText -Key 'diagnostics_saved' -Arguments @([string]$export.Result.Output) `
                    -ForegroundColor Green
            }
            'CollectDiagnostics' {
                Write-CoordinatorText -Key 'diagnostics_prompt' -ForegroundColor Cyan
                $startedAt = Get-Date
                [void](Invoke-ClawLabReadOnlyObject -ScriptPath $script:DiagnosticsToolPath `
                        -AllowEmptySuccess)
                $diagnosticRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) `
                    'ClawLab-Display-Diagnostics'
                $archive = if (Test-Path -LiteralPath $diagnosticRoot -PathType Container) {
                    Get-ChildItem -LiteralPath $diagnosticRoot -Filter '*.zip' -File |
                        Where-Object { $_.LastWriteTime -ge $startedAt.AddSeconds(-2) } |
                        Sort-Object LastWriteTime -Descending | Select-Object -First 1
                }
                if ($null -eq $archive) {
                    throw 'The diagnostic collector returned success, but its new ZIP archive was not found.'
                }
                Write-CoordinatorText -Key 'diagnostics_saved' -Arguments @($archive.FullName) `
                    -ForegroundColor Green
            }
        }
    }
    catch {
        $exitCode = 20
        Write-CoordinatorText -Key 'technical_error_envelope' -ForegroundColor Red
        Write-CoordinatorText -Key 'technical_details' -ForegroundColor Yellow
        Write-Host ([string]$_.Exception.Message) -ForegroundColor Red
    }
    Wait-CoordinatorEnter
    return $exitCode
}

if ($LibraryOnly) { return }

if (-not (Test-Path -LiteralPath $script:LocalizationPath -PathType Leaf)) {
    throw "Required localization module is missing: $($script:LocalizationPath)"
}
. $script:LocalizationPath
$script:SelectedLanguage = Initialize-ClawLabLocalization -Language $Language

if ($Action -in $script:NonMutatingActions) {
    exit (Invoke-ClawLabNonMutatingAction -RequestedAction $Action)
}

if ($Elevated) {
    if ([string]::IsNullOrWhiteSpace($ExpectedCallerSid) -or
        [string]::IsNullOrWhiteSpace($ExpectedCallerLocalAppData) -or
        [string]::IsNullOrWhiteSpace($TransactionId) -or
        $ExpectedCallerSessionId -lt 0) {
        Write-CoordinatorText -Key 'transaction_identity_mismatch' -ForegroundColor Red
        exit 31
    }
    $identity = Get-ClawLabIdentityContext
    $paths = New-ClawLabTransactionPaths -LocalAppData $identity.LocalAppData
    $operation = Invoke-ClawLabElevatedOperation -Identity $identity -Paths $paths `
        -RequestedAction $Action -Id $TransactionId
    if ([bool]$operation.Success) { exit 0 }
    exit 20
}

if (-not (Invoke-ClawLabPublicPreflight -RequestedAction $Action)) {
    Write-CoordinatorText -Key 'operation_cancelled' -ForegroundColor Yellow
    Wait-CoordinatorEnter
    exit 2
}

$caller = Get-ClawLabIdentityContext
$paths = New-ClawLabTransactionPaths -LocalAppData $caller.LocalAppData
$id = [Guid]::NewGuid().ToString('D')
if (-not [bool]$caller.IsAdministrator) {
    Write-CoordinatorText -Key 'administrator_required' -ForegroundColor Yellow
}
$elevatedExit = Start-ClawLabElevatedCoordinator -Identity $caller -RequestedAction $Action -Id $id
$shown = Show-ClawLabOperationResult -RequestedAction $Action -Id $id -Paths $paths -ExitCode $elevatedExit
if (-not $shown.Success) {
    Wait-CoordinatorEnter
    exit $shown.ExitCode
}

if ($shown.RestartRequired) {
    Write-CoordinatorText -Key 'restart_required' -ForegroundColor Yellow
    if (-not $NonInteractive -and (Read-CoordinatorYesNo -QuestionKey 'restart_prompt')) {
        shutdown.exe /r /t 0
        exit 0
    }
    Write-CoordinatorText -Key 'restart_reminder' -ForegroundColor Yellow
}
Wait-CoordinatorEnter
exit 0
