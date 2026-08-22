[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Test {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $Condition) { throw $Message }
}

function Get-PairKey {
    param([bool]$Low, [bool]$High)
    return ('{0}{1}' -f [int]$Low, [int]$High)
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$runtimeRoot = if (Test-Path -LiteralPath (Join-Path $projectRoot 'scripts\MSI-Claw-Intel-LFC-Fix.ps1') -PathType Leaf) {
    Join-Path $projectRoot 'scripts'
}
else { $projectRoot }
$lfcPath = Join-Path $runtimeRoot 'MSI-Claw-Intel-LFC-Fix.ps1'
$source = [IO.File]::ReadAllText($lfcPath, [Text.Encoding]::UTF8)
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    $lfcPath,
    [ref]$tokens,
    [ref]$parseErrors
)
Assert-Test ($parseErrors.Count -eq 0) 'The Intel LFC source does not parse.'

$transitionFunction = $ast.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Get-LfcFactoryTransitionStage'
    }, $true)
Assert-Test ($null -ne $transitionFunction) 'The factory-default safe-prefix function is missing.'
Invoke-Expression $transitionFunction.Extent.Text

$intentStageFunction = $ast.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Get-LfcFactoryIntentStage'
    }, $true)
$completeFunction = $ast.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Complete-LfcFactoryDefaultsTransaction'
    }, $true)
Assert-Test ($null -ne $intentStageFunction) 'The factory-default intent verifier is missing.'
Assert-Test ($null -ne $completeFunction) 'The resumable Factory Defaults transaction is missing.'

foreach ($functionName in @('Remove-FileIfPresent', 'Write-LfcJsonFileAtomically')) {
    $functionAst = $ast.Find({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq $functionName
        }, $true)
    Assert-Test ($null -ne $functionAst) "The required atomic-journal function is missing: $functionName"
    Invoke-Expression $functionAst.Extent.Text
}

$lfcStateRoot = Join-Path ([IO.Path]::GetTempPath()) ('ClawLab-LfcFactoryTest-{0}' -f [Guid]::NewGuid().ToString('N'))
try {
    $atomicRecordPath = Join-Path $lfcStateRoot 'factory-default-intent.json'
    Write-LfcJsonFileAtomically -LiteralPath $atomicRecordPath -Value ([ordered]@{
            SchemaVersion = 1
            TransactionId = [Guid]::NewGuid().ToString('D')
            TargetLowFpsSolutionEnabled = $true
            TargetHighFpsSolutionEnabled = $true
        })
    $atomicRecord = [IO.File]::ReadAllText($atomicRecordPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    Assert-Test ([int]$atomicRecord.SchemaVersion -eq 1) 'Atomic WAL readback changed its schema.'
    $duplicateRejected = $false
    try {
        Write-LfcJsonFileAtomically -LiteralPath $atomicRecordPath -Value ([ordered]@{ SchemaVersion = 999 })
    }
    catch {
        $duplicateRejected = $true
    }
    Assert-Test $duplicateRejected 'Atomic WAL creation overwrote an existing transaction record.'
    Assert-Test (@(Get-ChildItem -LiteralPath $lfcStateRoot -Filter '.lfc-journal-*.tmp').Count -eq 0) `
        'Atomic WAL creation left a temporary partial record.'
}
finally {
    if (Test-Path -LiteralPath $lfcStateRoot -PathType Container) {
        [IO.Directory]::Delete($lfcStateRoot, $true)
    }
}

$initialPairs = @(
    [pscustomobject]@{ Name = 'TT'; Low = $true; High = $true },
    [pscustomobject]@{ Name = 'TF'; Low = $true; High = $false },
    [pscustomobject]@{ Name = 'FT'; Low = $false; High = $true },
    [pscustomobject]@{ Name = 'FF'; Low = $false; High = $false }
)
$allPairs = @(
    [pscustomobject]@{ Low = $true; High = $true },
    [pscustomobject]@{ Low = $true; High = $false },
    [pscustomobject]@{ Low = $false; High = $true },
    [pscustomobject]@{ Low = $false; High = $false }
)

# Every possible original Intel pair is accepted, but only its exact initial
# pair, the post-low-write pair and the terminal true/true pair are resumable.
foreach ($initial in $initialPairs) {
    $safeKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    [void]$safeKeys.Add((Get-PairKey $initial.Low $initial.High))
    [void]$safeKeys.Add((Get-PairKey $true $initial.High))
    [void]$safeKeys.Add('11')
    foreach ($current in $allPairs) {
        $stage = Get-LfcFactoryTransitionStage `
            -InitialLowFpsSolutionEnabled $initial.Low `
            -InitialHighFpsSolutionEnabled $initial.High `
            -CurrentLowFpsSolutionEnabled $current.Low `
            -CurrentHighFpsSolutionEnabled $current.High
        $expectedSafe = $safeKeys.Contains((Get-PairKey $current.Low $current.High))
        Assert-Test (($stage -ne 'UNSAFE_STATE') -eq $expectedSafe) `
            "Safe-prefix classification failed for $($initial.Name) -> $(Get-PairKey $current.Low $current.High)."
    }
}

