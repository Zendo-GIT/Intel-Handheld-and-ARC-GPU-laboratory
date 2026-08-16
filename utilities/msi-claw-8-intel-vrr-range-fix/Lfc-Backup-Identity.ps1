Set-StrictMode -Version Latest

function Resolve-ClawLabLfcBackupIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Backup,
        [Parameter(Mandatory)][string]$PanelManufacturer,
        [Parameter(Mandatory)][string]$PanelProductCode,
        [Parameter(Mandatory)][string]$PanelName,
        [Parameter(Mandatory)][string]$PhysicalEdidSha256,
        [Parameter(Mandatory)][string[]]$ValidatedEdidHashes,
        [Parameter(Mandatory)][string]$CurrentPanelInstanceName,
        [Parameter(Mandatory)][string]$CurrentManagedMode,
        [Parameter(Mandatory)][ValidateSet('Apply', 'ApplyStartup', 'Restore')][string]$Action
    )

    foreach ($property in @('SchemaVersion', 'OriginalLowFpsSolutionEnabled')) {
        if ($property -notin $Backup.PSObject.Properties.Name) {
            return [pscustomobject]@{ Accepted = $false; State = 'INVALID_BACKUP'; Reason = "Missing $property."; NeedsSchema4Migration = $false; InstanceChanged = $false }
        }
    }

    $schema = [int]$Backup.SchemaVersion
    if ($schema -notin @(1, 2, 3, 4)) {
        return [pscustomobject]@{ Accepted = $false; State = 'UNSUPPORTED_SCHEMA'; Reason = "Unsupported schema $schema."; NeedsSchema4Migration = $false; InstanceChanged = $false }
    }

    if ($schema -in @(1, 2)) {
        if ('PanelInstanceName' -notin $Backup.PSObject.Properties.Name) {
            return [pscustomobject]@{ Accepted = $false; State = 'INVALID_LEGACY_BACKUP'; Reason = 'Missing PanelInstanceName.'; NeedsSchema4Migration = $false; InstanceChanged = $false }
        }
        $instanceChanged = [string]$Backup.PanelInstanceName -ne $CurrentPanelInstanceName
        if ($instanceChanged) {
            return [pscustomobject]@{
                Accepted = $false
                State = 'LEGACY_INSTANCE_MISMATCH'
                Reason = 'The schema 1/2 backup has no pinned EDID identity and cannot be migrated across a Windows monitor-instance change.'
                NeedsSchema4Migration = $false
                InstanceChanged = $true
            }
        }
        return [pscustomobject]@{
            Accepted = $true
            State = 'LEGACY_INSTANCE_VERIFIED'
            Reason = 'Legacy instance-bound backup accepted on its original Windows monitor instance.'
            NeedsSchema4Migration = $false
            InstanceChanged = $false
        }
    }

    foreach ($property in @('OriginalHighFpsSolutionEnabled', 'ManagedVrrMode')) {
        if ($property -notin $Backup.PSObject.Properties.Name) {
            return [pscustomobject]@{ Accepted = $false; State = 'INVALID_BACKUP'; Reason = "Missing $property."; NeedsSchema4Migration = $false; InstanceChanged = $false }
        }
    }
    if ($Action -in @('Apply', 'ApplyStartup') -and [string]$Backup.ManagedVrrMode -ne $CurrentManagedMode) {
        return [pscustomobject]@{
            Accepted = $false
            State = 'MANAGED_MODE_MISMATCH'
            Reason = "The backup belongs to $($Backup.ManagedVrrMode), not $CurrentManagedMode."
            NeedsSchema4Migration = $false
            InstanceChanged = $false
        }
    }

    if ($schema -eq 3) {
        if ('PanelInstanceName' -notin $Backup.PSObject.Properties.Name -or
            'PanelEdidSha256' -notin $Backup.PSObject.Properties.Name) {
            return [pscustomobject]@{ Accepted = $false; State = 'INVALID_SCHEMA3_BACKUP'; Reason = 'Missing schema 3 panel identity.'; NeedsSchema4Migration = $false; InstanceChanged = $false }
        }
        if ([string]$Backup.PanelEdidSha256 -notin $ValidatedEdidHashes) {
            return [pscustomobject]@{
                Accepted = $false
                State = 'EDID_IDENTITY_MISMATCH'
                Reason = 'The schema 3 backup EDID is not an exact approved state for the current validated panel.'
                NeedsSchema4Migration = $false
                InstanceChanged = $false
            }
        }
        $instanceChanged = [string]$Backup.PanelInstanceName -ne $CurrentPanelInstanceName
        return [pscustomobject]@{
            Accepted = $true
            State = if ($instanceChanged) { 'STABLE_EDID_MATCH_INSTANCE_CHANGED' } else { 'STABLE_EDID_MATCH' }
            Reason = 'The exact pinned EDID safely identifies the same panel definition.'
            NeedsSchema4Migration = $true
            InstanceChanged = $instanceChanged
        }
    }

    foreach ($property in @(
            'PanelManufacturer',
            'PanelProductCode',
            'PanelName',
            'PhysicalEdidSha256',
            'PanelInstanceNameAtSave',
            'LastValidatedPanelInstanceName',
            'PanelEdidSha256AtSave',
            'InstanceMigrationCount'
        )) {
        if ($property -notin $Backup.PSObject.Properties.Name) {
            return [pscustomobject]@{ Accepted = $false; State = 'INVALID_SCHEMA4_BACKUP'; Reason = "Missing $property."; NeedsSchema4Migration = $false; InstanceChanged = $false }
        }
    }
    $stableMatch = (
        [string]$Backup.PanelManufacturer -eq $PanelManufacturer -and
        [string]$Backup.PanelProductCode -eq $PanelProductCode -and
        [string]$Backup.PanelName -eq $PanelName -and
        [string]$Backup.PhysicalEdidSha256 -eq $PhysicalEdidSha256 -and
        [string]$Backup.PanelEdidSha256AtSave -in $ValidatedEdidHashes
    )
    if (-not $stableMatch) {
        return [pscustomobject]@{
            Accepted = $false
            State = 'STABLE_PANEL_IDENTITY_MISMATCH'
            Reason = 'The schema 4 stable panel identity does not match the current exact panel definition.'
            NeedsSchema4Migration = $false
            InstanceChanged = $false
        }
    }

    $schema4InstanceChanged = [string]$Backup.LastValidatedPanelInstanceName -ne $CurrentPanelInstanceName
    return [pscustomobject]@{
        Accepted = $true
        State = if ($schema4InstanceChanged) { 'STABLE_IDENTITY_VERIFIED_INSTANCE_REFRESH' } else { 'STABLE_IDENTITY_VERIFIED' }
        Reason = 'Stable panel identity and pinned EDID are verified.'
        NeedsSchema4Migration = $schema4InstanceChanged
        InstanceChanged = $schema4InstanceChanged
    }
}
