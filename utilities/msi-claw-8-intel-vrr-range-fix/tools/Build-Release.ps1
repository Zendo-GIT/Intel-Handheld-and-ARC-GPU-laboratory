[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version = '2.3.0',
    [switch]$ValidateOnly
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$projectRoot = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$packageName = 'MSI-Claw-Intel-VRR-Range-Fix'
$expectedLfcVersion = '2.0.7'
$expectedProtectedRuntimeVersion = '2.3.0'
$distRoot = Join-Path $projectRoot 'dist'
$stagingRoot = Join-Path $distRoot ".staging-$packageName-$Version"
$stagedPackageRoot = Join-Path $stagingRoot $packageName
$archiveName = "$packageName-$Version.zip"
$archivePath = Join-Path $distRoot $archiveName
$hashPath = Join-Path $distRoot 'RELEASE_SHA256.txt'
$archiveHashPath = "$archivePath.sha256.txt"
$cursorHelperRelativePath = 'ClawLab-Cursor-Refresh-Helper.exe'
$cursorHelperPath = Join-Path $projectRoot $cursorHelperRelativePath
$cursorHelperBuilder = Join-Path $projectRoot 'tools\CursorRefreshHelper\Build-CursorRefreshHelper.ps1'

function Assert-ContainsLiteral {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if (-not $Text.Contains($Value)) {
        throw "$Label is missing required value: $Value"
    }
}

function Get-LiteralStringArrayAssignment {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$VariableName
    )

    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile(
        [IO.Path]::GetFullPath($Path), [ref]$tokens, [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) {
        throw "Cannot parse $Path while validating $VariableName."
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

function Get-LiteralStringArrayFunctionResult {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$FunctionName
    )

    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile(
        [IO.Path]::GetFullPath($Path), [ref]$tokens, [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) {
        throw "Cannot parse $Path while validating $FunctionName."
    }
    $functions = @($ast.FindAll({
                param($node)
                $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -ceq $FunctionName
            }, $true))
    if ($functions.Count -ne 1) {
        throw "Expected one function named $FunctionName in $Path; found $($functions.Count)."
    }
    $returnStatements = @($functions[0].Body.FindAll({
                param($node)
                $node -is [Management.Automation.Language.ReturnStatementAst]
            }, $true))
    if ($returnStatements.Count -ne 1) {
        throw "Expected one literal return statement in $FunctionName; found $($returnStatements.Count)."
    }
    return @($returnStatements[0].Pipeline.FindAll({
                param($node)
                $node -is [Management.Automation.Language.StringConstantExpressionAst]
            }, $true) | ForEach-Object { [string]$_.Value })
}

function Invoke-ClawLabTestInShell {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string]$TestPath,
        [Parameter(Mandatory = $true)][string]$ShellLabel
    )

    Write-Host ("[{0}] {1}" -f $ShellLabel, (Split-Path $TestPath -Leaf)) -ForegroundColor Cyan
    & $Executable -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $TestPath | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "$ShellLabel validation failed: $TestPath (exit $LASTEXITCODE)."
    }
}

