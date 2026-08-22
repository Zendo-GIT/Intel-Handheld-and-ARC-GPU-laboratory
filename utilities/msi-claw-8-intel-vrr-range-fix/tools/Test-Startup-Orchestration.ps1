[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$runtimeRoot = if (Test-Path -LiteralPath (Join-Path $root 'scripts\MSI-Claw-VRR-Fix.ps1') -PathType Leaf) {
    Join-Path $root 'scripts'
}
else { $root }
$vrrPath = Join-Path $runtimeRoot 'MSI-Claw-VRR-Fix.ps1'
$lfcPath = Join-Path $runtimeRoot 'MSI-Claw-Intel-LFC-Fix.ps1'
$coordinatorPath = Join-Path $runtimeRoot 'ClawLab-VRR-Transaction.ps1'
$vrr = [IO.File]::ReadAllText($vrrPath, [Text.Encoding]::UTF8).Replace("`r`n", "`n")
$lfc = [IO.File]::ReadAllText($lfcPath, [Text.Encoding]::UTF8).Replace("`r`n", "`n")
$coordinator = [IO.File]::ReadAllText($coordinatorPath, [Text.Encoding]::UTF8).Replace("`r`n", "`n")

function Assert-Contains {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Needle,
        [Parameter(Mandatory)][string]$Message
    )
    if ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -lt 0) {
        throw $Message
    }
}

function Assert-NotContains {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Needle,
        [Parameter(Mandatory)][string]$Message
    )
    if ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -ge 0) {
        throw $Message
    }
}

function Assert-Ordered {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string[]]$Needles,
        [Parameter(Mandatory)][string]$Message
    )
    $cursor = 0
    foreach ($needle in $Needles) {
        $index = $Text.IndexOf($needle, $cursor, [StringComparison]::Ordinal)
        if ($index -lt 0) {
            throw "$Message Missing or out-of-order marker: $needle"
        }
        $cursor = $index + $needle.Length
    }
}

function Get-Region {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Start,
        [Parameter(Mandatory)][string]$End
    )
    $startIndex = $Text.IndexOf($Start, [StringComparison]::Ordinal)
    if ($startIndex -lt 0) { throw "Region start not found: $Start" }
    $endIndex = $Text.IndexOf($End, $startIndex + $Start.Length, [StringComparison]::Ordinal)
    if ($endIndex -lt 0) { throw "Region end not found: $End" }
    return $Text.Substring($startIndex, $endIndex - $startIndex)
}

$vrrTaskSpec = Get-Region -Text $vrr -Start 'function Get-LfcStartupOrchestratorTaskSpec {' `
    -End 'function Test-LfcStartupOrchestratorReady {'
$lfcTaskSpec = Get-Region -Text $lfc -Start 'function Get-StartupTaskSpec {' `
    -End 'function Install-StartupPersistence {'
foreach ($spec in @($vrrTaskSpec, $lfcTaskSpec)) {
    Assert-Contains -Text $spec -Needle '-ExecutionTimeLimitMinutes 12' `
        -Message 'The LFC orchestrator must have a twelve-minute fail-safe task budget.'
    Assert-Contains -Text $spec -Needle '-TriggerDelaySeconds 15' `
        -Message 'The VRR and LFC definitions must agree on the 15-second orchestrator delay.'
}

$directVrrTaskSpec = Get-Region -Text $vrr -Start 'function Get-VrrStartupTaskSpec {' `
    -End 'function Get-CursorRefreshHelperTaskSpec {'
Assert-Contains -Text $directVrrTaskSpec -Needle '-ExecutionTimeLimitMinutes 10' `
    -Message 'The direct VRR fallback must have enough budget for both bounded machine-wide lock waits and driver verification.'
$cursorTaskSpec = Get-Region -Text $vrr -Start 'function Get-CursorRefreshHelperTaskSpec {' `
    -End 'function Get-LfcStartupOrchestratorTaskSpec {'
foreach ($cursorTaskMarker in @(
        '-ExecutePath $installedCursorRefreshHelperPath',
        "-Arguments '--startup'",
        '-ExecutionTimeLimitMinutes 0',
        '-TaskPriority 2'
    )) {
    Assert-Contains -Text $cursorTaskSpec -Needle $cursorTaskMarker `
        -Message "The direct Cursor Refresh logon task is missing: $cursorTaskMarker"
}