function Resume-TestFactoryTransaction {
    param([Parameter(Mandatory)][hashtable]$State)

    if (-not $State.Intent) {
        Assert-Test ($State.FactoryFinalized -and $State.Low -and $State.High) `
            'A transaction without its WAL did not have durable terminal proof.'
        return
    }
    $stage = Get-LfcFactoryTransitionStage `
        -InitialLowFpsSolutionEnabled $State.InitialLow `
        -InitialHighFpsSolutionEnabled $State.InitialHigh `
        -CurrentLowFpsSolutionEnabled $State.Low `
        -CurrentHighFpsSolutionEnabled $State.High
    Assert-Test ($stage -ne 'UNSAFE_STATE') 'Crash recovery accepted no unsafe Intel flag prefix.'
    if (-not $State.Low) { $State.Low = $true }
    $stage = Get-LfcFactoryTransitionStage `
        -InitialLowFpsSolutionEnabled $State.InitialLow `
        -InitialHighFpsSolutionEnabled $State.InitialHigh `
        -CurrentLowFpsSolutionEnabled $State.Low `
        -CurrentHighFpsSolutionEnabled $State.High
    Assert-Test ($stage -ne 'UNSAFE_STATE') 'The low-FPS write did not produce a safe prefix.'
    if (-not $State.High) { $State.High = $true }
    Assert-Test ($State.Low -and $State.High) 'The resumed transaction did not reach true/true.'
    $State.FactoryFinalized = $true
    $State.RestoreFinalized = $false
    $State.Intent = $false
}

# Inject a crash after every durable/mutating step:
# 0 intent, 1 low flag, 2 high flag, 3 factory provenance,
# 4 source-provenance retirement, 5 intent retirement.
$crashCases = 0..5
$recoveryCases = 0
foreach ($initial in $initialPairs) {
    foreach ($sourceRestoreFinalized in @($false, $true)) {
        foreach ($crashAfter in $crashCases) {
            $state = @{
                InitialLow = [bool]$initial.Low
                InitialHigh = [bool]$initial.High
                Low = [bool]$initial.Low
                High = [bool]$initial.High
                Intent = $true
                RestoreFinalized = [bool]$sourceRestoreFinalized
                FactoryFinalized = $false
            }
            if ($crashAfter -ge 1 -and -not $state.Low) { $state.Low = $true }
            if ($crashAfter -ge 2 -and -not $state.High) { $state.High = $true }
            if ($crashAfter -ge 3) { $state.FactoryFinalized = $true }
            if ($crashAfter -ge 4) { $state.RestoreFinalized = $false }
            if ($crashAfter -ge 5) { $state.Intent = $false }

            Resume-TestFactoryTransaction -State $state
            Assert-Test ($state.Low -and $state.High) `
                "Crash recovery failed to reach true/true for $($initial.Name), step $crashAfter."
            Assert-Test ($state.FactoryFinalized -and -not $state.Intent -and -not $state.RestoreFinalized) `
                "Crash recovery left ambiguous artifacts for $($initial.Name), step $crashAfter."
            $recoveryCases++
        }
    }
}

# Execute the actual production completion function behind a deterministic
# mocked Intel interface. Each injected exception happens immediately after a
# real production mutation, then the same retained artifacts are passed through
# the production completion function again.
$actualRecoveryCases = & {
    param($IntentStageSource, $CompleteSource, $Pairs)

    Invoke-Expression $IntentStageSource
    Invoke-Expression $CompleteSource

    $lfcFactoryFinalizedPath = 'factory-finalized.json'
    $lfcRestoreFinalizedPath = 'restore-finalized.json'
    $lfcFactoryIntentPath = 'factory-default-intent.json'
    $script:harness = $null
    $script:harnessCrashPoint = ''
    $script:harnessCrashConsumed = $false

    function Invoke-HarnessCrash {
        param([Parameter(Mandatory)][string]$Point)
        if (-not $script:harnessCrashConsumed -and $script:harnessCrashPoint -eq $Point) {
            $script:harnessCrashConsumed = $true
            throw "INJECTED_CRASH_$Point"
        }
    }
    function Get-CurrentIntelVrrState {
        [pscustomobject]@{
            Result = 'Success'
            LowFpsSolutionEnabled = [bool]$script:harness.Low
            HighFpsSolutionEnabled = [bool]$script:harness.High
        }
    }
    function Set-LowFpsSolution {
        param([bool]$Enabled)
        $script:harness.Low = $Enabled
        Invoke-HarnessCrash -Point 'LOW_WRITTEN'
    }
    function Set-HighFpsSolution {
        param([bool]$Enabled)
        $script:harness.High = $Enabled
        Invoke-HarnessCrash -Point 'HIGH_WRITTEN'
    }
    function Start-Sleep { param([int]$Milliseconds) }
    function Test-Path {
        param([string]$LiteralPath, [object]$PathType)
        switch ($LiteralPath) {
            'factory-finalized.json' { return [bool]$script:harness.FactoryFinalized }
            'restore-finalized.json' { return [bool]$script:harness.RestoreFinalized }
            'factory-default-intent.json' { return [bool]$script:harness.Intent }
            default { return $false }
        }
    }
    function Get-FileHash {
        param([string]$LiteralPath, [string]$Algorithm)
        [pscustomobject]@{ Hash = ('A' * 64) }
    }
    function New-LfcFactoryFinalizedRecord {
        param([object]$Intent)
        [pscustomobject]@{
            SchemaVersion = 4
            FactoryTransactionId = [string]$Intent.TransactionId
            OriginalLowFpsSolutionEnabled = $true
            OriginalHighFpsSolutionEnabled = $true
        }
    }
    function Write-LfcJsonFileAtomically {
        param([string]$LiteralPath, [object]$Value)
        if ($script:harness.FactoryFinalized) { throw 'DUPLICATE_FACTORY_PROVENANCE' }
        $script:harness.FactoryFinalized = $true
        $script:harness.FactoryTransactionId = [string]$Value.FactoryTransactionId
        Invoke-HarnessCrash -Point 'FACTORY_PROVENANCE_WRITTEN'
    }
    function Get-LfcFactoryFinalizedRecord {
        param([string]$ExpectedTransactionId)
        if (-not $script:harness.FactoryFinalized) { return $null }
        if ([string]$script:harness.FactoryTransactionId -ne $ExpectedTransactionId) {
            throw 'FACTORY_TRANSACTION_MISMATCH'
        }
        [pscustomobject]@{
            SchemaVersion = 4
            FactoryTransactionId = $ExpectedTransactionId
            OriginalLowFpsSolutionEnabled = $true
            OriginalHighFpsSolutionEnabled = $true
        }
    }
    function Assert-LfcFactoryFinalizedMatchesCurrentState {
        param([object]$Record)
        $now = Get-CurrentIntelVrrState
        if (-not $now.LowFpsSolutionEnabled -or -not $now.HighFpsSolutionEnabled) {
            throw 'FACTORY_PROVENANCE_STATE_MISMATCH'
        }
        return $now
    }
    function Remove-FileIfPresent {
        param([string]$LiteralPath)
        if ($LiteralPath -eq $lfcRestoreFinalizedPath) {
            $script:harness.RestoreFinalized = $false
            Invoke-HarnessCrash -Point 'SOURCE_PROVENANCE_RETIRED'
        }
        elseif ($LiteralPath -eq $lfcFactoryIntentPath) {
            $script:harness.Intent = $false
            Invoke-HarnessCrash -Point 'INTENT_RETIRED'
        }
    }

    $executed = 0
    foreach ($initial in $Pairs) {
        foreach ($sourceRestoreFinalized in @($false, $true)) {
            $crashPoints = [Collections.Generic.List[string]]::new()
            $crashPoints.Add('AFTER_INTENT')
            if (-not $initial.Low) { $crashPoints.Add('LOW_WRITTEN') }
            if (-not $initial.High) { $crashPoints.Add('HIGH_WRITTEN') }
            $crashPoints.Add('FACTORY_PROVENANCE_WRITTEN')
            if ($sourceRestoreFinalized) { $crashPoints.Add('SOURCE_PROVENANCE_RETIRED') }
            $crashPoints.Add('INTENT_RETIRED')

            foreach ($crashPoint in $crashPoints) {
                $transactionId = [Guid]::NewGuid().ToString('D')
                $script:harness = @{
                    Low = [bool]$initial.Low
                    High = [bool]$initial.High
                    Intent = $true
                    RestoreFinalized = [bool]$sourceRestoreFinalized
                    FactoryFinalized = $false
                    FactoryTransactionId = ''
                }
                $intent = [pscustomobject]@{
                    TransactionId = $transactionId
                    InitialLowFpsSolutionEnabled = [bool]$initial.Low
                    InitialHighFpsSolutionEnabled = [bool]$initial.High
                    SourceKind = if ($sourceRestoreFinalized) { 'RESTORE_FINALIZED' } else { 'CURRENT_STATE_NO_PROVENANCE' }
                    SourceRestoreFinalizedSha256 = if ($sourceRestoreFinalized) { 'A' * 64 } else { '' }
                }
                $script:harnessCrashPoint = $crashPoint
                $script:harnessCrashConsumed = $crashPoint -eq 'AFTER_INTENT'
                if ($crashPoint -ne 'AFTER_INTENT') {
                    try {
                        [void](Complete-LfcFactoryDefaultsTransaction -Intent $intent)
                        throw "The expected injected crash did not occur: $crashPoint"
                    }
                    catch {
                        if ([string]$_.Exception.Message -ne "INJECTED_CRASH_$crashPoint") { throw }
                    }
                }

                $script:harnessCrashPoint = ''
                if ($script:harness.Intent) {
                    [void](Complete-LfcFactoryDefaultsTransaction -Intent $intent)
                }
                Assert-Test ($script:harness.Low -and $script:harness.High) `
                    "Production recovery did not reach true/true after $crashPoint."
                Assert-Test ($script:harness.FactoryFinalized -and
                    -not $script:harness.RestoreFinalized -and -not $script:harness.Intent) `
                    "Production recovery left ambiguous artifacts after $crashPoint."
                $executed++
            }
        }
    }
    return $executed
} $intentStageFunction.Extent.Text $completeFunction.Extent.Text $initialPairs

foreach ($requiredMarker in @(
        "'factory-default-intent.json'",
        "'factory-finalized.json'",
        'Write-LfcJsonFileAtomically -LiteralPath $lfcFactoryIntentPath',
        'Write-LfcJsonFileAtomically -LiteralPath $lfcFactoryFinalizedPath',
        'Get-LfcFactoryIntentStage',
        'Assert-LfcFactoryFinalizedMatchesCurrentState',
        'INTEL_VRR_SOLUTIONS_FACTORY_DEFAULTS_PENDING_RESUME',
        'INTEL_VRR_SOLUTIONS_FACTORY_DEFAULTS_FINALIZATION_PENDING',
        'INTEL_VRR_SOLUTIONS_FACTORY_DEFAULTS_FINALIZED'
    )) {
    Assert-Test ($source.Contains($requiredMarker)) "Missing factory recovery contract: $requiredMarker"
}

$intentWrite = $source.IndexOf('Write-LfcJsonFileAtomically -LiteralPath $lfcFactoryIntentPath')
$transactionCall = $source.IndexOf('Complete-LfcFactoryDefaultsTransaction -Intent $factoryIntent')
$completeStart = $source.IndexOf('function Complete-LfcFactoryDefaultsTransaction')
$lowWrite = $source.IndexOf('Set-LowFpsSolution -Enabled $true', $completeStart)
$highWrite = $source.IndexOf('Set-HighFpsSolution -Enabled $true', $completeStart)
$factoryWrite = $source.IndexOf('Write-LfcJsonFileAtomically -LiteralPath $lfcFactoryFinalizedPath', $completeStart)
$sourceRetire = $source.IndexOf('Remove-FileIfPresent -LiteralPath $lfcRestoreFinalizedPath', $completeStart)
$intentRetire = $source.IndexOf('Remove-FileIfPresent -LiteralPath $lfcFactoryIntentPath', $completeStart)
Assert-Test ($intentWrite -ge 0 -and $intentWrite -lt $transactionCall) `
    'The factory WAL is not durable before the mutating transaction begins.'
Assert-Test ($lowWrite -gt $completeStart -and $highWrite -gt $lowWrite) `
    'Factory flags are not written in the declared low-then-high order.'
Assert-Test ($factoryWrite -gt $highWrite -and $sourceRetire -gt $factoryWrite -and $intentRetire -gt $sourceRetire) `
    'Durable factory provenance must precede source and WAL retirement.'
Assert-Test ($source.Contains('$sourcePath = $lfcFactoryFinalizedPath')) `
    'Future Apply does not adopt durable true/true factory provenance as its original baseline.'
Assert-Test ($source.Contains('OriginalLowFpsSolutionEnabled = $true') -and
    $source.Contains('OriginalHighFpsSolutionEnabled = $true')) `
    'The durable factory provenance does not encode the exact true/true baseline.'

[pscustomobject]@{
    Result = 'PASS'
    OriginalFlagPairs = $initialPairs.Count
    CrashRecoveryCases = $recoveryCases
    ProductionCrashInjectionCases = $actualRecoveryCases
    SafePrefixPolicy = 'INITIAL_OR_LOW_APPLIED_OR_TRUE_TRUE'
    DurableOrder = 'INTENT_THEN_FLAGS_THEN_FACTORY_PROVENANCE_THEN_CLEANUP'
    FutureApplyBaseline = 'TRUE_TRUE_FACTORY_FINALIZED'
}