$releaseFiles = @(
    [pscustomobject]@{ Source = 'INSTALL_48_120_VRR.bat'; Destination = 'INSTALL_48_120_VRR.bat' },
    [pscustomobject]@{ Source = 'INSTALL_30_120_VRR.bat'; Destination = 'INSTALL_30_120_VRR.bat' },
    [pscustomobject]@{ Source = 'SELECT_LANGUAGE.bat'; Destination = 'SELECT_LANGUAGE.bat' },
    [pscustomobject]@{ Source = 'CHECK_STATUS.bat'; Destination = 'CHECK_STATUS.bat' },
    [pscustomobject]@{ Source = 'UPDATE_CURSOR_REFRESH_ENGINE.bat'; Destination = 'UPDATE_CURSOR_REFRESH_ENGINE.bat' },
    [pscustomobject]@{ Source = 'README.txt'; Destination = 'README.txt' },
    [pscustomobject]@{ Source = 'CHANGELOG.txt'; Destination = 'CHANGELOG.txt' },
    [pscustomobject]@{ Source = 'LICENSE.txt'; Destination = 'LICENSE.txt' },

    [pscustomobject]@{ Source = 'EXPERIMENTAL\INSTALL_STABLE_EXPERIMENTAL_48_144_VRR.bat'; Destination = 'EXPERIMENTAL\INSTALL_STABLE_EXPERIMENTAL_48_144_VRR.bat' },
    [pscustomobject]@{ Source = 'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_48_165_VRR.bat'; Destination = 'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_48_165_VRR.bat' },
    [pscustomobject]@{ Source = 'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_48_180_VRR.bat'; Destination = 'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_48_180_VRR.bat' },
    [pscustomobject]@{ Source = 'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_48_192_VRR.bat'; Destination = 'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_48_192_VRR.bat' },
    [pscustomobject]@{ Source = 'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_30_144_VRR.bat'; Destination = 'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_30_144_VRR.bat' },
    [pscustomobject]@{ Source = 'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_30_165_VRR.bat'; Destination = 'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_30_165_VRR.bat' },
    [pscustomobject]@{ Source = 'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_30_180_VRR.bat'; Destination = 'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_30_180_VRR.bat' },
    [pscustomobject]@{ Source = 'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_30_192_VRR.bat'; Destination = 'EXPERIMENTAL\INSTALL_UNSTABLE_EXPERIMENTAL_30_192_VRR.bat' },

    [pscustomobject]@{ Source = 'RESTORE_ORIGINAL_VRR.bat'; Destination = 'RECOVERY\RESTORE_ORIGINAL_VRR.bat' },
    [pscustomobject]@{ Source = 'RESTORE_INTEL_LFC_DEFAULTS.bat'; Destination = 'RECOVERY\RESTORE_INTEL_LFC_DEFAULTS.bat' },
    [pscustomobject]@{ Source = 'FACTORY_RESET_CLAWLAB_VRR.bat'; Destination = 'EMERGENCY\FACTORY_RESET_CLAWLAB_VRR.bat' },
    [pscustomobject]@{ Source = 'EMERGENCY_REMOVE_CLAWLAB_EDID.bat'; Destination = 'EMERGENCY\EMERGENCY_REMOVE_CLAWLAB_EDID.bat' },
    [pscustomobject]@{ Source = 'SET_INTEL_LFC_FACTORY_DEFAULTS.bat'; Destination = 'EMERGENCY\SET_INTEL_LFC_FACTORY_DEFAULTS.bat' },
    [pscustomobject]@{ Source = 'COLLECT_UNSUPPORTED_CLAW_DISPLAY.bat'; Destination = 'DIAGNOSTICS\COLLECT_UNSUPPORTED_CLAW_DISPLAY.bat' },
    [pscustomobject]@{ Source = 'EXPORT_STATUS_REPORT.bat'; Destination = 'DIAGNOSTICS\EXPORT_STATUS_REPORT.bat' },

    [pscustomobject]@{ Source = 'ClawLab-VRR-Transaction.ps1'; Destination = 'scripts\ClawLab-VRR-Transaction.ps1' },
    [pscustomobject]@{ Source = 'MSI-Claw-VRR-Fix.ps1'; Destination = 'scripts\MSI-Claw-VRR-Fix.ps1' },
    [pscustomobject]@{ Source = 'MSI-Claw-Intel-LFC-Fix.ps1'; Destination = 'scripts\MSI-Claw-Intel-LFC-Fix.ps1' },
    [pscustomobject]@{ Source = 'Intel-VRR-LFC-Driver-Interface.ps1'; Destination = 'scripts\Intel-VRR-LFC-Driver-Interface.ps1' },
    [pscustomobject]@{ Source = 'ClawLab-Health-Check.ps1'; Destination = 'scripts\ClawLab-Health-Check.ps1' },
    [pscustomobject]@{ Source = 'Export-ClawLab-Status.ps1'; Destination = 'scripts\Export-ClawLab-Status.ps1' },
    [pscustomobject]@{ Source = 'Collect-Claw-Display-Diagnostics.ps1'; Destination = 'scripts\Collect-Claw-Display-Diagnostics.ps1' },
    [pscustomobject]@{ Source = 'Edid-Normalization.ps1'; Destination = 'scripts\Edid-Normalization.ps1' },
    [pscustomobject]@{ Source = 'Lfc-Backup-Identity.ps1'; Destination = 'scripts\Lfc-Backup-Identity.ps1' },
    [pscustomobject]@{ Source = 'ArcSync-Range-Policy.ps1'; Destination = 'scripts\ArcSync-Range-Policy.ps1' },
    [pscustomobject]@{ Source = 'Scheduled-Task-Persistence.ps1'; Destination = 'scripts\Scheduled-Task-Persistence.ps1' },
    [pscustomobject]@{ Source = 'ClawLab-Localization.ps1'; Destination = 'scripts\ClawLab-Localization.ps1' },
    [pscustomobject]@{ Source = 'tools\Select-ClawLab-Language.ps1'; Destination = 'scripts\Select-ClawLab-Language.ps1' },
    [pscustomobject]@{ Source = 'locales\messages.json'; Destination = 'scripts\locales\messages.json' },
    [pscustomobject]@{ Source = 'Experimental-Overclock-VRR-Trial.ps1'; Destination = 'scripts\Experimental-Overclock-VRR-Trial.ps1' },
    [pscustomobject]@{ Source = 'ClawLab-Cursor-Refresh-Helper.exe'; Destination = 'scripts\ClawLab-Cursor-Refresh-Helper.exe' },
    [pscustomobject]@{ Source = 'ClawLab-VRR-Startup.vbs'; Destination = 'scripts\ClawLab-VRR-Startup.vbs' },
    [pscustomobject]@{ Source = 'ClawLab-LFC-Startup.vbs'; Destination = 'scripts\ClawLab-LFC-Startup.vbs' },
    [pscustomobject]@{ Source = 'ClawLab-Experimental-Trial-Startup.vbs'; Destination = 'scripts\ClawLab-Experimental-Trial-Startup.vbs' },

    [pscustomobject]@{ Source = 'docs\COMPATIBILITY.md'; Destination = 'docs\COMPATIBILITY.md' },
    [pscustomobject]@{ Source = 'docs\SAFETY.md'; Destination = 'docs\SAFETY.md' },
    [pscustomobject]@{ Source = 'docs\TECHNICAL_DETAILS.md'; Destination = 'docs\TECHNICAL_DETAILS.md' },
    [pscustomobject]@{ Source = 'docs\NEXUS_MODS.md'; Destination = 'docs\NEXUS_MODS.md' },
    [pscustomobject]@{ Source = 'docs\A1M_EDID_REFERENCE.md'; Destination = 'docs\A1M_EDID_REFERENCE.md' },
    [pscustomobject]@{ Source = 'docs\RELEASE_NOTES_2.3.0.md'; Destination = 'docs\RELEASE_NOTES_2.3.0.md' },

    [pscustomobject]@{ Source = 'tools\Test-A1M-Edid.ps1'; Destination = 'SOURCE\Test-A1M-Edid.ps1' },
    [pscustomobject]@{ Source = 'tools\Test-Lfc-Backup-Identity.ps1'; Destination = 'SOURCE\Test-Lfc-Backup-Identity.ps1' },
    [pscustomobject]@{ Source = 'tools\Test-Lfc-Atomic-Replace.ps1'; Destination = 'SOURCE\Test-Lfc-Atomic-Replace.ps1' },
    [pscustomobject]@{ Source = 'tools\Test-ArcSync-Range-Policy.ps1'; Destination = 'SOURCE\Test-ArcSync-Range-Policy.ps1' },
    [pscustomobject]@{ Source = 'tools\Test-Experimental-Overclock-Edids.ps1'; Destination = 'SOURCE\Test-Experimental-Overclock-Edids.ps1' },
    [pscustomobject]@{ Source = 'tools\Test-Public-Installer-Matrix.ps1'; Destination = 'SOURCE\Test-Public-Installer-Matrix.ps1' },
    [pscustomobject]@{ Source = 'tools\Test-Protected-Runtime-Acl.ps1'; Destination = 'SOURCE\Test-Protected-Runtime-Acl.ps1' },
    [pscustomobject]@{ Source = 'tools\Test-Scheduled-Task-Persistence.ps1'; Destination = 'SOURCE\Test-Scheduled-Task-Persistence.ps1' },
    [pscustomobject]@{ Source = 'tools\Test-Tma2027-Recovery-Flow.ps1'; Destination = 'SOURCE\Test-Tma2027-Recovery-Flow.ps1' },
    [pscustomobject]@{ Source = 'tools\Test-Guarded-Trial-FailClosed.ps1'; Destination = 'SOURCE\Test-Guarded-Trial-FailClosed.ps1' },
    [pscustomobject]@{ Source = 'tools\Test-ClawLab-VRR-Transaction.ps1'; Destination = 'SOURCE\Test-ClawLab-VRR-Transaction.ps1' },
    [pscustomobject]@{ Source = 'tools\Test-Startup-Orchestration.ps1'; Destination = 'SOURCE\Test-Startup-Orchestration.ps1' },
    [pscustomobject]@{ Source = 'tools\Test-Normalization-Compensation.ps1'; Destination = 'SOURCE\Test-Normalization-Compensation.ps1' },
    [pscustomobject]@{ Source = 'tools\Test-Lfc-Factory-Defaults-Recovery.ps1'; Destination = 'SOURCE\Test-Lfc-Factory-Defaults-Recovery.ps1' },
    [pscustomobject]@{ Source = 'tools\Test-Stable-Same-Profile-Repair.ps1'; Destination = 'SOURCE\Test-Stable-Same-Profile-Repair.ps1' },
    [pscustomobject]@{ Source = 'tests\Test-ClawLab-Localization.ps1'; Destination = 'SOURCE\Test-ClawLab-Localization.ps1' },
    [pscustomobject]@{ Source = 'tools\CursorRefreshHelper\ClawLabCursorRefreshHelperWpf.cs'; Destination = 'SOURCE\CursorRefreshHelper\ClawLabCursorRefreshHelperWpf.cs' },
    [pscustomobject]@{ Source = 'tools\CursorRefreshHelper\ClawLabCursorRefreshNativeDxgi.cs'; Destination = 'SOURCE\CursorRefreshHelper\ClawLabCursorRefreshNativeDxgi.cs' },
    [pscustomobject]@{ Source = 'tools\CursorRefreshHelper\Build-CursorRefreshHelper.ps1'; Destination = 'SOURCE\CursorRefreshHelper\Build-CursorRefreshHelper.ps1' },
    [pscustomobject]@{ Source = 'tools\CursorRefreshHelper\README.md'; Destination = 'SOURCE\CursorRefreshHelper\README.md' }
)

