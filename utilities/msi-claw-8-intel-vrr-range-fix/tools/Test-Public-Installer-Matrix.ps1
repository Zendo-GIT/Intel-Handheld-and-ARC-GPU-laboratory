[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$packageRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$isPackagedLayout = Test-Path -LiteralPath (Join-Path $packageRoot 'scripts\ClawLab-VRR-Transaction.ps1') -PathType Leaf
$runtimeRoot = if ($isPackagedLayout) {
    Join-Path $packageRoot 'scripts'
}
else {
    $packageRoot
}

function Assert-Test {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) { throw $Message }
}

function Get-TextSection {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$StartMarker,
        [Parameter(Mandatory = $true)][string]$EndMarker
    )

    $start = $Text.IndexOf($StartMarker, [StringComparison]::Ordinal)
    Assert-Test -Condition ($start -ge 0) -Message "Missing section start: $StartMarker"
    $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length, [StringComparison]::Ordinal)
    Assert-Test -Condition ($end -gt $start) -Message "Missing section end after ${StartMarker}: $EndMarker"
    return $Text.Substring($start, $end - $start)
}

function Get-LiteralValidateSet {
    param([Parameter(Mandatory = $true)][string]$Path)

    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile(
        [IO.Path]::GetFullPath($Path), [ref]$tokens, [ref]$parseErrors)
    Assert-Test -Condition (@($parseErrors).Count -eq 0) `
        -Message "Cannot parse coordinator while reading its action contract: $Path"

    $actionParameter = @($ast.ParamBlock.Parameters | Where-Object {
            $_.Name.VariablePath.UserPath -ceq 'Action'
        })
    Assert-Test -Condition ($actionParameter.Count -eq 1) `
        -Message 'The coordinator must expose exactly one Action parameter.'
    $validateSet = @($actionParameter[0].Attributes | Where-Object {
            $_.TypeName.Name -ceq 'ValidateSet'
        })
    Assert-Test -Condition ($validateSet.Count -eq 1) `
        -Message 'The coordinator Action parameter must have one literal ValidateSet.'
    return @($validateSet[0].PositionalArguments | ForEach-Object {
            [string]$_.SafeGetValue()
        })
}

$coordinatorPath = Join-Path $runtimeRoot 'ClawLab-VRR-Transaction.ps1'
Assert-Test -Condition (Test-Path -LiteralPath $coordinatorPath -PathType Leaf) `
    -Message 'ClawLab-VRR-Transaction.ps1 is missing.'
$coordinatorText = [IO.File]::ReadAllText($coordinatorPath, [Text.Encoding]::UTF8)

foreach ($marker in @(
        "`$script:CoordinatorVersion = '2.3.0'",
        "`$script:StableActions = @('Install30', 'Install48')",
        'VRR_AND_LFC_VERIFIED',
        'Invoke-ClawLabExactRestore',
        'Invoke-ClawLabInstallRollback',
        'I ACCEPT THE OVERCLOCK RISK',
        '[Console]::ReadKey($true)',
        '$readingSeconds = 10',
        'Start-Sleep -Seconds 1',
        'ClawLab-Localization.ps1'
    )) {
    Assert-Test -Condition ($coordinatorText.Contains($marker)) `
        -Message "The coordinator is missing a public safety marker: $marker"
}
Assert-Test -Condition ([regex]::Matches($coordinatorText, '(?i)-Verb\s+RunAs').Count -eq 1) `
    -Message 'The coordinator must own exactly one UAC boundary.'
Assert-Test -Condition ($coordinatorText -notmatch '(?i)(^|[^0-9])24[-_]120([^0-9]|$)') `
    -Message 'The coordinator exposes a forbidden 24-120 profile.'
Assert-Test -Condition ($coordinatorText -notmatch '(?i)(^|[^0-9])15[-_]120([^0-9]|$)') `
    -Message 'The coordinator exposes a forbidden 15-120 profile.'

$trialPath = Join-Path $runtimeRoot 'Experimental-Overclock-VRR-Trial.ps1'
Assert-Test -Condition (Test-Path -LiteralPath $trialPath -PathType Leaf) `
    -Message 'Experimental-Overclock-VRR-Trial.ps1 is missing.'
$trialText = [IO.File]::ReadAllText($trialPath, [Text.Encoding]::UTF8)
foreach ($marker in @(
        "`$fixVersion = '2.3.0'",
        'ObservationSeconds = $trialObservationSeconds',
        "-ToolAction 'ApplyExperimentalTrial' -TimeoutSeconds 15",
        'Invoke-ExperimentalObservationUi -Trial $trial',
        "-ToolAction 'VerifyExperimentalTrial' -TimeoutSeconds 15",
        "-ToolAction 'SetSafe120ForTrial' -TimeoutSeconds 15",
        "Get-ClawLabString -Key 'experimental_trial_confirmation'",
        '$trial.UserConfirmed = $true',
        "Set-TrialLifecycleState -Trial `$trial -LifecycleState 'CONFIRMING'",
        'Invoke-BoundElevatedTrialConfirmation -Trial $trial',
        '& $toolPath -Action ConfirmExperimentalTrial',
        "Get-ClawLabString -Key 'experimental_declined'"
    )) {
    Assert-Test -Condition ($trialText.Contains($marker)) `
        -Message "The guarded trial is missing a safety/localization marker: $marker"
}
$trialRun = Get-TextSection -Text $trialText `
    -StartMarker 'function Invoke-GuardedTrialRun {' -EndMarker '$trialExitCode = 1'
$trialOrder = @(
    '$readyAnswer = Show-Message',
    "-ToolAction 'ApplyExperimentalTrial' -TimeoutSeconds 15",
    'Invoke-ExperimentalObservationUi -Trial $trial',
    "-ToolAction 'VerifyExperimentalTrial' -TimeoutSeconds 15",
    "-ToolAction 'SetSafe120ForTrial' -TimeoutSeconds 15",
    "Set-TrialLifecycleState -Trial `$trial -LifecycleState 'AWAITING_CONFIRMATION'",
    '$answer = Show-Message',
    '$trial.UserConfirmed = $true',
    "Set-TrialLifecycleState -Trial `$trial -LifecycleState 'CONFIRMING'",
    'Invoke-BoundElevatedTrialConfirmation -Trial $trial'
)
$previousPosition = -1
foreach ($marker in $trialOrder) {
    $position = $trialRun.IndexOf($marker, [StringComparison]::Ordinal)
    Assert-Test -Condition ($position -gt $previousPosition) `
        -Message "The guarded trial action order is invalid at: $marker"
    $previousPosition = $position
}
Assert-Test -Condition (-not $trialRun.Contains("-ToolAction 'ConfirmExperimentalTrial'")) `
    -Message 'The guarded trial Run path bypasses the bound elevated confirmation bootstrap.'
Assert-Test -Condition ($trialText -notmatch [regex]::Escape("-ToolAction 'ConfirmExperimentalTrial' -TimeoutSeconds")) `
    -Message 'The guarded trial may not force-terminate persistence while UAC is pending.'

$launcherActions = [ordered]@{
    'CHECK_STATUS.bat' = 'CheckStatus'
    'UPDATE_CURSOR_REFRESH_ENGINE.bat' = 'UpdateCursorHelper'
    'COLLECT_UNSUPPORTED_CLAW_DISPLAY.bat' = 'CollectDiagnostics'
    'EXPORT_STATUS_REPORT.bat' = 'ExportStatus'
    'INSTALL_30_120_VRR.bat' = 'Install30'
    'INSTALL_48_120_VRR.bat' = 'Install48'
    'RESTORE_ORIGINAL_VRR.bat' = 'Restore'
    'RESTORE_INTEL_LFC_DEFAULTS.bat' = 'RestoreLfcOnly'
    'FACTORY_RESET_CLAWLAB_VRR.bat' = 'FactoryReset'
    'EMERGENCY_REMOVE_CLAWLAB_EDID.bat' = 'EmergencyRestoreEdid'
    'SET_INTEL_LFC_FACTORY_DEFAULTS.bat' = 'FactoryLfcDefaults'
    'EXPERIMENTAL\INSTALL_STABLE_EXPERIMENTAL_48_144_VRR.bat' = 'Install48_144'
    'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_30_144_VRR.bat' = 'Install30_144'
    'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_30_165_VRR.bat' = 'Install30_165'
    'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_30_180_VRR.bat' = 'Install30_180'
    'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_30_192_VRR.bat' = 'Install30_192'
    'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_48_165_VRR.bat' = 'Install48_165'
    'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_48_180_VRR.bat' = 'Install48_180'
    'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_48_192_VRR.bat' = 'Install48_192'
}
$packagedLauncherDirectories = @{
    'COLLECT_UNSUPPORTED_CLAW_DISPLAY.bat' = 'DIAGNOSTICS'
    'EXPORT_STATUS_REPORT.bat' = 'DIAGNOSTICS'
    'RESTORE_ORIGINAL_VRR.bat' = 'RECOVERY'
    'RESTORE_INTEL_LFC_DEFAULTS.bat' = 'RECOVERY'
    'FACTORY_RESET_CLAWLAB_VRR.bat' = 'EMERGENCY'
    'EMERGENCY_REMOVE_CLAWLAB_EDID.bat' = 'EMERGENCY'
    'SET_INTEL_LFC_FACTORY_DEFAULTS.bat' = 'EMERGENCY'
}

$allowedActions = @(Get-LiteralValidateSet -Path $coordinatorPath)
foreach ($entry in $launcherActions.GetEnumerator()) {
    $relativeLauncherPath = [string]$entry.Key
    if ($isPackagedLayout -and $packagedLauncherDirectories.ContainsKey($relativeLauncherPath)) {
        $relativeLauncherPath = Join-Path $packagedLauncherDirectories[$relativeLauncherPath] $relativeLauncherPath
    }
    $launcherPath = Join-Path $packageRoot $relativeLauncherPath
    Assert-Test -Condition (Test-Path -LiteralPath $launcherPath -PathType Leaf) `
        -Message "Public launcher is missing: $relativeLauncherPath"
    Assert-Test -Condition ([string]$entry.Value -in $allowedActions) `
        -Message "Launcher action is not accepted by the coordinator: $($entry.Value)"

    $launcher = [IO.File]::ReadAllText($launcherPath, [Text.Encoding]::Default)
    Assert-Test -Condition ([regex]::Matches($launcher,
            '(?im)^set "CLAWLAB_POWERSHELL=%SystemRoot%\\System32\\WindowsPowerShell\\v1\.0\\powershell\.exe"\s*$').Count -eq 1) `
        -Message "Public launcher does not pin Windows PowerShell by absolute System32 path: $($entry.Key)"
    Assert-Test -Condition ([regex]::Matches($launcher,
            '(?im)^if not exist "%CLAWLAB_POWERSHELL%" exit /b 1\s*$').Count -eq 1) `
        -Message "Public launcher does not fail closed when Windows PowerShell is absent: $($entry.Key)"
    Assert-Test -Condition ([regex]::Matches($launcher,
            '(?im)^"%CLAWLAB_POWERSHELL%"\s').Count -eq 1) `
        -Message "Public launcher must invoke the pinned Windows PowerShell exactly once: $($entry.Key)"
    Assert-Test -Condition ($launcher -notmatch '(?im)^\s*powershell(?:\.exe)?\s') `
        -Message "Public launcher still resolves PowerShell through PATH: $($entry.Key)"
    Assert-Test -Condition ($launcher -match ('(?i)-Action\s+' + [regex]::Escape([string]$entry.Value) + '(?:\s|$)')) `
        -Message "Public launcher routes to the wrong action: $($entry.Key)"
    Assert-Test -Condition ($launcher -match 'ClawLab-VRR-Transaction\.ps1') `
        -Message "Public launcher bypasses the coordinator: $($entry.Key)"
    Assert-Test -Condition ($launcher -notmatch '(?i)MSI-Claw-(?:VRR|Intel-LFC)-Fix\.ps1') `
        -Message "Public launcher invokes a core mutator directly: $($entry.Key)"
    Assert-Test -Condition ($launcher -notmatch '(?im)^\s*(?:choice|set\s+/p|pause|timeout|shutdown(?:\.exe)?)\b') `
        -Message "Public launcher contains a legacy prompt or restart side effect: $($entry.Key)"
    Assert-Test -Condition ($launcher -notmatch '(?im)^\s*echo\s+[^.]') `
        -Message "Public launcher contains user-facing text outside localization: $($entry.Key)"
    Assert-Test -Condition ((Get-Content -LiteralPath $launcherPath).Count -le 10) `
        -Message "Public launcher is no longer a thin wrapper: $($entry.Key)"
}

$stableActions = @('Install30', 'Install48')
$experimentalActions = @(
    'Install48_144', 'Install48_165', 'Install48_180', 'Install48_192',
    'Install30_144', 'Install30_165', 'Install30_180', 'Install30_192'
)
$profileActions = @($launcherActions.Values | Where-Object { $_ -like 'Install*' })
Assert-Test -Condition (@(Compare-Object -ReferenceObject @($stableActions + $experimentalActions) `
            -DifferenceObject $profileActions).Count -eq 0) `
    -Message 'The public launcher matrix does not expose exactly the ten approved profiles.'

$selectorPath = Join-Path $packageRoot 'SELECT_LANGUAGE.bat'
Assert-Test -Condition (Test-Path -LiteralPath $selectorPath -PathType Leaf) `
    -Message 'SELECT_LANGUAGE.bat is missing from the public package root.'
