[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$packageRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$runtimeRoot = if (Test-Path -LiteralPath (Join-Path $packageRoot 'scripts\MSI-Claw-VRR-Fix.ps1') -PathType Leaf) {
    Join-Path $packageRoot 'scripts'
}
else {
    $packageRoot
}

function Assert-Contains {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Marker,
        [Parameter(Mandatory)][string]$Label
    )
    if ($Text -notmatch [regex]::Escape($Marker)) {
        throw "$Label is missing: $Marker"
    }
}

function Assert-Ordered {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string[]]$Markers,
        [Parameter(Mandatory)][string]$Label
    )
    $last = -1
    foreach ($marker in $Markers) {
        $position = $Text.IndexOf($marker, [StringComparison]::OrdinalIgnoreCase)
        if ($position -lt 0 -or $position -le $last) {
            throw "$Label has an invalid guard/action order at: $marker"
        }
        $last = $position
    }
}

function Get-LiteralStringArrayAssignment {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$VariableName
    )

    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile(
        [IO.Path]::GetFullPath($Path), [ref]$tokens, [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) {
        throw "Cannot parse $Path while validating protected runtime payloads."
    }
    $assignments = @($ast.FindAll({
                param($node)
                $node -is [Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left -is [Management.Automation.Language.VariableExpressionAst] -and
                $node.Left.VariablePath.UserPath -ceq $VariableName
            }, $true))
    if ($assignments.Count -ne 1) {
        throw "Expected one literal assignment for $VariableName in $Path; found $($assignments.Count)."
    }
    return @($assignments[0].Right.FindAll({
                param($node)
                $node -is [Management.Automation.Language.StringConstantExpressionAst]
            }, $true) | ForEach-Object { [string]$_.Value })
}

$commonPreflight = @(
    'IMPORTANT VERSION UPGRADE',
    '2.1.2 or any older release',
    'refuses to overwrite an older managed installation',
    'reset-all.exe',
    'If CRU has never been used',
    'ClawTweaks',
    '3.0 or later',
    'optional and is not required',
    'ClawLab VRR compatibility patch'
)

$stableProfiles = @(
    [pscustomobject]@{ File = 'INSTALL_30_120_VRR.bat'; Action = 'Install30' },
    [pscustomobject]@{ File = 'INSTALL_48_120_VRR.bat'; Action = 'Install48' }
)
foreach ($profile in $stableProfiles) {
    $path = Join-Path $packageRoot $profile.File
    $text = Get-Content -LiteralPath $path -Raw
    foreach ($marker in $commonPreflight + @('VRR ownership preflight', 'MSI-Claw-Intel-LFC-Fix.ps1" -Action Apply')) {
        Assert-Contains -Text $text -Marker $marker -Label $profile.File
    }
    Assert-Ordered -Text $text -Label $profile.File -Markers @(
        'IMPORTANT CRU preflight',
        'Has CRU never been used',
        'IMPORTANT VRR ownership preflight',
        'Is every conflicting VRR/EDID tool disabled or removed',
        "MSI-Claw-VRR-Fix.ps1`" -Action $($profile.Action)",
        'MSI-Claw-Intel-LFC-Fix.ps1" -Action Apply',
        'Restart the PC now?'
    )
}

$experimentalProfiles = @(
    [pscustomobject]@{ File = 'INSTALL_STABLE_EXPERIMENTAL_48_144_VRR.bat'; Action = 'Install48_144'; Mode = 'CLAWLAB_48_144'; Classification = 'STABLE EXPERIMENTAL'; Minimum = 48; Maximum = 144 },
    [pscustomobject]@{ File = 'INSTALL_UNSTABLE_EXPERIMENTAL_48_165_VRR.bat'; Action = 'Install48_165'; Mode = 'CLAWLAB_48_165'; Classification = 'UNSTABLE EXPERIMENTAL'; Minimum = 48; Maximum = 165 },
    [pscustomobject]@{ File = 'INSTALL_UNSTABLE_EXPERIMENTAL_48_180_VRR.bat'; Action = 'Install48_180'; Mode = 'CLAWLAB_48_180'; Classification = 'UNSTABLE EXPERIMENTAL'; Minimum = 48; Maximum = 180 },
    [pscustomobject]@{ File = 'INSTALL_UNSTABLE_EXPERIMENTAL_30_144_VRR.bat'; Action = 'Install30_144'; Mode = 'CLAWLAB_30_144'; Classification = 'UNSTABLE EXPERIMENTAL'; Minimum = 30; Maximum = 144 },
    [pscustomobject]@{ File = 'INSTALL_UNSTABLE_EXPERIMENTAL_30_165_VRR.bat'; Action = 'Install30_165'; Mode = 'CLAWLAB_30_165'; Classification = 'UNSTABLE EXPERIMENTAL'; Minimum = 30; Maximum = 165 },
    [pscustomobject]@{ File = 'INSTALL_UNSTABLE_EXPERIMENTAL_30_180_VRR.bat'; Action = 'Install30_180'; Mode = 'CLAWLAB_30_180'; Classification = 'UNSTABLE EXPERIMENTAL'; Minimum = 30; Maximum = 180 }
)
foreach ($profile in $experimentalProfiles) {
    $relativePath = Join-Path 'EXPERIMENTAL' $profile.File
    $path = Join-Path $packageRoot $relativePath
    $text = Get-Content -LiteralPath $path -Raw
    foreach ($marker in $commonPreflight + @(
            'DISPLAY OVERCLOCK',
            "Profile: $($profile.Minimum)-$($profile.Maximum) Hz - $($profile.Classification)",
            'silicon lottery',
            'Has CRU never been used, or was reset-all.exe followed by a restart?',
            'Is every conflicting VRR/EDID tool disabled or removed?',
            'timeout /t 10 /nobreak',
            'I ACCEPT THE OVERCLOCK RISK',
            '15 SECONDS',
            'DO NOT POWER OFF OR REBOOT',
            'Disconnect every external display',
            "MSI-Claw-VRR-Fix.ps1`" -Action $($profile.Action)",
            'if errorlevel 1 goto :failed'
        )) {
        Assert-Contains -Text $text -Marker $marker -Label $profile.File
    }
    Assert-Ordered -Text $text -Label $profile.File -Markers @(
        'Has CRU never been used, or was reset-all.exe followed by a restart?',
        'Is every conflicting VRR/EDID tool disabled or removed?',
        'timeout /t 10 /nobreak',
        'I ACCEPT THE OVERCLOCK RISK',
        "MSI-Claw-VRR-Fix.ps1`" -Action $($profile.Action)",
        'Restart the PC now?'
    )
    if ($text -match '(?i)Install24|24[-_]120') {
        throw "$($profile.File) exposes a forbidden 24 Hz profile."
    }
}
$mainVrr = Get-Content -LiteralPath (Join-Path $runtimeRoot 'MSI-Claw-VRR-Fix.ps1') -Raw
foreach ($marker in @(
        "& `$trialSchedulerPath -Action Schedule -Mode `$DesiredState",
        'try { Remove-ExperimentalOverclockTrial }',
        '$backupPath,',
        "(Join-Path `$stateRoot 'MSI-Claw-Intel-LFC-Fix.ps1')",
        'ClawLab-VRR-Privileged\2.2.0',
        'Assert-ProtectedRuntimeIntegrity',
        'protected-runtime.json',
        'Remove-ProtectedExperimentalRuntime',
        "& `$protectedLfcToolPath -Action Apply",
        'LfcFixActive'
        'OLDER_VERSION_RESTORE_REQUIRED'
    )) {
    Assert-Contains -Text $mainVrr -Marker $marker -Label 'Atomic experimental install transaction'
}

$trialPath = Join-Path $runtimeRoot 'Experimental-Overclock-VRR-Trial.ps1'
$trial = Get-Content -LiteralPath $trialPath -Raw
$protectedMainPayload = @(Get-LiteralStringArrayAssignment `
        -Path (Join-Path $runtimeRoot 'MSI-Claw-VRR-Fix.ps1') `
        -VariableName 'protectedRuntimePayloadNames')
$protectedTrialPayload = @(Get-LiteralStringArrayAssignment -Path $trialPath -VariableName 'protectedPayload')
$protectedTrialExpected = @(Get-LiteralStringArrayAssignment -Path $trialPath -VariableName 'expectedFiles')
$expectedProtectedPayload = @(
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
$expectedPayloadKey = (@($expectedProtectedPayload | Sort-Object) -join '|')
foreach ($payload in @($protectedMainPayload, $protectedTrialPayload, $protectedTrialExpected)) {
    if ($payload.Count -ne $expectedProtectedPayload.Count -or
        (@($payload | Sort-Object) -join '|') -cne $expectedPayloadKey) {
        throw 'Protected runtime payload definitions are not identical and complete.'
    }
}
if ($mainVrr -notmatch 'Assert-ProtectedRuntimeIntegrity\s*\r?\nforeach \(\$requiredModule') {
    throw 'Protected main runtime integrity is not verified before module loading.'
}
if ($trial -notmatch 'Assert-ProtectedRuntimeIntegrity\s*\r?\n\$trial = Read-JsonFile') {
    throw 'Protected trial integrity is not verified before trial-state processing.'
}
foreach ($marker in @(
        "`$fixVersion = '2.2.0'",
        "'STABLE_EXPERIMENTAL'",
        "'UNSTABLE_EXPERIMENTAL'",
        'ObservationSeconds = 15',
        'TimeoutSeconds 15',
        "-ToolAction 'SetSafe120ForTrial'",
        'TimeoutSeconds 30',
        '$answer -eq 6',
        'Confirm-AdministratorOrRelaunch',
        '-RunLevel Limited',
        'ClawLab-VRR-Privileged\2.2.0',
        'Initialize-ProtectedRuntimeDirectory',
        'DirectorySecurity',
        'Write-ProtectedRuntimeManifest',
        'Assert-ProtectedRuntimeIntegrity',
        "-ToolAction 'ConfirmExperimentalTrial'",
        "-ToolAction 'Restore'",
        'Restart-AfterTrial'
)) {
    Assert-Contains -Text $trial -Marker $marker -Label 'Guarded trial runtime'
}
if ($trial -match [regex]::Escape('-RunLevel Highest')) {
    throw 'Guarded trial runtime schedules a user-writable script at Highest privilege.'
}
if (([regex]::Matches($trial, 'Confirm-AdministratorOrRelaunch')).Count -ne 2) {
    throw 'Guarded trial elevation is not restricted to its definition and Schedule action.'
}
foreach ($unsafeTimeout in @(
        "-ToolAction 'ConfirmExperimentalTrial' -TimeoutSeconds",
        "-ToolPath `$installedVrrToolPath -ToolAction 'Restore' -TimeoutSeconds",
        '-ExecutionTimeLimit'
    )) {
    if ($trial -match [regex]::Escape($unsafeTimeout)) {
        throw "Guarded trial can force-terminate an elevation-sensitive action: $unsafeTimeout"
    }
}
$trialLauncher = Get-Content -LiteralPath (Join-Path $runtimeRoot 'ClawLab-Experimental-Trial-Startup.vbs') -Raw
foreach ($marker in @('WScript.ScriptFullName', 'Experimental-Overclock-VRR-Trial.ps1')) {
    Assert-Contains -Text $trialLauncher -Marker $marker -Label 'Protected guarded-trial launcher'
}
if ($trialLauncher -match [regex]::Escape('%LOCALAPPDATA%')) {
    throw 'The guarded-trial task launcher still executes a user-writable LocalAppData script.'
}
$healthScript = Get-Content -LiteralPath (Join-Path $runtimeRoot 'ClawLab-Health-Check.ps1') -Raw
if ($healthScript -match '(?m)^\s*exit\s+0\s*$') {
    throw 'Health-check failure paths can terminate the parent diagnostics host.'
}
if ($mainVrr -notmatch '(?s)Write-Host "ERROR:.*?# Preserve a non-zero exit.*?\r?\n\s*throw\s*\r?\n\}') {
    throw 'VRR failures are not catchable by health and JSON diagnostic callers.'
}
foreach ($marker in @(
        'ActiveDisplayCount()',
        'Exactly one active display is required',
        'ClawLab.MSIClaw.VrrApplyStartup',
        'Enter-StartupApplyMutex',
        'Exit-StartupApplyMutex'
    )) {
    Assert-Contains -Text $mainVrr `
        -Marker $marker -Label 'Guarded display-target isolation'
}
Assert-Ordered -Text $trial -Label 'Guarded trial success path' -Markers @(
    "-ToolAction 'ApplyExperimentalTrial'",
    "-ToolAction 'SetSafe120ForTrial'",
    '$answer = Show-Message',
    'Set-TrialConfirmation -Confirmed $true',
    "-ToolAction 'ConfirmExperimentalTrial'"
)

[pscustomobject]@{
    Result = 'PASS'
    StableInstallers = $stableProfiles.Count
    ExperimentalInstallers = $experimentalProfiles.Count
    LfcIntegratedProfiles = $stableProfiles.Count + $experimentalProfiles.Count
    GuardedTrialOrder = 'PASS'
    Forbidden24HzProfiles = 0
}