foreach ($releaseFile in $releaseFiles) {
    $sourcePath = Join-Path $projectRoot $releaseFile.Source
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Release file missing: $($releaseFile.Source)"
    }
}
$releasePowerShellSources = @($releaseFiles | Where-Object {
        [IO.Path]::GetExtension([string]$_.Destination) -ieq '.ps1'
    })
foreach ($releasePowerShellSource in $releasePowerShellSources) {
    $sourcePath = Join-Path $projectRoot ([string]$releasePowerShellSource.Source)
    $nonAsciiBytes = @([IO.File]::ReadAllBytes($sourcePath) | Where-Object { $_ -gt 0x7F })
    if ($nonAsciiBytes.Count -gt 0) {
        throw "PowerShell release source is not code-page-independent ASCII: $($releasePowerShellSource.Source)"
    }
}
$plannedBatchLaunchers = @($releaseFiles | Where-Object {
        [IO.Path]::GetExtension([string]$_.Source) -ieq '.bat'
    })
foreach ($launcher in $plannedBatchLaunchers) {
    $launcherPath = Join-Path $projectRoot ([string]$launcher.Source)
    $launcherText = [IO.File]::ReadAllText($launcherPath, [Text.Encoding]::Default)
    if ([regex]::Matches($launcherText,
            '(?im)^set "CLAWLAB_POWERSHELL=%SystemRoot%\\System32\\WindowsPowerShell\\v1\.0\\powershell\.exe"\s*$').Count -ne 1 -or
        [regex]::Matches($launcherText,
            '(?im)^if not exist "%CLAWLAB_POWERSHELL%" exit /b 1\s*$').Count -ne 1 -or
        [regex]::Matches($launcherText,
            '(?im)^"%CLAWLAB_POWERSHELL%"\s').Count -ne 1 -or
        $launcherText -match '(?im)^\s*powershell(?:\.exe)?\s') {
        throw "Release launcher does not use the fail-closed absolute Windows PowerShell path: $($launcher.Source)"
    }
}
$duplicateDestinations = @($releaseFiles | Group-Object Destination | Where-Object Count -ne 1)
if ($duplicateDestinations.Count -gt 0) {
    throw "Duplicate release destinations: $($duplicateDestinations.Name -join ', ')"
}
foreach ($releaseFile in $releaseFiles) {
    $source = [string]$releaseFile.Source
    $destination = [string]$releaseFile.Destination
    if ([IO.Path]::IsPathRooted($source) -or $source -match '(^|[\\/])\.\.([\\/]|$)') {
        throw "Unsafe release source: $source"
    }
    if ([IO.Path]::IsPathRooted($destination) -or $destination -match '(^|[\\/])\.\.([\\/]|$)') {
        throw "Unsafe release destination: $destination"
    }
}
$expectedRootFiles = @(
    'INSTALL_30_120_VRR.bat', 'INSTALL_48_120_VRR.bat',
    'SELECT_LANGUAGE.bat', 'CHECK_STATUS.bat', 'UPDATE_CURSOR_REFRESH_ENGINE.bat', 'README.txt',
    'CHANGELOG.txt', 'LICENSE.txt', 'FILES_SHA256.txt'
)
$requiredStructuredEntries = @(
    'RECOVERY/RESTORE_ORIGINAL_VRR.bat',
    'EMERGENCY/FACTORY_RESET_CLAWLAB_VRR.bat',
    'DIAGNOSTICS/EXPORT_STATUS_REPORT.bat',
    'scripts/ClawLab-VRR-Transaction.ps1',
    'scripts/Scheduled-Task-Persistence.ps1',
    'scripts/ClawLab-Localization.ps1',
    'scripts/Select-ClawLab-Language.ps1',
    'scripts/locales/messages.json',
    'scripts/MSI-Claw-VRR-Fix.ps1',
    'scripts/MSI-Claw-Intel-LFC-Fix.ps1',
    'scripts/Experimental-Overclock-VRR-Trial.ps1',
    'scripts/ClawLab-Cursor-Refresh-Helper.exe',
    'SOURCE/Test-ClawLab-Localization.ps1',
    'SOURCE/Test-Scheduled-Task-Persistence.ps1',
    'SOURCE/Test-ClawLab-VRR-Transaction.ps1',
    'SOURCE/Test-Tma2027-Recovery-Flow.ps1',
    'SOURCE/Test-Guarded-Trial-FailClosed.ps1',
    'SOURCE/Test-Startup-Orchestration.ps1',
    'SOURCE/Test-Normalization-Compensation.ps1',
    'SOURCE/Test-Lfc-Factory-Defaults-Recovery.ps1',
    'SOURCE/Test-Stable-Same-Profile-Repair.ps1',
    'SOURCE/Test-Public-Installer-Matrix.ps1',
    'SOURCE/CursorRefreshHelper/ClawLabCursorRefreshNativeDxgi.cs',
    'docs/RELEASE_NOTES_2.3.0.md'
)
$plannedEntries = @($releaseFiles | ForEach-Object {
        ([string]$_.Destination).Replace('\', '/')
    }) + @('FILES_SHA256.txt')
$plannedRootFiles = @($plannedEntries | Where-Object { $_ -notmatch '/' } | Sort-Object)
$missingPlannedRoot = @($expectedRootFiles | Where-Object { $_ -notin $plannedRootFiles })
$unexpectedPlannedRoot = @($plannedRootFiles | Where-Object { $_ -notin $expectedRootFiles })
if ($missingPlannedRoot.Count -gt 0 -or $unexpectedPlannedRoot.Count -gt 0) {
    throw "Unexpected planned ZIP root. Missing: $($missingPlannedRoot -join ', '). Unexpected: $($unexpectedPlannedRoot -join ', ')."
}
foreach ($requiredEntry in $requiredStructuredEntries) {
    if ($requiredEntry -notin $plannedEntries) {
        throw "Required planned ZIP entry is missing: $requiredEntry"
    }
}

$retiredPublicFiles = @(
    'INSTALL_EXPERIMENTAL_48_144_VRR.bat',
    'INSTALL_EXPERIMENTAL_30_144_VRR.bat',
    'Experimental-144-VRR-Trial.ps1',
    'ClawLab-144-Trial-Startup.vbs'
)
foreach ($relativePath in $retiredPublicFiles) {
    if (Test-Path -LiteralPath (Join-Path $projectRoot $relativePath)) {
        throw "Retired public file must not exist: $relativePath"
    }
}

& $cursorHelperBuilder -OutputDirectory $projectRoot | Out-Host
if (-not (Test-Path -LiteralPath $cursorHelperPath -PathType Leaf)) {
    throw 'Cursor Refresh Helper build did not produce the expected executable.'
}
$cursorHelperAssembly = [Reflection.AssemblyName]::GetAssemblyName($cursorHelperPath)
if ($cursorHelperAssembly.Version.ToString() -ne "$Version.0") {
    throw "Cursor Refresh Helper version $($cursorHelperAssembly.Version) does not match release $Version."
}
$cursorHelperWpfSourceText = [IO.File]::ReadAllText(
    (Join-Path $projectRoot 'tools\CursorRefreshHelper\ClawLabCursorRefreshHelperWpf.cs'),
    [Text.Encoding]::UTF8)
foreach ($value in @(
        '1500L / 1000L', 'NearBlackBrush', 'RegisterRawInputDevices',
        'SetProcessWorkingSetSize', 'timeEndPeriod(1)', 'WaitForInteractiveDesktop();',
        'StartupWarmupTicks', 'BeginStartupWarmup();',
        'GetShellWindow()', 'DwmIsCompositionEnabled', "AssemblyVersion(`"$Version.0`")"
    )) {
    Assert-ContainsLiteral -Text $cursorHelperWpfSourceText -Value $value -Label 'Cursor Refresh WPF fallback source'
}
$cursorHelperNativeSourceText = [IO.File]::ReadAllText(
    (Join-Path $projectRoot 'tools\CursorRefreshHelper\ClawLabCursorRefreshNativeDxgi.cs'),
    [Text.Encoding]::UTF8)
foreach ($value in @(
        'NATIVE_WIN32_DXGI_FLIP_MODEL', 'DxgiSwapEffectFlipSequential',
        'MsgWaitForMultipleObjectsEx', 'RidevInputSink',
        'CursorRefreshControl.NativeWaitHandles', 'CursorRefreshControl.SignalReady();',
        'CursorRefreshControl.WriteRuntimeState(', 'WaitFailed',
        'ClearRenderTargetViewVtableIndex', 'ALTERNATING_OPAQUE_NEAR_BLACK',
        'GCHandleType.Pinned'
    )) {
    Assert-ContainsLiteral -Text $cursorHelperNativeSourceText -Value $value -Label 'Cursor Refresh native DXGI source'
}
foreach ($forbiddenMarker in @('GetRawInputData', 'AllocHGlobal', 'FreeHGlobal')) {
    if ($cursorHelperWpfSourceText.Contains($forbiddenMarker) -or
        $cursorHelperNativeSourceText.Contains($forbiddenMarker)) {
        throw "Cursor Refresh Helper reintroduced a per-packet allocation path: $forbiddenMarker"
    }
}

$mainVrrPath = Join-Path $projectRoot 'MSI-Claw-VRR-Fix.ps1'
$lfcPath = Join-Path $projectRoot 'MSI-Claw-Intel-LFC-Fix.ps1'
$trialPath = Join-Path $projectRoot 'Experimental-Overclock-VRR-Trial.ps1'
$coordinatorPath = Join-Path $projectRoot 'ClawLab-VRR-Transaction.ps1'
$mainVrr = [IO.File]::ReadAllText($mainVrrPath, [Text.Encoding]::UTF8)
$lfc = [IO.File]::ReadAllText($lfcPath, [Text.Encoding]::UTF8)
$trial = [IO.File]::ReadAllText($trialPath, [Text.Encoding]::UTF8)
$coordinator = [IO.File]::ReadAllText($coordinatorPath, [Text.Encoding]::UTF8)

Assert-ContainsLiteral -Text $mainVrr -Value "`$fixVersion = '$Version'" -Label 'VRR source'
Assert-ContainsLiteral -Text $mainVrr -Value "ClawLab-VRR-Privileged\$expectedProtectedRuntimeVersion" -Label 'VRR source'
Assert-ContainsLiteral -Text $lfc -Value "`$toolVersion = '$expectedLfcVersion'" -Label 'LFC source'
Assert-ContainsLiteral -Text $trial -Value "`$fixVersion = '$Version'" -Label 'Experimental trial source'
Assert-ContainsLiteral -Text $trial -Value "ClawLab-VRR-Privileged\$expectedProtectedRuntimeVersion" -Label 'Experimental trial source'
Assert-ContainsLiteral -Text $coordinator -Value "`$script:CoordinatorVersion = '$Version'" -Label 'Coordinator source'
foreach ($textDefinition in @(
        [pscustomobject]@{ Text = $mainVrr; Label = 'VRR source' },
        [pscustomobject]@{ Text = $lfc; Label = 'LFC source' },
        [pscustomobject]@{ Text = $trial; Label = 'Experimental trial source' },
        [pscustomobject]@{ Text = $coordinator; Label = 'Coordinator source' }
    )) {
    if ($textDefinition.Text -match '(?i)(^|[^0-9])(15|24)[-_]120([^0-9]|$)|Install(15|24)') {
        throw "$($textDefinition.Label) exposes a forbidden telemetry-only profile."
    }
}

$expectedProtectedPayload = @(
    'MSI-Claw-VRR-Fix.ps1',
    'Edid-Normalization.ps1',
    'ArcSync-Range-Policy.ps1',
    'Scheduled-Task-Persistence.ps1',
    'ClawLab-VRR-Startup.vbs',
    'ClawLab-Cursor-Refresh-Helper.exe',
    'MSI-Claw-Intel-LFC-Fix.ps1',
    'Intel-VRR-LFC-Driver-Interface.ps1',
    'Lfc-Backup-Identity.ps1',
    'ClawLab-LFC-Startup.vbs',
    'ClawLab-Localization.ps1',
    'locales\messages.json',
    'Experimental-Overclock-VRR-Trial.ps1',
    'ClawLab-Experimental-Trial-Startup.vbs'
)
$protectedPayloads = @(
    @(Get-LiteralStringArrayAssignment -Path $mainVrrPath -VariableName 'protectedRuntimePayloadNames'),
    @(Get-LiteralStringArrayFunctionResult -Path $trialPath -FunctionName 'Get-ProtectedRuntimePayload')
)
$expectedPayloadKey = (@($expectedProtectedPayload | Sort-Object) -join '|')
foreach ($payload in $protectedPayloads) {
    if ($payload.Count -ne $expectedProtectedPayload.Count -or
        (@($payload | Sort-Object) -join '|') -cne $expectedPayloadKey) {
        throw 'Protected runtime payload definitions are not identical and complete for 2.3.0.'
    }
}

$powerShellSources = @(Get-ChildItem -LiteralPath $projectRoot -Recurse -File -Filter '*.ps1' |
    Where-Object { $_.FullName -notmatch '[\\/]dist[\\/]' })
foreach ($source in $powerShellSources) {
    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $source.FullName, [ref]$tokens, [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) {
        throw "PowerShell parse failure in $($source.FullName): $((@($parseErrors | ForEach-Object Message)) -join ' | ')"
    }
}

$crossShellTests = @(
    'tests\Test-ClawLab-Localization.ps1',
    'tools\Test-Scheduled-Task-Persistence.ps1',
    'tools\Test-ArcSync-Range-Policy.ps1',
    'tools\Test-ClawLab-VRR-Transaction.ps1',
    'tools\Test-Tma2027-Recovery-Flow.ps1',
    'tools\Test-Guarded-Trial-FailClosed.ps1',
    'tools\Test-Startup-Orchestration.ps1',
    'tools\Test-Normalization-Compensation.ps1',
    'tools\Test-Lfc-Factory-Defaults-Recovery.ps1',
    'tools\Test-Stable-Same-Profile-Repair.ps1',
    'tools\Test-Public-Installer-Matrix.ps1',
    'tools\Test-A1M-Edid.ps1',
    'tools\Test-Experimental-Overclock-Edids.ps1',
    'tools\Test-Lfc-Backup-Identity.ps1',
    'tools\Test-Lfc-Atomic-Replace.ps1',
    'tools\Test-Protected-Runtime-Acl.ps1'
)
$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$powerShell7 = Get-Command pwsh.exe -ErrorAction SilentlyContinue
if (-not (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf)) {
    throw 'Windows PowerShell 5.1 was not found.'
}
if ($null -eq $powerShell7) {
    throw 'PowerShell 7 is required for the cross-version release validation.'
}
foreach ($relativeTest in $crossShellTests) {
    $testPath = Join-Path $projectRoot $relativeTest
    Invoke-ClawLabTestInShell -Executable $windowsPowerShell -TestPath $testPath -ShellLabel 'PS5.1'
    Invoke-ClawLabTestInShell -Executable $powerShell7.Source -TestPath $testPath -ShellLabel 'PS7'
}

$forbiddenExtensions = @('.dll', '.sys', '.bin', '.rom', '.zip', '.7z', '.rar', '.bak', '.dmp', '.etl')
$forbiddenFiles = @(Get-ChildItem -LiteralPath $projectRoot -Recurse -File | Where-Object {
        $_.FullName -notmatch '[\\/]dist[\\/]' -and
        $forbiddenExtensions -contains $_.Extension.ToLowerInvariant()
    })
if ($forbiddenFiles.Count -gt 0) {
    throw "Forbidden binary, driver, EDID dump, trace, backup or archive found:`n$($forbiddenFiles.FullName -join "`n")"
}
$unexpectedExecutables = @(Get-ChildItem -LiteralPath $projectRoot -Recurse -File -Filter '*.exe' | Where-Object {
        $_.FullName -notmatch '[\\/]dist[\\/]' -and
        -not $_.FullName.Equals($cursorHelperPath, [StringComparison]::OrdinalIgnoreCase)
    })
if ($unexpectedExecutables.Count -gt 0) {
    throw "Unexpected executable found in the release source:`n$($unexpectedExecutables.FullName -join "`n")"
}
$forbiddenPlannedEntries = @($plannedEntries | Where-Object {
        $extension = [IO.Path]::GetExtension($_).ToLowerInvariant()
        ($extension -in $forbiddenExtensions) -or
        ($extension -eq '.exe' -and $_ -cne 'scripts/ClawLab-Cursor-Refresh-Helper.exe')
    })
if ($forbiddenPlannedEntries.Count -gt 0) {
    throw "Forbidden file planned for the release ZIP:`n$($forbiddenPlannedEntries -join "`n")"
}

if ($ValidateOnly) {
    return [pscustomobject]@{
        Result = 'PASS'
        Version = $Version
        ValidationOnly = $true
        ReleaseFiles = $releaseFiles.Count
        PowerShellSources = $powerShellSources.Count
        Archive = $null
    }
}

$distFull = [IO.Path]::GetFullPath($distRoot)
$stagingFull = [IO.Path]::GetFullPath($stagingRoot)
if (-not $stagingFull.StartsWith($distFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe staging path: $stagingFull"
}

New-Item -ItemType Directory -Path $distRoot -Force | Out-Null
if (Test-Path -LiteralPath $stagingRoot) {
    [IO.Directory]::Delete($stagingRoot, $true)
}
if (Test-Path -LiteralPath $archivePath) {
    [IO.File]::Delete($archivePath)
}
if (Test-Path -LiteralPath $archiveHashPath) {
    [IO.File]::Delete($archiveHashPath)
}
if (Test-Path -LiteralPath $hashPath) {
    [IO.File]::Delete($hashPath)
}
New-Item -ItemType Directory -Path $stagedPackageRoot -Force | Out-Null

$buildSucceeded = $false
try {
    foreach ($releaseFile in $releaseFiles) {
        $destination = Join-Path $stagedPackageRoot $releaseFile.Destination
        [IO.Directory]::CreateDirectory((Split-Path $destination -Parent)) | Out-Null
        Copy-Item -LiteralPath (Join-Path $projectRoot $releaseFile.Source) -Destination $destination
    }

    $manifest = @(Get-ChildItem -LiteralPath $stagedPackageRoot -Recurse -File |
        Sort-Object FullName | ForEach-Object {
            $relativePath = $_.FullName.Substring($stagedPackageRoot.Length + 1).Replace('\', '/')
            $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            "$hash *$relativePath"
        })
    [IO.File]::WriteAllLines(
        (Join-Path $stagedPackageRoot 'FILES_SHA256.txt'), $manifest, [Text.Encoding]::ASCII)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory(
        $stagingRoot, $archivePath, [IO.Compression.CompressionLevel]::Optimal, $false)

    $zip = [IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        $entries = @($zip.Entries)
        $packagePrefix = "$packageName/"
        $relativeEntries = @($entries | Where-Object {
                -not [string]::IsNullOrWhiteSpace($_.Name)
            } | ForEach-Object {
                $entry = $_.FullName.Replace('\', '/')
                if (-not $entry.StartsWith($packagePrefix, [StringComparison]::OrdinalIgnoreCase)) {
                    throw "Release ZIP entry escaped the package root: $entry"
                }
                $entry.Substring($packagePrefix.Length)
            })

        $manifestEntry = @($entries | Where-Object {
                $_.FullName.Replace('\', '/').Equals(
                    ($packagePrefix + 'FILES_SHA256.txt'), [StringComparison]::OrdinalIgnoreCase)
            })
        if ($manifestEntry.Count -ne 1) {
            throw 'The release ZIP must contain exactly one FILES_SHA256.txt manifest.'
        }
        $manifestStream = $manifestEntry[0].Open()
        try {
            $manifestReader = [IO.StreamReader]::new($manifestStream, [Text.Encoding]::ASCII, $false, 1024, $true)
            try { $zippedManifest = $manifestReader.ReadToEnd() }
            finally { $manifestReader.Dispose() }
        }
        finally {
            $manifestStream.Dispose()
        }
        $manifestLines = @($zippedManifest -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($manifestLines.Count -ne $releaseFiles.Count) {
            throw "The ZIP manifest has $($manifestLines.Count) entries; expected $($releaseFiles.Count)."
        }
        $sha256 = [Security.Cryptography.SHA256]::Create()
        try {
            foreach ($line in $manifestLines) {
                $match = [regex]::Match($line, '^([a-f0-9]{64}) \*(.+)$')
                if (-not $match.Success) {
                    throw "Invalid FILES_SHA256.txt line: $line"
                }
                $manifestRelativePath = $match.Groups[2].Value
                $payloadEntry = @($entries | Where-Object {
                        $_.FullName.Replace('\', '/').Equals(
                            ($packagePrefix + $manifestRelativePath), [StringComparison]::Ordinal)
                    })
                if ($payloadEntry.Count -ne 1) {
                    throw "Manifest payload is missing or duplicated in the ZIP: $manifestRelativePath"
                }
                $payloadStream = $payloadEntry[0].Open()
                try {
                    $actualPayloadHash = ([BitConverter]::ToString(
                            $sha256.ComputeHash($payloadStream))).Replace('-', '').ToLowerInvariant()
                }
                finally {
                    $payloadStream.Dispose()
                }
                if ($actualPayloadHash -cne $match.Groups[1].Value) {
                    throw "ZIP payload hash mismatch: $manifestRelativePath"
                }
            }
        }
        finally {
            $sha256.Dispose()
        }

        $actualRootFiles = @($relativeEntries | Where-Object { $_ -notmatch '/' } | Sort-Object)
        $missingRoot = @($expectedRootFiles | Where-Object { $_ -notin $actualRootFiles })
        $unexpectedRoot = @($actualRootFiles | Where-Object { $_ -notin $expectedRootFiles })
        if ($missingRoot.Count -gt 0 -or $unexpectedRoot.Count -gt 0) {
            throw "Unexpected ZIP root. Missing: $($missingRoot -join ', '). Unexpected: $($unexpectedRoot -join ', ')."
        }

        foreach ($requiredEntry in $requiredStructuredEntries) {
            if ($requiredEntry -notin $relativeEntries) {
                throw "Required structured ZIP entry is missing: $requiredEntry"
            }
        }

        $forbiddenZipEntries = @($relativeEntries | Where-Object {
                $extension = [IO.Path]::GetExtension($_).ToLowerInvariant()
                ($extension -in $forbiddenExtensions) -or
                ($extension -eq '.exe' -and $_ -cne 'scripts/ClawLab-Cursor-Refresh-Helper.exe')
            })
        if ($forbiddenZipEntries.Count -gt 0) {
            throw "Forbidden file detected in release ZIP:`n$($forbiddenZipEntries -join "`n")"
        }
        $entryCount = $entries.Count
    }
    finally {
        $zip.Dispose()
    }

    $releaseHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText($hashPath, "$releaseHash *$archiveName`r`n", [Text.Encoding]::ASCII)
    [IO.File]::WriteAllText($archiveHashPath, "$releaseHash *$archiveName`r`n", [Text.Encoding]::ASCII)
    $buildSucceeded = $true
}
finally {
    if (Test-Path -LiteralPath $stagingRoot) {
        [IO.Directory]::Delete($stagingRoot, $true)
    }
    if (-not $buildSucceeded) {
        foreach ($failedArtifact in @($archivePath, $archiveHashPath, $hashPath)) {
            if (Test-Path -LiteralPath $failedArtifact -PathType Leaf) {
                [IO.File]::Delete($failedArtifact)
            }
        }
    }
}

[pscustomobject]@{
    Result = 'PASS'
    Archive = $archivePath
    HashFile = $archiveHashPath
    Sha256 = $releaseHash.ToUpperInvariant()
    Entries = $entryCount
    Version = $Version
}