$selector = [IO.File]::ReadAllText($selectorPath, [Text.Encoding]::Default)
Assert-Test -Condition ($selector -match '(?im)^set "CLAWLAB_POWERSHELL=%SystemRoot%\\System32\\WindowsPowerShell\\v1\.0\\powershell\.exe"\s*$' -and
    $selector -match '(?im)^if not exist "%CLAWLAB_POWERSHELL%" exit /b 1\s*$' -and
    $selector -match '(?im)^"%CLAWLAB_POWERSHELL%"\s') `
    -Message 'SELECT_LANGUAGE.bat does not fail closed around the absolute Windows PowerShell path.'
Assert-Test -Condition ($selector -notmatch '(?im)^\s*powershell(?:\.exe)?\s') `
    -Message 'SELECT_LANGUAGE.bat still resolves PowerShell through PATH.'
Assert-Test -Condition ($selector -match 'Select-ClawLab-Language\.ps1') `
    -Message 'SELECT_LANGUAGE.bat does not route to the language selector.'
Assert-Test -Condition ($selector -notmatch '(?i)MSI-Claw-(?:VRR|Intel-LFC)-Fix\.ps1') `
    -Message 'SELECT_LANGUAGE.bat must never invoke a VRR/LFC mutator.'

[pscustomobject]@{
    Result = 'PASS'
    StableInstallers = $stableActions.Count
    ExperimentalInstallers = $experimentalActions.Count
    LfcIntegratedProfiles = $stableActions.Count + $experimentalActions.Count
    RoutedLaunchers = $launcherActions.Count
    CoordinatorActions = $allowedActions.Count
    GuardedTrialOrder = 'PASS'
    ForbiddenTelemetryOnlyProfiles = 0
}
