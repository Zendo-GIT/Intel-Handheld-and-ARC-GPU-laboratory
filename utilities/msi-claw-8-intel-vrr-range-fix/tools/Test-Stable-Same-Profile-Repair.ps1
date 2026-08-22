[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Test {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}

$root = Split-Path -Parent $PSScriptRoot
$runtimeRoot = if (Test-Path -LiteralPath (Join-Path $root 'scripts\MSI-Claw-VRR-Fix.ps1') -PathType Leaf) {
    Join-Path $root 'scripts'
}
else { $root }
$corePath = Join-Path $runtimeRoot 'MSI-Claw-VRR-Fix.ps1'
$coordinatorPath = Join-Path $runtimeRoot 'ClawLab-VRR-Transaction.ps1'
$policyPath = Join-Path $runtimeRoot 'ArcSync-Range-Policy.ps1'
$core = [IO.File]::ReadAllText($corePath)
$coordinator = [IO.File]::ReadAllText($coordinatorPath)
$policy = [IO.File]::ReadAllText($policyPath)

foreach ($action in @('Repair30', 'Repair48')) {
    Assert-Test -Condition ($core.Contains("'$action'")) `
        -Message "The private core action $action is missing."
}
Assert-Test -Condition $core.Contains('function Assert-StableSameModeRepairAllowed') `
    -Message 'The private repair entry point has no independent core-side verifier.'
foreach ($marker in @(
        "@('CLAWLAB_30_120', 'OFFICIAL_48_120')",
        "@('CONSISTENT', 'INCONSISTENT_RESTORE_REQUIRED')",
        'Get-OriginalProfile',
        'Get-ManagedModeRecord',
        '$experimentalTrialStatePath',
        '$experimentalTrialTaskName',
        "[string]`$lfc.ToolVersion -ne '2.0.7'",
        'LfcTransition.BackupPresent',
        'LfcBackupIdentity.Accepted',
        'RestoreTombstonePresent',
        'RestoreFinalizedPresent'
    )) {
    Assert-Test -Condition $core.Contains($marker) `
        -Message "The core same-profile repair proof is missing: $marker"
}

$normalTransitionStart = $policy.IndexOf('function Test-ClawLabProfileTransitionAllowed', [StringComparison]::Ordinal)
$repairPolicyStart = $policy.IndexOf('function Get-ClawLabStableProfileRepairDisposition', [StringComparison]::Ordinal)
Assert-Test -Condition ($normalTransitionStart -ge 0 -and $repairPolicyStart -gt $normalTransitionStart) `
    -Message 'Could not isolate the normal transition policy.'
$normalTransition = $policy.Substring($normalTransitionStart, $repairPolicyStart - $normalTransitionStart)
Assert-Test -Condition (-not $normalTransition.Contains('INCONSISTENT_RESTORE_REQUIRED')) `
    -Message 'The public profile-transition guard was incorrectly widened for repair.'

foreach ($marker in @(
        "if ([string]`$installDisposition.Disposition -eq 'REPAIRABLE_SAME_MODE')",
        "if (`$RequestedAction -eq 'Install30') { 'Repair30' } else { 'Repair48' }",
        '-CoreAction $vrrCoreAction'
    )) {
    Assert-Test -Condition $coordinator.Contains($marker) `
        -Message "The coordinator repair routing is missing: $marker"
}

foreach ($bat in @(Get-ChildItem -LiteralPath $root -Filter '*.bat' -File -Recurse)) {
    $text = [IO.File]::ReadAllText($bat.FullName)
    Assert-Test -Condition (-not $text.Contains('Repair30') -and -not $text.Contains('Repair48')) `
        -Message "A public BAT exposes a private repair action: $($bat.FullName)"
}

[pscustomobject]@{
    Test = 'Stable same-profile repair entry point'
    PublicTransitionGuardUnchanged = $true
    PrivateRepairActions = @('Repair30', 'Repair48')
    Result = 'PASS'
}
