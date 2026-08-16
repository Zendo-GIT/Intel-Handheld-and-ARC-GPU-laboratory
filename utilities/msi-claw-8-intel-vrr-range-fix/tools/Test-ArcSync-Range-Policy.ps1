[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot '..\ArcSync-Range-Policy.ps1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    $modulePath = Join-Path $PSScriptRoot '..\scripts\ArcSync-Range-Policy.ps1'
}
. $modulePath

function Assert-Equal {
    param(
        [Parameter(Mandatory)][object]$Actual,
        [Parameter(Mandatory)][object]$Expected,
        [Parameter(Mandatory)][string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message Expected '$Expected', got '$Actual'."
    }
}

$claw8 = 'CLAW_8_AI_PLUS'
$tmaPanel = 'CLAW_A1M_CLAW_7_AI_PLUS'
$physicalEdid = 'PHYSICAL_EDID'
$customEdid = 'CUSTOM_EDID'

Assert-Equal `
    (Get-ClawLabArcSyncMonitorRangeState -PanelKey $claw8 -MonitorMinimumHz 48 -MonitorMaximumHz 120) `
    'DECLARED_KNOWN_RANGE' 'The Claw 8 physical range was rejected.'
Assert-Equal `
    (Get-ClawLabArcSyncMonitorRangeState -PanelKey $claw8 -MonitorMinimumHz 30 -MonitorMaximumHz 120) `
    'DECLARED_KNOWN_RANGE' 'The Claw 8 custom range was rejected.'
Assert-Equal `
    (Get-ClawLabArcSyncMonitorRangeState -PanelKey $claw8 -MonitorMinimumHz 24 -MonitorMaximumHz 120) `
    'UNSUPPORTED' 'The A1M-only telemetry anomaly leaked into the Claw 8 policy.'
Assert-Equal `
    (Get-ClawLabArcSyncMonitorRangeState -PanelKey $tmaPanel -MonitorMinimumHz 24 -MonitorMaximumHz 120) `
    'INTEL_CONTROL_LIB_HALF_PHYSICAL_FLOOR' 'The collected TMA2027 telemetry anomaly was not recognized.'
Assert-Equal `
    (Get-ClawLabArcSyncMonitorRangeState -PanelKey $tmaPanel -MonitorMinimumHz 25 -MonitorMaximumHz 120) `
    'UNSUPPORTED' 'An uncollected TMA2027 monitor floor was accepted.'

Assert-Equal `
    (Test-ClawLabArcSyncMonitorRangeCompatible -PanelKey $tmaPanel `
        -MonitorMinimumHz 24 -MonitorMaximumHz 120 -ExpectedMinimumHz 30 -ExpectedMaximumHz 120) `
    $true 'TMA2027 did not accept its selected 30-120 profile independently of monitor telemetry.'
Assert-Equal `
    (Test-ClawLabArcSyncMonitorRangeCompatible -PanelKey $tmaPanel `
        -MonitorMinimumHz 24 -MonitorMaximumHz 120 -ExpectedMinimumHz 48 -ExpectedMaximumHz 120) `
    $true 'TMA2027 did not accept its selected 48-120 profile independently of monitor telemetry.'
Assert-Equal `
    (Test-ClawLabArcSyncMonitorRangeCompatible -PanelKey $tmaPanel `
        -MonitorMinimumHz 24 -MonitorMaximumHz 120 -ExpectedMinimumHz 24 -ExpectedMaximumHz 120) `
    $false 'The telemetry-only floor was incorrectly accepted as an installable profile.'
Assert-Equal `
    (Test-ClawLabArcSyncMonitorRangeCompatible -PanelKey $tmaPanel `
        -MonitorMinimumHz 24 -MonitorMaximumHz 120 -ExpectedMinimumHz 30 -ExpectedMaximumHz 144) `
    $true 'The A1M/Claw 7 AI+ telemetry exception rejected the guarded 30-144 profile.'

foreach ($maximum in @(144, 165, 180)) {
    foreach ($minimum in @(30, 48)) {
        Assert-Equal `
            (Test-ClawLabArcSyncMonitorRangeCompatible -PanelKey $tmaPanel `
                -MonitorMinimumHz 24 -MonitorMaximumHz 120 `
                -ExpectedMinimumHz $minimum -ExpectedMaximumHz $maximum) `
            $true "TMA2027 rejected guarded profile $minimum-$maximum."
    }
}

Assert-Equal `
    (Test-ClawLabDirectRangeReady -PanelKey $claw8 -DirectMinimumHz 30 -DirectMaximumHz 120 `
        -ExpectedMinimumHz 30 -ExpectedMaximumHz 120 `
        -ReportedEdidSha256 $customEdid -ExpectedEdidSha256 $customEdid) `
    $true 'An exact Claw 8 direct custom range was rejected.'
Assert-Equal `
    (Test-ClawLabDirectRangeReady -PanelKey $claw8 -DirectMinimumHz 48 -DirectMaximumHz 120 `
        -ExpectedMinimumHz 30 -ExpectedMaximumHz 120 `
        -ReportedEdidSha256 $customEdid -ExpectedEdidSha256 $customEdid) `
    $false 'The TMA2027 direct-range exception leaked into the Claw 8 policy.'
Assert-Equal `
    (Test-ClawLabDirectRangeReady -PanelKey $tmaPanel -DirectMinimumHz 48 -DirectMaximumHz 120 `
        -ExpectedMinimumHz 30 -ExpectedMaximumHz 120 `
        -ReportedEdidSha256 $customEdid -ExpectedEdidSha256 $customEdid) `
    $true 'The collected TMA2027 physical direct range was rejected for the loaded custom EDID.'
Assert-Equal `
    (Test-ClawLabDirectRangeReady -PanelKey $tmaPanel -DirectMinimumHz 48 -DirectMaximumHz 120 `
        -ExpectedMinimumHz 30 -ExpectedMaximumHz 120 `
        -ReportedEdidSha256 $physicalEdid -ExpectedEdidSha256 $customEdid) `
    $false 'A pending TMA2027 custom EDID was incorrectly treated as loaded.'
Assert-Equal `
    (Test-ClawLabDirectRangeReady -PanelKey $tmaPanel -DirectMinimumHz 24 -DirectMaximumHz 120 `
        -ExpectedMinimumHz 30 -ExpectedMaximumHz 120 `
        -ReportedEdidSha256 $customEdid -ExpectedEdidSha256 $customEdid) `
    $false 'The telemetry-only floor was incorrectly accepted from the direct Intel interface.'

$profiles = @(
    'OFFICIAL_48_120', 'CLAWLAB_30_120',
    'CLAWLAB_48_144', 'CLAWLAB_48_165', 'CLAWLAB_48_180',
    'CLAWLAB_30_144', 'CLAWLAB_30_165', 'CLAWLAB_30_180'
)
foreach ($panelKey in @($claw8, $tmaPanel)) {
    foreach ($current in $profiles) {
        foreach ($desired in $profiles) {
            $expected = $current -eq $desired
            Assert-Equal `
                (Test-ClawLabProfileTransitionAllowed -CurrentMode $current `
                    -CurrentState 'CONSISTENT' -DesiredMode $desired) `
                $expected "$panelKey profile-transition guard failed for $current -> $desired."
        }
    }
    foreach ($desired in $profiles) {
        Assert-Equal `
            (Test-ClawLabProfileTransitionAllowed -CurrentMode 'NONE' `
                -CurrentState 'CLEAN' -DesiredMode $desired) `
            $true "$panelKey clean-state install was refused for $desired."
        Assert-Equal `
            (Test-ClawLabProfileTransitionAllowed -CurrentMode 'LEGACY_MANAGED_STATE' `
                -CurrentState 'RESTORE_REQUIRED' -DesiredMode $desired) `
            $false "$panelKey restore-required state allowed $desired."
    }
}

[pscustomobject]@{
    Result = 'PASS'
    StableProfiles = '30-120, 48-120'
    GuardedExperimentalProfiles = '30/48 x 144/165/180'
    Tma2027TelemetryPolicy = 'INTEL_CONTROL_LIB_HALF_PHYSICAL_FLOOR'
    TelemetryFloorInstallable = $false
    Claw8RegressionGuard = 'PASS'
    PendingEdidGuard = 'PASS'
    ProfileSwitchMatrix = 'PASS'
}
