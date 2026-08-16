[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$identityModule = Join-Path $PSScriptRoot '..\Lfc-Backup-Identity.ps1'
if (-not (Test-Path -LiteralPath $identityModule -PathType Leaf)) {
    $identityModule = Join-Path $PSScriptRoot '..\scripts\Lfc-Backup-Identity.ps1'
}
. $identityModule

$common = @{
    PanelManufacturer = 'CSW'
    PanelProductCode = '0801'
    PanelName = 'PN8007QB1-2'
    PhysicalEdidSha256 = 'PHYSICAL'
    ValidatedEdidHashes = @('PHYSICAL', 'CUSTOM30')
    CurrentPanelInstanceName = 'DISPLAY\CSW0801\NEW_0'
    CurrentManagedMode = 'CLAWLAB_30_120'
}

$schema3 = [pscustomobject]@{
    SchemaVersion = 3
    PanelInstanceName = 'DISPLAY\CSW0801\OLD_0'
    PanelEdidSha256 = 'CUSTOM30'
    ManagedVrrMode = 'CLAWLAB_30_120'
    OriginalLowFpsSolutionEnabled = $true
    OriginalHighFpsSolutionEnabled = $true
}
$migrated = Resolve-ClawLabLfcBackupIdentity @common -Backup $schema3 -Action Restore
if (-not $migrated.Accepted -or -not $migrated.NeedsSchema4Migration -or -not $migrated.InstanceChanged -or
    $migrated.State -ne 'STABLE_EDID_MATCH_INSTANCE_CHANGED') {
    throw 'A schema 3 backup did not migrate safely across a monitor-instance change.'
}

$wrongEdid = $schema3.PSObject.Copy()
$wrongEdid.PanelEdidSha256 = 'UNKNOWN'
$rejectedEdid = Resolve-ClawLabLfcBackupIdentity @common -Backup $wrongEdid -Action Restore
if ($rejectedEdid.Accepted -or $rejectedEdid.State -ne 'EDID_IDENTITY_MISMATCH') {
    throw 'An unknown schema 3 EDID was not rejected.'
}

$schema4 = [pscustomobject]@{
    SchemaVersion = 4
    PanelManufacturer = 'CSW'
    PanelProductCode = '0801'
    PanelName = 'PN8007QB1-2'
    PhysicalEdidSha256 = 'PHYSICAL'
    PanelInstanceNameAtSave = 'DISPLAY\CSW0801\ORIGINAL_0'
    LastValidatedPanelInstanceName = 'DISPLAY\CSW0801\OLD_0'
    PanelEdidSha256AtSave = 'CUSTOM30'
    InstanceMigrationCount = 0
    ManagedVrrMode = 'CLAWLAB_30_120'
    OriginalLowFpsSolutionEnabled = $true
    OriginalHighFpsSolutionEnabled = $true
}
$refreshed = Resolve-ClawLabLfcBackupIdentity @common -Backup $schema4 -Action Apply
if (-not $refreshed.Accepted -or -not $refreshed.NeedsSchema4Migration -or
    $refreshed.State -ne 'STABLE_IDENTITY_VERIFIED_INSTANCE_REFRESH') {
    throw 'A schema 4 stable identity did not allow its volatile instance to refresh.'
}

$wrongPanel = $schema4.PSObject.Copy()
$wrongPanel.PhysicalEdidSha256 = 'OTHER_PANEL'
$rejectedPanel = Resolve-ClawLabLfcBackupIdentity @common -Backup $wrongPanel -Action Restore
if ($rejectedPanel.Accepted -or $rejectedPanel.State -ne 'STABLE_PANEL_IDENTITY_MISMATCH') {
    throw 'A mismatched schema 4 stable panel identity was not rejected.'
}

$schema2 = [pscustomobject]@{
    SchemaVersion = 2
    PanelInstanceName = 'DISPLAY\CSW0801\OLD_0'
    OriginalLowFpsSolutionEnabled = $true
    OriginalHighFpsSolutionEnabled = $true
}
$legacyRejected = Resolve-ClawLabLfcBackupIdentity @common -Backup $schema2 -Action Restore
if ($legacyRejected.Accepted -or $legacyRejected.State -ne 'LEGACY_INSTANCE_MISMATCH') {
    throw 'An unverifiable schema 2 instance change was not rejected.'
}

[pscustomobject]@{
    Result = 'PASS'
    Schema3InstanceMigration = $migrated.State
    UnknownEdidRejection = $rejectedEdid.State
    Schema4InstanceRefresh = $refreshed.State
    StableIdentityRejection = $rejectedPanel.State
    UnverifiableLegacyRejection = $legacyRejected.State
}