$cursorStart = Get-Region -Text $vrr `
    -Start 'function Start-CursorRefreshHelper {' `
    -End 'function Sync-CursorRefreshHelper {'
Assert-Contains -Text $cursorStart -Needle 'Start-ClawLabScheduledTask' `
    -Message 'The cursor engine must be launched through its verified limited-user task.'
Assert-NotContains -Text $cursorStart -Needle 'Start-Process' `
    -Message 'The cursor engine still inherits the elevated installer token through Start-Process.'

$cursorOnlyUpdate = Get-Region -Text $vrr `
    -Start 'function Update-CursorRefreshHelperOnly {' `
    -End 'function Invoke-CursorRefreshHelperStartupBestEffort {'
Assert-Ordered -Text $cursorOnlyUpdate -Needles @(
    "[string]`$effective.State -ne 'CONSISTENT'",
    "[string]`$managed.FixVersion -ne `$fixVersion",
    'Test-ManagedArcSyncSnapshot',
    'Install-CursorRefreshHelper',
    'Start-CursorRefreshHelper',
    'Sync-CursorRefreshHelper',
    'ProfileChanged = $false',
    'LfcChanged = $false',
    'EdidChanged = $false',
    'RestartRequired = $false'
) -Message 'The cursor-only updater must prove the current profile and expose its no-display-mutation contract.'
foreach ($forbiddenCursorMutation in @(
        'Install-CustomEdidMode',
        'Invoke-SetProfile',
        'Set-ManagedModeRecord',
        'Set-VerifiedDisplayRefresh',
        'MSI-Claw-Intel-LFC-Fix.ps1',
        'New-ItemProperty',
        'SetValue('
    )) {
    Assert-NotContains -Text $cursorOnlyUpdate -Needle $forbiddenCursorMutation `
        -Message "The cursor-only updater contains a forbidden display/LFC mutation: $forbiddenCursorMutation"
}

$cursorMaintenance = Get-Region -Text $coordinator `
    -Start "elseif (`$RequestedAction -eq 'UpdateCursorHelper') {" `
    -End "elseif (`$RequestedAction -eq 'Restore') {"
Assert-Contains -Text $cursorMaintenance -Needle '-CoreAction UpdateCursorRefresh' `
    -Message 'The public cursor updater must route only to the core cursor-maintenance action.'
foreach ($forbiddenCoordinatorMutation in @(
        '$script:LfcToolPath',
        'Install30',
        'Install48',
        'FactoryReset',
        'EmergencyRestoreEdid'
    )) {
    Assert-NotContains -Text $cursorMaintenance -Needle $forbiddenCoordinatorMutation `
        -Message "The public cursor maintenance branch contains a forbidden profile/recovery action: $forbiddenCoordinatorMutation"
}

$maintenanceFailure = Get-Region -Text $coordinator `
    -Start 'if ($RequestedAction -in $script:MaintenanceActions -and' `
    -End 'elseif ($null -ne $journal'
Assert-Contains -Text $maintenanceFailure -Needle '[IO.File]::Delete($Paths.Journal)' `
    -Message 'A failed cursor-only update must discard its maintenance journal instead of forcing display recovery.'

$directDeferral = Get-Region -Text $vrr `
    -Start "if (`$Action -eq 'ApplyStartup' -and `$StartupSource -eq 'VrrTask'" `
    -End "if (`$Action -eq 'ApplyStartup') {`n        Enter-StartupTransactionLocks"
Assert-Ordered -Text $directDeferral -Needles @(
    'Test-LfcStartupOrchestratorReady',
    'Invoke-CursorRefreshHelperStartupBestEffort -Operation Start',
    'driver reapply deferred to the verified LFC startup orchestrator',
    'exit 0'
) -Message 'The direct VRR task must start only the desktop helper, then delegate every driver write.'

$settledHelperRefresh = Get-Region -Text $vrr `
    -Start '# The refresh transition and Intel Graphics Software startup can' `
    -End 'Write-StartupResult -Success $true'
Assert-Ordered -Text $settledHelperRefresh -Needles @(
    'Start-ManagedIntelGraphicsSoftware',
    'Get-VerifiedManagedArcSyncSnapshot',
    'Invoke-CursorRefreshHelperStartupBestEffort -Operation Resync'
) -Message 'The native helper must be resynchronized in place after final settled Arc Sync verification.'

$orchestratorReadiness = Get-Region -Text $vrr -Start 'function Test-LfcStartupOrchestratorReady {' `
    -End 'function Get-ExperimentalTrialTaskSpec {'
foreach ($payloadName in @(
    'MSI-Claw-Intel-LFC-Fix.ps1',
    'Intel-VRR-LFC-Driver-Interface.ps1',
    'Lfc-Backup-Identity.ps1',
    'Edid-Normalization.ps1',
    'ArcSync-Range-Policy.ps1',
    'Scheduled-Task-Persistence.ps1',
    'ClawLab-LFC-Startup.vbs'
)) {
    $variableDeclaration = $vrr.IndexOf("'$payloadName'", [StringComparison]::Ordinal)
    if ($variableDeclaration -lt 0) {
        throw "The full LFC orchestrator payload declaration is missing $payloadName."
    }
}
foreach ($payloadVariable in @(
    '$installedLfcToolPath',
    '$installedLfcDriverInterfacePath',
    '$installedLfcBackupIdentityPath',
    '$installedLfcEdidNormalizationPath',
    '$installedLfcArcSyncRangePolicyPath',
    '$installedLfcScheduledTaskPersistencePath',
    '$installedLfcLauncherPath'
)) {
    Assert-Contains -Text $orchestratorReadiness -Needle $payloadVariable `
        -Message "Delegation does not verify the complete LFC payload: $payloadVariable"
}

$vrrLockRegion = Get-Region -Text $vrr -Start 'function Enter-StartupTransactionLocks {' `
    -End 'function Exit-StartupTransactionLocks {'
Assert-Ordered -Text $vrrLockRegion -Needles @(
    "if (`$Source -eq 'VrrTask')",
    'Enter-StartupDisplayTransactionMutex',
    'Enter-StartupApplyMutex'
) -Message 'A direct VRR fallback must take DisplayTransaction before VrrApplyStartup.'

$lfcStartup = Get-Region -Text $lfc -Start "if (`$Action -eq 'ApplyStartup') {`n    `$clawTweaksTaskState" `
    -End '$current = Invoke-DirectVrrDriverAction -DriverAction Status'
Assert-Ordered -Text $lfcStartup -Needles @(
    '-Action ApplyStartup -StartupSource LfcTask',
    '.WaitForExit()',
    'if ($rangeProcess.ExitCode -ne 0)',
    'Enter-LfcStartupApplyMutex'
) -Message 'The LFC orchestrator must wait for verified VRR completion before taking the second lock.'
Assert-Contains -Text $lfc -Needle "if (`$Action -eq 'ApplyStartup') {`n    Enter-LfcStartupTransactionMutex" `
    -Message 'The LFC orchestrator must own DisplayTransaction for its complete startup flow.'
Assert-Contains -Text $lfc -Needle "Exit-LfcStartupApplyMutex`n        Exit-LfcStartupTransactionMutex" `
    -Message 'The LFC orchestrator must release startup then display locks.'

foreach ($text in @($vrr, $lfc)) {
    if ($text.IndexOf("Start-Process -FilePath 'powershell.exe'", [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw 'A core startup script still resolves powershell.exe through PATH.'
    }
}

$confirmation = Get-Region -Text $vrr -Start "'ConfirmExperimentalTrial' {" -End "'ApplyStartup' {"
Assert-Ordered -Text $confirmation -Needles @(
    'Set-ManagedModeRecord',
    'Install-StartupReapply -PreserveExperimentalRecovery',
    '-Action Apply',
    'LfcFixActive',
    "-NotePropertyValue 'PERSISTENCE_APPLIED'",
    "[string]`$confirmedManaged.State -ne 'EXPERIMENTAL_TRIAL_PENDING'",
    'Complete-ExperimentalOverclockTrialCommit'
) -Message 'A confirmed experimental profile must install and verify the same VRR/LFC persistence before commit.'

$experimentalActions = @(
    'Install48_144', 'Install48_165', 'Install48_180', 'Install48_192',
    'Install30_144', 'Install30_165', 'Install30_180', 'Install30_192'
)
foreach ($action in $experimentalActions) {
    Assert-Contains -Text $vrr -Needle "'$action'" `
        -Message "The experimental startup matrix is missing $action."
}

$intelStartupResolver = Get-Region -Text $vrr `
    -Start 'function Resolve-IntelGraphicsStartupCommand {' `
    -End 'function Write-IntelStartupBackupAtomically {'
foreach ($resolverMarker in @(
        '(?i)^\s*"',
        '\\IntelGraphicsSoftware\.exe)',
        '(?<Arguments>-s)\s*$',
        'Get-AuthenticodeSignature',
        'O=Intel Corporation',
        'Join-Path $env:ProgramFiles'
    )) {
    Assert-Contains -Text $intelStartupResolver -Needle $resolverMarker `
        -Message "The signed Intel startup resolver lost a safety boundary: $resolverMarker"
}

$intelStartupState = Get-Region -Text $vrr `
    -Start 'function Get-IntelStartupOrderState {' `
    -End 'function Set-ManagedIntelStartupOrder {'
Assert-Ordered -Text $intelStartupState -Needles @(
    'Resolve-IntelGraphicsStartupCommand -Command $current',
    "return 'SIGNED_INTEL_ENTRY_UPDATED'",
    "return 'UNKNOWN_STARTUP_ENTRY'"
) -Message 'A changed Intel startup entry must require a fresh signature proof and otherwise fail closed.'

$intelStartupManagement = Get-Region -Text $vrr `
    -Start 'function Set-ManagedIntelStartupOrder {' `
    -End 'function Restore-IntelStartupOrder {'
Assert-Ordered -Text $intelStartupManagement -Needles @(
    'Resolve-IntelGraphicsStartupCommand -Command $current',
    '$backup.OriginalEntryPresent = $true',
    'Set-IntelStartupTrustedIdentity',
    'Remove-ItemProperty'
) -Message 'A signed Intel updater entry must be adopted before ClawLab removes it for ordered startup.'

$intelStartupRestore = Get-Region -Text $vrr `
    -Start 'function Restore-IntelStartupOrder {' `
    -End 'function Get-FactoryIntelStartupCommand {'
Assert-Ordered -Text $intelStartupRestore -Needles @(
    'Resolve-IntelGraphicsStartupCommand -Command $current',
    '$signedIntelUpdatePresent = $true',
    'A newer signed Intel Graphics Software startup entry is present and was preserved.',
    'Remove-FileIfPresent -LiteralPath $intelStartupBackupPath',
    'return'
) -Message 'Restore must preserve a newer signed Intel startup entry instead of requiring the deleted old ZIP.'
Assert-Contains -Text $vrr -Needle "'SIGNED_INTEL_ENTRY_UPDATED'" `
    -Message 'The normal restore preflight does not permit the verified signed-Intel migration state.'

# Exercise the migration policy with an isolated in-memory Run value. No
# registry key, executable, task or display state is touched by this test.
$intelStartupStateDefinition = Get-Region -Text $vrr `
    -Start 'function Get-IntelStartupOrderState {' `
    -End 'function Set-ManagedIntelStartupOrder {'
$intelStartupManagementDefinition = Get-Region -Text $vrr `
    -Start 'function Set-ManagedIntelStartupOrder {' `
    -End 'function Restore-IntelStartupOrder {'
$intelStartupRestoreDefinition = Get-Region -Text $vrr `
    -Start 'function Restore-IntelStartupOrder {' `
    -End 'function Get-FactoryIntelStartupCommand {'

& {
    $script:testBackup = [pscustomobject]@{
        Command = '"C:\Program Files\Intel\Intel Graphics Software\IntelGraphicsSoftware.exe" -s'
        OriginalEntryPresent = $true
    }
    $script:testCurrent = ' "C:\Program Files\Intel\Intel Graphics Software\IntelGraphicsSoftware.exe"  -S '
    $script:testResolverAccepts = $true
    $script:testRegistryWrites = 0
    $script:testRegistryRemovals = 0
    $script:testBackupRemovals = 0
    $script:testAdoptedPresence = $false
    $script:intelStartupBackupPath = 'X:\ClawLab\intel-graphics-startup.json'
    $script:intelStartupRegistryPath = 'Registry::HKEY_LOCAL_MACHINE\ClawLab-Test'
    $script:intelStartupValueName = 'Intel Graphics Software Test'
    $script:stateRoot = 'X:\ClawLab'

    function Get-IntelStartupBackup { return $script:testBackup }
    function Get-IntelStartupRegistryValue { return $script:testCurrent }
    function Test-OriginalIntelStartupEntryPresent { param($Backup); return [bool]$Backup.OriginalEntryPresent }
    function Resolve-IntelGraphicsStartupCommand {
        param($Command)
        if (-not $script:testResolverAccepts) { throw 'unsigned test entry' }
        return [pscustomobject]@{
            Command = [string]$Command
            Executable = 'C:\Program Files\Intel\Intel Graphics Software\IntelGraphicsSoftware.exe'
            Arguments = '-s'
            SignerThumbprint = 'TEST-INTEL-SIGNER'
            FileSha256 = 'TEST-INTEL-HASH'
            FileVersion = '1.0.0.0'
        }
    }
    function Set-IntelStartupTrustedIdentity {
        param($ExistingBackup, $Resolved, [bool]$OriginalEntryPresent)
        $script:testAdoptedPresence = [bool]$ExistingBackup.OriginalEntryPresent -and $OriginalEntryPresent
        $script:testBackup = [pscustomobject]@{
            Command = [string]$Resolved.Command
            OriginalEntryPresent = [bool]$OriginalEntryPresent
        }
        return $script:testBackup
    }
    function Remove-ItemProperty {
        param($LiteralPath, $Name, $ErrorAction)
        $script:testRegistryRemovals++
        $script:testCurrent = $null
    }
    function New-ItemProperty {
        param($LiteralPath, $Name, $PropertyType, $Value, [switch]$Force)
        $script:testRegistryWrites++
        $script:testCurrent = [string]$Value
    }
    function Remove-FileIfPresent {
        param($LiteralPath)
        $script:testBackupRemovals++
    }

    Invoke-Expression $intelStartupStateDefinition
    Invoke-Expression $intelStartupManagementDefinition
    Invoke-Expression $intelStartupRestoreDefinition

    $signedState = Get-IntelStartupOrderState
    if ($signedState -ne 'SIGNED_INTEL_ENTRY_UPDATED') {
        throw "A freshly verified signed Intel replacement was classified as '$signedState'."
    }
    $script:testResolverAccepts = $false
    $unknownState = Get-IntelStartupOrderState
    if ($unknownState -ne 'UNKNOWN_STARTUP_ENTRY') {
        throw "An unsigned Intel startup replacement was classified as '$unknownState'."
    }

    $script:testResolverAccepts = $true
    Set-ManagedIntelStartupOrder
    if (-not $script:testAdoptedPresence -or $script:testRegistryRemovals -ne 1 -or
        -not [string]::IsNullOrEmpty($script:testCurrent)) {
        throw 'The signed Intel update was not adopted and removed into verified ClawLab startup order.'
    }

    $script:testCurrent = ' "C:\Program Files\Intel\Intel Graphics Software\IntelGraphicsSoftware.exe"  -S '
    $script:testBackup.Command = '"C:\Program Files\Intel\Intel Graphics Software\IntelGraphicsSoftware.exe" -s'
    $script:testRegistryWrites = 0
    $script:testBackupRemovals = 0
    Restore-IntelStartupOrder
    if ($script:testRegistryWrites -ne 0 -or $script:testBackupRemovals -ne 1 -or
        [string]::IsNullOrWhiteSpace($script:testCurrent)) {
        throw 'Restore did not preserve the independently verified newer Intel startup entry.'
    }

    $script:testResolverAccepts = $false
    $script:testBackupRemovals = 0
    $unsignedRestoreRejected = $false
    try { Restore-IntelStartupOrder }
    catch { $unsignedRestoreRejected = $true }
    if (-not $unsignedRestoreRejected -or $script:testBackupRemovals -ne 0) {
        throw 'Restore accepted or destructively changed an unsigned Intel startup replacement.'
    }
}

[pscustomobject]@{
    Result = 'PASS'
    StableProfiles = 2
    ConfirmedExperimentalProfiles = 8
    DriverOrder = 'VRR_VERIFY_THEN_LFC'
    ObservationPersistence = 'NONE_UNTIL_CONFIRMATION'
    IntelStartupMigration = 'SIGNED_CANONICAL_ONLY'
}
