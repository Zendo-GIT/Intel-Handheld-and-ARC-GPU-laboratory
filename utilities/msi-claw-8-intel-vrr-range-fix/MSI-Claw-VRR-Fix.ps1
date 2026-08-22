[CmdletBinding()]
param(
    [ValidateSet(
        'Status', 'Install48', 'Install30', 'Repair48', 'Repair30',
        'Install48_144', 'Install48_165', 'Install48_180', 'Install48_192',
        'Install30_144', 'Install30_165', 'Install30_180', 'Install30_192',
        'ApplyExperimentalTrial', 'VerifyExperimentalTrial', 'ConfirmExperimentalTrial', 'SetSafe120ForTrial',
        'Restore', 'RestoreGuardedTrial', 'RecoverOrphanedDefaultState', 'FactoryReset', 'EmergencyRestoreEdid',
        'UpdateCursorRefresh', 'ApplyStartup'
    )]
    [string]$Action = 'Status',

    [ValidateSet('VrrTask', 'LfcTask')]
    [string]$StartupSource = 'VrrTask'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$fixVersion = '2.3.0'
$targetMinimumHz = 48.0
$experimentalMinimumHz = 30.0
$targetMaximumHz = 120.0
$experimentalMaximumHz = 144.0
$profileRecommended = 1
$profileExcellent = 2
$profileCustom = 7
$stateRoot = Join-Path $env:LOCALAPPDATA 'ClawLab\Intel-Arc-Sync-Full-Range'
$backupPath = Join-Path $stateRoot 'original-profile.json'
$normalizationCompensationPath = Join-Path $stateRoot 'normalization-compensation.json'
$experimentalStatePath = Join-Path $stateRoot 'experimental-edid.json'
$managedModeStatePath = Join-Path $stateRoot 'managed-mode.json'
$installedScriptPath = Join-Path $stateRoot 'MSI-Claw-VRR-Fix.ps1'
$edidNormalizationModuleName = 'Edid-Normalization.ps1'
$edidNormalizationModulePath = Join-Path $PSScriptRoot $edidNormalizationModuleName
$installedEdidNormalizationModulePath = Join-Path $stateRoot $edidNormalizationModuleName
$arcSyncRangePolicyModuleName = 'ArcSync-Range-Policy.ps1'
$arcSyncRangePolicyModulePath = Join-Path $PSScriptRoot $arcSyncRangePolicyModuleName
$installedArcSyncRangePolicyModulePath = Join-Path $stateRoot $arcSyncRangePolicyModuleName
$scheduledTaskPersistenceModuleName = 'Scheduled-Task-Persistence.ps1'
$scheduledTaskPersistenceModulePath = Join-Path $PSScriptRoot $scheduledTaskPersistenceModuleName
$installedScheduledTaskPersistenceModulePath = Join-Path $stateRoot $scheduledTaskPersistenceModuleName
$startupLauncherName = 'ClawLab-VRR-Startup.vbs'
$installedLauncherPath = Join-Path $stateRoot $startupLauncherName
$startupStatusPath = Join-Path $stateRoot 'startup-last-run.json'
$lastErrorPath = Join-Path $stateRoot 'last-error.txt'
$startupTaskName = 'ClawLab MSI Claw 8 VRR Range'
$lfcStartupTaskName = 'ClawLab MSI Claw Intel LFC Fix'
$lfcStateRoot = Join-Path $env:LOCALAPPDATA 'ClawLab\Intel-LFC-Fix'
$installedLfcToolPath = Join-Path $lfcStateRoot 'MSI-Claw-Intel-LFC-Fix.ps1'
$installedLfcDriverInterfacePath = Join-Path $lfcStateRoot 'Intel-VRR-LFC-Driver-Interface.ps1'
$installedLfcBackupIdentityPath = Join-Path $lfcStateRoot 'Lfc-Backup-Identity.ps1'
$installedLfcEdidNormalizationPath = Join-Path $lfcStateRoot 'Edid-Normalization.ps1'
$installedLfcArcSyncRangePolicyPath = Join-Path $lfcStateRoot 'ArcSync-Range-Policy.ps1'
$installedLfcScheduledTaskPersistencePath = Join-Path $lfcStateRoot 'Scheduled-Task-Persistence.ps1'
$installedLfcLauncherPath = Join-Path $lfcStateRoot 'ClawLab-LFC-Startup.vbs'
$cursorRefreshHelperName = 'ClawLab-Cursor-Refresh-Helper.exe'
$installedCursorRefreshHelperPath = Join-Path $stateRoot $cursorRefreshHelperName
$cursorRefreshHelperStatePath = Join-Path $stateRoot 'cursor-refresh-helper.json'
$cursorRefreshTaskName = 'ClawLab MSI Claw Cursor Refresh Engine'
$cursorRefreshReadyEventName = 'Local\ClawLab.MSIClaw.CursorRefresh.Ready'
$cursorRefreshResyncEventName = 'Local\ClawLab.MSIClaw.CursorRefresh.Resync'
$cursorRefreshShutdownEventName = 'Local\ClawLab.MSIClaw.CursorRefresh.Shutdown'
$cursorRefreshRuntimeStatePath = Join-Path $env:LOCALAPPDATA 'ClawLab\Cursor-Refresh-Helper\runtime-state.txt'
$experimentalTrialTaskName = 'ClawLab MSI Claw Experimental Overclock Trial'
$experimentalTrialStatePath = Join-Path $stateRoot 'experimental-overclock-trial.json'
$installedExperimentalTrialPath = Join-Path $stateRoot 'Experimental-Overclock-VRR-Trial.ps1'
$installedExperimentalTrialLauncherPath = Join-Path $stateRoot 'ClawLab-Experimental-Trial-Startup.vbs'
$intelStartupBackupPath = Join-Path $stateRoot 'intel-graphics-startup.json'
$intelStartupRegistryPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
$intelStartupValueName = 'Intel' + [char]0x00AE + ' Graphics Software'
$script:intelStartupIdentityRenewed = $false
$script:activePanelDefinition = $null
$script:activeEdidNormalization = 'NOT_READ'
$script:activeEdidSourceLength = 0
$displayTransactionMutexName = 'Global\ClawLab.VRR.DisplayTransaction'
$startupApplyMutexName = 'Global\ClawLab.MSIClaw.VrrApplyStartup'
$script:startupDisplayTransactionMutex = $null
$script:startupApplyMutex = $null
$script:intelGraphicsLaunchWarning = $null
$script:cursorRefreshLaunchWarning = $null
$script:normalizationCompensationContext = $null
$protectedRuntimeRoot = Join-Path $env:ProgramData 'ClawLab-VRR-Privileged\2.3.0'
$protectedRuntimePayloadNames = @(
    'MSI-Claw-VRR-Fix.ps1',
    'Edid-Normalization.ps1',
    'ArcSync-Range-Policy.ps1',
    'Scheduled-Task-Persistence.ps1',
    'ClawLab-Localization.ps1',
    'locales\messages.json',
    'ClawLab-VRR-Startup.vbs',
    'ClawLab-Cursor-Refresh-Helper.exe',
    'MSI-Claw-Intel-LFC-Fix.ps1',
    'Intel-VRR-LFC-Driver-Interface.ps1',
    'Lfc-Backup-Identity.ps1',
    'ClawLab-LFC-Startup.vbs',
    'Experimental-Overclock-VRR-Trial.ps1',
    'ClawLab-Experimental-Trial-Startup.vbs'
)
$protectedRuntimeFileNames = @($protectedRuntimePayloadNames) + @('protected-runtime.json')

function Assert-ProtectedRuntimeIntegrity {
    $scriptDirectory = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
    $expectedDirectory = [IO.Path]::GetFullPath($protectedRuntimeRoot).TrimEnd('\')
    if (-not $scriptDirectory.Equals($expectedDirectory, [StringComparison]::OrdinalIgnoreCase)) {
        return
    }

    $manifestPath = Join-Path $expectedDirectory 'protected-runtime.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw 'The protected experimental runtime manifest is missing.'
    }
    $manifest = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if ([int]$manifest.SchemaVersion -ne 1 -or [string]$manifest.FixVersion -ne $fixVersion) {
        throw 'The protected experimental runtime manifest has an invalid version.'
    }
    $entries = @($manifest.Files)
    if ($entries.Count -ne $protectedRuntimePayloadNames.Count) {
        throw 'The protected experimental runtime manifest has an unexpected file count.'
    }
    foreach ($fileName in $protectedRuntimePayloadNames) {
        $entry = @($entries | Where-Object { [string]$_.Name -ceq $fileName })
        if ($entry.Count -ne 1 -or [string]$entry[0].Sha256 -notmatch '^[A-F0-9]{64}$') {
            throw "The protected experimental runtime manifest is invalid for $fileName."
        }
        $filePath = Join-Path $expectedDirectory $fileName
        if (-not (Test-Path -LiteralPath $filePath -PathType Leaf) -or
            (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash -cne [string]$entry[0].Sha256) {
            throw "Protected experimental runtime integrity failed for $fileName."
        }
    }
}

Assert-ProtectedRuntimeIntegrity
foreach ($requiredModule in @(
        $edidNormalizationModulePath,
        $arcSyncRangePolicyModulePath,
        $scheduledTaskPersistenceModulePath
    )) {
    if (-not (Test-Path -LiteralPath $requiredModule -PathType Leaf)) {
        throw "A required VRR safety module is missing: $requiredModule"
    }
    . $requiredModule
}

$panelCatalog = @(
    [pscustomobject]@{
        Key = 'CLAW_8_AI_PLUS'
        Models = 'MSI Claw 8 AI+ / 8 EX AI+'
        Manufacturer = 'CSW'
        ProductCode = '0801'
        Name = 'PN8007QB1-2'
        Width = 1920
        Height = 1200
        EdidLength = 256
        RangeOffsets = @(
            [pscustomobject]@{ Minimum = 95; Maximum = 96 },
            [pscustomobject]@{ Minimum = 142; Maximum = 143 }
        )
        ChecksumStarts = @(0, 128)
        PhysicalEdidSha256 = 'E49BC570225510B7C889ED292570F1345CAA07F5840DB57EA6998A403DB5CEF0'
        Custom30EdidSha256 = '14CDDC390CF69367C4B6821A46728518200446A33F708A1A87CA673B68B66918'
        Custom30Block0Sha256 = '597D5A95C28171B7B9DF111C1BB12830532F63831EA38111E02D618850E76698'
        Custom30Block1Sha256 = 'C2000A5E8A3D91C80DCE75DC5BB2F63269C77501338FD059B4CF71CD0CE94743'
        Legacy48_144EdidSha256 = '4CFB165CE96119BA37A07176F9D346691D447E0A40E8697777E499E1556A744E'
        Legacy48_144Block0Sha256 = '65E46C6D528BF69D31D17BB88FD47A17C98576597508CC75D3AD047A029A7172'
        Legacy48_144Block1Sha256 = 'CA1A52F35378CB58709876EDD9BC648224D3C8AE0FA176E96A587BE8DABD8EB2'
        Legacy30_144EdidSha256 = '0B8E8A25325B4D9CAC2B6A03CF9B574688B1A6D2DEDF10401605C4898E0CAC05'
        Legacy30_144Block0Sha256 = '7773D16AFD7F0C9AE0363D1FDE684C12E20F460DB5815516EF76633F70FBF60D'
        Legacy30_144Block1Sha256 = '8AD37320E4C2FF8DF4E71E205241A152DA3136CB0BE25F54E7A78D6273317640'
        SupportsLegacy144Recovery = $true
        HighRefreshTimingKind = 'DISPLAYID_TYPE_VII'
        PhysicalSecondaryTiming = $null
        Overclock48_144EdidSha256 = '4CFB165CE96119BA37A07176F9D346691D447E0A40E8697777E499E1556A744E'
        Overclock48_144Block0Sha256 = '65E46C6D528BF69D31D17BB88FD47A17C98576597508CC75D3AD047A029A7172'
        Overclock48_144Block1Sha256 = 'CA1A52F35378CB58709876EDD9BC648224D3C8AE0FA176E96A587BE8DABD8EB2'
        Overclock48_165EdidSha256 = 'FBB2CEFA8A0CC36CD5231D1070D4271165CAB9EA43A22271E3B2FD49D6914677'
        Overclock48_165Block0Sha256 = '7009CE8788321E3FE0FAB1BF3789F70DA254048B36D14FDE0BC0A68BE1304788'
        Overclock48_165Block1Sha256 = 'FAF57667FF2039219CA70124764FB9FA53CC6E1003DDAC27F34860A85269CA10'
        Overclock48_180EdidSha256 = '279EA02FF5AEB3FA474235ECFCD3119AE7845A969C2F6BB7A63866CC3151EF62'
        Overclock48_180Block0Sha256 = '441D68C76B23063CDC879B6E119D2F7B43F7067B0F019A7C89D1BA6E94FF7080'
        Overclock48_180Block1Sha256 = '156506633F8D543C7BE72ADF35D2C4A0311A0156B4C21E0C6A913D4663F0ADD6'
        Overclock48_192EdidSha256 = 'DC60F9E3CC7B33C4F094181C57E4AF271C1BFB4449AFDE2614B4EAC27C032752'
        Overclock48_192Block0Sha256 = '1BFACB4E04EA4311DB37602B37993084B92224409D74F1E02B72FB60960780DA'
        Overclock48_192Block1Sha256 = 'D64A5FBADB951D28D0B48D798E90844192D91974F60331E95FBF7AEB8A90E93E'
        Overclock30_144EdidSha256 = '0B8E8A25325B4D9CAC2B6A03CF9B574688B1A6D2DEDF10401605C4898E0CAC05'
        Overclock30_144Block0Sha256 = '7773D16AFD7F0C9AE0363D1FDE684C12E20F460DB5815516EF76633F70FBF60D'
        Overclock30_144Block1Sha256 = '8AD37320E4C2FF8DF4E71E205241A152DA3136CB0BE25F54E7A78D6273317640'
        Overclock30_165EdidSha256 = '8EDC82A04D9E1FAD037CA4D794D53BD0D374C9554059B137E75C40D9F9C416A7'
        Overclock30_165Block0Sha256 = '61296485EF811F1DA0F38D35F3785C527FDCA71111618E9F1E325A1D287E4969'
        Overclock30_165Block1Sha256 = '2C6EF47AD7F7EB9A9E13401AC2C1ACE489CD3136CCEF7E335FDABE6781447675'
        Overclock30_180EdidSha256 = '0D1969CF0C7CFBA3CF9F077667C1427E202DB895DFA0A750FAF1323F57A88E4B'
        Overclock30_180Block0Sha256 = 'BBE14483FE647D0B2F525538820F753A36EB4F4FC5500BB8903CA34F0E7CF5BD'
        Overclock30_180Block1Sha256 = '0BBB9F4ABCFEF81A270FE926D2BE3AA9E7AA47FD3DB44673E9C75E57D1045292'
        Overclock30_192EdidSha256 = '949A7143DB4549FC7D0D36F9F2521A528C1C796DE8F3F1FA948E4B3DBF5ECED6'
        Overclock30_192Block0Sha256 = 'F2C2663185750971DDCB28E8398F4F39E42E97864F0D738069003C5A26F98B42'
        Overclock30_192Block1Sha256 = '10768276A262262FC0C99256AE0E2AFD23CFE6C2061A4FC90918AB758CA3FEFE'
    },
    [pscustomobject]@{
        Key = 'CLAW_A1M_CLAW_7_AI_PLUS'
        Models = 'MSI Claw A1M / Claw 7 AI+'
        Manufacturer = 'TMA'
        ProductCode = '2027'
        Name = 'TL070FVXS02-0'
        Width = 1920
        Height = 1080
        EdidLength = 128
        RangeOffsets = @(
            [pscustomobject]@{ Minimum = 95; Maximum = 96 }
        )
        ChecksumStarts = @(0)
        PhysicalEdidSha256 = '3518AB4456669D12A7B8D254F63005EAE143C784DCE02EC56C3753C41A664CA1'
        Custom30EdidSha256 = '7B5EE7D96BC91E83EBD2419B3A4F12771035D76303F77EEB0E356C996BFA4647'
        Custom30Block0Sha256 = '7B5EE7D96BC91E83EBD2419B3A4F12771035D76303F77EEB0E356C996BFA4647'
        Custom30Block1Sha256 = $null
        Legacy48_144EdidSha256 = $null
        Legacy48_144Block0Sha256 = $null
        Legacy48_144Block1Sha256 = $null
        Legacy30_144EdidSha256 = $null
        Legacy30_144Block0Sha256 = $null
        Legacy30_144Block1Sha256 = $null
        SupportsLegacy144Recovery = $false
        HighRefreshTimingKind = 'BASE_DTD_SECOND_SLOT'
        PhysicalSecondaryTiming = [byte[]]@(
            0xC6, 0x37, 0x80, 0xA0, 0x70, 0x38, 0x40, 0x40, 0x30,
            0x20, 0x62, 0x0C, 0x9B, 0x57, 0x00, 0x00, 0x00, 0x1A
        )
        Overclock48_144EdidSha256 = 'AF1F6DEB144767F089522C37B89C1171DE59D06107B5F5073877A5693EBC9ADB'
        Overclock48_144Block0Sha256 = 'AF1F6DEB144767F089522C37B89C1171DE59D06107B5F5073877A5693EBC9ADB'
        Overclock48_144Block1Sha256 = $null
        Overclock48_165EdidSha256 = '89B0BDD6ACEB5A2320F235864314CC33CD67E4F3E4107E21573D506594E902D2'
        Overclock48_165Block0Sha256 = '89B0BDD6ACEB5A2320F235864314CC33CD67E4F3E4107E21573D506594E902D2'
        Overclock48_165Block1Sha256 = $null
        Overclock48_180EdidSha256 = '0AA3BFD4DA2D6EB8D36BBA9F87CD476D453AD86651348CC3D17E8314BD3C898D'
        Overclock48_180Block0Sha256 = '0AA3BFD4DA2D6EB8D36BBA9F87CD476D453AD86651348CC3D17E8314BD3C898D'
        Overclock48_180Block1Sha256 = $null
        Overclock48_192EdidSha256 = '4FA15135645E89BF10DA6B007921BA6702E03951C8FB9D2E2576F2837AD02BDE'
        Overclock48_192Block0Sha256 = '4FA15135645E89BF10DA6B007921BA6702E03951C8FB9D2E2576F2837AD02BDE'
        Overclock48_192Block1Sha256 = $null
        Overclock30_144EdidSha256 = 'DFD9CBDDB7C0B8A711F026C43E3EB73165958F2E129857B97EB7EB008CB71B5E'
        Overclock30_144Block0Sha256 = 'DFD9CBDDB7C0B8A711F026C43E3EB73165958F2E129857B97EB7EB008CB71B5E'
        Overclock30_144Block1Sha256 = $null
        Overclock30_165EdidSha256 = 'C0147C505E16907C62E66B56A3436870B591E1CB7B2FBA6CA410EEE3BEBDDC51'
        Overclock30_165Block0Sha256 = 'C0147C505E16907C62E66B56A3436870B591E1CB7B2FBA6CA410EEE3BEBDDC51'
        Overclock30_165Block1Sha256 = $null
        Overclock30_180EdidSha256 = 'CE853C0CB689CC6247E72E59C7965FEDCAE49479BCFD04EE7959FA3113A9D679'
        Overclock30_180Block0Sha256 = 'CE853C0CB689CC6247E72E59C7965FEDCAE49479BCFD04EE7959FA3113A9D679'
        Overclock30_180Block1Sha256 = $null
        Overclock30_192EdidSha256 = '6553A5DA6651D29D447F0E0D14EC80CA631B1178544DA60E1CC2D54C4FAFB4C9'
        Overclock30_192Block0Sha256 = '6553A5DA6651D29D447F0E0D14EC80CA631B1178544DA60E1CC2D54C4FAFB4C9'
        Overclock30_192Block1Sha256 = $null
    }
)

$experimentalOverclockModes = @{
    'CLAWLAB_48_144' = [pscustomobject]@{ MinimumHz = 48; MaximumHz = 144; Stability = 'STABLE_EXPERIMENTAL' }
    'CLAWLAB_48_165' = [pscustomobject]@{ MinimumHz = 48; MaximumHz = 165; Stability = 'UNSTABLE_EXPERIMENTAL' }
    'CLAWLAB_48_180' = [pscustomobject]@{ MinimumHz = 48; MaximumHz = 180; Stability = 'UNSTABLE_EXPERIMENTAL' }
    'CLAWLAB_48_192' = [pscustomobject]@{ MinimumHz = 48; MaximumHz = 192; Stability = 'UNSTABLE_EXPERIMENTAL' }
    'CLAWLAB_30_144' = [pscustomobject]@{ MinimumHz = 30; MaximumHz = 144; Stability = 'UNSTABLE_EXPERIMENTAL' }
    'CLAWLAB_30_165' = [pscustomobject]@{ MinimumHz = 30; MaximumHz = 165; Stability = 'UNSTABLE_EXPERIMENTAL' }
    'CLAWLAB_30_180' = [pscustomobject]@{ MinimumHz = 30; MaximumHz = 180; Stability = 'UNSTABLE_EXPERIMENTAL' }
    'CLAWLAB_30_192' = [pscustomobject]@{ MinimumHz = 30; MaximumHz = 192; Stability = 'UNSTABLE_EXPERIMENTAL' }
}
$managedModeNames = @('OFFICIAL_48_120', 'CLAWLAB_30_120') + @($experimentalOverclockModes.Keys)

function Test-IsExperimentalOverclockMode {
    param([Parameter(Mandatory)][string]$Mode)

    return $experimentalOverclockModes.ContainsKey($Mode)
}

function Get-ExperimentalOverclockMode {
    param([Parameter(Mandatory)][string]$Mode)

    if (-not (Test-IsExperimentalOverclockMode -Mode $Mode)) {
        throw "Unknown experimental overclock mode: $Mode"
    }
    return $experimentalOverclockModes[$Mode]
}

function Convert-WmiText {
    param([AllowNull()][object]$Values)

    if ($null -eq $Values) {
        return ''
    }
    return (-join @($Values | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }))
}

function Remove-FileIfPresent {
    param([Parameter(Mandatory)][string]$LiteralPath)

    if (Test-Path -LiteralPath $LiteralPath -PathType Leaf) {
        [IO.File]::Delete($LiteralPath)
    }
}

function Write-ClawLabJsonAtomically {
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)][object]$Value
    )

    $directory = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($LiteralPath))
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $temporaryPath = Join-Path $directory ('.clawlab-json-{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
    $rollbackPath = Join-Path $directory ('.clawlab-json-previous-{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText(
            $temporaryPath,
            ($Value | ConvertTo-Json -Depth 8),
            [Text.UTF8Encoding]::new($false)
        )
        if (Test-Path -LiteralPath $LiteralPath -PathType Leaf) {
            [IO.File]::Replace($temporaryPath, $LiteralPath, $rollbackPath, $true)
        }
        else {
            [IO.File]::Move($temporaryPath, $LiteralPath)
        }
    }
    finally {
        Remove-FileIfPresent -LiteralPath $temporaryPath
        Remove-FileIfPresent -LiteralPath $rollbackPath
    }
}

function Remove-ProtectedExperimentalRuntime {
    $programDataRoot = [IO.Path]::GetFullPath($env:ProgramData).TrimEnd('\')
    $runtimeRoot = [IO.Path]::GetFullPath($protectedRuntimeRoot).TrimEnd('\')
    if (-not $runtimeRoot.StartsWith(
            $programDataRoot + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe protected runtime path: $runtimeRoot"
    }
    $parentRoot = [IO.Path]::GetDirectoryName($runtimeRoot)
    if (Test-Path -LiteralPath $parentRoot -PathType Container) {
        $parentItem = Get-Item -LiteralPath $parentRoot -Force
        if (($parentItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to clean through a protected runtime parent reparse point: $parentRoot"
        }
    }
    if (-not (Test-Path -LiteralPath $runtimeRoot -PathType Container)) {
        return
    }
    $runtimeItem = Get-Item -LiteralPath $runtimeRoot -Force
    if (($runtimeItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to clean a protected runtime reparse point: $runtimeRoot"
    }
    foreach ($fileName in $protectedRuntimeFileNames) {
        Remove-FileIfPresent -LiteralPath (Join-Path $runtimeRoot $fileName)
    }
    $localesRoot = Join-Path $runtimeRoot 'locales'
    if (Test-Path -LiteralPath $localesRoot -PathType Container) {
        $localesItem = Get-Item -LiteralPath $localesRoot -Force
        if (($localesItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to clean a protected locales reparse point: $localesRoot"
        }
        if (@([IO.Directory]::EnumerateFileSystemEntries($localesRoot)).Count -eq 0) {
            [IO.Directory]::Delete($localesRoot, $false)
        }
    }
    if (@([IO.Directory]::EnumerateFileSystemEntries($runtimeRoot)).Count -eq 0) {
        [IO.Directory]::Delete($runtimeRoot, $false)
    }
}

function Enter-StartupApplyMutex {
    $mutex = [Threading.Mutex]::new($false, $startupApplyMutexName)
    $acquired = $false
    try {
        try {
            $acquired = $mutex.WaitOne(180000)
        }
        catch [Threading.AbandonedMutexException] {
            # The previous process ended unexpectedly. Windows grants this
            # caller ownership, so startup recovery may continue safely.
            $acquired = $true
        }
        if (-not $acquired) {
            throw 'Another ClawLab VRR startup reapply did not finish within three minutes.'
        }
        $script:startupApplyMutex = $mutex
    }
    catch {
        if (-not $acquired) {
            $mutex.Dispose()
        }
        throw
    }
}

function Enter-StartupDisplayTransactionMutex {
    $mutex = [Threading.Mutex]::new($false, $displayTransactionMutexName)
    $acquired = $false
    try {
        try {
            $acquired = $mutex.WaitOne(180000)
        }
        catch [Threading.AbandonedMutexException] {
            $acquired = $true
        }
        if (-not $acquired) {
            throw 'Another ClawLab display transaction did not finish within three minutes.'
        }
        $script:startupDisplayTransactionMutex = $mutex
    }
    catch {
        if (-not $acquired) {
            $mutex.Dispose()
        }
        throw
    }
}

function Exit-StartupDisplayTransactionMutex {
    if ($null -eq $script:startupDisplayTransactionMutex) {
        return
    }
    try {
        $script:startupDisplayTransactionMutex.ReleaseMutex()
    }
    finally {
        $script:startupDisplayTransactionMutex.Dispose()
        $script:startupDisplayTransactionMutex = $null
    }
}

function Enter-StartupTransactionLocks {
    param([Parameter(Mandatory)][ValidateSet('VrrTask', 'LfcTask')][string]$Source)

    # The LFC orchestrator already owns DisplayTransaction in its parent
    # process. Its VRR child must only take the second lock. A direct VRR-task
    # fallback owns both locks in the same machine-wide order as installers,
    # recovery and guarded overclock trials.
    if ($Source -eq 'VrrTask') {
        Enter-StartupDisplayTransactionMutex
    }
    try {
        Enter-StartupApplyMutex
    }
    catch {
        if ($Source -eq 'VrrTask') {
            Exit-StartupDisplayTransactionMutex
        }
        throw
    }
}

function Exit-StartupTransactionLocks {
    Exit-StartupApplyMutex
    Exit-StartupDisplayTransactionMutex
}

function Exit-StartupApplyMutex {
    if ($null -eq $script:startupApplyMutex) {
        return
    }
    try {
        $script:startupApplyMutex.ReleaseMutex()
    }
    finally {
        $script:startupApplyMutex.Dispose()
        $script:startupApplyMutex = $null
    }
}

function Get-ValidatedPanel {
    $matches = [Collections.Generic.List[object]]::new()
    foreach ($monitor in @(Get-CimInstance -Namespace 'root\wmi' -ClassName 'WmiMonitorID' -ErrorAction Stop)) {
        $manufacturer = Convert-WmiText -Values $monitor.ManufacturerName
        $productCode = Convert-WmiText -Values $monitor.ProductCodeID
        $name = Convert-WmiText -Values $monitor.UserFriendlyName
        $definitions = @($panelCatalog | Where-Object {
                $_.Manufacturer -eq $manufacturer -and
                $_.ProductCode -eq $productCode -and
                $_.Name -eq $name
            })
        foreach ($definition in $definitions) {
            $matches.Add([pscustomobject]@{
                    InstanceName = [string]$monitor.InstanceName
                    Manufacturer = $manufacturer
                    ProductCode = $productCode
                    Name = $name
                    Definition = $definition
                })
        }
    }

    if ($matches.Count -ne 1) {
        $supported = ($panelCatalog | ForEach-Object { "$($_.Manufacturer)$($_.ProductCode) / $($_.Name)" }) -join '; '
        throw "A supported internal panel was not found exactly once. Expected one of: $supported. No display setting was changed."
    }
    $script:activePanelDefinition = $matches[0].Definition
    return $matches[0]
}

function Get-IntelGpu {
    $gpus = @(
        Get-CimInstance -ClassName 'Win32_VideoController' -ErrorAction Stop |
            Where-Object { $_.PNPDeviceID -like 'PCI\VEN_8086&*' }
    )
    if ($gpus.Count -lt 1) {
        throw 'No Intel graphics adapter was found. No display setting was changed.'
    }
    return $gpus[0]
}

function Get-ByteArraySha256 {
    param([Parameter(Mandatory)][byte[]]$Bytes)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
}

function Get-FileSha256 {
    param([Parameter(Mandatory)][string]$LiteralPath)

    $stream = [IO.File]::OpenRead($LiteralPath)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '')
    }
    finally {
        $sha.Dispose()
        $stream.Dispose()
    }
}

function Test-ByteArrayEqual {
    param(
        [AllowNull()][byte[]]$Left,
        [AllowNull()][byte[]]$Right
    )

    if ($null -eq $Left -and $null -eq $Right) {
        return $true
    }
    if ($null -eq $Left -or $null -eq $Right -or $Left.Length -ne $Right.Length) {
        return $false
    }
    for ($index = 0; $index -lt $Left.Length; $index++) {
        if ($Left[$index] -ne $Right[$index]) {
            return $false
        }
    }
    return $true
}

function Get-KnownOverrideHashes {
    param([Parameter(Mandatory)][string]$EdidSha256)

    foreach ($definition in $panelCatalog) {
        foreach ($candidate in @(
                [pscustomobject]@{ Edid = $definition.Custom30EdidSha256; Block0 = $definition.Custom30Block0Sha256; Block1 = $definition.Custom30Block1Sha256 },
                [pscustomobject]@{ Edid = $definition.Legacy48_144EdidSha256; Block0 = $definition.Legacy48_144Block0Sha256; Block1 = $definition.Legacy48_144Block1Sha256 },
                [pscustomobject]@{ Edid = $definition.Legacy30_144EdidSha256; Block0 = $definition.Legacy30_144Block0Sha256; Block1 = $definition.Legacy30_144Block1Sha256 },
                [pscustomobject]@{ Edid = $definition.Overclock48_144EdidSha256; Block0 = $definition.Overclock48_144Block0Sha256; Block1 = $definition.Overclock48_144Block1Sha256 },
                [pscustomobject]@{ Edid = $definition.Overclock48_165EdidSha256; Block0 = $definition.Overclock48_165Block0Sha256; Block1 = $definition.Overclock48_165Block1Sha256 },
                [pscustomobject]@{ Edid = $definition.Overclock48_180EdidSha256; Block0 = $definition.Overclock48_180Block0Sha256; Block1 = $definition.Overclock48_180Block1Sha256 },
                [pscustomobject]@{ Edid = $definition.Overclock48_192EdidSha256; Block0 = $definition.Overclock48_192Block0Sha256; Block1 = $definition.Overclock48_192Block1Sha256 },
                [pscustomobject]@{ Edid = $definition.Overclock30_144EdidSha256; Block0 = $definition.Overclock30_144Block0Sha256; Block1 = $definition.Overclock30_144Block1Sha256 },
                [pscustomobject]@{ Edid = $definition.Overclock30_165EdidSha256; Block0 = $definition.Overclock30_165Block0Sha256; Block1 = $definition.Overclock30_165Block1Sha256 },
                [pscustomobject]@{ Edid = $definition.Overclock30_180EdidSha256; Block0 = $definition.Overclock30_180Block0Sha256; Block1 = $definition.Overclock30_180Block1Sha256 },
                [pscustomobject]@{ Edid = $definition.Overclock30_192EdidSha256; Block0 = $definition.Overclock30_192Block0Sha256; Block1 = $definition.Overclock30_192Block1Sha256 }
            )) {
            if (-not [string]::IsNullOrWhiteSpace([string]$candidate.Edid) -and $EdidSha256 -eq $candidate.Edid) {
                return [pscustomobject]@{
                    Block0 = $candidate.Block0
                    Block1 = $candidate.Block1
                    Definition = $definition
                }
            }
        }
    }
    throw "Unknown ClawLab custom EDID hash: $EdidSha256"
}

function Get-ThirdPartyEdidOverrideValueNames {
    param([Parameter(Mandatory)][string]$OverridePath)

    if (-not (Test-Path -LiteralPath $OverridePath -PathType Container)) {
        return @()
    }

    $overrideKey = Get-Item -LiteralPath $OverridePath -ErrorAction Stop
    return @(
        $overrideKey.GetValueNames() |
            Where-Object { [string]$_ -notin @('0', '1') } |
            Sort-Object -Unique
    )
}

function Assert-NoThirdPartyEdidOverrideValues {
    param([Parameter(Mandatory)][object]$RegistryContext)

    $valueNames = @($RegistryContext.ThirdPartyOverrideValueNames)
    if ($valueNames.Count -eq 0) {
        return
    }

    $listedNames = $valueNames -join ', '
    throw "Third-party EDID override metadata is still installed: $listedNames. If CRU was ever used, run reset-all.exe from the current official CRU release and restart Windows before retrying. ClawLab will not modify, adopt or overwrite this third-party state."
}

function Get-PanelRegistryContext {
    param([Parameter(Mandatory)][object]$Panel)

    $definition = $Panel.Definition
    $instanceId = $Panel.InstanceName -replace '_\d+$', ''
    $expectedInstancePattern = "DISPLAY\$($definition.Manufacturer)$($definition.ProductCode)\*"
    if ($instanceId -notlike $expectedInstancePattern) {
        throw "Unexpected validated-panel instance ID: $instanceId"
    }

    $deviceParameters = "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\$instanceId\Device Parameters"
    if (-not (Test-Path -LiteralPath $deviceParameters -PathType Container)) {
        throw 'The validated panel registry key is missing.'
    }

    $overridePath = Join-Path $deviceParameters 'EDID_OVERRIDE'
    $thirdPartyOverrideValueNames = @(Get-ThirdPartyEdidOverrideValueNames -OverridePath $overridePath)
    $rawReportedEdid = [byte[]](Get-ItemPropertyValue -LiteralPath $deviceParameters -Name 'EDID' -ErrorAction Stop)
    $canonicalEdid = Get-ClawLabCanonicalEdid -Bytes $rawReportedEdid -ExpectedLength ([int]$definition.EdidLength)
    $reportedEdid = [byte[]]$canonicalEdid.Bytes
    $script:activeEdidNormalization = [string]$canonicalEdid.State
    $script:activeEdidSourceLength = [int]$canonicalEdid.SourceLength

    # After the Intel display device reloads an override, Windows can expose the
    # exact overridden EDID through the EDID value itself. Reconstruct the
    # validated physical baseline only from an exact, pinned ClawLab hash. No
    # arbitrary EDID is accepted or normalized.
    $reportedHash = Get-ByteArraySha256 -Bytes $reportedEdid
    $physicalEdid = [byte[]]$reportedEdid.Clone()
    if ($reportedHash -ne [string]$definition.PhysicalEdidSha256) {
        $knownCompleteOverride = $reportedHash -in @(
                $definition.Custom30EdidSha256,
                $definition.Legacy48_144EdidSha256,
                $definition.Legacy30_144EdidSha256,
                $definition.Overclock48_144EdidSha256,
                $definition.Overclock48_165EdidSha256,
                $definition.Overclock48_180EdidSha256,
                $definition.Overclock48_192EdidSha256,
                $definition.Overclock30_144EdidSha256,
                $definition.Overclock30_165EdidSha256,
                $definition.Overclock30_180EdidSha256,
                $definition.Overclock30_192EdidSha256
            )
        $recoverableClawLabBlocks = $false
        if (-not $knownCompleteOverride -and $Action -eq 'FactoryReset') {
            $overridePath = Join-Path $deviceParameters 'EDID_OVERRIDE'
            if (Test-Path -LiteralPath $overridePath -PathType Container) {
                $block0 = $null
                $block1 = $null
                try { $block0 = [byte[]](Get-ItemPropertyValue -LiteralPath $overridePath -Name '0' -ErrorAction Stop) } catch {}
                try { $block1 = [byte[]](Get-ItemPropertyValue -LiteralPath $overridePath -Name '1' -ErrorAction Stop) } catch {}
                $knownBlock0 = $null -eq $block0 -or
                    (Get-ByteArraySha256 -Bytes $block0) -in @(
                        $definition.Custom30Block0Sha256,
                        $definition.Legacy48_144Block0Sha256,
                        $definition.Legacy30_144Block0Sha256,
                        $definition.Overclock48_144Block0Sha256,
                        $definition.Overclock48_165Block0Sha256,
                        $definition.Overclock48_180Block0Sha256,
                        $definition.Overclock48_192Block0Sha256,
                        $definition.Overclock30_144Block0Sha256,
                        $definition.Overclock30_165Block0Sha256,
                        $definition.Overclock30_180Block0Sha256,
                        $definition.Overclock30_192Block0Sha256
                    )
                $knownBlock1 = $null -eq $block1 -or
                    (Get-ByteArraySha256 -Bytes $block1) -in @(
                        $definition.Custom30Block1Sha256,
                        $definition.Legacy48_144Block1Sha256,
                        $definition.Legacy30_144Block1Sha256,
                        $definition.Overclock48_144Block1Sha256,
                        $definition.Overclock48_165Block1Sha256,
                        $definition.Overclock48_180Block1Sha256,
                        $definition.Overclock48_192Block1Sha256,
                        $definition.Overclock30_144Block1Sha256,
                        $definition.Overclock30_165Block1Sha256,
                        $definition.Overclock30_180Block1Sha256,
                        $definition.Overclock30_192Block1Sha256
                    )
                $recoverableClawLabBlocks = ($null -ne $block0 -or $null -ne $block1) -and $knownBlock0 -and $knownBlock1
            }
        }
        if (-not $knownCompleteOverride -and -not $recoverableClawLabBlocks) {
            if ($thirdPartyOverrideValueNames.Count -gt 0) {
                $listedNames = $thirdPartyOverrideValueNames -join ', '
                throw "Unsupported active EDID $reportedHash with third-party override metadata: $listedNames. If CRU was ever used, run reset-all.exe from the current official CRU release and restart Windows. ClawLab refused to trust or overwrite this state."
            }
            throw "Unsupported panel EDID: $reportedHash. Custom modes are restricted to the validated EDID."
        }

        foreach ($range in $definition.RangeOffsets) {
            $physicalEdid[[int]$range.Minimum] = [byte]$targetMinimumHz
            $physicalEdid[[int]$range.Maximum] = [byte]$targetMaximumHz
        }
        if ([string]$definition.HighRefreshTimingKind -eq 'DISPLAYID_TYPE_VII') {
            foreach ($offset in 156..178) { $physicalEdid[$offset] = 0 }
        }
        elseif ([string]$definition.HighRefreshTimingKind -eq 'BASE_DTD_SECOND_SLOT') {
            [Array]::Copy([byte[]]$definition.PhysicalSecondaryTiming, 0, $physicalEdid, 72, 18)
            $physicalEdid[98] = 140
            $physicalEdid[99] = 29
        }
        foreach ($checksumStart in $definition.ChecksumStarts) {
            Set-EdidChecksum -Edid $physicalEdid -Start ([int]$checksumStart)
        }
        if ((Get-ByteArraySha256 -Bytes $physicalEdid) -ne [string]$definition.PhysicalEdidSha256) {
            throw 'The known custom EDID could not be reduced to the validated physical baseline.'
        }
    }

    [pscustomobject]@{
        InstanceId = $instanceId
        DeviceParametersPath = $deviceParameters
        OverridePath = $overridePath
        ThirdPartyOverrideValueNames = @($thirdPartyOverrideValueNames)
        PhysicalEdid = $physicalEdid
        PhysicalEdidSha256 = [string]$definition.PhysicalEdidSha256
        ReportedEdidSha256 = $reportedHash
        ReportedEdidSourceLength = [int]$canonicalEdid.SourceLength
        ReportedEdidNormalization = [string]$canonicalEdid.State
        Definition = $definition
    }
}

function Set-EdidChecksum {
    param(
        [Parameter(Mandatory)][byte[]]$Edid,
        [Parameter(Mandatory)][int]$Start
    )

    $sum = 0
    for ($offset = $Start; $offset -lt ($Start + 127); $offset++) {
        $sum += $Edid[$offset]
    }
    $Edid[$Start + 127] = [byte]((256 - ($sum % 256)) % 256)
}

function New-ExperimentalEdidVariant {
    param(
        [Parameter(Mandatory)][byte[]]$PhysicalEdid,
        [Parameter(Mandatory)][object]$Definition,
        [Parameter(Mandatory)][string]$State,
        [Parameter(Mandatory)][float]$MinimumHz,
        [Parameter(Mandatory)][float]$MaximumHz,
        [Parameter(Mandatory)][string]$ExpectedEdidSha256,
        [Parameter(Mandatory)][string]$ExpectedBlock0Sha256,
        [AllowNull()][string]$ExpectedBlock1Sha256,
        [int]$ExperimentalTimingHz = 0
    )

    $physicalHash = Get-ByteArraySha256 -Bytes $PhysicalEdid
    if ($physicalHash -ne [string]$Definition.PhysicalEdidSha256) {
        throw "Unsupported panel EDID: $physicalHash. Custom modes are restricted to the validated EDID."
    }
    foreach ($range in $Definition.RangeOffsets) {
        if ($PhysicalEdid[[int]$range.Minimum] -ne 48 -or
            $PhysicalEdid[[int]$range.Maximum] -ne 120) {
            throw 'The validated EDID no longer contains the expected 48-120 Hz range fields.'
        }
    }

    foreach ($start in $Definition.ChecksumStarts) {
        $sum = 0
        for ($offset = [int]$start; $offset -lt ([int]$start + 128); $offset++) {
            $sum += $PhysicalEdid[$offset]
        }
        if (($sum % 256) -ne 0) {
            throw "The physical EDID block at offset $start has an invalid checksum."
        }
    }

    $modified = [byte[]]$PhysicalEdid.Clone()
    foreach ($range in $Definition.RangeOffsets) {
        $modified[[int]$range.Minimum] = [byte]$MinimumHz
        $modified[[int]$range.Maximum] = [byte]$MaximumHz
    }

    if ($ExperimentalTimingHz -ne 0) {
        if ($ExperimentalTimingHz -notin @(144, 165, 180, 192) -or
            [Math]::Abs($MaximumHz - $ExperimentalTimingHz) -gt 0.1 -or
            ([Math]::Abs($MinimumHz - $targetMinimumHz) -gt 0.1 -and
                [Math]::Abs($MinimumHz - $experimentalMinimumHz) -gt 0.1)) {
            throw "Unsupported experimental timing request: $MinimumHz-$MaximumHz Hz."
        }

        switch ([string]$Definition.HighRefreshTimingKind) {
            'DISPLAYID_TYPE_VII' {
                if ($PhysicalEdid.Length -ne 256) {
                    throw 'The validated DisplayID overclock panel no longer has a 256-byte EDID.'
                }
                foreach ($offset in 156..178) {
                    if ($PhysicalEdid[$offset] -ne 0) {
                        throw 'The validated DisplayID extension no longer has the empty detailed-timing slot.'
                    }
                }

                # DisplayID 2.0 Type VII detailed timing. The 2080x1264 totals
                # are inherited from the validated native panel timing. The
                # one-kHz conservative bias preserves the previously field-
                # tested 144 Hz timing byte-for-byte.
                $pixelClockKHz = [uint32]([Math]::Floor((2080.0 * 1264.0 * $ExperimentalTimingHz) / 1000.0) - 1)
                $timingBlock = [byte[]]@(
                    0x22, 0x00, 0x14,
                    [byte]($pixelClockKHz -band 0xFF),
                    [byte](($pixelClockKHz -shr 8) -band 0xFF),
                    [byte](($pixelClockKHz -shr 16) -band 0xFF),
                    [byte](($pixelClockKHz -shr 24) -band 0xFF),
                    0x7F, 0x07, 0x9F, 0x00,
                    0x2F, 0x00, 0x1F, 0x00,
                    0xAF, 0x04, 0x3F, 0x00,
                    0x35, 0x00, 0x05, 0x00
                )
                [Array]::Copy($timingBlock, 0, $modified, 156, $timingBlock.Length)
            }
            'BASE_DTD_SECOND_SLOT' {
                if ($PhysicalEdid.Length -ne 128 -or
                    -not (Test-ByteArrayEqual -Left ([byte[]]$PhysicalEdid[72..89]) -Right ([byte[]]$Definition.PhysicalSecondaryTiming))) {
                    throw 'The validated base EDID no longer has the pinned secondary detailed-timing slot.'
                }

                # Preserve the vendor native 1920x1080 totals and sync fields,
                # replacing only the secondary timing pixel clock. The native
                # 120 Hz timing remains untouched as the recovery mode.
                [Array]::Copy($PhysicalEdid, 54, $modified, 72, 18)
                $pixelClock10KHz = [uint16][Math]::Round((2080.0 * 1144.0 * $ExperimentalTimingHz) / 10000.0)
                $modified[72] = [byte]($pixelClock10KHz -band 0xFF)
                $modified[73] = [byte](($pixelClock10KHz -shr 8) -band 0xFF)
                $modified[98] = [byte][Math]::Ceiling((1144.0 * $ExperimentalTimingHz) / 1000.0)
                $modified[99] = [byte][Math]::Ceiling((2080.0 * 1144.0 * $ExperimentalTimingHz) / 10000000.0)
            }
            default {
                throw "The validated panel has no experimental high-refresh timing policy: $($Definition.HighRefreshTimingKind)"
            }
        }
    }

    foreach ($checksumStart in $Definition.ChecksumStarts) {
        Set-EdidChecksum -Edid $modified -Start ([int]$checksumStart)
    }

    $modifiedHash = Get-ByteArraySha256 -Bytes $modified
    $block0 = [byte[]]$modified[0..127]
    $block1 = if ($modified.Length -eq 256) { [byte[]]$modified[128..255] } else { $null }
    if ($modifiedHash -ne $ExpectedEdidSha256 -or
        (Get-ByteArraySha256 -Bytes $block0) -ne $ExpectedBlock0Sha256 -or
        ($null -ne $block1 -and (Get-ByteArraySha256 -Bytes $block1) -ne $ExpectedBlock1Sha256) -or
        ($null -eq $block1 -and -not [string]::IsNullOrWhiteSpace($ExpectedBlock1Sha256))) {
        throw "Internal $State EDID verification failed: $modifiedHash"
    }

    [pscustomobject]@{
        State = $State
        MinimumHz = $MinimumHz
        MaximumHz = $MaximumHz
        Complete = $modified
        Block0 = $block0
        Block1 = $block1
        Sha256 = $modifiedHash
        Block0Sha256 = $ExpectedBlock0Sha256
        Block1Sha256 = $ExpectedBlock1Sha256
    }
}

function Get-ExperimentalEdidCatalog {
    param(
        [Parameter(Mandatory)][byte[]]$PhysicalEdid,
        [Parameter(Mandatory)][object]$Definition
    )

    $variants = [Collections.Generic.List[object]]::new()
    $variants.Add((New-ExperimentalEdidVariant -PhysicalEdid $PhysicalEdid -Definition $Definition -State 'CLAWLAB_30_120' `
            -MinimumHz $experimentalMinimumHz -MaximumHz $targetMaximumHz `
            -ExpectedEdidSha256 $Definition.Custom30EdidSha256 `
            -ExpectedBlock0Sha256 $Definition.Custom30Block0Sha256 `
            -ExpectedBlock1Sha256 $Definition.Custom30Block1Sha256))
    $variants.Add((New-ExperimentalEdidVariant -PhysicalEdid $PhysicalEdid -Definition $Definition -State 'CLAWLAB_48_144' `
            -MinimumHz $targetMinimumHz -MaximumHz 144 `
            -ExpectedEdidSha256 $Definition.Overclock48_144EdidSha256 `
            -ExpectedBlock0Sha256 $Definition.Overclock48_144Block0Sha256 `
            -ExpectedBlock1Sha256 $Definition.Overclock48_144Block1Sha256 -ExperimentalTimingHz 144))
    $variants.Add((New-ExperimentalEdidVariant -PhysicalEdid $PhysicalEdid -Definition $Definition -State 'CLAWLAB_48_165' `
            -MinimumHz $targetMinimumHz -MaximumHz 165 `
            -ExpectedEdidSha256 $Definition.Overclock48_165EdidSha256 `
            -ExpectedBlock0Sha256 $Definition.Overclock48_165Block0Sha256 `
            -ExpectedBlock1Sha256 $Definition.Overclock48_165Block1Sha256 -ExperimentalTimingHz 165))
    $variants.Add((New-ExperimentalEdidVariant -PhysicalEdid $PhysicalEdid -Definition $Definition -State 'CLAWLAB_48_180' `
            -MinimumHz $targetMinimumHz -MaximumHz 180 `
            -ExpectedEdidSha256 $Definition.Overclock48_180EdidSha256 `
            -ExpectedBlock0Sha256 $Definition.Overclock48_180Block0Sha256 `
            -ExpectedBlock1Sha256 $Definition.Overclock48_180Block1Sha256 -ExperimentalTimingHz 180))
    $variants.Add((New-ExperimentalEdidVariant -PhysicalEdid $PhysicalEdid -Definition $Definition -State 'CLAWLAB_48_192' `
            -MinimumHz $targetMinimumHz -MaximumHz 192 `
            -ExpectedEdidSha256 $Definition.Overclock48_192EdidSha256 `
            -ExpectedBlock0Sha256 $Definition.Overclock48_192Block0Sha256 `
            -ExpectedBlock1Sha256 $Definition.Overclock48_192Block1Sha256 -ExperimentalTimingHz 192))

    $variants.Add((New-ExperimentalEdidVariant -PhysicalEdid $PhysicalEdid -Definition $Definition -State 'CLAWLAB_30_144' `
            -MinimumHz $experimentalMinimumHz -MaximumHz 144 `
            -ExpectedEdidSha256 $Definition.Overclock30_144EdidSha256 `
            -ExpectedBlock0Sha256 $Definition.Overclock30_144Block0Sha256 `
            -ExpectedBlock1Sha256 $Definition.Overclock30_144Block1Sha256 -ExperimentalTimingHz 144))
    $variants.Add((New-ExperimentalEdidVariant -PhysicalEdid $PhysicalEdid -Definition $Definition -State 'CLAWLAB_30_165' `
            -MinimumHz $experimentalMinimumHz -MaximumHz 165 `
            -ExpectedEdidSha256 $Definition.Overclock30_165EdidSha256 `
            -ExpectedBlock0Sha256 $Definition.Overclock30_165Block0Sha256 `
            -ExpectedBlock1Sha256 $Definition.Overclock30_165Block1Sha256 -ExperimentalTimingHz 165))
    $variants.Add((New-ExperimentalEdidVariant -PhysicalEdid $PhysicalEdid -Definition $Definition -State 'CLAWLAB_30_180' `
            -MinimumHz $experimentalMinimumHz -MaximumHz 180 `
            -ExpectedEdidSha256 $Definition.Overclock30_180EdidSha256 `
            -ExpectedBlock0Sha256 $Definition.Overclock30_180Block0Sha256 `
            -ExpectedBlock1Sha256 $Definition.Overclock30_180Block1Sha256 -ExperimentalTimingHz 180))
    $variants.Add((New-ExperimentalEdidVariant -PhysicalEdid $PhysicalEdid -Definition $Definition -State 'CLAWLAB_30_192' `
            -MinimumHz $experimentalMinimumHz -MaximumHz 192 `
            -ExpectedEdidSha256 $Definition.Overclock30_192EdidSha256 `
            -ExpectedBlock0Sha256 $Definition.Overclock30_192Block0Sha256 `
            -ExpectedBlock1Sha256 $Definition.Overclock30_192Block1Sha256 -ExperimentalTimingHz 192))
    return @($variants)
}

function Get-EdidOverrideState {
    param(
        [Parameter(Mandatory)][object]$RegistryContext,
        [Parameter(Mandatory)][object[]]$ExperimentalEdids
    )

    if (-not (Test-Path -LiteralPath $RegistryContext.OverridePath -PathType Container)) {
        return [pscustomobject]@{
            State = 'NONE'; Block0 = $null; Block1 = $null
            MinimumHz = $targetMinimumHz; MaximumHz = $targetMaximumHz; Variant = $null
        }
    }

    $block0 = $null
    $block1 = $null
    try { $block0 = [byte[]](Get-ItemPropertyValue -LiteralPath $RegistryContext.OverridePath -Name '0' -ErrorAction Stop) } catch {}
    try { $block1 = [byte[]](Get-ItemPropertyValue -LiteralPath $RegistryContext.OverridePath -Name '1' -ErrorAction Stop) } catch {}

    if ($null -eq $block0 -and $null -eq $block1) {
        return [pscustomobject]@{
            State = 'NONE'; Block0 = $null; Block1 = $null
            MinimumHz = $targetMinimumHz; MaximumHz = $targetMaximumHz; Variant = $null
        }
    }

    foreach ($variant in $ExperimentalEdids) {
        if ((Test-ByteArrayEqual -Left $block0 -Right $variant.Block0) -and
            (Test-ByteArrayEqual -Left $block1 -Right $variant.Block1)) {
            return [pscustomobject]@{
                State = $variant.State
                Block0 = $block0
                Block1 = $block1
                MinimumHz = $variant.MinimumHz
                MaximumHz = $variant.MaximumHz
                Variant = $variant
            }
        }
    }

    return [pscustomobject]@{
        State = 'UNKNOWN_OVERRIDE'; Block0 = $block0; Block1 = $block1
        MinimumHz = $null; MaximumHz = $null; Variant = $null
    }
}

function Get-ClawLabRecoveryBlockState {
    param(
        [AllowNull()][byte[]]$Block0,
        [AllowNull()][byte[]]$Block1,
        [Parameter(Mandatory)][object]$Definition
    )

    $block0 = $Block0
    $block1 = $Block1
    if ($null -eq $block0 -and $null -eq $block1) {
        return [pscustomobject]@{ State = 'NONE'; Block0Present = $false; Block1Present = $false }
    }

    $knownBlock0Hashes = @(
        $Definition.Custom30Block0Sha256
        $Definition.Legacy48_144Block0Sha256
        $Definition.Legacy30_144Block0Sha256
        $Definition.Overclock48_144Block0Sha256
        $Definition.Overclock48_165Block0Sha256
        $Definition.Overclock48_180Block0Sha256
        $Definition.Overclock48_192Block0Sha256
        $Definition.Overclock30_144Block0Sha256
        $Definition.Overclock30_165Block0Sha256
        $Definition.Overclock30_180Block0Sha256
        $Definition.Overclock30_192Block0Sha256
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
    $knownBlock1Hashes = @(
        $Definition.Custom30Block1Sha256
        $Definition.Legacy48_144Block1Sha256
        $Definition.Legacy30_144Block1Sha256
        $Definition.Overclock48_144Block1Sha256
        $Definition.Overclock48_165Block1Sha256
        $Definition.Overclock48_180Block1Sha256
        $Definition.Overclock48_192Block1Sha256
        $Definition.Overclock30_144Block1Sha256
        $Definition.Overclock30_165Block1Sha256
        $Definition.Overclock30_180Block1Sha256
        $Definition.Overclock30_192Block1Sha256
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
    $knownBlock0 = $null -eq $block0 -or (Get-ByteArraySha256 -Bytes $block0) -in $knownBlock0Hashes
    $knownBlock1 = $null -eq $block1 -or (Get-ByteArraySha256 -Bytes $block1) -in $knownBlock1Hashes
    if (-not $knownBlock0 -or -not $knownBlock1) {
        return [pscustomobject]@{ State = 'UNKNOWN_THIRD_PARTY'; Block0Present = $null -ne $block0; Block1Present = $null -ne $block1 }
    }
    return [pscustomobject]@{
        State = 'CLAWLAB_RECOVERABLE'
        Block0Present = $null -ne $block0
        Block1Present = $null -ne $block1
    }
}

function Get-ClawLabRecoveryOverrideState {
    param([Parameter(Mandatory)][object]$RegistryContext)

    $block0 = $null
    $block1 = $null
    if (Test-Path -LiteralPath $RegistryContext.OverridePath -PathType Container) {
        try { $block0 = [byte[]](Get-ItemPropertyValue -LiteralPath $RegistryContext.OverridePath -Name '0' -ErrorAction Stop) } catch {}
        try { $block1 = [byte[]](Get-ItemPropertyValue -LiteralPath $RegistryContext.OverridePath -Name '1' -ErrorAction Stop) } catch {}
    }
    return Get-ClawLabRecoveryBlockState -Block0 $block0 -Block1 $block1 -Definition $RegistryContext.Definition
}

function Get-VrrStartupTaskSpec {
    $wscriptPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
    New-ClawLabLogonTaskSpec -TaskName $startupTaskName -ExecutePath $wscriptPath `
        -Arguments ("//B //Nologo `"$installedLauncherPath`"") `
        -Description 'Silently applies MSI Claw Intel Arc Sync VRR, then starts Intel Graphics Software.' `
        -ExecutionTimeLimitMinutes 10
}

function Get-CursorRefreshHelperTaskSpec {
    # The native engine starts directly at interactive logon. It no longer
    # waits behind PowerShell, WMI, Intel Graphics Software or the ordered VRR
    # transaction. PT0S deliberately allows this event-driven process to stay
    # registered for the complete user session.
    New-ClawLabLogonTaskSpec -TaskName $cursorRefreshTaskName `
        -ExecutePath $installedCursorRefreshHelperPath -Arguments '--startup' `
        -Description 'Starts the native ClawLab Win32/DXGI desktop refresh engine directly at interactive logon.' `
        -ExecutionTimeLimitMinutes 0 -TaskPriority 2
}

function Get-LfcStartupOrchestratorTaskSpec {
    $wscriptPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
    New-ClawLabLogonTaskSpec -TaskName $lfcStartupTaskName -ExecutePath $wscriptPath `
        -Arguments ("//B //Nologo `"$installedLfcLauncherPath`"") `
        -Description 'Silently reapplies the selected ClawLab VRR range and Intel LFC state once at logon, then exits.' `
        -ExecutionTimeLimitMinutes 12 -TriggerDelaySeconds 15
}

function Test-LfcStartupOrchestratorReady {
    foreach ($payloadPath in @(
        $installedLfcToolPath,
        $installedLfcDriverInterfacePath,
        $installedLfcBackupIdentityPath,
        $installedLfcEdidNormalizationPath,
        $installedLfcArcSyncRangePolicyPath,
        $installedLfcScheduledTaskPersistencePath,
        $installedLfcLauncherPath
    )) {
        if (-not (Test-Path -LiteralPath $payloadPath -PathType Leaf)) {
            return $false
        }
    }
    $record = Get-ClawLabScheduledTaskRecord -TaskName $lfcStartupTaskName
    if ($null -eq $record) { return $false }
    return [bool](Test-ClawLabScheduledTaskRecord -Record $record `
        -Spec (Get-LfcStartupOrchestratorTaskSpec)).Valid
}

function Get-ExperimentalTrialTaskSpec {
    $wscriptPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
    $protectedTrialLauncher = Join-Path $protectedRuntimeRoot 'ClawLab-Experimental-Trial-Startup.vbs'
    New-ClawLabLogonTaskSpec -TaskName $experimentalTrialTaskName -ExecutePath $wscriptPath `
        -Arguments ("//B //Nologo `"$protectedTrialLauncher`"") `
        -Description 'Runs one user-started MSI Claw display-overclock trial with a visible 30-second observation, automatic safe-120 restoration and explicit confirmation.' `
        -ExecutionTimeLimitMinutes 5 -TriggerDelaySeconds 10
}

function Get-ManagedArtifactSnapshot {
    $task = Get-ClawLabScheduledTaskRecord -TaskName $startupTaskName
    $taskValid = $false
    if ($null -ne $task) {
        $taskValid = [bool](Test-ClawLabScheduledTaskRecord -Record $task -Spec (Get-VrrStartupTaskSpec)).Valid
    }
    $cursorTask = Get-ClawLabScheduledTaskRecord -TaskName $cursorRefreshTaskName
    $cursorTaskValid = $false
    if ($null -ne $cursorTask) {
        $cursorTaskValid = [bool](Test-ClawLabScheduledTaskRecord -Record $cursorTask `
            -Spec (Get-CursorRefreshHelperTaskSpec)).Valid
    }
    $snapshot = [pscustomobject]@{
        OriginalProfile = Test-Path -LiteralPath $backupPath -PathType Leaf
        NormalizationCompensation = Test-Path -LiteralPath $normalizationCompensationPath -PathType Leaf
        ExperimentalState = Test-Path -LiteralPath $experimentalStatePath -PathType Leaf
        InstalledScript = Test-Path -LiteralPath $installedScriptPath -PathType Leaf
        InstalledEdidNormalizationModule = Test-Path -LiteralPath $installedEdidNormalizationModulePath -PathType Leaf
        InstalledArcSyncRangePolicyModule = Test-Path -LiteralPath $installedArcSyncRangePolicyModulePath -PathType Leaf
        InstalledScheduledTaskPersistenceModule = Test-Path -LiteralPath $installedScheduledTaskPersistenceModulePath -PathType Leaf
        InstalledLauncher = Test-Path -LiteralPath $installedLauncherPath -PathType Leaf
        StartupStatus = Test-Path -LiteralPath $startupStatusPath -PathType Leaf
        IntelStartupBackup = Test-Path -LiteralPath $intelStartupBackupPath -PathType Leaf
        StartupTask = $null -ne $task
        StartupTaskValid = $taskValid
        CursorRefreshHelper = Test-Path -LiteralPath $installedCursorRefreshHelperPath -PathType Leaf
        CursorRefreshHelperState = Test-Path -LiteralPath $cursorRefreshHelperStatePath -PathType Leaf
        CursorRefreshTask = $null -ne $cursorTask
        CursorRefreshTaskValid = $cursorTaskValid
    }
    $snapshot | Add-Member -NotePropertyName Any -NotePropertyValue (
        $snapshot.OriginalProfile -or
        $snapshot.NormalizationCompensation -or
        $snapshot.ExperimentalState -or
        $snapshot.InstalledScript -or
        $snapshot.InstalledEdidNormalizationModule -or
        $snapshot.InstalledArcSyncRangePolicyModule -or
        $snapshot.InstalledScheduledTaskPersistenceModule -or
        $snapshot.InstalledLauncher -or
        $snapshot.StartupStatus -or
        $snapshot.IntelStartupBackup -or
        $snapshot.StartupTask -or
        $snapshot.CursorRefreshHelper -or
        $snapshot.CursorRefreshHelperState -or
        $snapshot.CursorRefreshTask
    )
    return $snapshot
}

function Get-ManagedModeExpectedRange {
    param([Parameter(Mandatory)][string]$Mode)

    if ($Mode -eq 'OFFICIAL_48_120') {
        return [pscustomobject]@{ MinimumHz = 48.0; MaximumHz = 120.0 }
    }
    if ($Mode -eq 'CLAWLAB_30_120') {
        return [pscustomobject]@{ MinimumHz = 30.0; MaximumHz = 120.0 }
    }
    $experimental = Get-ExperimentalOverclockMode -Mode $Mode
    return [pscustomobject]@{
        MinimumHz = [float]$experimental.MinimumHz
        MaximumHz = [float]$experimental.MaximumHz
    }
}

function Get-ExperimentalEdidRecord {
    param(
        [Parameter(Mandatory)][object]$OverrideState,
        [Parameter(Mandatory)][object]$ManagedRecord
    )

    if (-not (Test-Path -LiteralPath $experimentalStatePath -PathType Leaf)) {
        return $null
    }
    $record = [IO.File]::ReadAllText($experimentalStatePath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($property in @(
            'SchemaVersion', 'FixVersion', 'Mode', 'PanelKey', 'PhysicalEdidSha256',
            'ExperimentalEdidSha256', 'ExperimentalMinimumHz', 'MaximumHz',
            'ArcSyncPolicy', 'OriginalBaselinePolicy'
        )) {
        if ($property -notin $record.PSObject.Properties.Name) {
            throw "The custom EDID state is invalid: missing $property."
        }
    }
    if ([int]$record.SchemaVersion -ne 4 -or [string]$record.FixVersion -ne $fixVersion) {
        throw 'The custom EDID state belongs to another ClawLab schema or release.'
    }
    if ([string]$record.Mode -ne [string]$ManagedRecord.Mode -or
        [string]$record.PanelKey -ne [string]$ManagedRecord.PanelKey -or
        [string]$record.ArcSyncPolicy -ne [string]$ManagedRecord.ArcSyncPolicy) {
        throw 'The custom EDID state and managed VRR record do not share one exact identity.'
    }
    if ($null -eq $script:activePanelDefinition -or
        [string]$record.PanelKey -ne [string]$script:activePanelDefinition.Key -or
        [string]$record.PhysicalEdidSha256 -ne [string]$script:activePanelDefinition.PhysicalEdidSha256) {
        throw 'The custom EDID state does not match the active validated physical panel.'
    }
    $expected = Get-ManagedModeExpectedRange -Mode ([string]$record.Mode)
    if (-not (Test-ClawLabFrequencyEqual -Left ([float]$record.ExperimentalMinimumHz) -Right ([float]$expected.MinimumHz)) -or
        -not (Test-ClawLabFrequencyEqual -Left ([float]$record.MaximumHz) -Right ([float]$expected.MaximumHz)) -or
        [string]$OverrideState.State -ne [string]$record.Mode -or
        [string]$OverrideState.Variant.Sha256 -ne [string]$record.ExperimentalEdidSha256) {
        throw 'The active EDID override does not match the verified custom EDID state.'
    }
    if ([string]$record.ArcSyncPolicy -eq 'TMA2027_PRESERVE_EXACT_CUSTOM_30_120') {
        if ([string]$record.OriginalBaselinePolicy -ne 'TMA2027_VERIFIED_CUSTOM_30_120' -or
            [string]$record.Mode -ne 'CLAWLAB_30_120') {
            throw 'The TMA2027 custom EDID state contains an invalid original-baseline binding.'
        }
    }
    elseif ([string]$record.OriginalBaselinePolicy -ne 'INTEL_STANDARD_BASELINE') {
        throw 'The custom EDID state contains an invalid Intel baseline binding.'
    }
    return $record
}

function Get-ManagedModeRecord {
    if (-not (Test-Path -LiteralPath $managedModeStatePath -PathType Leaf)) {
        return $null
    }

    $record = [IO.File]::ReadAllText($managedModeStatePath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($property in @('SchemaVersion', 'FixVersion', 'Mode', 'InstalledAt')) {
        if ($property -notin $record.PSObject.Properties.Name) {
            throw "The managed VRR mode record is invalid: missing $property. Run RECOVERY\RESTORE_ORIGINAL_VRR.bat."
        }
    }
    if ([string]$record.Mode -notin $managedModeNames) {
        throw 'The managed VRR mode record contains an unsupported value. Run RECOVERY\RESTORE_ORIGINAL_VRR.bat.'
    }
    if ([string]$record.FixVersion -ne $fixVersion) {
        return $record
    }
    foreach ($property in @('PanelKey', 'ArcSyncPolicy', 'ExpectedMinimumHz', 'ExpectedMaximumHz')) {
        if ($property -notin $record.PSObject.Properties.Name) {
            throw "The current managed VRR record is missing $property. Run RECOVERY\RESTORE_ORIGINAL_VRR.bat."
        }
    }
    if ([int]$record.SchemaVersion -ne 2) {
        throw 'The current managed VRR record has an unsupported schema. Run RECOVERY\RESTORE_ORIGINAL_VRR.bat.'
    }
    $expected = Get-ManagedModeExpectedRange -Mode ([string]$record.Mode)
    if (-not (Test-ClawLabFrequencyEqual -Left ([float]$record.ExpectedMinimumHz) -Right ([float]$expected.MinimumHz)) -or
        -not (Test-ClawLabFrequencyEqual -Left ([float]$record.ExpectedMaximumHz) -Right ([float]$expected.MaximumHz))) {
        throw 'The managed VRR record range does not match its mode. Run RECOVERY\RESTORE_ORIGINAL_VRR.bat.'
    }
    if ($null -ne $script:activePanelDefinition -and
        [string]$record.PanelKey -ne [string]$script:activePanelDefinition.Key) {
        throw 'The managed VRR record belongs to another panel. Run RECOVERY\RESTORE_ORIGINAL_VRR.bat.'
    }
    $policyValid = if ([string]$record.ArcSyncPolicy -eq 'INTEL_EXCELLENT_REQUIRED') {
        $true
    }
    elseif ([string]$record.ArcSyncPolicy -eq 'TMA2027_PRESERVE_EXACT_CUSTOM_30_120') {
        [string]$record.PanelKey -eq 'CLAW_A1M_CLAW_7_AI_PLUS' -and [string]$record.Mode -eq 'CLAWLAB_30_120'
    }
    else {
        $false
    }
    if (-not $policyValid) {
        throw 'The managed VRR Arc Sync policy is invalid. Run RECOVERY\RESTORE_ORIGINAL_VRR.bat.'
    }
    return $record
}

function Get-EffectiveManagedMode {
    param([Parameter(Mandatory)][object]$OverrideState)

    $record = Get-ManagedModeRecord
    $overrideMode = if ($OverrideState.State -eq 'NONE') { 'NONE' } else { [string]$OverrideState.State }
    if ($null -ne $record) {
        if ([string]$record.FixVersion -ne $fixVersion) {
            return [pscustomobject]@{
                Mode = [string]$record.Mode
                State = 'OLDER_VERSION_RESTORE_REQUIRED'
                Source = 'MANAGED_RECORD'
            }
        }
        $expectedOverride = if ([string]$record.Mode -eq 'OFFICIAL_48_120') { 'NONE' } else { [string]$record.Mode }
        $artifacts = Get-ManagedArtifactSnapshot
        $requiresExperimentalState = [string]$record.Mode -ne 'OFFICIAL_48_120'
        $experimentalStateValid = -not $requiresExperimentalState
        if ($requiresExperimentalState) {
            try {
                $experimentalStateValid = $null -ne (Get-ExperimentalEdidRecord -OverrideState $OverrideState -ManagedRecord $record)
            }
            catch {
                $experimentalStateValid = $false
            }
        }
        $trialTaskRecord = Get-ClawLabScheduledTaskRecord -TaskName $experimentalTrialTaskName
        $trialTaskValid = $null -ne $trialTaskRecord -and
            [bool](Test-ClawLabScheduledTaskRecord -Record $trialTaskRecord -Spec (Get-ExperimentalTrialTaskSpec)).Valid
        $trialPending = (Test-IsExperimentalOverclockMode -Mode ([string]$record.Mode)) -and
            (Test-Path -LiteralPath $experimentalTrialStatePath -PathType Leaf) -and
            $trialTaskValid
        if ($trialPending -and $overrideMode -eq $expectedOverride -and
            $artifacts.OriginalProfile -and $artifacts.ExperimentalState -and $artifacts.InstalledScript) {
            return [pscustomobject]@{
                Mode = [string]$record.Mode
                State = 'EXPERIMENTAL_TRIAL_PENDING'
                Source = 'MANAGED_RECORD'
            }
        }
        $artifactsComplete = (
            $artifacts.OriginalProfile -and
            $artifacts.InstalledScript -and
            $artifacts.InstalledEdidNormalizationModule -and
            $artifacts.InstalledArcSyncRangePolicyModule -and
            $artifacts.InstalledScheduledTaskPersistenceModule -and
            $artifacts.InstalledLauncher -and
            $artifacts.IntelStartupBackup -and
            $artifacts.StartupTask -and $artifacts.StartupTaskValid -and
            ($artifacts.ExperimentalState -eq $requiresExperimentalState) -and
            $experimentalStateValid
        )
        if ($overrideMode -ne $expectedOverride -or -not $artifactsComplete) {
            return [pscustomobject]@{
                Mode = [string]$record.Mode
                State = 'INCONSISTENT_RESTORE_REQUIRED'
                Source = 'MANAGED_RECORD'
            }
        }
        return [pscustomobject]@{
            Mode = [string]$record.Mode
            State = 'CONSISTENT'
            Source = 'MANAGED_RECORD'
        }
    }

    if ($OverrideState.State -in (@('CLAWLAB_30_120') + @($experimentalOverclockModes.Keys))) {
        return [pscustomobject]@{
            Mode = [string]$OverrideState.State
            State = 'LEGACY_MATCHING_OVERRIDE'
            Source = 'EDID_OVERRIDE'
        }
    }
    if ($OverrideState.State -ne 'NONE') {
        return [pscustomobject]@{
            Mode = [string]$OverrideState.State
            State = 'UNSUPPORTED_RESTORE_REQUIRED'
            Source = 'EDID_OVERRIDE'
        }
    }

    $artifacts = Get-ManagedArtifactSnapshot
    if ($artifacts.Any) {
        return [pscustomobject]@{
            Mode = 'LEGACY_MANAGED_STATE'
            State = 'RESTORE_REQUIRED'
            Source = 'MANAGED_ARTIFACTS'
        }
    }
    return [pscustomobject]@{
        Mode = 'NONE'
        State = 'CLEAN'
        Source = 'NONE'
    }
}

function Assert-ProfileTransitionAllowed {
    param(
        [Parameter(Mandatory)][object]$OverrideState,
        [Parameter(Mandatory)][string]$DesiredMode
    )

    $current = Get-EffectiveManagedMode -OverrideState $OverrideState
    if (Test-ClawLabProfileTransitionAllowed -CurrentMode ([string]$current.Mode) `
            -CurrentState ([string]$current.State) -DesiredMode $DesiredMode) {
        return $current
    }
    throw "VRR profile switch refused. Current managed state: $($current.Mode) / $($current.State). Run RECOVERY\RESTORE_ORIGINAL_VRR.bat successfully before installing $DesiredMode."
}

function Assert-StableSameModeRepairAllowed {
    param(
        [Parameter(Mandatory)][object]$OverrideState,
        [Parameter(Mandatory)][string]$DesiredMode,
        [Parameter(Mandatory)][object]$Panel,
        [Parameter(Mandatory)][object]$Snapshot
    )

    $repairIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $repairPrincipal = [Security.Principal.WindowsPrincipal]::new($repairIdentity)
    if (-not $repairPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Private same-profile repair must be invoked by the already elevated ClawLab transaction coordinator.'
    }
    if ($DesiredMode -notin @('CLAWLAB_30_120', 'OFFICIAL_48_120')) {
        throw 'Internal same-profile repair is restricted to the stable 30-120 and 48-120 modes.'
    }
    $expectedOverride = if ($DesiredMode -eq 'CLAWLAB_30_120') { 'CLAWLAB_30_120' } else { 'NONE' }
    $current = Get-EffectiveManagedMode -OverrideState $OverrideState
    if ([string]$current.Mode -ne $DesiredMode -or
        [string]$current.State -notin @('CONSISTENT', 'INCONSISTENT_RESTORE_REQUIRED') -or
        [string]$OverrideState.State -ne $expectedOverride) {
        throw "Same-profile repair refused the current managed identity: $($current.Mode) / $($current.State) / override $($OverrideState.State)."
    }

    $record = Get-ManagedModeRecord
    $original = Get-OriginalProfile
    if ($null -eq $record -or $null -eq $original -or
        [string]$record.FixVersion -ne $fixVersion -or
        [string]$record.Mode -ne $DesiredMode -or
        [string]$record.PanelKey -ne [string]$Panel.Definition.Key -or
        [string]$original.PanelKey -ne [string]$Panel.Definition.Key -or
        [string]$original.PhysicalEdidSha256 -ne [string]$Panel.Definition.PhysicalEdidSha256) {
        throw 'Same-profile repair could not verify one current-version managed record and its exact original-profile backup.'
    }
    if ((Test-Path -LiteralPath $experimentalTrialStatePath -PathType Leaf) -or
        (Test-Path -LiteralPath $installedExperimentalTrialPath -PathType Leaf) -or
        (Test-Path -LiteralPath $installedExperimentalTrialLauncherPath -PathType Leaf) -or
        $null -ne (Get-ClawLabScheduledTaskRecord -TaskName $experimentalTrialTaskName)) {
        throw 'Same-profile repair is unavailable while guarded-trial artifacts exist. Run verified Restore instead.'
    }

    $expected = Get-ManagedModeExpectedRange -Mode $DesiredMode
    if (-not (Test-ClawLabArcSyncMonitorRangeCompatible `
            -PanelKey ([string]$Panel.Definition.Key) `
            -MonitorMinimumHz ([float]$Snapshot.MonitorMinimumHz) `
            -MonitorMaximumHz ([float]$Snapshot.MonitorMaximumHz) `
            -ExpectedMinimumHz ([float]$expected.MinimumHz) `
            -ExpectedMaximumHz ([float]$expected.MaximumHz) `
            -PhysicalMinimumHz $targetMinimumHz -CustomMinimumHz $experimentalMinimumHz `
            -SupportedMaximumHz $targetMaximumHz -LegacyRecoveryMaximumHz $experimentalMaximumHz)) {
        throw "Same-profile repair found an incompatible monitor range: $($Snapshot.MonitorMinimumHz)-$($Snapshot.MonitorMaximumHz) Hz."
    }

    $lfcToolPath = Join-Path $PSScriptRoot 'MSI-Claw-Intel-LFC-Fix.ps1'
    if (-not (Test-Path -LiteralPath $lfcToolPath -PathType Leaf)) {
        throw 'Same-profile repair requires the matching Intel LFC component.'
    }
    $lfcResults = @(& $lfcToolPath -Action Status)
    $lfc = if ($lfcResults.Count -gt 0) { $lfcResults[-1] } else { $null }
    if ($null -eq $lfc -or [string]$lfc.ToolVersion -ne '2.0.7' -or
        [string]$lfc.ManagedVrrMode -ne $DesiredMode -or
        -not [bool]$lfc.LfcTransition.BackupPresent -or
        $null -eq $lfc.LfcBackupIdentity -or -not [bool]$lfc.LfcBackupIdentity.Accepted -or
        [bool]$lfc.RestoreTombstonePresent -or [bool]$lfc.RestoreFinalizedPresent) {
        throw 'Same-profile repair could not verify the matching 2.0.7 LFC original-state backup identity.'
    }
    return $current
}

function Set-ManagedModeRecord {
    param(
        [Parameter(Mandatory)][string]$Mode,
        [ValidateSet('INTEL_EXCELLENT_REQUIRED', 'TMA2027_PRESERVE_EXACT_CUSTOM_30_120')]
        [string]$ArcSyncPolicy = 'INTEL_EXCELLENT_REQUIRED',
        [string]$PanelKey = ([string]$script:activePanelDefinition.Key)
    )

    if ($Mode -notin $managedModeNames) {
        throw "Internal managed VRR mode is invalid: $Mode"
    }
    $expected = Get-ManagedModeExpectedRange -Mode $Mode
    if ($ArcSyncPolicy -eq 'TMA2027_PRESERVE_EXACT_CUSTOM_30_120' -and
        ($PanelKey -ne 'CLAW_A1M_CLAW_7_AI_PLUS' -or $Mode -ne 'CLAWLAB_30_120')) {
        throw 'The TMA2027 Arc Sync policy can only be bound to the exact ClawLab 30-120 mode.'
    }
    $record = [ordered]@{
        SchemaVersion = 2
        FixVersion = $fixVersion
        Mode = $Mode
        InstalledAt = (Get-Date).ToString('o')
        PanelKey = $PanelKey
        ArcSyncPolicy = $ArcSyncPolicy
        ExpectedMinimumHz = [float]$expected.MinimumHz
        ExpectedMaximumHz = [float]$expected.MaximumHz
    }
    Write-ClawLabJsonAtomically -LiteralPath $managedModeStatePath -Value $record
    $verified = Get-ManagedModeRecord
    if ([string]$verified.Mode -ne $Mode) {
        throw 'The managed VRR mode record failed verification.'
    }
}

function Confirm-AdministratorOrRelaunch {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        return
    }

    $windowsPowerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $windowsPowerShellPath -PathType Leaf)) {
        throw "Windows PowerShell was not found at the trusted system path: $windowsPowerShellPath"
    }
    $arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Action $Action"
    $process = Start-Process -FilePath $windowsPowerShellPath -Verb RunAs -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -ne 0 -and (Test-Path -LiteralPath $lastErrorPath -PathType Leaf)) {
        Write-Host 'The elevated operation reported:' -ForegroundColor Red
        Get-Content -LiteralPath $lastErrorPath | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    }
    exit $process.ExitCode
}

function Get-StartupReapplyState {
    $spec = Get-VrrStartupTaskSpec
    $task = Get-ClawLabScheduledTaskRecord -TaskName $startupTaskName
    if ($null -eq $task) {
        return 'NOT_INSTALLED'
    }
    $validation = Test-ClawLabScheduledTaskRecord -Record $task -Spec $spec
    if (-not $validation.Valid) {
        return 'TASK_INVALID'
    }
    if (-not (Test-Path -LiteralPath $installedScriptPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $installedEdidNormalizationModulePath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $installedArcSyncRangePolicyModulePath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $installedScheduledTaskPersistenceModulePath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $installedLauncherPath -PathType Leaf)) {
        return 'TASK_WITHOUT_FILES'
    }
    return [string]$task.State
}

function Remove-ExperimentalOverclockTrial {
    [void](Remove-ClawLabScheduledTask -Spec (Get-ExperimentalTrialTaskSpec) -AllowAbsent)
    Remove-FileIfPresent -LiteralPath $experimentalTrialStatePath
    Remove-FileIfPresent -LiteralPath $installedExperimentalTrialPath
    Remove-FileIfPresent -LiteralPath $installedExperimentalTrialLauncherPath
    Remove-ProtectedExperimentalRuntime
}

function Get-ExperimentalOverclockTrialRecord {
    if (-not (Test-Path -LiteralPath $experimentalTrialStatePath -PathType Leaf)) {
        throw 'The mandatory experimental overclock trial state is missing.'
    }
    $record = [IO.File]::ReadAllText($experimentalTrialStatePath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($property in @(
        'SchemaVersion', 'FixVersion', 'Mode', 'MinimumHz', 'MaximumHz',
        'PanelKey', 'PhysicalEdidSha256', 'ExperimentalEdidSha256',
        'Stability', 'ObservationSeconds', 'UserConfirmed',
        'LifecycleState', 'AttemptConsumed', 'TaskConsumed',
        'PreTrialLfcDisposition', 'PreTrialLfc',
        'OwnerSid', 'OwnerLocalAppData', 'RunSessionId'
    )) {
        if ($property -notin $record.PSObject.Properties.Name) {
            throw "The experimental overclock trial state is invalid: missing $property."
        }
    }
    if ([int]$record.SchemaVersion -ne 2 -or [string]$record.FixVersion -ne $fixVersion -or
        -not (Test-IsExperimentalOverclockMode -Mode ([string]$record.Mode))) {
        throw 'The experimental overclock trial state has an unsupported identity.'
    }
    $mode = Get-ExperimentalOverclockMode -Mode ([string]$record.Mode)
    if ([int]$record.MinimumHz -ne [int]$mode.MinimumHz -or
        [int]$record.MaximumHz -ne [int]$mode.MaximumHz -or
        [string]$record.Stability -ne [string]$mode.Stability -or
        [int]$record.ObservationSeconds -ne 30) {
        throw 'The experimental overclock trial state has unexpected range or timeout values.'
    }
    return $record
}

function Assert-ExperimentalOverclockTrialContext {
    param(
        [Parameter(Mandatory)][object]$Panel,
        [Parameter(Mandatory)][object]$OverrideState,
        [switch]$RequireUserConfirmation,
        [string[]]$RequiredLifecycleStates = @()
    )

    $trial = Get-ExperimentalOverclockTrialRecord
    $modeName = [string]$trial.Mode
    $mode = Get-ExperimentalOverclockMode -Mode $modeName
    if ([string]$Panel.Definition.Key -ne [string]$trial.PanelKey -or
        [string]$Panel.Definition.PhysicalEdidSha256 -ne [string]$trial.PhysicalEdidSha256 -or
        [string]$OverrideState.State -ne $modeName -or
        [string]$OverrideState.Variant.Sha256 -ne [string]$trial.ExperimentalEdidSha256 -or
        [int]$OverrideState.MinimumHz -ne [int]$mode.MinimumHz -or
        [int]$OverrideState.MaximumHz -ne [int]$mode.MaximumHz) {
        throw 'The active panel, EDID override and guarded trial do not have one exact shared identity.'
    }
    $managed = Get-ManagedModeRecord
    if ($null -eq $managed -or [string]$managed.Mode -ne $modeName) {
        throw 'The guarded trial does not match the managed VRR mode record.'
    }
    if ($RequireUserConfirmation -and -not [bool]$trial.UserConfirmed) {
        throw 'The experimental overclock cannot be persisted before the user confirms the completed 30-second trial.'
    }
    if ($RequiredLifecycleStates.Count -gt 0 -and
        [string]$trial.LifecycleState -notin $RequiredLifecycleStates) {
        throw "The guarded trial lifecycle is $($trial.LifecycleState); expected one of: $($RequiredLifecycleStates -join ', ')."
    }
    if ([string]$trial.LifecycleState -ne 'SCHEDULED' -and
        (-not [bool]$trial.AttemptConsumed -or -not [bool]$trial.TaskConsumed)) {
        throw 'The guarded trial was not durably consumed before a display operation was requested.'
    }
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $currentSid = if ($null -eq $currentIdentity.User) { '' } else { [string]$currentIdentity.User.Value }
    $currentLocalAppData = [IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd('\')
    $ownerLocalAppData = [IO.Path]::GetFullPath([string]$trial.OwnerLocalAppData).TrimEnd('\')
    $currentSessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId
    if ([string]::IsNullOrWhiteSpace($currentSid) -or
        -not $currentSid.Equals([string]$trial.OwnerSid, [StringComparison]::OrdinalIgnoreCase) -or
        -not $currentLocalAppData.Equals($ownerLocalAppData, [StringComparison]::OrdinalIgnoreCase) -or
        $currentSessionId -ne [int]$trial.RunSessionId) {
        throw 'The guarded trial owner SID, current session or canonical LOCALAPPDATA identity did not verify.'
    }
    return [pscustomobject]@{ Trial = $trial; Mode = $mode }
}

function Complete-ExperimentalOverclockTrialCommit {
    param([Parameter(Mandatory)][object]$Trial)

    # Commit evidence is durable before any recovery payload can be removed.
    # ConfirmExperimentalTrial reaches this function only after VRR, startup
    # persistence and Intel LFC have all been independently verified.
    $Trial | Add-Member -NotePropertyName LifecycleState `
        -NotePropertyValue 'COMMIT_VERIFIED' -Force
    $Trial | Add-Member -NotePropertyName CommitVerifiedAt `
        -NotePropertyValue (Get-Date).ToString('o') -Force
    $Trial | Add-Member -NotePropertyName RecoveryRequired `
        -NotePropertyValue $false -Force
    Write-ClawLabJsonAtomically -LiteralPath $experimentalTrialStatePath -Value $Trial

    [void](Remove-ClawLabScheduledTask -Spec (Get-ExperimentalTrialTaskSpec) -AllowAbsent)
    if ($null -ne (Get-ClawLabScheduledTaskRecord -TaskName $experimentalTrialTaskName)) {
        throw 'The consumed guarded-trial task could not be removed before final cleanup.'
    }
    Remove-FileIfPresent -LiteralPath $installedExperimentalTrialPath
    Remove-FileIfPresent -LiteralPath $installedExperimentalTrialLauncherPath
    if ((Test-Path -LiteralPath $installedExperimentalTrialPath -PathType Leaf) -or
        (Test-Path -LiteralPath $installedExperimentalTrialLauncherPath -PathType Leaf)) {
        throw 'Local guarded-trial launch artifacts remain after final cleanup.'
    }

    # Protected runtime deletion is intentionally last. If it cannot be
    # completed, retain the atomic COMMIT_VERIFIED state and report success for
    # the already verified profile; Restore can retry this housekeeping later.
    try {
        Remove-ProtectedExperimentalRuntime
        if (Test-Path -LiteralPath $protectedRuntimeRoot -PathType Container) {
            throw 'The protected guarded-trial runtime remains after cleanup.'
        }
        Remove-FileIfPresent -LiteralPath $experimentalTrialStatePath
        return 'PROTECTED_RUNTIME_REMOVED_AFTER_COMMIT_VERIFICATION'
    }
    catch {
        $Trial | Add-Member -NotePropertyName ProtectedRuntimeCleanupPending `
            -NotePropertyValue $true -Force
        $Trial | Add-Member -NotePropertyName ProtectedRuntimeCleanupError `
            -NotePropertyValue ([string]$_.Exception.Message) -Force
        Write-ClawLabJsonAtomically -LiteralPath $experimentalTrialStatePath -Value $Trial
        Write-Warning "The confirmed profile is verified; protected recovery-payload cleanup will be retried by Restore: $($_.Exception.Message)"
        return 'PROTECTED_RUNTIME_RETAINED_FOR_RECOVERY'
    }
}

function Get-CursorRefreshHelperProcesses {
    $expectedPath = [IO.Path]::GetFullPath($installedCursorRefreshHelperPath)
    return @(
        Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($cursorRefreshHelperName)) -ErrorAction SilentlyContinue |
            Where-Object {
                try {
                    $processPath = [IO.Path]::GetFullPath([string]$_.Path)
                    $processPath.Equals($expectedPath, [StringComparison]::OrdinalIgnoreCase)
                }
                catch {
                    $false
                }
            }
    )
}

function Get-CursorRefreshRuntimeState {
    if (-not (Test-Path -LiteralPath $cursorRefreshRuntimeStatePath -PathType Leaf)) {
        return $null
    }
    try {
        $values = [ordered]@{}
        foreach ($line in [IO.File]::ReadAllLines($cursorRefreshRuntimeStatePath, [Text.Encoding]::UTF8)) {
            $separator = $line.IndexOf('=')
            if ($separator -le 0) { continue }
            $values[$line.Substring(0, $separator)] = $line.Substring($separator + 1)
        }
        foreach ($required in @('SchemaVersion', 'FixVersion', 'Engine', 'ProcessId', 'SessionId')) {
            if (-not $values.Contains($required)) { return $null }
        }
        return [pscustomobject]$values
    }
    catch {
        return $null
    }
}

function Test-CursorRefreshControlEvent {
    param([Parameter(Mandatory)][string]$Name)

    $event = $null
    try {
        $event = [Threading.EventWaitHandle]::OpenExisting($Name)
        return $event.WaitOne(0)
    }
    catch {
        return $false
    }
    finally {
        if ($null -ne $event) { $event.Dispose() }
    }
}

function Set-CursorRefreshControlEvent {
    param([Parameter(Mandatory)][string]$Name)

    $event = $null
    try {
        $event = [Threading.EventWaitHandle]::OpenExisting($Name)
        return [bool]$event.Set()
    }
    catch {
        return $false
    }
    finally {
        if ($null -ne $event) { $event.Dispose() }
    }
}

function Get-CursorRefreshHelperState {
    $binaryPresent = Test-Path -LiteralPath $installedCursorRefreshHelperPath -PathType Leaf
    $statePresent = Test-Path -LiteralPath $cursorRefreshHelperStatePath -PathType Leaf
    $task = Get-ClawLabScheduledTaskRecord -TaskName $cursorRefreshTaskName
    if (-not $binaryPresent -and -not $statePresent -and $null -eq $task) {
        return 'NOT_INSTALLED'
    }
    if (-not $binaryPresent -or -not $statePresent -or $null -eq $task) {
        return 'INCOMPLETE'
    }

    try {
        $taskValidation = Test-ClawLabScheduledTaskRecord -Record $task `
            -Spec (Get-CursorRefreshHelperTaskSpec)
        if (-not $taskValidation.Valid) { return 'TASK_INVALID' }
        $record = [IO.File]::ReadAllText($cursorRefreshHelperStatePath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        foreach ($property in @('SchemaVersion', 'FixVersion', 'FileName', 'FileSha256')) {
            if ($property -notin $record.PSObject.Properties.Name) {
                return 'INVALID_STATE'
            }
        }
        if ([int]$record.SchemaVersion -ne 1 -or
            [string]$record.FileName -ne $cursorRefreshHelperName) {
            return 'INVALID_STATE'
        }
        if ([string]$record.FixVersion -ne $fixVersion) {
            return 'VERSION_MISMATCH'
        }
        $actualHash = (Get-FileHash -LiteralPath $installedCursorRefreshHelperPath -Algorithm SHA256).Hash
        if ($actualHash -ne [string]$record.FileSha256) {
            return 'HASH_MISMATCH'
        }
        $processes = @(Get-CursorRefreshHelperProcesses)
        if ($processes.Count -eq 1) {
            if (-not (Test-CursorRefreshControlEvent -Name $cursorRefreshReadyEventName)) {
                return 'STARTING'
            }
            $runtime = Get-CursorRefreshRuntimeState
            if ($null -eq $runtime -or
                [int]$runtime.ProcessId -ne [int]$processes[0].Id -or
                [string]$runtime.FixVersion -ne $fixVersion) {
                return 'RUNNING_UNVERIFIED'
            }
            if ([string]$runtime.Engine -eq 'NATIVE_WIN32_DXGI_FLIP_MODEL') {
                return 'RUNNING_NATIVE_DXGI'
            }
            if ([string]$runtime.Engine -eq 'NATIVE_WIN32_DXGI_SEQUENTIAL_FALLBACK') {
                return 'RUNNING_NATIVE_DXGI_COMPATIBILITY'
            }
            if ([string]$runtime.Engine -eq 'WPF_FALLBACK') {
                return 'RUNNING_WPF_FALLBACK'
            }
            return 'RUNNING_UNVERIFIED'
        }
        if ($processes.Count -gt 1) { return 'MULTIPLE_INSTANCES' }
        return 'READY_AT_NEXT_SIGN_IN'
    }
    catch {
        return 'INVALID_STATE'
    }
}

function Stop-CursorRefreshHelper {
    $processes = @(Get-CursorRefreshHelperProcesses)
    if ($processes.Count -eq 0) { return }

    # New engines leave cooperatively through the named shutdown event. The
    # forced path is retained only for legacy binaries or a genuinely hung
    # helper and never touches the display driver or its managed profile.
    [void](Set-CursorRefreshControlEvent -Name $cursorRefreshShutdownEventName)
    $deadline = [DateTime]::UtcNow.AddSeconds(3)
    foreach ($process in $processes) {
        $remaining = [int][Math]::Max(0, ($deadline - [DateTime]::UtcNow).TotalMilliseconds)
        if ($remaining -gt 0) {
            try { [void]$process.WaitForExit($remaining) } catch {}
        }
    }
    foreach ($process in @(Get-CursorRefreshHelperProcesses)) {
        Stop-Process -Id $process.Id -Force -ErrorAction Stop
        try { [void]$process.WaitForExit(3000) } catch {}
    }
}

function Install-CursorRefreshHelper {
    $sourcePath = Join-Path (Split-Path $PSCommandPath -Parent) $cursorRefreshHelperName
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "The Cursor Refresh Helper binary is missing: $cursorRefreshHelperName"
    }

    Stop-CursorRefreshHelper
    Remove-FileIfPresent -LiteralPath $cursorRefreshRuntimeStatePath
    [IO.Directory]::CreateDirectory($stateRoot) | Out-Null
    if (-not [IO.Path]::GetFullPath($sourcePath).Equals(
            [IO.Path]::GetFullPath($installedCursorRefreshHelperPath),
            [StringComparison]::OrdinalIgnoreCase)) {
        [IO.File]::Copy($sourcePath, $installedCursorRefreshHelperPath, $true)
    }
    $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
    $installedHash = (Get-FileHash -LiteralPath $installedCursorRefreshHelperPath -Algorithm SHA256).Hash
    if ($sourceHash -ne $installedHash) {
        throw 'The installed Cursor Refresh Helper failed its integrity check.'
    }

    $record = [ordered]@{
        SchemaVersion = 1
        FixVersion = $fixVersion
        FileName = $cursorRefreshHelperName
        FileSha256 = $sourceHash
        InstalledAt = (Get-Date).ToString('o')
        Activation = 'NATIVE_WIN32_DXGI_FLIP_MODEL_WITH_WPF_FAILSAFE'
        Synchronization = 'NAMED_EVENT_RESYNC_WITHOUT_PROCESS_RESTART'
        IdleBehavior = 'KERNEL_EVENT_WAIT_NO_ACTIVE_PRESENTS_OR_TIMER_RESOLUTION'
    }
    [IO.File]::WriteAllText(
        $cursorRefreshHelperStatePath,
        ($record | ConvertTo-Json),
        [Text.UTF8Encoding]::new($false)
    )
    [void](Install-ClawLabScheduledTask -Spec (Get-CursorRefreshHelperTaskSpec))
    if ((Get-CursorRefreshHelperState) -ne 'READY_AT_NEXT_SIGN_IN') {
        throw 'The Cursor Refresh Helper installation could not be verified.'
    }
}

function Start-CursorRefreshHelper {
    $state = Get-CursorRefreshHelperState
    $runningStates = @(
        'RUNNING_NATIVE_DXGI',
        'RUNNING_NATIVE_DXGI_COMPATIBILITY',
        'RUNNING_WPF_FALLBACK'
    )
    if ($state -in $runningStates) {
        return $state
    }
    if ($state -notin @('READY_AT_NEXT_SIGN_IN', 'STARTING')) {
        throw "The Cursor Refresh Helper cannot start from state $state. Run UPDATE_CURSOR_REFRESH_ENGINE.bat; the managed VRR profile does not need to be reinstalled."
    }

    if ($state -eq 'READY_AT_NEXT_SIGN_IN') {
        # Never inherit the elevated installer token. The exact verified task
        # owns InteractiveToken + Limited and starts the process in the bound
        # user's desktop session even when this maintenance action has UAC.
        [void](Start-ClawLabScheduledTask -Spec (Get-CursorRefreshHelperTaskSpec))
    }
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 100
        $state = Get-CursorRefreshHelperState
        if ($state -in $runningStates) { return $state }
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "The Cursor Refresh Helper did not publish a verified runtime state after launch (state $state)."
}

function Sync-CursorRefreshHelper {
    $state = Start-CursorRefreshHelper
    $runtimeBefore = Get-CursorRefreshRuntimeState
    $resyncBefore = if ($null -ne $runtimeBefore -and
        'Resynchronizations' -in $runtimeBefore.PSObject.Properties.Name) {
        [int64]$runtimeBefore.Resynchronizations
    }
    else { -1 }

    if (-not (Set-CursorRefreshControlEvent -Name $cursorRefreshResyncEventName)) {
        throw 'The Cursor Refresh Helper resynchronization channel is unavailable.'
    }
    if ($state -eq 'RUNNING_WPF_FALLBACK') {
        return $state
    }

    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    do {
        Start-Sleep -Milliseconds 100
        $currentState = Get-CursorRefreshHelperState
        if ($currentState -notin @(
                'RUNNING_NATIVE_DXGI',
                'RUNNING_NATIVE_DXGI_COMPATIBILITY'
            )) {
            throw "The native Cursor Refresh Engine left its verified state during resynchronization ($currentState)."
        }
        $runtimeAfter = Get-CursorRefreshRuntimeState
        if ($null -ne $runtimeAfter -and
            'Resynchronizations' -in $runtimeAfter.PSObject.Properties.Name -and
            [int64]$runtimeAfter.Resynchronizations -gt $resyncBefore) {
            return $currentState
        }
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'The native Cursor Refresh Engine did not acknowledge the resynchronization request.'
}

function Update-CursorRefreshHelperOnly {
    param(
        [Parameter(Mandatory)][object]$Panel,
        [Parameter(Mandatory)][object]$Snapshot,
        [Parameter(Mandatory)][object]$OverrideState
    )

    if (Test-Path -LiteralPath $normalizationCompensationPath -PathType Leaf) {
        throw 'A display recovery transaction is pending. The cursor-only update was refused without changing the VRR profile.'
    }
    $effective = Get-EffectiveManagedMode -OverrideState $OverrideState
    if ([string]$effective.State -ne 'CONSISTENT') {
        throw "The cursor-only update requires an already consistent managed VRR profile. Current state: $($effective.Mode) / $($effective.State)."
    }
    $managed = Get-ManagedModeRecord
    if ($null -eq $managed -or [string]$managed.FixVersion -ne $fixVersion) {
        throw 'The cursor-only update requires a verified ClawLab 2.3.0 managed profile.'
    }
    $expected = Get-ManagedModeExpectedRange -Mode ([string]$managed.Mode)
    if (-not (Test-ManagedArcSyncSnapshot -Snapshot $Snapshot `
            -PanelKey ([string]$Panel.Definition.Key) -Mode ([string]$managed.Mode) `
            -Policy ([string]$managed.ArcSyncPolicy) `
            -ExpectedMinimumHz ([float]$expected.MinimumHz) `
            -ExpectedMaximumHz ([float]$expected.MaximumHz))) {
        throw 'The active Intel Arc Sync state is not the verified managed profile. The cursor-only update made no change.'
    }

    Install-CursorRefreshHelper
    $engine = Start-CursorRefreshHelper
    $engine = Sync-CursorRefreshHelper
    return [pscustomobject]@{
        State = 'CURSOR_REFRESH_ENGINE_UPDATED'
        Engine = $engine
        ManagedMode = [string]$managed.Mode
        DriverActiveRange = '{0:0.#}-{1:0.#} Hz' -f `
            $Snapshot.ActiveMinimumHz, $Snapshot.ActiveMaximumHz
        ProfileChanged = $false
        LfcChanged = $false
        EdidChanged = $false
        RestartRequired = $false
    }
}

function Invoke-CursorRefreshHelperStartupBestEffort {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Start', 'Resync')]
        [string]$Operation
    )

    try {
        $engine = if ($Operation -eq 'Resync') {
            Sync-CursorRefreshHelper
        }
        else {
            Start-CursorRefreshHelper
        }
        $script:cursorRefreshLaunchWarning = if ($engine -eq 'RUNNING_WPF_FALLBACK') {
            'The native DXGI engine was unavailable; the isolated WPF compatibility engine is active.'
        }
        elseif ($engine -eq 'RUNNING_NATIVE_DXGI_COMPATIBILITY') {
            'The native DXGI engine is active with its sequential compatibility presentation model.'
        }
        else { $null }
        return $true
    }
    catch {
        # The desktop helper is optional and independent from the game-facing
        # Intel Arc Sync/LFC correction. Never hide its failure, but do not let
        # it prevent the independently verified VRR setter/readback path.
        $script:cursorRefreshLaunchWarning = "Cursor Refresh Helper $Operation failed: $($_.Exception.Message)"
        Write-Warning $script:cursorRefreshLaunchWarning
        return $false
    }
}

function Remove-CursorRefreshHelper {
    Stop-CursorRefreshHelper
    [void](Remove-ClawLabScheduledTask -Spec (Get-CursorRefreshHelperTaskSpec) -AllowAbsent)
    Remove-FileIfPresent -LiteralPath $installedCursorRefreshHelperPath
    Remove-FileIfPresent -LiteralPath $cursorRefreshHelperStatePath
    Remove-FileIfPresent -LiteralPath $cursorRefreshRuntimeStatePath
    if ((Get-CursorRefreshHelperState) -ne 'NOT_INSTALLED') {
        throw 'The Cursor Refresh Helper could not be removed completely.'
    }
}

function Install-StartupReapply {
    param([switch]$PreserveExperimentalRecovery)

    [IO.Directory]::CreateDirectory($stateRoot) | Out-Null
    $sourceLauncherPath = Join-Path (Split-Path $PSCommandPath -Parent) $startupLauncherName
    if (-not (Test-Path -LiteralPath $sourceLauncherPath -PathType Leaf)) {
        throw "The windowless startup launcher is missing: $startupLauncherName"
    }
    foreach ($pair in @(
        @($PSCommandPath, $installedScriptPath),
        @($edidNormalizationModulePath, $installedEdidNormalizationModulePath),
        @($arcSyncRangePolicyModulePath, $installedArcSyncRangePolicyModulePath),
        @($scheduledTaskPersistenceModulePath, $installedScheduledTaskPersistenceModulePath),
        @($sourceLauncherPath, $installedLauncherPath)
    )) {
        if (-not [IO.Path]::GetFullPath($pair[0]).Equals(
                [IO.Path]::GetFullPath($pair[1]),
                [StringComparison]::OrdinalIgnoreCase)) {
            [IO.File]::Copy($pair[0], $pair[1], $true)
        }
    }

    $sourceHash = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
    $installedHash = (Get-FileHash -LiteralPath $installedScriptPath -Algorithm SHA256).Hash
    $sourceEdidModuleHash = (Get-FileHash -LiteralPath $edidNormalizationModulePath -Algorithm SHA256).Hash
    $installedEdidModuleHash = (Get-FileHash -LiteralPath $installedEdidNormalizationModulePath -Algorithm SHA256).Hash
    $sourceRangePolicyHash = (Get-FileHash -LiteralPath $arcSyncRangePolicyModulePath -Algorithm SHA256).Hash
    $installedRangePolicyHash = (Get-FileHash -LiteralPath $installedArcSyncRangePolicyModulePath -Algorithm SHA256).Hash
    $sourceTaskModuleHash = (Get-FileHash -LiteralPath $scheduledTaskPersistenceModulePath -Algorithm SHA256).Hash
    $installedTaskModuleHash = (Get-FileHash -LiteralPath $installedScheduledTaskPersistenceModulePath -Algorithm SHA256).Hash
    $sourceLauncherHash = (Get-FileHash -LiteralPath $sourceLauncherPath -Algorithm SHA256).Hash
    $installedLauncherHash = (Get-FileHash -LiteralPath $installedLauncherPath -Algorithm SHA256).Hash
    if ($sourceHash -ne $installedHash -or
        $sourceEdidModuleHash -ne $installedEdidModuleHash -or
        $sourceRangePolicyHash -ne $installedRangePolicyHash -or
        $sourceTaskModuleHash -ne $installedTaskModuleHash -or
        $sourceLauncherHash -ne $installedLauncherHash) {
        throw 'The installed startup files failed their integrity check.'
    }

    try {
        [void](Install-ClawLabScheduledTask -Spec (Get-VrrStartupTaskSpec))
        Set-ManagedIntelStartupOrder
        Install-CursorRefreshHelper
    }
    catch {
        try { Restore-IntelStartupOrder } catch { Write-Warning "Intel startup rollback failed: $($_.Exception.Message)" }
        try { Remove-StartupReapply -PreserveExperimentalRecovery:$PreserveExperimentalRecovery } catch {}
        throw
    }
}

function Remove-StartupReapply {
    param([switch]$PreserveExperimentalRecovery)

    [void](Remove-ClawLabScheduledTask -Spec (Get-VrrStartupTaskSpec) -AllowAbsent)
    if (-not $PreserveExperimentalRecovery) {
        Remove-ExperimentalOverclockTrial
    }
    Remove-CursorRefreshHelper
    Remove-FileIfPresent -LiteralPath $installedScriptPath
    Remove-FileIfPresent -LiteralPath $installedEdidNormalizationModulePath
    Remove-FileIfPresent -LiteralPath $installedArcSyncRangePolicyModulePath
    Remove-FileIfPresent -LiteralPath $installedScheduledTaskPersistenceModulePath
    Remove-FileIfPresent -LiteralPath $installedLauncherPath
    Remove-FileIfPresent -LiteralPath $startupStatusPath
    if ((Get-StartupReapplyState) -ne 'NOT_INSTALLED') {
        throw 'The startup reapply task could not be removed completely.'
    }
}

function Write-StartupResult {
    param(
        [Parameter(Mandatory)][bool]$Success,
        [Parameter(Mandatory)][string]$Message
    )

    [IO.Directory]::CreateDirectory($stateRoot) | Out-Null
    $result = [ordered]@{
        SchemaVersion = 1
        FixVersion = $fixVersion
        Timestamp = (Get-Date).ToString('o')
        InvocationSource = $StartupSource
        Success = $Success
        Message = $Message
        IntelGraphicsLaunchWarning = $script:intelGraphicsLaunchWarning
        CursorRefreshLaunchWarning = $script:cursorRefreshLaunchWarning
    }
    [IO.File]::WriteAllText(
        $startupStatusPath,
        ($result | ConvertTo-Json),
        [Text.UTF8Encoding]::new($false)
    )
}

function Resolve-IntelGraphicsStartupCommand {
    param(
        [Parameter(Mandatory)][string]$Command,
        [switch]$SkipAuthenticode
    )

    $match = [regex]::Match(
        $Command,
        '(?i)^\s*"(?<Executable>[A-Za-z]:\\[^"]+\\IntelGraphicsSoftware\.exe)"\s+(?<Arguments>-s)\s*$'
    )
    if (-not $match.Success) {
        throw "Unexpected Intel Graphics Software startup command: $Command"
    }

    $executable = [IO.Path]::GetFullPath($match.Groups['Executable'].Value)
    $expectedRoot = [IO.Path]::GetFullPath((Join-Path $env:ProgramFiles 'Intel\Intel Graphics Software'))
    if (-not $executable.StartsWith($expectedRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Intel Graphics Software is outside its expected installation directory: $executable"
    }
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        throw "Intel Graphics Software executable is missing: $executable"
    }

    $signerThumbprint = $null
    if (-not $SkipAuthenticode) {
        $signature = Get-AuthenticodeSignature -LiteralPath $executable
        if ($signature.Status -ne [Management.Automation.SignatureStatus]::Valid -or
            $null -eq $signature.SignerCertificate -or
            $signature.SignerCertificate.Subject -notmatch '(^|, )O=Intel Corporation(,|$)') {
            throw 'Intel Graphics Software does not have the expected valid Intel signature.'
        }
        $signerThumbprint = $signature.SignerCertificate.Thumbprint
    }

    [pscustomobject]@{
        Command = $Command
        Executable = $executable
        Arguments = $match.Groups['Arguments'].Value
        SignerThumbprint = $signerThumbprint
        FileSha256 = Get-FileSha256 -LiteralPath $executable
        FileVersion = [string](Get-Item -LiteralPath $executable).VersionInfo.FileVersion
    }
}

function Write-IntelStartupBackupAtomically {
    param([Parameter(Mandatory)][object]$Backup)

    [IO.Directory]::CreateDirectory($stateRoot) | Out-Null
    $temporaryPath = Join-Path $stateRoot ('.intel-graphics-startup-{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
    $replacementBackupPath = Join-Path $stateRoot ('.intel-graphics-startup-previous-{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText(
            $temporaryPath,
            ($Backup | ConvertTo-Json),
            [Text.UTF8Encoding]::new($false)
        )
        if (Test-Path -LiteralPath $intelStartupBackupPath -PathType Leaf) {
            [IO.File]::Replace($temporaryPath, $intelStartupBackupPath, $replacementBackupPath)
            [IO.File]::Delete($replacementBackupPath)
        }
        else {
            [IO.File]::Move($temporaryPath, $intelStartupBackupPath)
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            [IO.File]::Delete($temporaryPath)
        }
        if (Test-Path -LiteralPath $replacementBackupPath -PathType Leaf) {
            [IO.File]::Delete($replacementBackupPath)
        }
    }
}

function Set-IntelStartupTrustedIdentity {
    param(
        [AllowNull()][object]$ExistingBackup,
        [Parameter(Mandatory)][object]$Resolved,
        [bool]$OriginalEntryPresent = $true
    )

    if ([string]::IsNullOrWhiteSpace([string]$Resolved.SignerThumbprint) -or
        [string]::IsNullOrWhiteSpace([string]$Resolved.FileSha256) -or
        [string]::IsNullOrWhiteSpace([string]$Resolved.FileVersion)) {
        throw 'An incomplete Intel Graphics Software identity cannot be trusted.'
    }

    $savedAt = (Get-Date).ToString('o')
    if ($null -ne $ExistingBackup -and 'SavedAt' -in $ExistingBackup.PSObject.Properties.Name) {
        $savedAt = [string]$ExistingBackup.SavedAt
    }
    if ($null -ne $ExistingBackup -and 'OriginalEntryPresent' -in $ExistingBackup.PSObject.Properties.Name) {
        $OriginalEntryPresent = [bool]$ExistingBackup.OriginalEntryPresent
    }
    $record = [ordered]@{
        SchemaVersion = 4
        FixVersion = $fixVersion
        SavedAt = $savedAt
        IdentityVerifiedAt = (Get-Date).ToString('o')
        OriginalEntryPresent = $OriginalEntryPresent
        RegistryPath = $intelStartupRegistryPath
        ValueName = $intelStartupValueName
        Command = $Resolved.Command
        Executable = $Resolved.Executable
        Arguments = $Resolved.Arguments
        SignerThumbprint = $Resolved.SignerThumbprint
        FileSha256 = $Resolved.FileSha256
        FileVersion = $Resolved.FileVersion
    }
    Write-IntelStartupBackupAtomically -Backup $record

    $verified = [IO.File]::ReadAllText($intelStartupBackupPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if ([int]$verified.SchemaVersion -ne 4 -or
        [bool]$verified.OriginalEntryPresent -ne $OriginalEntryPresent -or
        [string]$verified.Command -ne [string]$Resolved.Command -or
        [string]$verified.SignerThumbprint -ne [string]$Resolved.SignerThumbprint -or
        [string]$verified.FileSha256 -ne [string]$Resolved.FileSha256 -or
        [string]$verified.FileVersion -ne [string]$Resolved.FileVersion) {
        throw 'The verified Intel Graphics Software identity could not be saved safely.'
    }
    return $verified
}

function Set-IntelStartupAbsentState {
    $record = [ordered]@{
        SchemaVersion = 4
        FixVersion = $fixVersion
        SavedAt = (Get-Date).ToString('o')
        IdentityVerifiedAt = $null
        OriginalEntryPresent = $false
        RegistryPath = $intelStartupRegistryPath
        ValueName = $intelStartupValueName
        Command = $null
        Executable = $null
        Arguments = $null
        SignerThumbprint = $null
        FileSha256 = $null
        FileVersion = $null
    }
    Write-IntelStartupBackupAtomically -Backup $record

    $verified = [IO.File]::ReadAllText($intelStartupBackupPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if ([int]$verified.SchemaVersion -ne 4 -or
        [bool]$verified.OriginalEntryPresent -or
        -not [string]::IsNullOrEmpty([string]$verified.Command)) {
        throw 'The absent Intel Graphics Software startup state could not be saved safely.'
    }
    return $verified
}

function Get-IntelStartupBackup {
    if (-not (Test-Path -LiteralPath $intelStartupBackupPath -PathType Leaf)) {
        return $null
    }
    $backup = [IO.File]::ReadAllText($intelStartupBackupPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($property in @('RegistryPath', 'ValueName')) {
        if ($property -notin $backup.PSObject.Properties.Name) {
            throw "The saved Intel startup entry is invalid: missing $property."
        }
    }
    if ([string]$backup.RegistryPath -ne $intelStartupRegistryPath -or
        [string]$backup.ValueName -ne $intelStartupValueName) {
        throw 'The saved Intel startup registry target is invalid.'
    }
    if ('SchemaVersion' -in $backup.PSObject.Properties.Name -and
        [int]$backup.SchemaVersion -notin @(1, 2, 3, 4)) {
        throw 'The saved Intel startup entry uses an unsupported schema.'
    }

    $originalEntryPresent = Test-OriginalIntelStartupEntryPresent -Backup $backup
    if (-not $originalEntryPresent) {
        if ([int]$backup.SchemaVersion -eq 4 -and
            [string]::IsNullOrEmpty([string]$backup.Command)) {
            return $backup
        }
        # Version 2.0.2 could save an absent original entry together with a
        # verified canonical Intel command. Keep supporting that schema.
    }

    foreach ($property in @('Command', 'Executable', 'Arguments', 'SignerThumbprint')) {
        if ($property -notin $backup.PSObject.Properties.Name) {
            throw "The saved Intel startup identity is invalid: missing $property."
        }
    }

    $startupMode = $Action -eq 'ApplyStartup'
    $resolved = Resolve-IntelGraphicsStartupCommand -Command ([string]$backup.Command) -SkipAuthenticode:$startupMode
    if ($resolved.Executable -ne [string]$backup.Executable -or
        $resolved.Arguments -ne [string]$backup.Arguments) {
        throw 'The saved Intel startup command no longer passes verification.'
    }

    $hasPinnedIdentity = (
        'FileSha256' -in $backup.PSObject.Properties.Name -and
        'FileVersion' -in $backup.PSObject.Properties.Name -and
        'SchemaVersion' -in $backup.PSObject.Properties.Name -and
        [int]$backup.SchemaVersion -in @(2, 3, 4)
    )
    $hashChanged = -not $hasPinnedIdentity -or
        $resolved.FileSha256 -ne [string]$backup.FileSha256
    $signerChanged = -not $startupMode -and
        $resolved.SignerThumbprint -ne [string]$backup.SignerThumbprint

    if ($hashChanged -or $signerChanged) {
        # A graphics-driver update can replace IntelGraphicsSoftware.exe. Trust
        # is renewed only after a fresh Authenticode check of the canonical
        # Intel path; a changed hash by itself is never accepted.
        $verifiedUpdate = Resolve-IntelGraphicsStartupCommand -Command ([string]$backup.Command)
        if ($verifiedUpdate.Executable -ne [string]$backup.Executable -or
            $verifiedUpdate.Arguments -ne [string]$backup.Arguments) {
            throw 'The updated Intel Graphics Software command no longer matches the saved command.'
        }
        $stableHash = Get-FileSha256 -LiteralPath $verifiedUpdate.Executable
        if ($stableHash -ne $verifiedUpdate.FileSha256) {
            throw 'Intel Graphics Software changed while its signed update was being verified. Startup reapply was cancelled.'
        }
        $backup = Set-IntelStartupTrustedIdentity -ExistingBackup $backup -Resolved $verifiedUpdate
        $script:intelStartupIdentityRenewed = $true
    }

    $final = Resolve-IntelGraphicsStartupCommand -Command ([string]$backup.Command) -SkipAuthenticode
    if ($final.FileSha256 -ne [string]$backup.FileSha256) {
        throw 'Intel Graphics Software no longer matches the trusted identity after verification.'
    }
    return $backup
}

function Get-IntelStartupRegistryValue {
    try {
        $key = Get-Item -LiteralPath $intelStartupRegistryPath -ErrorAction Stop
        if ($intelStartupValueName -notin @($key.GetValueNames())) {
            return $null
        }
        return [string]$key.GetValue(
            $intelStartupValueName,
            $null,
            [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
        )
    }
    catch [Management.Automation.ItemNotFoundException] {
        return $null
    }
}

function Test-OriginalIntelStartupEntryPresent {
    param([Parameter(Mandatory)][object]$Backup)

    if ('OriginalEntryPresent' -in $Backup.PSObject.Properties.Name) {
        return [bool]$Backup.OriginalEntryPresent
    }
    # Schemas 1 and 2 were only created from an existing Intel Run value.
    return $true
}

function Get-IntelStartupOrderState {
    $backup = Get-IntelStartupBackup
    $current = Get-IntelStartupRegistryValue
    if ($null -eq $backup) {
        if ([string]::IsNullOrEmpty($current)) {
            return 'MISSING_WITHOUT_BACKUP'
        }
        [void](Resolve-IntelGraphicsStartupCommand -Command $current)
        return 'INTEL_DEFAULT'
    }
    if ([string]::IsNullOrEmpty($current)) {
        return 'CLAWLAB_ORDERED'
    }
    if ($current -eq [string]$backup.Command) {
        if (Test-OriginalIntelStartupEntryPresent -Backup $backup) {
            return 'ORIGINAL_STILL_PRESENT'
        }
        return 'MANAGED_COMMAND_REAPPEARED'
    }
    try {
        # Intel Graphics Software/driver updates can legitimately rewrite the
        # Run value while ClawLab owns startup ordering. Treat it as an Intel
        # update only after a fresh canonical-path and Authenticode proof. An
        # arbitrary or unsigned replacement remains UNKNOWN and fail-closed.
        [void](Resolve-IntelGraphicsStartupCommand -Command $current)
        return 'SIGNED_INTEL_ENTRY_UPDATED'
    }
    catch {
        return 'UNKNOWN_STARTUP_ENTRY'
    }
}

function Set-ManagedIntelStartupOrder {
    $backup = Get-IntelStartupBackup
    $current = Get-IntelStartupRegistryValue

    if ($null -eq $backup) {
        if ([string]::IsNullOrEmpty($current)) {
            [IO.Directory]::CreateDirectory($stateRoot) | Out-Null
            [void](Set-IntelStartupAbsentState)
            $backup = Get-IntelStartupBackup
        }
        else {
            $resolved = Resolve-IntelGraphicsStartupCommand -Command $current
            [IO.Directory]::CreateDirectory($stateRoot) | Out-Null
            [void](Set-IntelStartupTrustedIdentity -ExistingBackup $null -Resolved $resolved -OriginalEntryPresent $true)
            $backup = Get-IntelStartupBackup
        }
    }
    elseif (-not [string]::IsNullOrEmpty($current) -and $current -ne [string]$backup.Command) {
        try {
            $resolvedUpdate = Resolve-IntelGraphicsStartupCommand -Command $current
        }
        catch {
            throw 'An unknown Intel Graphics Software startup entry is present. It was not modified.'
        }

        # The updater reintroduced a freshly signed canonical Intel entry. It
        # is now the state that must be restored after ClawLab is removed, even
        # when Intel Graphics Software was absent at the original installation.
        if ('OriginalEntryPresent' -in $backup.PSObject.Properties.Name) {
            $backup.OriginalEntryPresent = $true
        }
        else {
            $backup | Add-Member -NotePropertyName OriginalEntryPresent -NotePropertyValue $true
        }
        $backup = Set-IntelStartupTrustedIdentity -ExistingBackup $backup `
            -Resolved $resolvedUpdate -OriginalEntryPresent $true
        if ([string]$backup.Command -ne $current -or
            (Get-IntelStartupRegistryValue) -ne $current) {
            throw 'Intel Graphics Software changed while its signed startup update was being adopted.'
        }
        Write-Warning 'A newly signed Intel Graphics Software startup entry was adopted after a verified Intel update.'
    }

    if (-not [string]::IsNullOrEmpty($current)) {
        Remove-ItemProperty -LiteralPath $intelStartupRegistryPath -Name $intelStartupValueName -ErrorAction Stop
    }
    if ((Get-IntelStartupOrderState) -ne 'CLAWLAB_ORDERED') {
        throw 'Could not establish the verified ClawLab Intel startup order.'
    }
}

function Restore-IntelStartupOrder {
    $backup = Get-IntelStartupBackup
    if ($null -eq $backup) {
        return
    }
    $current = Get-IntelStartupRegistryValue
    $originalEntryPresent = Test-OriginalIntelStartupEntryPresent -Backup $backup
    $signedIntelUpdatePresent = $false
    if (-not [string]::IsNullOrEmpty($current) -and $current -ne [string]$backup.Command) {
        try {
            [void](Resolve-IntelGraphicsStartupCommand -Command $current)
            $signedIntelUpdatePresent = $true
        }
        catch {
            throw 'An unknown Intel Graphics Software startup entry is present. The saved entry was not restored.'
        }
    }

    if ($signedIntelUpdatePresent) {
        # Do not replace a newer, independently verified Intel Run entry with a
        # stale command saved before a driver/IGS update. Leaving it untouched
        # restores normal Intel startup ownership without needing the old ZIP.
        Write-Warning 'A newer signed Intel Graphics Software startup entry is present and was preserved.'
        Remove-FileIfPresent -LiteralPath $intelStartupBackupPath
        return
    }
    if ($originalEntryPresent) {
        New-ItemProperty -LiteralPath $intelStartupRegistryPath -Name $intelStartupValueName `
            -PropertyType String -Value ([string]$backup.Command) -Force | Out-Null
        if ((Get-IntelStartupRegistryValue) -ne [string]$backup.Command) {
            throw 'The original Intel Graphics Software startup entry could not be verified after restoration.'
        }
    }
    else {
        if (-not [string]::IsNullOrEmpty($current)) {
            Write-Warning 'Intel Graphics Software gained a startup entry after installation. The external entry was preserved.'
        }
    }
    Remove-FileIfPresent -LiteralPath $intelStartupBackupPath
}

function Get-FactoryIntelStartupCommand {
    $current = Get-IntelStartupRegistryValue
    if (-not [string]::IsNullOrEmpty($current)) {
        [void](Resolve-IntelGraphicsStartupCommand -Command $current)
        return $current
    }

    if (Test-Path -LiteralPath $intelStartupBackupPath -PathType Leaf) {
        try {
            $backup = Get-IntelStartupBackup
            if ($null -ne $backup) {
                if (-not (Test-OriginalIntelStartupEntryPresent -Backup $backup)) {
                    return $null
                }
                return [string]$backup.Command
            }
        }
        catch {
            Write-Warning "The saved Intel startup entry is unusable; attempting signed factory-path recovery: $($_.Exception.Message)"
        }
    }

    $executable = Join-Path $env:ProgramFiles 'Intel\Intel Graphics Software\IntelGraphicsSoftware.exe'
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        return $null
    }
    $command = '"{0}" -s' -f $executable
    [void](Resolve-IntelGraphicsStartupCommand -Command $command)
    return $command
}

function Set-FactoryIntelStartupCommand {
    param([AllowNull()][string]$Command)

    if ([string]::IsNullOrEmpty($Command)) {
        if (-not [string]::IsNullOrEmpty((Get-IntelStartupRegistryValue))) {
            throw 'Factory reset expected Intel Graphics Software startup to remain absent, but an entry is present.'
        }
        return
    }

    [void](Resolve-IntelGraphicsStartupCommand -Command $Command)
    $current = Get-IntelStartupRegistryValue
    if (-not [string]::IsNullOrEmpty($current) -and $current -ne $Command) {
        throw 'An unexpected Intel Graphics Software startup entry appeared during factory reset. It was not overwritten.'
    }
    if ([string]::IsNullOrEmpty($current)) {
        New-ItemProperty -LiteralPath $intelStartupRegistryPath -Name $intelStartupValueName `
            -PropertyType String -Value $Command -Force | Out-Null
    }
    if ((Get-IntelStartupRegistryValue) -ne $Command) {
        throw 'Factory reset could not verify the Intel Graphics Software startup entry.'
    }
}

function Start-ManagedIntelGraphicsSoftware {
    $backup = Get-IntelStartupBackup
    if ($null -eq $backup) {
        return
    }
    if (-not (Test-OriginalIntelStartupEntryPresent -Backup $backup)) {
        return
    }
    if ($null -ne (Get-Process -Name 'IntelGraphicsSoftware' -ErrorAction SilentlyContinue)) {
        return
    }
    $resolved = Resolve-IntelGraphicsStartupCommand -Command ([string]$backup.Command)
    if ($resolved.FileSha256 -ne [string]$backup.FileSha256 -or
        $resolved.SignerThumbprint -ne [string]$backup.SignerThumbprint) {
        throw 'Intel Graphics Software changed between trust verification and launch.'
    }
    try {
        Start-Process -FilePath $resolved.Executable -ArgumentList $resolved.Arguments -WindowStyle Hidden
    }
    catch {
        # Starting the optional Intel UI can be rejected with Win32
        # ERROR_CANCELLED (1223), for example when its own elevation request is
        # dismissed. That must not prevent the independent Arc Sync setter and
        # readback below from running. Trust/identity failures above and every
        # other launch error remain fatal.
        $exception = $_.Exception
        $userCancelled = $false
        for ($depth = 0; $depth -lt 6 -and $null -ne $exception; $depth++) {
            if ($exception -is [System.ComponentModel.Win32Exception] -and
                [int]$exception.NativeErrorCode -eq 1223) {
                $userCancelled = $true
                break
            }
            $exception = $exception.InnerException
        }
        if (-not $userCancelled) {
            throw
        }
        $script:intelGraphicsLaunchWarning = 'Intel Graphics Software launch was cancelled by Windows or the user; VRR validation continued independently.'
        Write-Warning $script:intelGraphicsLaunchWarning
    }
}

function Add-ArcSyncControlType {
    if ($null -ne ('ClawLab.VrrFix.ArcSyncControl' -as [type])) {
        return
    }

    $controlLibrary = Join-Path $env:SystemRoot 'System32\ControlLib.dll'
    if (-not (Test-Path -LiteralPath $controlLibrary -PathType Leaf)) {
        throw 'Intel Control Library (ControlLib.dll) is missing. Install a current Intel graphics driver first.'
    }

    $source = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace ClawLab.VrrFix
{
    [StructLayout(LayoutKind.Sequential)]
    public struct CtlApplicationId
    {
        public UInt32 Data1;
        public UInt16 Data2;
        public UInt16 Data3;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 8)]
        public byte[] Data4;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct CtlInitArgs
    {
        public UInt32 Size;
        public byte Version;
        public UInt32 AppVersion;
        public UInt32 Flags;
        public UInt32 SupportedVersion;
        public CtlApplicationId ApplicationUid;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct ArcSyncMonitorParams
    {
        public UInt32 Size;
        public byte Version;
        [MarshalAs(UnmanagedType.U1)] public bool IsSupported;
        public float MinimumRefreshRateInHz;
        public float MaximumRefreshRateInHz;
        public UInt32 MaxFrameTimeIncreaseInUs;
        public UInt32 MaxFrameTimeDecreaseInUs;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct ArcSyncProfileParams
    {
        public UInt32 Size;
        public byte Version;
        public Int32 Profile;
        public float MaxRefreshRateInHz;
        public float MinRefreshRateInHz;
        public UInt32 MaxFrameTimeIncreaseInUs;
        public UInt32 MaxFrameTimeDecreaseInUs;
    }

    public sealed class ArcSyncSnapshot
    {
        public int AdapterIndex { get; set; }
        public int DisplayIndex { get; set; }
        public int MonitorResult { get; set; }
        public bool Supported { get; set; }
        public float MonitorMinimumHz { get; set; }
        public float MonitorMaximumHz { get; set; }
        public UInt32 MonitorMaxIncreaseUs { get; set; }
        public UInt32 MonitorMaxDecreaseUs { get; set; }
        public int ProfileResult { get; set; }
        public int ProfileId { get; set; }
        public string ProfileName { get; set; }
        public float ActiveMinimumHz { get; set; }
        public float ActiveMaximumHz { get; set; }
        public UInt32 ActiveMaxIncreaseUs { get; set; }
        public UInt32 ActiveMaxDecreaseUs { get; set; }
    }

    public static class ArcSyncControl
    {
        [DllImport("ControlLib.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int ctlInit(ref CtlInitArgs args, out IntPtr api);

        [DllImport("ControlLib.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int ctlClose(IntPtr api);

        [DllImport("ControlLib.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int ctlEnumerateDevices(IntPtr api, ref UInt32 count, IntPtr devices);

        [DllImport("ControlLib.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int ctlEnumerateDisplayOutputs(IntPtr adapter, ref UInt32 count, IntPtr displays);

        [DllImport("ControlLib.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int ctlGetIntelArcSyncInfoForMonitor(IntPtr display, ref ArcSyncMonitorParams parameters);

        [DllImport("ControlLib.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int ctlGetIntelArcSyncProfile(IntPtr display, ref ArcSyncProfileParams parameters);

        [DllImport("ControlLib.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int ctlSetIntelArcSyncProfile(IntPtr display, ref ArcSyncProfileParams parameters);

        private static CtlInitArgs CreateInitArgs()
        {
            return new CtlInitArgs
            {
                Size = (UInt32)Marshal.SizeOf(typeof(CtlInitArgs)),
                Version = 0,
                AppVersion = 0x00010001,
                Flags = 0,
                ApplicationUid = new CtlApplicationId { Data4 = new byte[8] }
            };
        }

        private static string GetProfileName(int profile)
        {
            string[] names = { "INVALID", "RECOMMENDED", "EXCELLENT", "GOOD", "COMPATIBLE", "OFF", "VESA", "CUSTOM" };
            return profile >= 0 && profile < names.Length ? names[profile] : "UNKNOWN_" + profile;
        }

        public static ArcSyncSnapshot[] Query()
        {
            List<ArcSyncSnapshot> results = new List<ArcSyncSnapshot>();
            CtlInitArgs init = CreateInitArgs();
            IntPtr api;
            int result = ctlInit(ref init, out api);
            if (result != 0)
                throw new InvalidOperationException("ctlInit failed: 0x" + result.ToString("X8"));

            IntPtr adapters = IntPtr.Zero;
            try
            {
                UInt32 adapterCount = 0;
                result = ctlEnumerateDevices(api, ref adapterCount, IntPtr.Zero);
                if (result != 0)
                    throw new InvalidOperationException("ctlEnumerateDevices(count) failed: 0x" + result.ToString("X8"));

                adapters = Marshal.AllocHGlobal(checked((int)adapterCount * IntPtr.Size));
                result = ctlEnumerateDevices(api, ref adapterCount, adapters);
                if (result != 0)
                    throw new InvalidOperationException("ctlEnumerateDevices(list) failed: 0x" + result.ToString("X8"));

                for (int adapterIndex = 0; adapterIndex < adapterCount; adapterIndex++)
                {
                    IntPtr adapter = Marshal.ReadIntPtr(adapters, adapterIndex * IntPtr.Size);
                    UInt32 displayCount = 0;
                    result = ctlEnumerateDisplayOutputs(adapter, ref displayCount, IntPtr.Zero);
                    if (result != 0 || displayCount == 0)
                        continue;

                    IntPtr displays = Marshal.AllocHGlobal(checked((int)displayCount * IntPtr.Size));
                    try
                    {
                        result = ctlEnumerateDisplayOutputs(adapter, ref displayCount, displays);
                        if (result != 0)
                            continue;

                        for (int displayIndex = 0; displayIndex < displayCount; displayIndex++)
                        {
                            IntPtr display = Marshal.ReadIntPtr(displays, displayIndex * IntPtr.Size);
                            ArcSyncMonitorParams monitor = new ArcSyncMonitorParams
                            {
                                Size = (UInt32)Marshal.SizeOf(typeof(ArcSyncMonitorParams)),
                                Version = 0
                            };
                            int monitorResult = ctlGetIntelArcSyncInfoForMonitor(display, ref monitor);

                            ArcSyncProfileParams profile = new ArcSyncProfileParams
                            {
                                Size = (UInt32)Marshal.SizeOf(typeof(ArcSyncProfileParams)),
                                Version = 0
                            };
                            int profileResult = ctlGetIntelArcSyncProfile(display, ref profile);

                            results.Add(new ArcSyncSnapshot
                            {
                                AdapterIndex = adapterIndex,
                                DisplayIndex = displayIndex,
                                MonitorResult = monitorResult,
                                Supported = monitor.IsSupported,
                                MonitorMinimumHz = monitor.MinimumRefreshRateInHz,
                                MonitorMaximumHz = monitor.MaximumRefreshRateInHz,
                                MonitorMaxIncreaseUs = monitor.MaxFrameTimeIncreaseInUs,
                                MonitorMaxDecreaseUs = monitor.MaxFrameTimeDecreaseInUs,
                                ProfileResult = profileResult,
                                ProfileId = profile.Profile,
                                ProfileName = GetProfileName(profile.Profile),
                                ActiveMinimumHz = profile.MinRefreshRateInHz,
                                ActiveMaximumHz = profile.MaxRefreshRateInHz,
                                ActiveMaxIncreaseUs = profile.MaxFrameTimeIncreaseInUs,
                                ActiveMaxDecreaseUs = profile.MaxFrameTimeDecreaseInUs
                            });
                        }
                    }
                    finally
                    {
                        Marshal.FreeHGlobal(displays);
                    }
                }
            }
            finally
            {
                if (adapters != IntPtr.Zero)
                    Marshal.FreeHGlobal(adapters);
                ctlClose(api);
            }
            return results.ToArray();
        }

        public static int SetProfile(int targetAdapterIndex, int targetDisplayIndex,
            float expectedMonitorMinimumHz, float expectedMonitorMaximumHz, int profileId,
            float minimumHz, float maximumHz, UInt32 maxIncreaseUs, UInt32 maxDecreaseUs)
        {
            CtlInitArgs init = CreateInitArgs();
            IntPtr api;
            int result = ctlInit(ref init, out api);
            if (result != 0)
                return result;

            IntPtr adapters = IntPtr.Zero;
            try
            {
                UInt32 adapterCount = 0;
                result = ctlEnumerateDevices(api, ref adapterCount, IntPtr.Zero);
                if (result != 0)
                    return result;
                if (targetAdapterIndex < 0 || targetAdapterIndex >= adapterCount)
                    return -1001;

                adapters = Marshal.AllocHGlobal(checked((int)adapterCount * IntPtr.Size));
                result = ctlEnumerateDevices(api, ref adapterCount, adapters);
                if (result != 0)
                    return result;

                IntPtr adapter = Marshal.ReadIntPtr(adapters, targetAdapterIndex * IntPtr.Size);
                UInt32 displayCount = 0;
                result = ctlEnumerateDisplayOutputs(adapter, ref displayCount, IntPtr.Zero);
                if (result != 0)
                    return result;
                if (targetDisplayIndex < 0 || targetDisplayIndex >= displayCount)
                    return -1002;

                IntPtr displays = Marshal.AllocHGlobal(checked((int)displayCount * IntPtr.Size));
                try
                {
                    result = ctlEnumerateDisplayOutputs(adapter, ref displayCount, displays);
                    if (result != 0)
                        return result;

                    IntPtr display = Marshal.ReadIntPtr(displays, targetDisplayIndex * IntPtr.Size);
                    ArcSyncMonitorParams monitor = new ArcSyncMonitorParams
                    {
                        Size = (UInt32)Marshal.SizeOf(typeof(ArcSyncMonitorParams)),
                        Version = 0
                    };
                    result = ctlGetIntelArcSyncInfoForMonitor(display, ref monitor);
                    if (result != 0 || !monitor.IsSupported)
                        return result != 0 ? result : -1003;
                    if (Math.Abs(monitor.MinimumRefreshRateInHz - expectedMonitorMinimumHz) > 0.1f ||
                        Math.Abs(monitor.MaximumRefreshRateInHz - expectedMonitorMaximumHz) > 0.1f)
                        return -1004;

                    ArcSyncProfileParams profile = new ArcSyncProfileParams
                    {
                        Size = (UInt32)Marshal.SizeOf(typeof(ArcSyncProfileParams)),
                        Version = 0,
                        Profile = profileId,
                        MinRefreshRateInHz = minimumHz,
                        MaxRefreshRateInHz = maximumHz,
                        MaxFrameTimeIncreaseInUs = maxIncreaseUs,
                        MaxFrameTimeDecreaseInUs = maxDecreaseUs
                    };
                    return ctlSetIntelArcSyncProfile(display, ref profile);
                }
                finally
                {
                    Marshal.FreeHGlobal(displays);
                }
            }
            finally
            {
                if (adapters != IntPtr.Zero)
                    Marshal.FreeHGlobal(adapters);
                ctlClose(api);
            }
        }
    }
}
'@

    Add-Type -TypeDefinition $source -Language CSharp
}

function Add-DisplayModeControlType {
    if ($null -ne ('ClawLab.VrrFix.DisplayModeControl' -as [type])) {
        return
    }

    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace ClawLab.VrrFix
{
    public sealed class DisplayModeSnapshot
    {
        public int Width { get; set; }
        public int Height { get; set; }
        public int RefreshHz { get; set; }
    }

    public static class DisplayModeControl
    {
        private const int ENUM_CURRENT_SETTINGS = -1;
        private const int DM_DISPLAYFREQUENCY = 0x00400000;
        private const int CDS_UPDATEREGISTRY = 0x00000001;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct DEVMODE
        {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
            public short dmSpecVersion;
            public short dmDriverVersion;
            public short dmSize;
            public short dmDriverExtra;
            public int dmFields;
            public int dmPositionX;
            public int dmPositionY;
            public int dmDisplayOrientation;
            public int dmDisplayFixedOutput;
            public short dmColor;
            public short dmDuplex;
            public short dmYResolution;
            public short dmTTOption;
            public short dmCollate;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
            public short dmLogPixels;
            public int dmBitsPerPel;
            public int dmPelsWidth;
            public int dmPelsHeight;
            public int dmDisplayFlags;
            public int dmDisplayFrequency;
            public int dmICMMethod;
            public int dmICMIntent;
            public int dmMediaType;
            public int dmDitherType;
            public int dmReserved1;
            public int dmReserved2;
            public int dmPanningWidth;
            public int dmPanningHeight;
        }

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int ChangeDisplaySettingsEx(string deviceName, ref DEVMODE devMode, IntPtr hwnd, int flags, IntPtr param);

        [DllImport("user32.dll")]
        private static extern int GetSystemMetrics(int index);

        public static int ActiveDisplayCount()
        {
            const int SM_CMONITORS = 80;
            return GetSystemMetrics(SM_CMONITORS);
        }

        private static DEVMODE NewMode()
        {
            DEVMODE mode = new DEVMODE();
            mode.dmDeviceName = new string('\0', 32);
            mode.dmFormName = new string('\0', 32);
            mode.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
            return mode;
        }

        public static DisplayModeSnapshot Current()
        {
            DEVMODE mode = NewMode();
            if (!EnumDisplaySettings(null, ENUM_CURRENT_SETTINGS, ref mode))
                throw new InvalidOperationException("EnumDisplaySettings(current) failed.");
            return new DisplayModeSnapshot
            {
                Width = mode.dmPelsWidth,
                Height = mode.dmPelsHeight,
                RefreshHz = mode.dmDisplayFrequency
            };
        }

        public static bool HasMode(int width, int height, int refreshHz)
        {
            for (int index = 0; index < 1024; index++)
            {
                DEVMODE mode = NewMode();
                if (!EnumDisplaySettings(null, index, ref mode))
                    break;
                if (mode.dmPelsWidth == width && mode.dmPelsHeight == height && mode.dmDisplayFrequency == refreshHz)
                    return true;
            }
            return false;
        }

        public static int SetRefresh(int refreshHz)
        {
            DEVMODE mode = NewMode();
            if (!EnumDisplaySettings(null, ENUM_CURRENT_SETTINGS, ref mode))
                throw new InvalidOperationException("EnumDisplaySettings(current) failed.");
            mode.dmFields = DM_DISPLAYFREQUENCY;
            mode.dmDisplayFrequency = refreshHz;
            return ChangeDisplaySettingsEx(null, ref mode, IntPtr.Zero, CDS_UPDATEREGISTRY, IntPtr.Zero);
        }
    }
}
'@
}

function Get-CurrentDisplayMode {
    $mode = [ClawLab.VrrFix.DisplayModeControl]::Current()
    return [pscustomobject]@{
        Width = [int]$mode.Width
        Height = [int]$mode.Height
        RefreshHz = [int]$mode.RefreshHz
    }
}

function Set-VerifiedDisplayRefresh {
    param([Parameter(Mandatory)][int]$RefreshHz)

    if ($null -eq $script:activePanelDefinition) {
        throw 'The active panel definition is unavailable.'
    }
    $width = [int]$script:activePanelDefinition.Width
    $height = [int]$script:activePanelDefinition.Height
    $activeDisplayCount = [ClawLab.VrrFix.DisplayModeControl]::ActiveDisplayCount()
    if ($activeDisplayCount -ne 1) {
        throw "Exactly one active display is required for a guarded refresh-rate change; found $activeDisplayCount. Disconnect every external display and retry."
    }
    $current = Get-CurrentDisplayMode
    if ($current.Width -ne $width -or $current.Height -ne $height) {
        throw "The validated internal panel must be the active primary display at ${width}x${height}. Disconnect external displays and retry."
    }
    if (-not [ClawLab.VrrFix.DisplayModeControl]::HasMode($width, $height, $RefreshHz)) {
        throw "The validated ${width}x${height} $RefreshHz Hz Windows display mode is not available."
    }

    if ($current.Width -eq $width -and $current.Height -eq $height -and $current.RefreshHz -eq $RefreshHz) {
        return $current
    }
    $result = [ClawLab.VrrFix.DisplayModeControl]::SetRefresh($RefreshHz)
    if ($result -notin @(0, 1)) {
        throw "Windows rejected the $RefreshHz Hz display mode with code $result."
    }
    Start-Sleep -Seconds 1
    $after = Get-CurrentDisplayMode
    if ($after.Width -ne $width -or $after.Height -ne $height -or $after.RefreshHz -ne $RefreshHz) {
        throw "Windows did not activate ${width}x${height} at $RefreshHz Hz; current mode is $($after.Width)x$($after.Height) at $($after.RefreshHz) Hz."
    }
    return $after
}

function Set-Safe120DisplayMode {
    Set-VerifiedDisplayRefresh -RefreshHz 120
}

function Get-TargetSnapshot {
    param([int]$Attempts = 1)

    $lastError = $null
    $telemetryExpectedMinimumHz = -1.0
    $telemetryExpectedMaximumHz = -1.0
    $managedTelemetryRecord = Get-ManagedModeRecord
    if ($null -ne $managedTelemetryRecord -and
        [string]$managedTelemetryRecord.FixVersion -eq $fixVersion -and
        $null -ne $script:activePanelDefinition -and
        [string]$managedTelemetryRecord.PanelKey -eq [string]$script:activePanelDefinition.Key) {
        $managedTelemetryRange = Get-ManagedModeExpectedRange `
            -Mode ([string]$managedTelemetryRecord.Mode)
        $telemetryExpectedMinimumHz = [float]$managedTelemetryRange.MinimumHz
        $telemetryExpectedMaximumHz = [float]$managedTelemetryRange.MaximumHz
    }
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            $candidates = @(
                [ClawLab.VrrFix.ArcSyncControl]::Query() |
                    Where-Object {
                        $_.MonitorResult -eq 0 -and
                        $_.ProfileResult -eq 0 -and
                        $_.Supported
                    }
            )
            if ($candidates.Count -eq 1) {
                $telemetryState = Get-ClawLabArcSyncMonitorRangeState `
                    -PanelKey ([string]$script:activePanelDefinition.Key) `
                    -MonitorMinimumHz ([float]$candidates[0].MonitorMinimumHz) `
                    -MonitorMaximumHz ([float]$candidates[0].MonitorMaximumHz) `
                    -ExpectedMinimumHz $telemetryExpectedMinimumHz `
                    -ExpectedMaximumHz $telemetryExpectedMaximumHz `
                    -PhysicalMinimumHz $targetMinimumHz -CustomMinimumHz $experimentalMinimumHz `
                    -SupportedMaximumHz $targetMaximumHz -LegacyRecoveryMaximumHz $experimentalMaximumHz
                if ($telemetryState -eq 'UNSUPPORTED') {
                    throw "Unexpected Arc Sync monitor range: $($candidates[0].MonitorMinimumHz)-$($candidates[0].MonitorMaximumHz) Hz."
                }
                return $candidates[0]
            }
            $lastError = "Expected exactly one active Intel Arc Sync output; found $($candidates.Count). Disconnect external VRR displays and retry."
        }
        catch {
            $lastError = $_.Exception.Message
        }

        if ($attempt -lt $Attempts) {
            Start-Sleep -Milliseconds 500
        }
    }
    throw "$lastError No display setting was changed."
}

function Get-OriginalProfile {
    if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
        return $null
    }
    $backup = [IO.File]::ReadAllText($backupPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($property in @(
        'SchemaVersion',
        'FixVersion',
        'BaselinePolicy',
        'PanelKey',
        'PhysicalEdidSha256',
        'EdidOverrideStateAtSave',
        'ProfileId',
        'ProfileName',
        'MinRefreshRateInHz',
        'MaxRefreshRateInHz',
        'MaxFrameTimeIncreaseInUs',
        'MaxFrameTimeDecreaseInUs'
    )) {
        if ($property -notin $backup.PSObject.Properties.Name) {
            throw "The saved original profile is invalid: missing $property. No display setting was changed."
        }
    }
    if ([int]$backup.ProfileId -lt 1 -or [int]$backup.ProfileId -gt 7) {
        throw 'The saved original profile ID is invalid. No display setting was changed.'
    }
    if ([string]$backup.FixVersion -ne $fixVersion -or [int]$backup.SchemaVersion -ne 2) {
        throw 'The saved original profile belongs to another ClawLab release. Use that release to restore it before installing 2.3.0.'
    }
    if ($null -eq $script:activePanelDefinition -or
        [string]$backup.PanelKey -ne [string]$script:activePanelDefinition.Key -or
        [string]$backup.PhysicalEdidSha256 -ne [string]$script:activePanelDefinition.PhysicalEdidSha256) {
        throw 'The saved original profile does not match the validated physical panel. No display setting was changed.'
    }
    if ([string]$backup.EdidOverrideStateAtSave -ne 'NONE') {
        throw 'The saved original profile was not captured from the physical EDID state. No display setting was changed.'
    }
    if ([string]$backup.BaselinePolicy -eq 'INTEL_STANDARD_BASELINE') {
        if ([int]$backup.ProfileId -notin @(1, 2)) {
            throw 'The saved Intel standard baseline contains a non-standard profile ID.'
        }
    }
    elseif ([string]$backup.BaselinePolicy -eq 'TMA2027_VERIFIED_CUSTOM_30_120') {
        if (-not (Test-ClawLabKnownTma2027Custom30Profile `
                -PanelKey ([string]$backup.PanelKey) `
                -TelemetryState 'INTEL_CONTROL_LIB_HALF_PHYSICAL_FLOOR' `
                -ProfileId ([int]$backup.ProfileId) `
                -MinimumHz ([float]$backup.MinRefreshRateInHz) `
                -MaximumHz ([float]$backup.MaxRefreshRateInHz) `
                -MaxIncreaseUs ([uint32]$backup.MaxFrameTimeIncreaseInUs) `
                -MaxDecreaseUs ([uint32]$backup.MaxFrameTimeDecreaseInUs))) {
            throw 'The saved TMA2027 custom baseline is not the exact validated 30-120 profile.'
        }
    }
    else {
        throw "Unknown saved original baseline policy: $($backup.BaselinePolicy)"
    }
    return $backup
}

function Save-OriginalProfile {
    param(
        [Parameter(Mandatory)][object]$Snapshot,
        [Parameter(Mandatory)][object]$Panel,
        [Parameter(Mandatory)][object]$Gpu,
        [ValidateSet('INTEL_STANDARD_BASELINE', 'TMA2027_VERIFIED_CUSTOM_30_120')]
        [string]$BaselinePolicy = 'INTEL_STANDARD_BASELINE'
    )

    if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
        [void](Get-OriginalProfile)
        return
    }

    if ([string]$Panel.Definition.Key -ne [string]$script:activePanelDefinition.Key -or
        [string]$Panel.Definition.PhysicalEdidSha256 -ne [string]$script:activePanelDefinition.PhysicalEdidSha256) {
        throw 'The original profile cannot be saved for a panel identity that is not currently active.'
    }
    if ($BaselinePolicy -eq 'INTEL_STANDARD_BASELINE' -and [int]$Snapshot.ProfileId -notin @(1, 2)) {
        throw 'A non-standard Intel profile cannot be saved as an Intel standard baseline.'
    }
    if ($BaselinePolicy -eq 'TMA2027_VERIFIED_CUSTOM_30_120') {
        $telemetryState = Get-ClawLabArcSyncMonitorRangeState `
            -PanelKey ([string]$Panel.Definition.Key) `
            -MonitorMinimumHz ([float]$Snapshot.MonitorMinimumHz) `
            -MonitorMaximumHz ([float]$Snapshot.MonitorMaximumHz) `
            -PhysicalMinimumHz $targetMinimumHz -CustomMinimumHz $experimentalMinimumHz `
            -SupportedMaximumHz $targetMaximumHz -LegacyRecoveryMaximumHz $experimentalMaximumHz
        if (-not (Test-ClawLabKnownTma2027Custom30Profile `
                -PanelKey ([string]$Panel.Definition.Key) -TelemetryState $telemetryState `
                -ProfileId ([int]$Snapshot.ProfileId) `
                -MinimumHz ([float]$Snapshot.ActiveMinimumHz) `
                -MaximumHz ([float]$Snapshot.ActiveMaximumHz) `
                -MaxIncreaseUs ([uint32]$Snapshot.ActiveMaxIncreaseUs) `
                -MaxDecreaseUs ([uint32]$Snapshot.ActiveMaxDecreaseUs))) {
            throw 'The current Intel profile is not the exact verified TMA2027 CUSTOM 30-120 baseline.'
        }
    }

    [IO.Directory]::CreateDirectory($stateRoot) | Out-Null
    $backup = [ordered]@{
        SchemaVersion = 2
        FixVersion = $fixVersion
        BaselinePolicy = $BaselinePolicy
        SavedAt = (Get-Date).ToString('o')
        PanelKey = [string]$Panel.Definition.Key
        PhysicalEdidSha256 = [string]$Panel.Definition.PhysicalEdidSha256
        EdidOverrideStateAtSave = 'NONE'
        PanelInstanceName = $Panel.InstanceName
        PanelName = $Panel.Name
        IntelDriverVersion = [string]$Gpu.DriverVersion
        ProfileId = $Snapshot.ProfileId
        ProfileName = $Snapshot.ProfileName
        MinRefreshRateInHz = $Snapshot.ActiveMinimumHz
        MaxRefreshRateInHz = $Snapshot.ActiveMaximumHz
        MaxFrameTimeIncreaseInUs = $Snapshot.ActiveMaxIncreaseUs
        MaxFrameTimeDecreaseInUs = $Snapshot.ActiveMaxDecreaseUs
    }
    Write-ClawLabJsonAtomically -LiteralPath $backupPath -Value $backup
    $verified = Get-OriginalProfile
    if ([string]$verified.BaselinePolicy -ne $BaselinePolicy -or
        -not (Test-SnapshotMatchesSavedProfile -Snapshot $Snapshot -Profile $verified)) {
        throw 'The saved original Intel Arc Sync profile failed atomic readback verification.'
    }
    Complete-NormalizationCompensationAfterBackup -Panel $Panel -Gpu $Gpu `
        -CurrentTarget $Snapshot
}

function Invoke-SetProfile {
    param(
        [Parameter(Mandatory)][object]$Target,
        [Parameter(Mandatory)][int]$ProfileId,
        [float]$MinimumHz = 0,
        [float]$MaximumHz = 0,
        [uint32]$MaxIncreaseUs = 0,
        [uint32]$MaxDecreaseUs = 0
    )

    $result = 0
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $result = [ClawLab.VrrFix.ArcSyncControl]::SetProfile(
            [int]$Target.AdapterIndex,
            [int]$Target.DisplayIndex,
            [float]$Target.MonitorMinimumHz,
            [float]$Target.MonitorMaximumHz,
            $ProfileId,
            $MinimumHz,
            $MaximumHz,
            $MaxIncreaseUs,
            $MaxDecreaseUs
        )
        if ($result -eq 0) {
            return
        }

        # Intel documents these as transient device/KMD/retry conditions. A
        # fresh ControlLib session is created by every SetProfile call.
        if ($result -notin @(0x40000003, 0x40000017, 0x40000027, 0x40010000) -or $attempt -eq 3) {
            break
        }
        Start-Sleep -Milliseconds 750
    }

    switch ([int]$result) {
        -1001 { throw 'The previously selected Intel Arc Sync adapter disappeared before the profile write. No profile change was verified.' }
        -1002 { throw 'The previously selected Intel Arc Sync display disappeared before the profile write. Disconnect external displays and retry.' }
        -1003 { throw 'The selected display stopped reporting Intel Arc Sync support before the profile write.' }
        -1004 { throw 'Intel Arc Sync monitor telemetry changed between validation and the profile write. No profile change was verified.' }
        0x40000017 { throw 'Intel ctlSetIntelArcSyncProfile reached the driver, but the Intel kernel-mode driver rejected the request (CTL_RESULT_ERROR_KMD_CALL, 0x40000017).' }
        default { throw ('Intel ctlSetIntelArcSyncProfile failed with code 0x{0:X8}.' -f ([uint32]$result)) }
    }
}

function Test-SnapshotMatchesSavedProfile {
    param(
        [Parameter(Mandatory)][object]$Snapshot,
        [Parameter(Mandatory)][object]$Profile
    )

    return Test-ClawLabSnapshotMatchesSavedProfile `
        -CurrentProfileId ([int]$Snapshot.ProfileId) `
        -CurrentMinimumHz ([float]$Snapshot.ActiveMinimumHz) `
        -CurrentMaximumHz ([float]$Snapshot.ActiveMaximumHz) `
        -CurrentMaxIncreaseUs ([uint32]$Snapshot.ActiveMaxIncreaseUs) `
        -CurrentMaxDecreaseUs ([uint32]$Snapshot.ActiveMaxDecreaseUs) `
        -SavedProfileId ([int]$Profile.ProfileId) `
        -SavedMinimumHz ([float]$Profile.MinRefreshRateInHz) `
        -SavedMaximumHz ([float]$Profile.MaxRefreshRateInHz) `
        -SavedMaxIncreaseUs ([uint32]$Profile.MaxFrameTimeIncreaseInUs) `
        -SavedMaxDecreaseUs ([uint32]$Profile.MaxFrameTimeDecreaseInUs)
}

function Test-ManagedArcSyncSnapshot {
    param(
        [Parameter(Mandatory)][object]$Snapshot,
        [Parameter(Mandatory)][string]$PanelKey,
        [Parameter(Mandatory)][string]$Mode,
        [Parameter(Mandatory)][string]$Policy,
        [Parameter(Mandatory)][float]$ExpectedMinimumHz,
        [Parameter(Mandatory)][float]$ExpectedMaximumHz
    )

    $telemetryState = Get-ClawLabArcSyncMonitorRangeState `
        -PanelKey $PanelKey `
        -MonitorMinimumHz ([float]$Snapshot.MonitorMinimumHz) `
        -MonitorMaximumHz ([float]$Snapshot.MonitorMaximumHz) `
        -ExpectedMinimumHz $ExpectedMinimumHz -ExpectedMaximumHz $ExpectedMaximumHz `
        -PhysicalMinimumHz $targetMinimumHz -CustomMinimumHz $experimentalMinimumHz `
        -SupportedMaximumHz $targetMaximumHz -LegacyRecoveryMaximumHz $experimentalMaximumHz
    if (-not (Test-ClawLabArcSyncMonitorRangeCompatible `
            -PanelKey $PanelKey `
            -MonitorMinimumHz ([float]$Snapshot.MonitorMinimumHz) `
            -MonitorMaximumHz ([float]$Snapshot.MonitorMaximumHz) `
            -ExpectedMinimumHz $ExpectedMinimumHz -ExpectedMaximumHz $ExpectedMaximumHz `
            -PhysicalMinimumHz $targetMinimumHz -CustomMinimumHz $experimentalMinimumHz `
            -SupportedMaximumHz $targetMaximumHz -LegacyRecoveryMaximumHz $experimentalMaximumHz)) {
        return $false
    }

    Test-ClawLabManagedArcSyncSnapshot -Policy $Policy -PanelKey $PanelKey -Mode $Mode `
        -TelemetryState $telemetryState `
        -ProfileId ([int]$Snapshot.ProfileId) `
        -MinimumHz ([float]$Snapshot.ActiveMinimumHz) `
        -MaximumHz ([float]$Snapshot.ActiveMaximumHz) `
        -MaxIncreaseUs ([uint32]$Snapshot.ActiveMaxIncreaseUs) `
        -MaxDecreaseUs ([uint32]$Snapshot.ActiveMaxDecreaseUs) `
        -ExpectedMinimumHz $ExpectedMinimumHz -ExpectedMaximumHz $ExpectedMaximumHz
}

function Get-FactoryResetDecisionForSnapshot {
    param(
        [Parameter(Mandatory)][object]$Panel,
        [Parameter(Mandatory)][object]$Snapshot
    )

    $telemetryState = Get-ClawLabArcSyncMonitorRangeState `
        -PanelKey ([string]$Panel.Definition.Key) `
        -MonitorMinimumHz ([float]$Snapshot.MonitorMinimumHz) `
        -MonitorMaximumHz ([float]$Snapshot.MonitorMaximumHz) `
        -PhysicalMinimumHz $targetMinimumHz -CustomMinimumHz $experimentalMinimumHz `
        -SupportedMaximumHz $targetMaximumHz -LegacyRecoveryMaximumHz $experimentalMaximumHz
    return Get-ClawLabFactoryResetProfileDecision `
        -PanelKey ([string]$Panel.Definition.Key) -TelemetryState $telemetryState `
        -ProfileId ([int]$Snapshot.ProfileId) `
        -MinimumHz ([float]$Snapshot.ActiveMinimumHz) `
        -MaximumHz ([float]$Snapshot.ActiveMaximumHz) `
        -MaxIncreaseUs ([uint32]$Snapshot.ActiveMaxIncreaseUs) `
        -MaxDecreaseUs ([uint32]$Snapshot.ActiveMaxDecreaseUs)
}

function Assert-OrphanedDefaultVrrShellCleanupAllowed {
    param(
        [Parameter(Mandatory)][object]$Panel,
        [Parameter(Mandatory)][object]$Snapshot,
        [Parameter(Mandatory)][object]$OverrideState
    )

    if ($null -ne (Get-OriginalProfile)) {
        throw 'Orphaned-state cleanup refused because an original VRR backup exists.'
    }
    if ([string]$OverrideState.State -ne 'NONE') {
        throw "Orphaned-state cleanup requires no EDID override; current state is $([string]$OverrideState.State)."
    }

    $managed = Get-EffectiveManagedMode -OverrideState $OverrideState
    if ([string]$managed.Mode -ne 'LEGACY_MANAGED_STATE' -or
        [string]$managed.State -ne 'RESTORE_REQUIRED' -or
        [string]$managed.Source -ne 'MANAGED_ARTIFACTS') {
        throw "Orphaned-state cleanup refused the managed identity: $([string]$managed.Mode) / $([string]$managed.State) / $([string]$managed.Source)."
    }

    $artifacts = Get-ManagedArtifactSnapshot
    if ([bool]$artifacts.OriginalProfile -or
        [bool]$artifacts.NormalizationCompensation -or
        [bool]$artifacts.ExperimentalState -or
        [bool]$artifacts.IntelStartupBackup) {
        throw 'Orphaned-state cleanup found recovery-bearing VRR metadata and will not discard it.'
    }
    if (Test-Path -LiteralPath $managedModeStatePath -PathType Leaf) {
        throw 'Orphaned-state cleanup found a managed-mode record and will not infer its missing original backup.'
    }
    if (Test-Path -LiteralPath $experimentalTrialStatePath -PathType Leaf) {
        throw 'Orphaned-state cleanup found a guarded-trial state and will not discard it.'
    }
    if (Test-Path -LiteralPath $protectedRuntimeRoot) {
        throw 'Orphaned-state cleanup found a protected guarded-trial runtime and will not discard it.'
    }

    $startupState = Get-StartupReapplyState
    if ($startupState -notin @('TASK_INVALID', 'TASK_WITHOUT_FILES')) {
        throw "Orphaned-state cleanup expected one stale startup task; current state is $startupState."
    }
    $startupTask = Get-ClawLabScheduledTaskRecord -TaskName $startupTaskName
    if ($null -eq $startupTask -or
        -not (Test-ClawLabScheduledTaskOwned -Record $startupTask -Spec (Get-VrrStartupTaskSpec))) {
        throw 'The stale startup task is not provably owned by ClawLab and was not removed.'
    }
    if ($null -ne (Get-ClawLabScheduledTaskRecord -TaskName $cursorRefreshTaskName) -or
        $null -ne (Get-ClawLabScheduledTaskRecord -TaskName $experimentalTrialTaskName)) {
        throw 'Orphaned-state cleanup found another managed task and requires explicit recovery.'
    }
    if ((Get-CursorRefreshHelperState) -ne 'NOT_INSTALLED') {
        throw 'Orphaned-state cleanup found a desktop helper state and requires explicit recovery.'
    }

    $intelStartupState = Get-IntelStartupOrderState
    if ($intelStartupState -notin @('INTEL_DEFAULT', 'MISSING_WITHOUT_BACKUP')) {
        throw "Orphaned-state cleanup found an unsafe Intel Graphics Software startup state: $intelStartupState."
    }

    $telemetryState = Get-ClawLabArcSyncMonitorRangeState `
        -PanelKey ([string]$Panel.Definition.Key) `
        -MonitorMinimumHz ([float]$Snapshot.MonitorMinimumHz) `
        -MonitorMaximumHz ([float]$Snapshot.MonitorMaximumHz) `
        -PhysicalMinimumHz $targetMinimumHz -CustomMinimumHz $experimentalMinimumHz `
        -SupportedMaximumHz $targetMaximumHz -LegacyRecoveryMaximumHz $experimentalMaximumHz
    if (-not (Test-ClawLabKnownUnmanagedFactoryProfile `
            -PanelKey ([string]$Panel.Definition.Key) -TelemetryState $telemetryState `
            -ProfileId ([int]$Snapshot.ProfileId) `
            -MinimumHz ([float]$Snapshot.ActiveMinimumHz) `
            -MaximumHz ([float]$Snapshot.ActiveMaximumHz) `
            -MaxIncreaseUs ([uint32]$Snapshot.ActiveMaxIncreaseUs) `
            -MaxDecreaseUs ([uint32]$Snapshot.ActiveMaxDecreaseUs))) {
        throw "Orphaned-state cleanup could not prove the exact unmanaged Intel factory profile: $($Snapshot.ProfileName) $($Snapshot.ActiveMinimumHz)-$($Snapshot.ActiveMaximumHz) Hz, timings $($Snapshot.ActiveMaxIncreaseUs)/$($Snapshot.ActiveMaxDecreaseUs) us."
    }

    $displayMode = Get-CurrentDisplayMode
    if ([int]$displayMode.Width -ne [int]$Panel.Definition.Width -or
        [int]$displayMode.Height -ne [int]$Panel.Definition.Height -or
        [int]$displayMode.RefreshHz -ne 120) {
        throw "Orphaned-state cleanup requires the validated native 120 Hz mode; current mode is $($displayMode.Width)x$($displayMode.Height) at $($displayMode.RefreshHz) Hz."
    }

    return [pscustomobject]@{
        ManagedMode = [string]$managed.Mode
        StartupState = $startupState
        IntelStartupState = $intelStartupState
        FactoryProfile = [string]$Snapshot.ProfileName
        FactoryRange = '{0:0.#}-{1:0.#} Hz' -f $Snapshot.ActiveMinimumHz, $Snapshot.ActiveMaximumHz
    }
}

function Get-VerifiedManagedArcSyncSnapshot {
    param(
        [Parameter(Mandatory)][object]$Target,
        [Parameter(Mandatory)][string]$PanelKey,
        [Parameter(Mandatory)][string]$Mode,
        [Parameter(Mandatory)][string]$Policy,
        [Parameter(Mandatory)][float]$ExpectedMinimumHz,
        [Parameter(Mandatory)][float]$ExpectedMaximumHz,
        [switch]$AllowExcellentWrite
    )

    $snapshot = $Target
    if (Test-ManagedArcSyncSnapshot -Snapshot $snapshot -PanelKey $PanelKey -Mode $Mode `
            -Policy $Policy -ExpectedMinimumHz $ExpectedMinimumHz -ExpectedMaximumHz $ExpectedMaximumHz) {
        return $snapshot
    }
    if ($Policy -eq 'TMA2027_PRESERVE_EXACT_CUSTOM_30_120') {
        throw "The exact TMA2027 CUSTOM 30-120 profile drifted and was not rewritten automatically: $($snapshot.ProfileName), $($snapshot.ActiveMinimumHz)-$($snapshot.ActiveMaximumHz) Hz, timings $($snapshot.ActiveMaxIncreaseUs)/$($snapshot.ActiveMaxDecreaseUs) us. Restore or reinstall after collecting diagnostics."
    }
    if (-not $AllowExcellentWrite) {
        throw "Intel EXCELLENT is not active at $ExpectedMinimumHz-$ExpectedMaximumHz Hz. No profile write was requested."
    }

    Invoke-SetProfile -Target $snapshot -ProfileId $profileExcellent
    for ($attempt = 1; $attempt -le 10; $attempt++) {
        Start-Sleep -Milliseconds 500
        $snapshot = Get-TargetSnapshot -Attempts 3
        if (Test-ManagedArcSyncSnapshot -Snapshot $snapshot -PanelKey $PanelKey -Mode $Mode `
                -Policy $Policy -ExpectedMinimumHz $ExpectedMinimumHz -ExpectedMaximumHz $ExpectedMaximumHz) {
            return $snapshot
        }
    }
    throw "Intel profile verification failed: expected EXCELLENT $ExpectedMinimumHz-$ExpectedMaximumHz Hz, got $($snapshot.ProfileName) $($snapshot.ActiveMinimumHz)-$($snapshot.ActiveMaximumHz) Hz."
}

function Assert-KnownTma2027CustomBaselineEnvironment {
    param(
        [Parameter(Mandatory)][object]$Panel,
        [Parameter(Mandatory)][object]$RegistryContext,
        [Parameter(Mandatory)][object]$Snapshot
    )

    if ([string]$Panel.Definition.Key -ne 'CLAW_A1M_CLAW_7_AI_PLUS' -or
        [string]$RegistryContext.PhysicalEdidSha256 -ne [string]$Panel.Definition.PhysicalEdidSha256) {
        throw 'The TMA2027 custom-baseline path requires the exact pinned physical panel EDID.'
    }
    $telemetryState = Get-ClawLabArcSyncMonitorRangeState `
        -PanelKey ([string]$Panel.Definition.Key) `
        -MonitorMinimumHz ([float]$Snapshot.MonitorMinimumHz) `
        -MonitorMaximumHz ([float]$Snapshot.MonitorMaximumHz) `
        -PhysicalMinimumHz $targetMinimumHz -CustomMinimumHz $experimentalMinimumHz `
        -SupportedMaximumHz $targetMaximumHz -LegacyRecoveryMaximumHz $experimentalMaximumHz
    if (-not (Test-ClawLabKnownTma2027Custom30Profile `
            -PanelKey ([string]$Panel.Definition.Key) -TelemetryState $telemetryState `
            -ProfileId ([int]$Snapshot.ProfileId) `
            -MinimumHz ([float]$Snapshot.ActiveMinimumHz) `
            -MaximumHz ([float]$Snapshot.ActiveMaximumHz) `
            -MaxIncreaseUs ([uint32]$Snapshot.ActiveMaxIncreaseUs) `
            -MaxDecreaseUs ([uint32]$Snapshot.ActiveMaxDecreaseUs))) {
        throw 'The active Intel profile is no longer the exact TMA2027 OEM CUSTOM 30-120 baseline.'
    }
    $displayMode = Get-CurrentDisplayMode
    if ($displayMode.Width -ne [int]$Panel.Definition.Width -or
        $displayMode.Height -ne [int]$Panel.Definition.Height -or
        $displayMode.RefreshHz -ne 120) {
        throw "This TMA2027 driver state must be installed from the native $($Panel.Definition.Width)x$($Panel.Definition.Height) at 120 Hz Windows mode. Current mode is $($displayMode.Width)x$($displayMode.Height) at $($displayMode.RefreshHz) Hz. No setting was changed."
    }

    $driverInterfacePath = Join-Path $PSScriptRoot 'Intel-VRR-LFC-Driver-Interface.ps1'
    if (-not (Test-Path -LiteralPath $driverInterfacePath -PathType Leaf)) {
        throw 'The direct Intel VRR verification component is missing.'
    }
    $directResults = @(& $driverInterfacePath -Action Status)
    $direct = if ($directResults.Count -gt 0) { $directResults[-1] } else { $null }
    if ($null -eq $direct -or [uint32]$direct.NtStatus -ne 0 -or
        [uint32]$direct.DisplayCount -ne 1 -or -not [bool]$direct.Supported -or
        -not [bool]$direct.Enabled -or [uint32]$direct.MinimumHz -ne 48 -or
        [uint32]$direct.MaximumHz -ne 120 -or
        -not [bool]$direct.LowFpsSolutionEnabled -or
        -not [bool]$direct.HighFpsSolutionEnabled) {
        $details = if ($null -eq $direct) { 'no direct Intel state' } else { $direct | ConvertTo-Json -Compress }
        throw "The exact TMA2027 CUSTOM baseline was not paired with a clean direct Intel 48-120 VRR/LFC state: $details"
    }
}

function Resolve-FirstInstallProfileBaseline {
    param(
        [Parameter(Mandatory)][object]$Panel,
        [Parameter(Mandatory)][object]$Gpu,
        [Parameter(Mandatory)][object]$RegistryContext,
        [Parameter(Mandatory)][object]$OverrideState,
        [Parameter(Mandatory)][string]$DesiredMode,
        [Parameter(Mandatory)][object]$Transition,
        [Parameter(Mandatory)][object]$Snapshot
    )

    $telemetryState = Get-ClawLabArcSyncMonitorRangeState `
        -PanelKey ([string]$Panel.Definition.Key) `
        -MonitorMinimumHz ([float]$Snapshot.MonitorMinimumHz) `
        -MonitorMaximumHz ([float]$Snapshot.MonitorMaximumHz) `
        -PhysicalMinimumHz $targetMinimumHz -CustomMinimumHz $experimentalMinimumHz `
        -SupportedMaximumHz $targetMaximumHz -LegacyRecoveryMaximumHz $experimentalMaximumHz
    $decision = Get-ClawLabFirstInstallBaselineDecision `
        -PanelKey ([string]$Panel.Definition.Key) `
        -CurrentMode ([string]$Transition.Mode) -CurrentState ([string]$Transition.State) `
        -OverrideState ([string]$OverrideState.State) -DesiredMode $DesiredMode `
        -TelemetryState $telemetryState -ProfileId ([int]$Snapshot.ProfileId) `
        -MinimumHz ([float]$Snapshot.ActiveMinimumHz) -MaximumHz ([float]$Snapshot.ActiveMaximumHz) `
        -MaxIncreaseUs ([uint32]$Snapshot.ActiveMaxIncreaseUs) `
        -MaxDecreaseUs ([uint32]$Snapshot.ActiveMaxDecreaseUs)

    if ($decision -eq 'MANAGED_REPAIR') {
        $managed = Get-ManagedModeRecord
        if ($null -eq $managed -or [string]$managed.Mode -ne $DesiredMode) {
            throw 'The managed repair has no matching current-version policy record.'
        }
        return [pscustomobject]@{
            Snapshot = $Snapshot
            BaselinePolicy = [string](Get-OriginalProfile).BaselinePolicy
            ManagedArcSyncPolicy = [string]$managed.ArcSyncPolicy
            Decision = $decision
        }
    }
    if ($decision -eq 'STANDARD_PROFILE') {
        return [pscustomobject]@{
            Snapshot = $Snapshot
            BaselinePolicy = 'INTEL_STANDARD_BASELINE'
            ManagedArcSyncPolicy = 'INTEL_EXCELLENT_REQUIRED'
            Decision = $decision
        }
    }
    if ($decision -eq 'TMA2027_PRESERVE_EXACT_CUSTOM_30_120') {
        Confirm-AdministratorOrRelaunch
        Assert-KnownTma2027CustomBaselineEnvironment -Panel $Panel -RegistryContext $RegistryContext -Snapshot $Snapshot
        Write-Host 'Verified the exact A1M/Claw 7 AI+ OEM CUSTOM 30-120 baseline.' -ForegroundColor Green
        Write-Host 'ClawLab will preserve this profile and will not call the rejected Intel RECOMMENDED/EXCELLENT setters.' -ForegroundColor Yellow
        return [pscustomobject]@{
            Snapshot = $Snapshot
            BaselinePolicy = 'TMA2027_VERIFIED_CUSTOM_30_120'
            ManagedArcSyncPolicy = 'TMA2027_PRESERVE_EXACT_CUSTOM_30_120'
            Decision = $decision
        }
    }
    if ($decision -eq 'REFUSE_TMA2027_CUSTOM_FOR_MODE') {
        throw 'This exact TMA2027 driver preserves CUSTOM 30-120 and rejects Intel EXCELLENT. Version 2.3.0 can safely preserve it only for the stable 30-120 profile; 48-120 and display overclocks remain blocked on this driver state. No setting was changed.'
    }
    if ($decision -eq 'REFUSE_UNSAFE_TMA2027_CUSTOM') {
        throw "The A1M/Claw 7 AI+ exposes an unknown CUSTOM profile ($($Snapshot.ActiveMinimumHz)-$($Snapshot.ActiveMaximumHz) Hz, timings $($Snapshot.ActiveMaxIncreaseUs)/$($Snapshot.ActiveMaxDecreaseUs) us). It was not adopted or modified."
    }

    # RECOMMENDED and EXCELLENT are Intel driver API profiles; current Intel
    # Graphics Software builds do not expose a UI control that can select them.
    # A clean first install therefore normalizes an otherwise unowned CUSTOM
    # profile itself, verifies the standard profile, and only then saves the
    # restorable baseline. The unknown CUSTOM values are never adopted.
    Confirm-AdministratorOrRelaunch
    Write-Host 'A clean first installation found an unmanaged Intel Arc Sync CUSTOM profile.' -ForegroundColor Yellow
    Write-Host 'Intel Graphics Software cannot select the internal RECOMMENDED/EXCELLENT profiles manually.' -ForegroundColor Yellow
    Write-Host 'ClawLab will establish and verify an Intel standard profile before creating its original-profile backup.' -ForegroundColor Yellow
    $normalized = $Snapshot
    $normalizationVerified = $false
    $normalizationResults = [Collections.Generic.List[string]]::new()
    $normalizationRecord = New-NormalizationCompensationRecord -Panel $Panel `
        -Gpu $Gpu -Snapshot $Snapshot
    foreach ($candidate in @(
            [pscustomobject]@{ ProfileId = $profileRecommended; Name = 'RECOMMENDED' },
            [pscustomobject]@{ ProfileId = $profileExcellent; Name = 'EXCELLENT' }
        )) {
        try {
            $normalizationRecord = Set-NormalizationCompensationPhase `
                -Record $normalizationRecord -Phase MUTATION_ATTEMPTED `
                -CandidateName ([string]$candidate.Name)
            Invoke-SetProfile -Target $normalized -ProfileId ([int]$candidate.ProfileId)
            Start-Sleep -Milliseconds 750
            for ($readbackAttempt = 1; $readbackAttempt -le 10; $readbackAttempt++) {
                Start-Sleep -Milliseconds 500
                $normalized = Get-TargetSnapshot -Attempts 3
                Assert-NormalizationCompensationIdentity -Record $normalizationRecord `
                    -Panel $Panel -Gpu $Gpu -Target $normalized
                if ([int]$normalized.ProfileId -eq [int]$candidate.ProfileId) { break }
            }
            if ([int]$normalized.ProfileId -eq [int]$candidate.ProfileId) {
                $normalizationRecord = Set-NormalizationCompensationPhase `
                    -Record $normalizationRecord -Phase NORMALIZED_VERIFIED `
                    -CandidateName ([string]$candidate.Name)
                $normalizationVerified = $true
                Write-Host "The Intel $($candidate.Name) first-install baseline is active and verified." -ForegroundColor Green
                break
            }
            $normalizationResults.Add("$($candidate.Name) returned success but read back as $($normalized.ProfileName)")
        }
        catch {
            $normalizationResults.Add("$($candidate.Name) failed: $($_.Exception.Message)")
            try { $normalized = Get-TargetSnapshot -Attempts 10 } catch { $normalized = $Snapshot }
        }
        try {
            $normalized = Invoke-NormalizationCompensationRestore -Panel $Panel `
                -Gpu $Gpu -CurrentTarget $normalized -RetainJournal
            $normalizationRecord = Get-NormalizationCompensationRecord
        }
        catch {
            throw "Intel $($candidate.Name) normalization failed and the exact original profile could not be recovered: $($_.Exception.Message) The compensation journal was retained."
        }
    }
    if (-not $normalizationVerified) {
        try {
            [void](Invoke-NormalizationCompensationRestore -Panel $Panel `
                -Gpu $Gpu -CurrentTarget $normalized)
        }
        catch {
            throw "Could not verify an automatic Intel RECOMMENDED or EXCELLENT baseline. Attempts: $($normalizationResults -join ' | '). Exact compensation also failed: $($_.Exception.Message)"
        }
        throw "Could not verify an automatic Intel RECOMMENDED or EXCELLENT baseline. Attempts: $($normalizationResults -join ' | '). The original unmanaged profile was restored and verified; no ClawLab original-profile backup was created."
    }
    return [pscustomobject]@{
        Snapshot = $normalized
        BaselinePolicy = 'INTEL_STANDARD_BASELINE'
        ManagedArcSyncPolicy = 'INTEL_EXCELLENT_REQUIRED'
        Decision = 'STANDARD_PROFILE_NORMALIZED'
    }
}

function Restore-SnapshotProfile {
    param(
        [Parameter(Mandatory)][object]$Target,
        [Parameter(Mandatory)][object]$Profile
    )

    if ([int]$Profile.ProfileId -eq $profileCustom) {
        Invoke-SetProfile -Target $Target -ProfileId ([int]$Profile.ProfileId) `
            -MinimumHz ([float]$Profile.MinRefreshRateInHz) `
            -MaximumHz ([float]$Profile.MaxRefreshRateInHz) `
            -MaxIncreaseUs ([uint32]$Profile.MaxFrameTimeIncreaseInUs) `
            -MaxDecreaseUs ([uint32]$Profile.MaxFrameTimeDecreaseInUs)
    }
    else {
        Invoke-SetProfile -Target $Target -ProfileId ([int]$Profile.ProfileId)
    }
}

function Test-NormalizationTargetIdentity {
    param(
        [Parameter(Mandatory)][object]$Snapshot,
        [Parameter(Mandatory)][object]$SavedTarget
    )

    return [int]$Snapshot.AdapterIndex -eq [int]$SavedTarget.AdapterIndex -and
        [int]$Snapshot.DisplayIndex -eq [int]$SavedTarget.DisplayIndex -and
        (Test-ClawLabFrequencyEqual -Left ([float]$Snapshot.MonitorMinimumHz) `
            -Right ([float]$SavedTarget.MonitorMinimumHz)) -and
        (Test-ClawLabFrequencyEqual -Left ([float]$Snapshot.MonitorMaximumHz) `
            -Right ([float]$SavedTarget.MonitorMaximumHz)) -and
        [uint32]$Snapshot.MonitorMaxIncreaseUs -eq [uint32]$SavedTarget.MonitorMaxIncreaseUs -and
        [uint32]$Snapshot.MonitorMaxDecreaseUs -eq [uint32]$SavedTarget.MonitorMaxDecreaseUs
}

function Test-NormalizationProfileExact {
    param(
        [Parameter(Mandatory)][object]$Snapshot,
        [Parameter(Mandatory)][object]$SavedProfile
    )

    return [int]$Snapshot.ProfileId -eq [int]$SavedProfile.ProfileId -and
        ([string]$Snapshot.ProfileName).Equals(
            [string]$SavedProfile.ProfileName, [StringComparison]::OrdinalIgnoreCase) -and
        (Test-ClawLabFrequencyEqual -Left ([float]$Snapshot.ActiveMinimumHz) `
            -Right ([float]$SavedProfile.MinRefreshRateInHz)) -and
        (Test-ClawLabFrequencyEqual -Left ([float]$Snapshot.ActiveMaximumHz) `
            -Right ([float]$SavedProfile.MaxRefreshRateInHz)) -and
        [uint32]$Snapshot.ActiveMaxIncreaseUs -eq [uint32]$SavedProfile.MaxFrameTimeIncreaseInUs -and
        [uint32]$Snapshot.ActiveMaxDecreaseUs -eq [uint32]$SavedProfile.MaxFrameTimeDecreaseInUs
}

function Get-NormalizationCompensationRecord {
    if (-not (Test-Path -LiteralPath $normalizationCompensationPath -PathType Leaf)) {
        return $null
    }

    $record = [IO.File]::ReadAllText(
        $normalizationCompensationPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($property in @(
            'SchemaVersion', 'FixVersion', 'Phase', 'CreatedAt', 'UpdatedAt',
            'Panel', 'Gpu', 'Target', 'OriginalProfile'
        )) {
        if ($property -notin $record.PSObject.Properties.Name) {
            throw "The Intel normalization compensation journal is invalid: missing $property."
        }
    }
    if ([int]$record.SchemaVersion -ne 1 -or
        [string]$record.FixVersion -ne $fixVersion -or
        [string]$record.Phase -notin @(
            'PREPARED', 'MUTATION_ATTEMPTED', 'NORMALIZED_VERIFIED',
            'RESTORE_ATTEMPTED', 'RESTORE_VERIFIED', 'BACKUP_VERIFIED'
        )) {
        throw 'The Intel normalization compensation journal has an unsupported identity or phase.'
    }
    foreach ($property in @(
            'Key', 'Manufacturer', 'ProductCode', 'Name', 'InstanceName',
            'PhysicalEdidSha256'
        )) {
        if ($property -notin $record.Panel.PSObject.Properties.Name) {
            throw "The Intel normalization compensation panel identity is invalid: missing $property."
        }
    }
    foreach ($property in @('Name', 'PnpDeviceId', 'DriverVersion')) {
        if ($property -notin $record.Gpu.PSObject.Properties.Name) {
            throw "The Intel normalization compensation GPU identity is invalid: missing $property."
        }
    }
    foreach ($property in @(
            'AdapterIndex', 'DisplayIndex', 'MonitorMinimumHz', 'MonitorMaximumHz',
            'MonitorMaxIncreaseUs', 'MonitorMaxDecreaseUs'
        )) {
        if ($property -notin $record.Target.PSObject.Properties.Name) {
            throw "The Intel normalization compensation target identity is invalid: missing $property."
        }
    }
    foreach ($property in @(
            'ProfileId', 'ProfileName', 'MinRefreshRateInHz', 'MaxRefreshRateInHz',
            'MaxFrameTimeIncreaseInUs', 'MaxFrameTimeDecreaseInUs'
        )) {
        if ($property -notin $record.OriginalProfile.PSObject.Properties.Name) {
            throw "The Intel normalization compensation snapshot is invalid: missing $property."
        }
    }
    if ([string]$record.Panel.PhysicalEdidSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or
        [string]::IsNullOrWhiteSpace([string]$record.Panel.InstanceName) -or
        [string]::IsNullOrWhiteSpace([string]$record.Gpu.PnpDeviceId) -or
        [string]::IsNullOrWhiteSpace([string]$record.Gpu.DriverVersion) -or
        [int]$record.Target.AdapterIndex -lt 0 -or
        [int]$record.Target.DisplayIndex -lt 0 -or
        [int]$record.OriginalProfile.ProfileId -lt 1 -or
        [int]$record.OriginalProfile.ProfileId -gt 7 -or
        [float]::IsNaN([float]$record.Target.MonitorMinimumHz) -or
        [float]::IsNaN([float]$record.Target.MonitorMaximumHz) -or
        [float]::IsNaN([float]$record.OriginalProfile.MinRefreshRateInHz) -or
        [float]::IsNaN([float]$record.OriginalProfile.MaxRefreshRateInHz) -or
        [float]$record.Target.MonitorMinimumHz -le 0 -or
        [float]$record.Target.MonitorMaximumHz -lt [float]$record.Target.MonitorMinimumHz -or
        [float]$record.OriginalProfile.MinRefreshRateInHz -lt 0 -or
        [float]$record.OriginalProfile.MaxRefreshRateInHz -lt
            [float]$record.OriginalProfile.MinRefreshRateInHz) {
        throw 'The Intel normalization compensation journal contains invalid values.'
    }
    return $record
}

function Assert-NormalizationCompensationIdentity {
    param(
        [Parameter(Mandatory)][object]$Record,
        [Parameter(Mandatory)][object]$Panel,
        [Parameter(Mandatory)][object]$Gpu,
        [Parameter(Mandatory)][object]$Target
    )

    $panelMatches = [string]$Record.Panel.Key -eq [string]$Panel.Definition.Key -and
        [string]$Record.Panel.Manufacturer -eq [string]$Panel.Manufacturer -and
        [string]$Record.Panel.ProductCode -eq [string]$Panel.ProductCode -and
        [string]$Record.Panel.Name -eq [string]$Panel.Name -and
        [string]$Record.Panel.InstanceName -eq [string]$Panel.InstanceName -and
        [string]$Record.Panel.PhysicalEdidSha256 -eq
            [string]$Panel.Definition.PhysicalEdidSha256
    $gpuMatches = ([string]$Record.Gpu.Name).Equals(
            [string]$Gpu.Name, [StringComparison]::OrdinalIgnoreCase) -and
        ([string]$Record.Gpu.PnpDeviceId).Equals(
            [string]$Gpu.PNPDeviceID, [StringComparison]::OrdinalIgnoreCase) -and
        ([string]$Record.Gpu.DriverVersion).Equals(
            [string]$Gpu.DriverVersion, [StringComparison]::OrdinalIgnoreCase)
    if (-not $panelMatches -or -not $gpuMatches -or
        -not (Test-NormalizationTargetIdentity -Snapshot $Target -SavedTarget $Record.Target)) {
        throw 'The Intel normalization compensation journal does not match the exact active panel, GPU, driver and Arc Sync target. It was retained without a profile write.'
    }
}

function Set-NormalizationCompensationPhase {
    param(
        [Parameter(Mandatory)][object]$Record,
        [Parameter(Mandatory)][ValidateSet(
            'PREPARED', 'MUTATION_ATTEMPTED', 'NORMALIZED_VERIFIED',
            'RESTORE_ATTEMPTED', 'RESTORE_VERIFIED', 'BACKUP_VERIFIED'
        )][string]$Phase,
        [AllowNull()][string]$CandidateName = $null
    )

    $Record | Add-Member -NotePropertyName Phase -NotePropertyValue $Phase -Force
    $Record | Add-Member -NotePropertyName UpdatedAt `
        -NotePropertyValue (Get-Date).ToString('o') -Force
    if (-not [string]::IsNullOrWhiteSpace($CandidateName)) {
        $Record | Add-Member -NotePropertyName CandidateName `
            -NotePropertyValue $CandidateName -Force
    }
    Write-ClawLabJsonAtomically -LiteralPath $normalizationCompensationPath -Value $Record
    $verified = Get-NormalizationCompensationRecord
    if ($null -eq $verified -or [string]$verified.Phase -ne $Phase) {
        throw "The Intel normalization compensation phase failed atomic readback: $Phase"
    }
    return $verified
}

function New-NormalizationCompensationRecord {
    param(
        [Parameter(Mandatory)][object]$Panel,
        [Parameter(Mandatory)][object]$Gpu,
        [Parameter(Mandatory)][object]$Snapshot
    )

    if (Test-Path -LiteralPath $normalizationCompensationPath -PathType Leaf) {
        throw 'A previous Intel normalization compensation journal is still present. Run verified Restore before retrying.'
    }
    if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
        throw 'Intel normalization cannot begin after an original-profile backup already exists.'
    }

    $now = (Get-Date).ToString('o')
    $record = [ordered]@{
        SchemaVersion = 1
        FixVersion = $fixVersion
        Phase = 'PREPARED'
        CreatedAt = $now
        UpdatedAt = $now
        Panel = [ordered]@{
            Key = [string]$Panel.Definition.Key
            Manufacturer = [string]$Panel.Manufacturer
            ProductCode = [string]$Panel.ProductCode
            Name = [string]$Panel.Name
            InstanceName = [string]$Panel.InstanceName
            PhysicalEdidSha256 = [string]$Panel.Definition.PhysicalEdidSha256
        }
        Gpu = [ordered]@{
            Name = [string]$Gpu.Name
            PnpDeviceId = [string]$Gpu.PNPDeviceID
            DriverVersion = [string]$Gpu.DriverVersion
        }
        Target = [ordered]@{
            AdapterIndex = [int]$Snapshot.AdapterIndex
            DisplayIndex = [int]$Snapshot.DisplayIndex
            MonitorMinimumHz = [float]$Snapshot.MonitorMinimumHz
            MonitorMaximumHz = [float]$Snapshot.MonitorMaximumHz
            MonitorMaxIncreaseUs = [uint32]$Snapshot.MonitorMaxIncreaseUs
            MonitorMaxDecreaseUs = [uint32]$Snapshot.MonitorMaxDecreaseUs
        }
        OriginalProfile = [ordered]@{
            ProfileId = [int]$Snapshot.ProfileId
            ProfileName = [string]$Snapshot.ProfileName
            MinRefreshRateInHz = [float]$Snapshot.ActiveMinimumHz
            MaxRefreshRateInHz = [float]$Snapshot.ActiveMaximumHz
            MaxFrameTimeIncreaseInUs = [uint32]$Snapshot.ActiveMaxIncreaseUs
            MaxFrameTimeDecreaseInUs = [uint32]$Snapshot.ActiveMaxDecreaseUs
        }
    }
    Write-ClawLabJsonAtomically -LiteralPath $normalizationCompensationPath -Value $record
    $verified = Get-NormalizationCompensationRecord
    Assert-NormalizationCompensationIdentity -Record $verified -Panel $Panel -Gpu $Gpu -Target $Snapshot
    if (-not (Test-NormalizationProfileExact -Snapshot $Snapshot `
            -SavedProfile $verified.OriginalProfile)) {
        throw 'The Intel normalization compensation snapshot failed atomic readback verification.'
    }
    $script:normalizationCompensationContext = [pscustomobject]@{
        Panel = $Panel
        Gpu = $Gpu
    }
    return $verified
}

function Remove-NormalizationCompensationRecord {
    Remove-FileIfPresent -LiteralPath $normalizationCompensationPath
    if (Test-Path -LiteralPath $normalizationCompensationPath -PathType Leaf) {
        throw 'The verified Intel normalization compensation journal could not be removed.'
    }
    $script:normalizationCompensationContext = $null
}

function Invoke-NormalizationCompensationRestore {
    param(
        [Parameter(Mandatory)][object]$Panel,
        [Parameter(Mandatory)][object]$Gpu,
        [Parameter(Mandatory)][object]$CurrentTarget,
        [switch]$RetainJournal
    )

    $record = Get-NormalizationCompensationRecord
    if ($null -eq $record) { return $CurrentTarget }
    Assert-NormalizationCompensationIdentity -Record $record -Panel $Panel -Gpu $Gpu -Target $CurrentTarget
    if (-not (Test-NormalizationProfileExact -Snapshot $CurrentTarget `
            -SavedProfile $record.OriginalProfile)) {
        $record = Set-NormalizationCompensationPhase -Record $record `
            -Phase RESTORE_ATTEMPTED
        Restore-SnapshotProfile -Target $CurrentTarget -Profile $record.OriginalProfile
        $restored = $null
        for ($attempt = 1; $attempt -le 10; $attempt++) {
            Start-Sleep -Milliseconds 500
            $restored = Get-TargetSnapshot -Attempts 3
            Assert-NormalizationCompensationIdentity -Record $record -Panel $Panel -Gpu $Gpu -Target $restored
            if (Test-NormalizationProfileExact -Snapshot $restored `
                    -SavedProfile $record.OriginalProfile) {
                break
            }
        }
        if ($null -eq $restored -or
            -not (Test-NormalizationProfileExact -Snapshot $restored `
                -SavedProfile $record.OriginalProfile)) {
            throw 'The original unmanaged Intel profile could not be restored exactly. The compensation journal was retained.'
        }
        $CurrentTarget = $restored
    }
    $record = Set-NormalizationCompensationPhase -Record $record -Phase RESTORE_VERIFIED
    if ($RetainJournal) {
        [void](Set-NormalizationCompensationPhase -Record $record -Phase PREPARED)
    }
    else {
        Remove-NormalizationCompensationRecord
    }
    return $CurrentTarget
}

function Complete-NormalizationCompensationAfterBackup {
    param(
        [Parameter(Mandatory)][object]$Panel,
        [Parameter(Mandatory)][object]$Gpu,
        [Parameter(Mandatory)][object]$CurrentTarget
    )

    $record = Get-NormalizationCompensationRecord
    if ($null -eq $record) { return }
    Assert-NormalizationCompensationIdentity -Record $record -Panel $Panel -Gpu $Gpu -Target $CurrentTarget
    if ([string]$record.Phase -ne 'NORMALIZED_VERIFIED') {
        throw "The normalization journal cannot commit from phase $($record.Phase)."
    }
    $original = Get-OriginalProfile
    if ($null -eq $original -or
        [string]$original.BaselinePolicy -ne 'INTEL_STANDARD_BASELINE' -or
        -not (Test-NormalizationProfileExact -Snapshot $CurrentTarget -SavedProfile $original)) {
        throw 'The normalized Intel profile has no exact validated original-profile backup. The compensation journal was retained.'
    }
    [void](Set-NormalizationCompensationPhase -Record $record -Phase BACKUP_VERIFIED)
    Remove-NormalizationCompensationRecord
}

function Resolve-PendingNormalizationCompensation {
    param(
        [Parameter(Mandatory)][string]$RequestedAction,
        [Parameter(Mandatory)][object]$Panel,
        [Parameter(Mandatory)][object]$Gpu,
        [Parameter(Mandatory)][object]$CurrentTarget
    )

    $record = Get-NormalizationCompensationRecord
    if ($null -eq $record) {
        return [pscustomobject]@{ Outcome = 'NONE'; Target = $CurrentTarget; RecoveredWithoutBackup = $false }
    }
    Assert-NormalizationCompensationIdentity -Record $record -Panel $Panel -Gpu $Gpu -Target $CurrentTarget
    if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
        $saved = Get-OriginalProfile
        if ([string]$record.Phase -eq 'NORMALIZED_VERIFIED' -and
            (Test-NormalizationProfileExact -Snapshot $CurrentTarget -SavedProfile $saved)) {
            Complete-NormalizationCompensationAfterBackup -Panel $Panel -Gpu $Gpu `
                -CurrentTarget $CurrentTarget
            return [pscustomobject]@{ Outcome = 'BACKUP_COMMIT_FINALIZED'; Target = $CurrentTarget; RecoveredWithoutBackup = $false }
        }
        if ($RequestedAction -notin @('Restore', 'FactoryReset')) {
            throw 'A normalization compensation journal and original-profile backup require verified Restore before another operation.'
        }
        Restore-SnapshotProfile -Target $CurrentTarget -Profile $saved
        $restoredBackup = $null
        for ($attempt = 1; $attempt -le 10; $attempt++) {
            Start-Sleep -Milliseconds 500
            $restoredBackup = Get-TargetSnapshot -Attempts 3
            Assert-NormalizationCompensationIdentity -Record $record -Panel $Panel -Gpu $Gpu -Target $restoredBackup
            if (Test-NormalizationProfileExact -Snapshot $restoredBackup -SavedProfile $saved) { break }
        }
        if ($null -eq $restoredBackup -or
            -not (Test-NormalizationProfileExact -Snapshot $restoredBackup -SavedProfile $saved)) {
            throw 'The validated standard backup could not be restored while finalizing normalization compensation. The journal was retained.'
        }
        $record = Set-NormalizationCompensationPhase -Record $record -Phase NORMALIZED_VERIFIED
        Complete-NormalizationCompensationAfterBackup -Panel $Panel -Gpu $Gpu `
            -CurrentTarget $restoredBackup
        return [pscustomobject]@{ Outcome = 'BACKUP_RESTORED_AND_COMMITTED'; Target = $restoredBackup; RecoveredWithoutBackup = $false }
    }
    if ($RequestedAction -notin @('Restore', 'FactoryReset')) {
        throw 'An interrupted Intel profile normalization requires RECOVERY\RESTORE_ORIGINAL_VRR.bat before another install. The exact compensation journal was retained.'
    }
    $restoredOriginal = Invoke-NormalizationCompensationRestore -Panel $Panel -Gpu $Gpu `
        -CurrentTarget $CurrentTarget
    return [pscustomobject]@{
        Outcome = 'UNMANAGED_ORIGINAL_RESTORED'
        Target = $restoredOriginal
        RecoveredWithoutBackup = $true
    }
}

function Install-CustomEdidMode {
    param(
        [Parameter(Mandatory)][object]$Panel,
        [Parameter(Mandatory)][object]$Gpu,
        [Parameter(Mandatory)][object]$RegistryContext,
        [Parameter(Mandatory)][object[]]$ExperimentalEdids,
        [Parameter(Mandatory)][object]$OverrideState,
        [Parameter(Mandatory)][object]$Before,
        [Parameter(Mandatory)][string]$DesiredState,
        [switch]$StableSameModeRepair
    )

    if ($DesiredState -ne 'CLAWLAB_30_120' -and -not (Test-IsExperimentalOverclockMode -Mode $DesiredState)) {
        throw "Unknown ClawLab custom profile: $DesiredState"
    }

    $desired = @($ExperimentalEdids | Where-Object { $_.State -eq $DesiredState })
    if ($desired.Count -ne 1) {
        throw "Internal custom profile lookup failed: $DesiredState"
    }
    $variant = $desired[0]
    $isOverclock = Test-IsExperimentalOverclockMode -Mode $DesiredState
    $transition = if ($StableSameModeRepair) {
        Assert-StableSameModeRepairAllowed -OverrideState $OverrideState `
            -DesiredMode $DesiredState -Panel $Panel -Snapshot $Before
    }
    else {
        Assert-ProfileTransitionAllowed -OverrideState $OverrideState -DesiredMode $DesiredState
    }
    $baselinePlan = Resolve-FirstInstallProfileBaseline -Panel $Panel -Gpu $Gpu -RegistryContext $RegistryContext `
        -OverrideState $OverrideState -DesiredMode $DesiredState -Transition $transition -Snapshot $Before
    $Before = $baselinePlan.Snapshot
    $arcSyncPolicy = [string]$baselinePlan.ManagedArcSyncPolicy

    if ($OverrideState.State -eq 'UNKNOWN_OVERRIDE') {
        throw 'An unknown EDID override is installed. Remove it with its original tool before using a ClawLab custom range.'
    }
    if ($OverrideState.State -ne 'NONE' -and $OverrideState.State -ne $DesiredState) {
        throw "Another ClawLab custom range is installed ($($OverrideState.State)). Run RECOVERY\RESTORE_ORIGINAL_VRR.bat before changing modes."
    }

    Confirm-AdministratorOrRelaunch
    if ($OverrideState.State -eq 'NONE') {
        if (Test-Path -LiteralPath $experimentalStatePath -PathType Leaf) {
            throw 'A stale custom-range state file exists without its EDID override. Run RECOVERY\RESTORE_ORIGINAL_VRR.bat before retrying.'
        }
        if (-not (Test-ClawLabArcSyncMonitorRangeCompatible `
                -PanelKey ([string]$Panel.Definition.Key) `
                -MonitorMinimumHz ([float]$Before.MonitorMinimumHz) `
                -MonitorMaximumHz ([float]$Before.MonitorMaximumHz) `
                -ExpectedMinimumHz $targetMinimumHz -ExpectedMaximumHz $targetMaximumHz `
                -PhysicalMinimumHz $targetMinimumHz -CustomMinimumHz $experimentalMinimumHz `
                -SupportedMaximumHz $targetMaximumHz -LegacyRecoveryMaximumHz $experimentalMaximumHz)) {
            throw "Custom-range installation must start from the native 48-120 Hz EDID, but the driver reports $($Before.MonitorMinimumHz)-$($Before.MonitorMaximumHz) Hz."
        }
    }
    Save-OriginalProfile -Snapshot $Before -Panel $Panel -Gpu $Gpu `
        -BaselinePolicy ([string]$baselinePlan.BaselinePolicy)

    if ($OverrideState.State -eq 'NONE') {
        if ($arcSyncPolicy -eq 'TMA2027_PRESERVE_EXACT_CUSTOM_30_120') {
            $official = Get-VerifiedManagedArcSyncSnapshot -Target $Before `
                -PanelKey ([string]$Panel.Definition.Key) -Mode $DesiredState -Policy $arcSyncPolicy `
                -ExpectedMinimumHz 30 -ExpectedMaximumHz 120
        }
        else {
            $official = Get-VerifiedManagedArcSyncSnapshot -Target $Before `
                -PanelKey ([string]$Panel.Definition.Key) -Mode 'OFFICIAL_48_120' -Policy $arcSyncPolicy `
                -ExpectedMinimumHz 48 -ExpectedMaximumHz 120 -AllowExcellentWrite
        }

        [IO.Directory]::CreateDirectory($stateRoot) | Out-Null
        $experimentalState = [ordered]@{
            SchemaVersion = 4
            FixVersion = $fixVersion
            InstalledAt = (Get-Date).ToString('o')
            Mode = $variant.State
            PanelKey = [string]$Panel.Definition.Key
            PanelInstanceId = $RegistryContext.InstanceId
            RegistryPath = $RegistryContext.OverridePath
            PhysicalEdidSha256 = $RegistryContext.PhysicalEdidSha256
            ExperimentalEdidSha256 = $variant.Sha256
            Block0Sha256 = $variant.Block0Sha256
            Block1Sha256 = $variant.Block1Sha256
            ExperimentalMinimumHz = $variant.MinimumHz
            MaximumHz = $variant.MaximumHz
            Classification = if ($isOverclock) { [string](Get-ExperimentalOverclockMode -Mode $DesiredState).Stability } else { 'STABLE' }
            RequiresGuardedTrial = $isOverclock
            ArcSyncPolicy = $arcSyncPolicy
            OriginalBaselinePolicy = [string]$baselinePlan.BaselinePolicy
        }
        Write-ClawLabJsonAtomically -LiteralPath $experimentalStatePath -Value $experimentalState

        try {
            New-Item -Path $RegistryContext.OverridePath -Force | Out-Null
            New-ItemProperty -LiteralPath $RegistryContext.OverridePath -Name '0' -PropertyType Binary -Value $variant.Block0 -Force | Out-Null
            if ($null -ne $variant.Block1) {
                New-ItemProperty -LiteralPath $RegistryContext.OverridePath -Name '1' -PropertyType Binary -Value $variant.Block1 -Force | Out-Null
            }
            $writtenState = Get-EdidOverrideState -RegistryContext $RegistryContext -ExperimentalEdids $ExperimentalEdids
            if ($writtenState.State -ne $DesiredState) {
                throw 'The custom EDID registry write did not verify.'
            }
            Set-ManagedModeRecord -Mode $DesiredState -ArcSyncPolicy $arcSyncPolicy `
                -PanelKey ([string]$Panel.Definition.Key)
            if ($isOverclock) {
                $trialSchedulerPath = Join-Path $PSScriptRoot 'Experimental-Overclock-VRR-Trial.ps1'
                if (-not (Test-Path -LiteralPath $trialSchedulerPath -PathType Leaf)) {
                    throw "The guarded-trial scheduler is missing: $trialSchedulerPath"
                }
                # This function already required elevation. Register the
                # limited one-time trial inside the same transaction so a
                # scheduler failure rolls the pending EDID back atomically.
                & $trialSchedulerPath -Action Schedule -Mode $DesiredState
            }
            else {
                Install-StartupReapply
            }
        }
        catch {
            if ($isOverclock) {
                $installFailure = $_.Exception
                $rollbackFailures = [Collections.Generic.List[string]]::new()
                try { Remove-ExperimentalOverclockTrial }
                catch { $rollbackFailures.Add("trial cleanup: $($_.Exception.Message)") }

                Remove-ItemProperty -LiteralPath $RegistryContext.OverridePath -Name '0' -ErrorAction SilentlyContinue
                Remove-ItemProperty -LiteralPath $RegistryContext.OverridePath -Name '1' -ErrorAction SilentlyContinue
                try {
                    $rolledBackOverride = Get-EdidOverrideState -RegistryContext $RegistryContext -ExperimentalEdids $ExperimentalEdids
                    if ($rolledBackOverride.State -ne 'NONE') {
                        throw "EDID override remains in state $($rolledBackOverride.State)."
                    }
                }
                catch { $rollbackFailures.Add("EDID rollback: $($_.Exception.Message)") }

                try {
                    Restore-SnapshotProfile -Target $official -Profile $Before
                    $rolledBackProfile = Get-TargetSnapshot -Attempts 10
                    if ($rolledBackProfile.ProfileId -ne [int]$Before.ProfileId) {
                        throw "expected profile ID $($Before.ProfileId), got $($rolledBackProfile.ProfileId)."
                    }
                    if ([int]$Before.ProfileId -eq $profileCustom -and
                        ([Math]::Abs($rolledBackProfile.ActiveMinimumHz - [float]$Before.ActiveMinimumHz) -gt 0.1 -or
                         [Math]::Abs($rolledBackProfile.ActiveMaximumHz - [float]$Before.ActiveMaximumHz) -gt 0.1)) {
                        throw "original custom range verification failed."
                    }
                }
                catch { $rollbackFailures.Add("Intel profile rollback: $($_.Exception.Message)") }

                if ($rollbackFailures.Count -eq 0) {
                    # A new overclock transaction can reach this block only
                    # from CLEAN/NONE. Once EDID and Intel profile rollback are
                    # verified, remove every file created solely by the failed
                    # transaction. Keep the original backup until last.
                    foreach ($failedTransactionPath in @(
                            $experimentalStatePath,
                            $managedModeStatePath,
                            $installedScriptPath,
                            $installedEdidNormalizationModulePath,
                            $installedArcSyncRangePolicyModulePath,
                            $installedScheduledTaskPersistenceModulePath,
                            $installedLauncherPath,
                            $installedCursorRefreshHelperPath,
                            $cursorRefreshHelperStatePath,
                            (Join-Path $stateRoot 'MSI-Claw-Intel-LFC-Fix.ps1'),
                            (Join-Path $stateRoot 'Intel-VRR-LFC-Driver-Interface.ps1'),
                            (Join-Path $stateRoot 'Lfc-Backup-Identity.ps1'),
                            (Join-Path $stateRoot 'ClawLab-LFC-Startup.vbs')
                        )) {
                        try { Remove-FileIfPresent -LiteralPath $failedTransactionPath }
                        catch { $rollbackFailures.Add("artifact cleanup: $($_.Exception.Message)") }
                    }
                    if ($rollbackFailures.Count -eq 0) {
                        try { Remove-FileIfPresent -LiteralPath $backupPath }
                        catch { $rollbackFailures.Add("backup cleanup: $($_.Exception.Message)") }
                    }
                }

                if ($rollbackFailures.Count -gt 0) {
                    throw "Experimental installation failed: $($installFailure.Message) Automatic rollback also reported: $($rollbackFailures -join ' | '). Keep the ClawLab state folder and run RECOVERY\RESTORE_ORIGINAL_VRR.bat."
                }
                throw $installFailure
            }
            Remove-ItemProperty -LiteralPath $RegistryContext.OverridePath -Name '0' -ErrorAction SilentlyContinue
            Remove-ItemProperty -LiteralPath $RegistryContext.OverridePath -Name '1' -ErrorAction SilentlyContinue
            Remove-FileIfPresent -LiteralPath $experimentalStatePath
            Remove-FileIfPresent -LiteralPath $managedModeStatePath
            try { Restore-SnapshotProfile -Target $official -Profile $Before } catch {}
            throw
        }

        $modeLabel = if ($isOverclock) { [string](Get-ExperimentalOverclockMode -Mode $DesiredState).Stability } else { 'ClawLab default' }
        Write-Host "$modeLabel $($variant.MinimumHz)-$($variant.MaximumHz) Hz EDID override is installed and verified." -ForegroundColor Yellow
        if ($isOverclock) {
            Write-Warning 'This display overclock is not active yet. Its mandatory guarded trial is scheduled for the next sign-in.'
        }
        Write-Host 'Restart the PC to make Windows and the Intel driver reload the display EDID.' -ForegroundColor Yellow
        $status = Get-StatusObject -Panel $Panel -Gpu $Gpu -Snapshot $official -OverrideState $writtenState
        $status.RestartRequired = $true
        return $status
    }

    if (-not (Test-Path -LiteralPath $experimentalStatePath -PathType Leaf)) {
        throw 'The matching EDID override exists without its ClawLab state file. It was not adopted or modified.'
    }

    if ($isOverclock) {
        Write-Host 'The experimental overclock EDID is present. Complete or recover the mandatory guarded trial.' -ForegroundColor Yellow
        $status = Get-StatusObject -Panel $Panel -Gpu $Gpu -Snapshot $Before -OverrideState $OverrideState
        $status.RestartRequired = $true
        return $status
    }

    if (Test-ClawLabArcSyncMonitorRangeCompatible `
            -PanelKey ([string]$Panel.Definition.Key) `
            -MonitorMinimumHz ([float]$Before.MonitorMinimumHz) `
            -MonitorMaximumHz ([float]$Before.MonitorMaximumHz) `
            -ExpectedMinimumHz ([float]$variant.MinimumHz) -ExpectedMaximumHz ([float]$variant.MaximumHz) `
            -PhysicalMinimumHz $targetMinimumHz -CustomMinimumHz $experimentalMinimumHz `
            -SupportedMaximumHz $targetMaximumHz -LegacyRecoveryMaximumHz $experimentalMaximumHz) {
        $after = Get-VerifiedManagedArcSyncSnapshot -Target $Before `
            -PanelKey ([string]$Panel.Definition.Key) -Mode $DesiredState -Policy $arcSyncPolicy `
            -ExpectedMinimumHz ([float]$variant.MinimumHz) -ExpectedMaximumHz ([float]$variant.MaximumHz) `
            -AllowExcellentWrite
        Install-StartupReapply
        Set-ManagedModeRecord -Mode $DesiredState -ArcSyncPolicy $arcSyncPolicy `
            -PanelKey ([string]$Panel.Definition.Key)
        $modeLabel = if ($DesiredState -eq 'CLAWLAB_30_120') { 'ClawLab default' } else { 'Experimental' }
        Write-Host "$modeLabel $($variant.MinimumHz)-$($variant.MaximumHz) Hz mode is active and verified by the Intel driver." -ForegroundColor Yellow
        $status = Get-StatusObject -Panel $Panel -Gpu $Gpu -Snapshot $after -OverrideState $OverrideState
        return $status
    }

    Install-StartupReapply
    Set-ManagedModeRecord -Mode $DesiredState -ArcSyncPolicy $arcSyncPolicy `
        -PanelKey ([string]$Panel.Definition.Key)
    Write-Host 'The custom EDID override is present but has not been loaded by Windows yet.' -ForegroundColor Yellow
    Write-Host 'Restart the PC, then run CHECK_STATUS.bat.' -ForegroundColor Yellow
    $status = Get-StatusObject -Panel $Panel -Gpu $Gpu -Snapshot $Before -OverrideState $OverrideState
    $status.RestartRequired = $true
    return $status
}

function Get-StatusObject {
    param(
        [Parameter(Mandatory)][object]$Panel,
        [Parameter(Mandatory)][object]$Gpu,
        [Parameter(Mandatory)][object]$Snapshot,
        [Parameter(Mandatory)][object]$OverrideState
    )

    $managedRecord = Get-ManagedModeRecord
    $currentArcSyncPolicy = if ($null -ne $managedRecord -and [string]$managedRecord.FixVersion -eq $fixVersion) {
        [string]$managedRecord.ArcSyncPolicy
    }
    else {
        'INTEL_EXCELLENT_REQUIRED'
    }
    $officialRangeActive = Test-ManagedArcSyncSnapshot -Snapshot $Snapshot `
        -PanelKey ([string]$Panel.Definition.Key) -Mode 'OFFICIAL_48_120' `
        -Policy $currentArcSyncPolicy -ExpectedMinimumHz 48 -ExpectedMaximumHz 120
    $knownExperimentalOverride = $OverrideState.State -in (@('CLAWLAB_30_120') + @($experimentalOverclockModes.Keys))
    $experimentalRangeActive = $knownExperimentalOverride -and
        (Test-ManagedArcSyncSnapshot -Snapshot $Snapshot `
            -PanelKey ([string]$Panel.Definition.Key) -Mode ([string]$OverrideState.State) `
            -Policy $currentArcSyncPolicy -ExpectedMinimumHz ([float]$OverrideState.MinimumHz) `
            -ExpectedMaximumHz ([float]$OverrideState.MaximumHz))

    $state = if ($experimentalRangeActive) {
        if ($OverrideState.State -eq 'CLAWLAB_30_120') {
            'CLAWLAB_30_120_ACTIVE'
        }
        else {
            'EXPERIMENTAL_{0}_{1}_ACTIVE' -f ([int]$OverrideState.MinimumHz), ([int]$OverrideState.MaximumHz)
        }
    }
    elseif ($knownExperimentalOverride) {
        if ($OverrideState.State -eq 'CLAWLAB_30_120') {
            'CLAWLAB_30_120_PENDING_RESTART'
        }
        else {
            'EXPERIMENTAL_{0}_{1}_PENDING_RESTART' -f ([int]$OverrideState.MinimumHz), ([int]$OverrideState.MaximumHz)
        }
    }
    elseif ($OverrideState.State -eq 'UNKNOWN_OVERRIDE') {
        'UNKNOWN_EDID_OVERRIDE'
    }
    elseif ($officialRangeActive) {
        'OFFICIAL_48_120_ACTIVE'
    }
    else {
        'DRIVER_PROFILE_CONSTRAINED'
    }

    $intelStartupState = Get-IntelStartupOrderState

    $displayMode = Get-CurrentDisplayMode
    $managedMode = Get-EffectiveManagedMode -OverrideState $OverrideState

    $telemetryExpectedMinimumHz = -1.0
    $telemetryExpectedMaximumHz = -1.0
    if ($null -ne $managedRecord -and
        [string]$managedRecord.FixVersion -eq $fixVersion -and
        [string]$managedRecord.PanelKey -eq [string]$Panel.Definition.Key) {
        $telemetryExpectedRange = Get-ManagedModeExpectedRange -Mode ([string]$managedRecord.Mode)
        $telemetryExpectedMinimumHz = [float]$telemetryExpectedRange.MinimumHz
        $telemetryExpectedMaximumHz = [float]$telemetryExpectedRange.MaximumHz
    }
    $monitorTelemetryState = Get-ClawLabArcSyncMonitorRangeState `
        -PanelKey ([string]$Panel.Definition.Key) `
        -MonitorMinimumHz ([float]$Snapshot.MonitorMinimumHz) `
        -MonitorMaximumHz ([float]$Snapshot.MonitorMaximumHz) `
        -ExpectedMinimumHz $telemetryExpectedMinimumHz `
        -ExpectedMaximumHz $telemetryExpectedMaximumHz `
        -PhysicalMinimumHz $targetMinimumHz -CustomMinimumHz $experimentalMinimumHz `
        -SupportedMaximumHz $targetMaximumHz -LegacyRecoveryMaximumHz $experimentalMaximumHz

    [pscustomobject]@{
        FixVersion = $fixVersion
        State = $state
        Panel = $Panel.Name
        PanelId = "$($Panel.Manufacturer)$($Panel.ProductCode)"
        IntelGpu = [string]$Gpu.Name
        IntelDriver = [string]$Gpu.DriverVersion
        MonitorSupportedRange = '{0:0.#}-{1:0.#} Hz' -f $Snapshot.MonitorMinimumHz, $Snapshot.MonitorMaximumHz
        PhysicalPanelRange = '{0:0.#}-{1:0.#} Hz' -f $targetMinimumHz, $targetMaximumHz
        ArcSyncMonitorTelemetry = $monitorTelemetryState
        ArcSyncPolicy = if ($null -eq $managedRecord) { 'UNMANAGED' } else { $currentArcSyncPolicy }
        ArcSyncVerification = if ($officialRangeActive -or $experimentalRangeActive) {
            if ($currentArcSyncPolicy -eq 'TMA2027_PRESERVE_EXACT_CUSTOM_30_120') { 'TMA2027_CUSTOM_EXACT' } else { 'EXCELLENT_EXACT' }
        }
        else { 'NOT_VERIFIED' }
        DriverProfile = $Snapshot.ProfileName
        DriverActiveRange = '{0:0.#}-{1:0.#} Hz' -f $Snapshot.ActiveMinimumHz, $Snapshot.ActiveMaximumHz
        DriverProfileMaxIncreaseUs = [uint32]$Snapshot.ActiveMaxIncreaseUs
        DriverProfileMaxDecreaseUs = [uint32]$Snapshot.ActiveMaxDecreaseUs
        WindowsDisplayMode = '{0}x{1} @ {2} Hz' -f $displayMode.Width, $displayMode.Height, $displayMode.RefreshHz
        ManagedMode = $managedMode.Mode
        ProfileSwitchGuard = $managedMode.State
        OriginalProfileSaved = Test-Path -LiteralPath $backupPath -PathType Leaf
        BackupPath = $backupPath
        StartupReapply = Get-StartupReapplyState
        CursorRefreshHelper = Get-CursorRefreshHelperState
        IntelGraphicsStartup = $intelStartupState
        EdidOverride = $OverrideState.State
        PhysicalEdidRead = $script:activeEdidNormalization
        PhysicalEdidSourceLength = $script:activeEdidSourceLength
        NormalizationCompensation = if (Test-Path -LiteralPath $normalizationCompensationPath -PathType Leaf) {
            'RECOVERY_REQUIRED'
        }
        else {
            'NONE'
        }
        RecoveryRequired = Test-Path -LiteralPath $normalizationCompensationPath -PathType Leaf
        RestartRequired = $knownExperimentalOverride -and -not $experimentalRangeActive
        RegistryModified = (
            $knownExperimentalOverride -or
            $intelStartupState -eq 'CLAWLAB_ORDERED'
        )
        DriverFilesModified = $false
    }
}

try {
    if ($Action -notin @('Status', 'ApplyStartup')) {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Remove-FileIfPresent -LiteralPath $lastErrorPath
        }
    }
    if ($Action -eq 'EmergencyRestoreEdid') {
        Confirm-AdministratorOrRelaunch
        if (-not (Test-Path -LiteralPath $experimentalStatePath -PathType Leaf)) {
            throw 'The ClawLab custom EDID state file is missing. Nothing was removed.'
        }
        $emergencyState = [IO.File]::ReadAllText($experimentalStatePath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        if ('RegistryPath' -notin $emergencyState.PSObject.Properties.Name) {
            throw 'The ClawLab custom EDID state file is invalid. Nothing was removed.'
        }
        $emergencyOverridePath = [string]$emergencyState.RegistryPath
        if ('ExperimentalEdidSha256' -notin $emergencyState.PSObject.Properties.Name) {
            throw 'The ClawLab custom-range state file has no EDID hash. Nothing was removed.'
        }
        $expectedEmergencyHashes = Get-KnownOverrideHashes -EdidSha256 ([string]$emergencyState.ExperimentalEdidSha256)
        $emergencyPanelId = [regex]::Escape(
            "$($expectedEmergencyHashes.Definition.Manufacturer)$($expectedEmergencyHashes.Definition.ProductCode)"
        )
        $expectedEmergencyPattern = '^Registry::HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Enum\\DISPLAY\\{0}\\[^\\]+\\Device Parameters\\EDID_OVERRIDE$' -f $emergencyPanelId
        if (-not [regex]::IsMatch(
                $emergencyOverridePath,
                $expectedEmergencyPattern,
                [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            throw "Unsafe or unexpected EDID override path: $emergencyOverridePath"
        }
        $emergencyBlock0 = [byte[]](Get-ItemPropertyValue -LiteralPath $emergencyOverridePath -Name '0' -ErrorAction Stop)
        $emergencyBlock1 = $null
        try { $emergencyBlock1 = [byte[]](Get-ItemPropertyValue -LiteralPath $emergencyOverridePath -Name '1' -ErrorAction Stop) } catch {}
        $emergencyBlock1Matches = if ([string]::IsNullOrWhiteSpace([string]$expectedEmergencyHashes.Block1)) {
            $null -eq $emergencyBlock1
        }
        else {
            $null -ne $emergencyBlock1 -and
                (Get-ByteArraySha256 -Bytes $emergencyBlock1) -eq $expectedEmergencyHashes.Block1
        }
        if ((Get-ByteArraySha256 -Bytes $emergencyBlock0) -ne $expectedEmergencyHashes.Block0 -or
            -not $emergencyBlock1Matches) {
            throw 'The installed EDID override does not match a known ClawLab custom mode. Nothing was removed.'
        }
        Remove-ItemProperty -LiteralPath $emergencyOverridePath -Name '0' -ErrorAction Stop
        if ($null -ne $emergencyBlock1) {
            Remove-ItemProperty -LiteralPath $emergencyOverridePath -Name '1' -ErrorAction Stop
        }
        Remove-FileIfPresent -LiteralPath $experimentalStatePath
        Write-Host 'Removed the verified ClawLab custom EDID override.' -ForegroundColor Green
        Write-Host 'Restart the PC. Then run RECOVERY\RESTORE_ORIGINAL_VRR.bat in normal Windows to restore the saved Intel profile.' -ForegroundColor Yellow
        exit 0
    }

    if ($Action -eq 'ApplyStartup' -and $StartupSource -eq 'VrrTask' -and
        (Test-LfcStartupOrchestratorReady)) {
        # Keep the desktop helper responsive immediately after sign-in without
        # performing any driver write. The delayed, verified LFC orchestrator
        # remains the sole owner of the ordered VRR -> LFC reapply transaction.
        [void](Invoke-CursorRefreshHelperStartupBestEffort -Operation Start)
        $helperSuffix = if ([string]::IsNullOrWhiteSpace([string]$script:cursorRefreshLaunchWarning)) {
            'Desktop helper started; '
        }
        else {
            'Desktop helper unavailable; '
        }
        Write-StartupResult -Success $true -Message ($helperSuffix + 'driver reapply deferred to the verified LFC startup orchestrator, which applies VRR first and LFC second.')
        exit 0
    }
    if ($Action -eq 'ApplyStartup') {
        Enter-StartupTransactionLocks -Source $StartupSource
    }
    $panel = Get-ValidatedPanel
    $gpu = Get-IntelGpu
    if ($Action -eq 'ApplyStartup') {
        # The helper only needs the validated panel, installed state and the
        # current interactive desktop. Start it before the slower Intel driver
        # stabilization path. The final verified path recreates its DWM surface
        # once after Intel/display initialization has settled.
        [void](Invoke-CursorRefreshHelperStartupBestEffort -Operation Start)
    }
    $registryContext = Get-PanelRegistryContext -Panel $panel
    if ($Action -in @(
            'Install48', 'Install30', 'Repair48', 'Repair30',
            'Install48_144', 'Install48_165', 'Install48_180', 'Install48_192',
            'Install30_144', 'Install30_165', 'Install30_180', 'Install30_192',
            'ApplyExperimentalTrial', 'VerifyExperimentalTrial', 'ConfirmExperimentalTrial', 'ApplyStartup'
        )) {
        Assert-NoThirdPartyEdidOverrideValues -RegistryContext $registryContext
    }
    $experimentalEdids = @(Get-ExperimentalEdidCatalog -PhysicalEdid $registryContext.PhysicalEdid -Definition $registryContext.Definition)
    $overrideState = Get-EdidOverrideState -RegistryContext $registryContext -ExperimentalEdids $experimentalEdids
    Add-ArcSyncControlType
    Add-DisplayModeControlType
    $snapshotAttempts = if ($Action -eq 'ApplyStartup') { 180 } else { 5 }
    $before = Get-TargetSnapshot -Attempts $snapshotAttempts

    if ($Action -notin @('Status', 'UpdateCursorRefresh') -and
        (Test-Path -LiteralPath $normalizationCompensationPath -PathType Leaf)) {
        $normalizationResolution = Resolve-PendingNormalizationCompensation `
            -RequestedAction $Action -Panel $panel -Gpu $gpu -CurrentTarget $before
        $before = $normalizationResolution.Target
        if ([bool]$normalizationResolution.RecoveredWithoutBackup) {
            $recoveryStatus = Get-StatusObject -Panel $panel -Gpu $gpu `
                -Snapshot $before -OverrideState $overrideState
            $recoveryStatus | Add-Member -NotePropertyName NormalizationCompensationOutcome `
                -NotePropertyValue ([string]$normalizationResolution.Outcome)
            $recoveryStatus
            exit 0
        }
    }

    switch ($Action) {
        'Status' {
            Get-StatusObject -Panel $panel -Gpu $gpu -Snapshot $before -OverrideState $overrideState
        }

        'UpdateCursorRefresh' {
            Confirm-AdministratorOrRelaunch
            Update-CursorRefreshHelperOnly -Panel $panel -Snapshot $before `
                -OverrideState $overrideState
        }

        'ApplyExperimentalTrial' {
            $context = Assert-ExperimentalOverclockTrialContext -Panel $panel `
                -OverrideState $overrideState `
                -RequiredLifecycleStates @('ATTEMPT_CONSUMED')
            $mode = $context.Mode
            if (-not (Test-ClawLabArcSyncMonitorRangeCompatible `
                    -PanelKey ([string]$panel.Definition.Key) `
                    -MonitorMinimumHz ([float]$before.MonitorMinimumHz) `
                    -MonitorMaximumHz ([float]$before.MonitorMaximumHz) `
                    -ExpectedMinimumHz ([float]$mode.MinimumHz) `
                    -ExpectedMaximumHz ([float]$mode.MaximumHz) `
                    -PhysicalMinimumHz $targetMinimumHz -CustomMinimumHz $experimentalMinimumHz `
                    -SupportedMaximumHz $targetMaximumHz -LegacyRecoveryMaximumHz $experimentalMaximumHz)) {
                throw "The guarded trial found an unexpected monitor range: $($before.MonitorMinimumHz)-$($before.MonitorMaximumHz) Hz."
            }

            $displayMode = Set-VerifiedDisplayRefresh -RefreshHz ([int]$mode.MaximumHz)
            $target = Get-TargetSnapshot -Attempts 10
            Invoke-SetProfile -Target $target -ProfileId $profileExcellent
            Start-Sleep -Milliseconds 750
            $after = Get-TargetSnapshot -Attempts 10
            if ($after.ProfileId -ne $profileExcellent -or
                [Math]::Abs($after.ActiveMinimumHz - [float]$mode.MinimumHz) -gt 0.1 -or
                [Math]::Abs($after.ActiveMaximumHz - [float]$mode.MaximumHz) -gt 0.1) {
                throw "The guarded trial could not verify Intel EXCELLENT at $($mode.MinimumHz)-$($mode.MaximumHz) Hz."
            }
            [pscustomobject]@{
                State = 'EXPERIMENTAL_OVERCLOCK_TRIAL_ACTIVE'
                Mode = [string]$context.Trial.Mode
                WindowsDisplayMode = '{0}x{1} @ {2} Hz' -f $displayMode.Width, $displayMode.Height, $displayMode.RefreshHz
                DriverActiveRange = '{0:0.#}-{1:0.#} Hz' -f $after.ActiveMinimumHz, $after.ActiveMaximumHz
            }
        }

        'VerifyExperimentalTrial' {
            $context = Assert-ExperimentalOverclockTrialContext -Panel $panel `
                -OverrideState $overrideState `
                -RequiredLifecycleStates @('ATTEMPT_CONSUMED')
            $mode = $context.Mode
            $displayMode = Get-CurrentDisplayMode
            if ($displayMode.Width -ne [int]$panel.Definition.Width -or
                $displayMode.Height -ne [int]$panel.Definition.Height -or
                $displayMode.RefreshHz -ne [int]$mode.MaximumHz) {
                throw "The guarded trial did not remain at $($panel.Definition.Width)x$($panel.Definition.Height) @ $($mode.MaximumHz) Hz for the complete observation."
            }
            $after = Get-TargetSnapshot -Attempts 10
            if ($after.ProfileId -ne $profileExcellent -or
                [Math]::Abs($after.ActiveMinimumHz - [float]$mode.MinimumHz) -gt 0.1 -or
                [Math]::Abs($after.ActiveMaximumHz - [float]$mode.MaximumHz) -gt 0.1) {
                throw "The guarded trial did not retain Intel EXCELLENT at $($mode.MinimumHz)-$($mode.MaximumHz) Hz for the complete observation."
            }
            [pscustomobject]@{
                State = 'EXPERIMENTAL_OVERCLOCK_TRIAL_VERIFIED'
                Mode = [string]$context.Trial.Mode
                WindowsDisplayMode = '{0}x{1} @ {2} Hz' -f $displayMode.Width, $displayMode.Height, $displayMode.RefreshHz
                DriverActiveRange = '{0:0.#}-{1:0.#} Hz' -f $after.ActiveMinimumHz, $after.ActiveMaximumHz
            }
        }

        'SetSafe120ForTrial' {
            $context = Assert-ExperimentalOverclockTrialContext -Panel $panel `
                -OverrideState $overrideState `
                -RequiredLifecycleStates @(
                    'RUNNING', 'ATTEMPT_CONSUMED', 'AWAITING_CONFIRMATION',
                    'CONFIRMING', 'PERSISTENCE_APPLIED', 'RECOVERY_REQUIRED'
                )
            $safeMode = Set-Safe120DisplayMode
            [pscustomobject]@{
                State = 'EXPERIMENTAL_OVERCLOCK_TRIAL_SAFE_120'
                Mode = [string]$context.Trial.Mode
                WindowsDisplayMode = '{0}x{1} @ {2} Hz' -f $safeMode.Width, $safeMode.Height, $safeMode.RefreshHz
            }
        }

        'ConfirmExperimentalTrial' {
            Confirm-AdministratorOrRelaunch
            $context = Assert-ExperimentalOverclockTrialContext -Panel $panel `
                -OverrideState $overrideState -RequireUserConfirmation `
                -RequiredLifecycleStates @('CONFIRMING')
            $mode = $context.Mode
            $displayMode = Set-VerifiedDisplayRefresh -RefreshHz ([int]$mode.MaximumHz)
            $target = Get-TargetSnapshot -Attempts 10
            Invoke-SetProfile -Target $target -ProfileId $profileExcellent
            Start-Sleep -Milliseconds 750
            $after = Get-TargetSnapshot -Attempts 10
            if ($after.ProfileId -ne $profileExcellent -or
                [Math]::Abs($after.ActiveMinimumHz - [float]$mode.MinimumHz) -gt 0.1 -or
                [Math]::Abs($after.ActiveMaximumHz - [float]$mode.MaximumHz) -gt 0.1) {
                throw "The confirmed overclock could not verify Intel EXCELLENT at $($mode.MinimumHz)-$($mode.MaximumHz) Hz."
            }
            Set-ManagedModeRecord -Mode ([string]$context.Trial.Mode)
            Install-StartupReapply -PreserveExperimentalRecovery
            $protectedLfcToolPath = Join-Path $PSScriptRoot 'MSI-Claw-Intel-LFC-Fix.ps1'
            if (-not (Test-Path -LiteralPath $protectedLfcToolPath -PathType Leaf)) {
                throw 'The protected Intel LFC component is missing.'
            }
            $lfcResults = @(& $protectedLfcToolPath -Action Apply)
            $lfcResult = if ($lfcResults.Count -gt 0) { $lfcResults[-1] } else { $null }
            if ($null -eq $lfcResult -or
                -not [bool]$lfcResult.LfcFixActive -or
                -not [bool]$lfcResult.LfcTransition.BackupPresent -or
                [string]$lfcResult.StartupPersistence -ne 'INSTALLED_ONE_SHOT_AT_LOGON' -or
                [string]$lfcResult.ManagedVrrMode -ne [string]$context.Trial.Mode) {
                throw 'The protected Intel LFC component did not verify an active, backed and persistent correction.'
            }
            $vrrStartupState = Get-StartupReapplyState
            if ($vrrStartupState -in @('NOT_INSTALLED', 'TASK_INVALID', 'TASK_WITHOUT_FILES')) {
                throw "The confirmed overclock startup task is not valid: $vrrStartupState"
            }

            # The one-time guarded-trial task deliberately remains registered
            # until Complete-ExperimentalOverclockTrialCommit records durable
            # commit evidence and consumes it. Consequently, the managed-mode
            # resolver must still report EXPERIMENTAL_TRIAL_PENDING here; asking
            # for CONSISTENT before task consumption creates an impossible
            # circular dependency and rolls back an otherwise valid profile.
            # Persist the fact that every long-lived VRR/LFC component was
            # independently verified before accepting that exact transition.
            $context.Trial | Add-Member -NotePropertyName LifecycleState `
                -NotePropertyValue 'PERSISTENCE_APPLIED' -Force
            $context.Trial | Add-Member -NotePropertyName LifecycleUpdatedAt `
                -NotePropertyValue (Get-Date).ToString('o') -Force
            $context.Trial | Add-Member -NotePropertyName PersistenceAppliedAt `
                -NotePropertyValue (Get-Date).ToString('o') -Force
            Write-ClawLabJsonAtomically -LiteralPath $experimentalTrialStatePath `
                -Value $context.Trial

            $confirmedManaged = Get-EffectiveManagedMode -OverrideState $overrideState
            if ([string]$confirmedManaged.Mode -ne [string]$context.Trial.Mode -or
                [string]$confirmedManaged.State -ne 'EXPERIMENTAL_TRIAL_PENDING') {
                throw "The confirmed overclock is not in the verified pre-commit trial state: $($confirmedManaged.Mode) / $($confirmedManaged.State)"
            }
            $cleanupState = Complete-ExperimentalOverclockTrialCommit -Trial $context.Trial
            [pscustomobject]@{
                State = 'EXPERIMENTAL_OVERCLOCK_CONFIRMED'
                Mode = [string]$context.Trial.Mode
                WindowsDisplayMode = '{0}x{1} @ {2} Hz' -f $displayMode.Width, $displayMode.Height, $displayMode.RefreshHz
                DriverActiveRange = '{0:0.#}-{1:0.#} Hz' -f $after.ActiveMinimumHz, $after.ActiveMaximumHz
                LfcFixActive = $true
                TrialCleanup = $cleanupState
            }
        }

        'ApplyStartup' {
            if ($overrideState.State -eq 'UNKNOWN_OVERRIDE') {
                throw 'An unknown EDID override is installed. Startup reapply was cancelled.'
            }
            $expectedManagedMode = if ($overrideState.State -eq 'NONE') { 'OFFICIAL_48_120' } else { [string]$overrideState.State }
            $managedMode = Get-EffectiveManagedMode -OverrideState $overrideState
            if ($managedMode.Mode -ne $expectedManagedMode -or $managedMode.State -ne 'CONSISTENT') {
                throw "Startup reapply refused an unmanaged or inconsistent VRR state: $($managedMode.Mode) / $($managedMode.State). Run RECOVERY\RESTORE_ORIGINAL_VRR.bat."
            }
            $expectedMinimumHz = [float]$overrideState.MinimumHz
            $expectedMaximumHz = [float]$overrideState.MaximumHz
            $managedRecord = Get-ManagedModeRecord
            if ($null -eq $managedRecord -or [string]$managedRecord.FixVersion -ne $fixVersion) {
                throw 'Startup reapply requires the exact current-version managed profile record.'
            }
            $arcSyncPolicy = [string]$managedRecord.ArcSyncPolicy
            if (-not (Test-ClawLabArcSyncMonitorRangeCompatible `
                    -PanelKey ([string]$panel.Definition.Key) `
                    -MonitorMinimumHz ([float]$before.MonitorMinimumHz) `
                    -MonitorMaximumHz ([float]$before.MonitorMaximumHz) `
                    -ExpectedMinimumHz $expectedMinimumHz -ExpectedMaximumHz $expectedMaximumHz `
                    -PhysicalMinimumHz $targetMinimumHz -CustomMinimumHz $experimentalMinimumHz `
                    -SupportedMaximumHz $targetMaximumHz -LegacyRecoveryMaximumHz $experimentalMaximumHz)) {
                throw "Startup reapply found an unexpected monitor range: $($before.MonitorMinimumHz)-$($before.MonitorMaximumHz) Hz."
            }

            $displayMode = if (Test-IsExperimentalOverclockMode -Mode ([string]$managedMode.Mode)) {
                Set-VerifiedDisplayRefresh -RefreshHz ([int]$expectedMaximumHz)
            }
            else {
                $null
            }

            # The refresh transition and Intel Graphics Software startup can
            # transiently restore RECOMMENDED. Start the UI first, then apply
            # EXCELLENT against the settled output and verify the final state.
            Start-ManagedIntelGraphicsSoftware
            Start-Sleep -Seconds 2

            $target = Get-TargetSnapshot -Attempts 10
            $after = Get-VerifiedManagedArcSyncSnapshot -Target $target `
                -PanelKey ([string]$panel.Definition.Key) -Mode ([string]$managedRecord.Mode) `
                -Policy $arcSyncPolicy -ExpectedMinimumHz $expectedMinimumHz `
                -ExpectedMaximumHz $expectedMaximumHz -AllowExcellentWrite
            $displaySuffix = ''
            if ($null -ne $displayMode) {
                $displaySuffix = ", $($displayMode.Width)x$($displayMode.Height) at $($displayMode.RefreshHz) Hz"
            }
            $identitySuffix = if ($script:intelStartupIdentityRenewed) { ', signed Intel Graphics Software update trusted' } else { '' }
            $intelUiSuffix = if ([string]::IsNullOrWhiteSpace([string]$script:intelGraphicsLaunchWarning)) {
                ''
            }
            else {
                ', Intel Graphics Software launch cancelled; VRR verified independently'
            }
            # Intel/display initialization can invalidate a surface created at
            # the beginning of sign-in. Ask the native process to recreate its
            # DXGI swap chain in place after final Arc Sync verification. This
            # avoids a process gap and never rewrites the managed VRR profile.
            [void](Invoke-CursorRefreshHelperStartupBestEffort -Operation Resync)
            $cursorStatus = if ([string]::IsNullOrWhiteSpace([string]$script:cursorRefreshLaunchWarning)) {
                'event-driven cursor refresh active'
            }
            else {
                'optional cursor refresh unavailable; core VRR/LFC startup continued'
            }
            Write-StartupResult -Success $true -Message (("{0}, {1}-{2} Hz, {3}" -f $after.ProfileName, $after.ActiveMinimumHz, $after.ActiveMaximumHz, $cursorStatus) + $displaySuffix + $identitySuffix + $intelUiSuffix)
            Exit-StartupTransactionLocks
            exit 0
        }

        { $_ -in @('Install48', 'Repair48') } {
            $transition = if ($Action -eq 'Repair48') {
                Assert-StableSameModeRepairAllowed -OverrideState $overrideState `
                    -DesiredMode 'OFFICIAL_48_120' -Panel $panel -Snapshot $before
            }
            else {
                Assert-ProfileTransitionAllowed -OverrideState $overrideState -DesiredMode 'OFFICIAL_48_120'
            }
            $baselinePlan = Resolve-FirstInstallProfileBaseline -Panel $panel -Gpu $gpu -RegistryContext $registryContext `
                -OverrideState $overrideState -DesiredMode 'OFFICIAL_48_120' `
                -Transition $transition -Snapshot $before
            $before = $baselinePlan.Snapshot
            if ($overrideState.State -eq 'UNKNOWN_OVERRIDE') {
                throw 'An unknown EDID override is installed. Remove it with its original tool before using official mode.'
            }
            if ($overrideState.State -ne 'NONE') {
                throw "ClawLab custom mode $($overrideState.State) is installed. Run RECOVERY\RESTORE_ORIGINAL_VRR.bat before installing official mode."
            }
            if (-not (Test-ClawLabArcSyncMonitorRangeCompatible `
                    -PanelKey ([string]$panel.Definition.Key) `
                    -MonitorMinimumHz ([float]$before.MonitorMinimumHz) `
                    -MonitorMaximumHz ([float]$before.MonitorMaximumHz) `
                    -ExpectedMinimumHz $targetMinimumHz -ExpectedMaximumHz $targetMaximumHz `
                    -PhysicalMinimumHz $targetMinimumHz -CustomMinimumHz $experimentalMinimumHz `
                    -SupportedMaximumHz $targetMaximumHz -LegacyRecoveryMaximumHz $experimentalMaximumHz)) {
                throw "Official mode expected the panel's native 48-120 Hz range, but the driver reports $($before.MonitorMinimumHz)-$($before.MonitorMaximumHz) Hz."
            }

            Confirm-AdministratorOrRelaunch
            Save-OriginalProfile -Snapshot $before -Panel $panel -Gpu $gpu `
                -BaselinePolicy ([string]$baselinePlan.BaselinePolicy)
            if (Test-ManagedArcSyncSnapshot -Snapshot $before `
                    -PanelKey ([string]$panel.Definition.Key) -Mode 'OFFICIAL_48_120' `
                    -Policy ([string]$baselinePlan.ManagedArcSyncPolicy) `
                    -ExpectedMinimumHz 48 -ExpectedMaximumHz 120) {
                Install-StartupReapply
                Set-ManagedModeRecord -Mode 'OFFICIAL_48_120' `
                    -ArcSyncPolicy ([string]$baselinePlan.ManagedArcSyncPolicy) `
                    -PanelKey ([string]$panel.Definition.Key)
                Write-Host 'Official Intel Arc Sync 48-120 Hz mode is already active.' -ForegroundColor Green
                Get-StatusObject -Panel $panel -Gpu $gpu -Snapshot $before -OverrideState $overrideState
                break
            }

            try {
                $after = Get-VerifiedManagedArcSyncSnapshot -Target $before `
                    -PanelKey ([string]$panel.Definition.Key) -Mode 'OFFICIAL_48_120' `
                    -Policy ([string]$baselinePlan.ManagedArcSyncPolicy) `
                    -ExpectedMinimumHz 48 -ExpectedMaximumHz 120 -AllowExcellentWrite
            }
            catch {
                try {
                    Restore-SnapshotProfile -Target $before -Profile $before
                }
                catch {
                    Write-Warning "Automatic rollback also failed: $($_.Exception.Message)"
                }
                throw
            }

            Install-StartupReapply
            Set-ManagedModeRecord -Mode 'OFFICIAL_48_120' `
                -ArcSyncPolicy ([string]$baselinePlan.ManagedArcSyncPolicy) `
                -PanelKey ([string]$panel.Definition.Key)
            Write-Host 'Official Intel Arc Sync 48-120 Hz mode is active and verified.' -ForegroundColor Green
            Write-Host 'Automatic reapply is installed for future Windows sign-ins.' -ForegroundColor Green
            Get-StatusObject -Panel $panel -Gpu $gpu -Snapshot $after -OverrideState $overrideState
        }

        { $_ -in @('Install30', 'Repair30') } {
            Install-CustomEdidMode -Panel $panel -Gpu $gpu -RegistryContext $registryContext `
                -ExperimentalEdids $experimentalEdids -OverrideState $overrideState -Before $before `
                -DesiredState 'CLAWLAB_30_120' -StableSameModeRepair:($Action -eq 'Repair30')
        }

        'Install48_144' {
            Install-CustomEdidMode -Panel $panel -Gpu $gpu -RegistryContext $registryContext `
                -ExperimentalEdids $experimentalEdids -OverrideState $overrideState -Before $before `
                -DesiredState 'CLAWLAB_48_144'
        }

        'Install48_165' {
            Install-CustomEdidMode -Panel $panel -Gpu $gpu -RegistryContext $registryContext `
                -ExperimentalEdids $experimentalEdids -OverrideState $overrideState -Before $before `
                -DesiredState 'CLAWLAB_48_165'
        }

        'Install48_180' {
            Install-CustomEdidMode -Panel $panel -Gpu $gpu -RegistryContext $registryContext `
                -ExperimentalEdids $experimentalEdids -OverrideState $overrideState -Before $before `
                -DesiredState 'CLAWLAB_48_180'
        }

        'Install48_192' {
            Install-CustomEdidMode -Panel $panel -Gpu $gpu -RegistryContext $registryContext `
                -ExperimentalEdids $experimentalEdids -OverrideState $overrideState -Before $before `
                -DesiredState 'CLAWLAB_48_192'
        }

        'Install30_144' {
            Install-CustomEdidMode -Panel $panel -Gpu $gpu -RegistryContext $registryContext `
                -ExperimentalEdids $experimentalEdids -OverrideState $overrideState -Before $before `
                -DesiredState 'CLAWLAB_30_144'
        }

        'Install30_165' {
            Install-CustomEdidMode -Panel $panel -Gpu $gpu -RegistryContext $registryContext `
                -ExperimentalEdids $experimentalEdids -OverrideState $overrideState -Before $before `
                -DesiredState 'CLAWLAB_30_165'
        }

        'Install30_180' {
            Install-CustomEdidMode -Panel $panel -Gpu $gpu -RegistryContext $registryContext `
                -ExperimentalEdids $experimentalEdids -OverrideState $overrideState -Before $before `
                -DesiredState 'CLAWLAB_30_180'
        }

        'Install30_192' {
            Install-CustomEdidMode -Panel $panel -Gpu $gpu -RegistryContext $registryContext `
                -ExperimentalEdids $experimentalEdids -OverrideState $overrideState -Before $before `
                -DesiredState 'CLAWLAB_30_192'
        }

        'RecoverOrphanedDefaultState' {
            # This private recovery path never writes an Intel profile, display
            # mode or EDID. It is allowed only when fresh readback proves the
            # exact known factory profile and the sole active managed component
            # is one owned but invalid legacy ClawLab startup task.
            $cleanupProof = Assert-OrphanedDefaultVrrShellCleanupAllowed `
                -Panel $panel -Snapshot $before -OverrideState $overrideState
            Confirm-AdministratorOrRelaunch
            Remove-StartupReapply

            $afterOverride = Get-EdidOverrideState -RegistryContext $registryContext `
                -ExperimentalEdids $experimentalEdids
            $afterManaged = Get-EffectiveManagedMode -OverrideState $afterOverride
            if ([string]$afterOverride.State -ne 'NONE' -or
                [string]$afterManaged.Mode -ne 'NONE' -or
                [string]$afterManaged.State -ne 'CLEAN' -or
                (Get-StartupReapplyState) -ne 'NOT_INSTALLED' -or
                (Get-CursorRefreshHelperState) -ne 'NOT_INSTALLED') {
                throw 'The orphaned ClawLab startup shell was not removed completely.'
            }

            $after = Get-TargetSnapshot -Attempts 10
            $afterTelemetry = Get-ClawLabArcSyncMonitorRangeState `
                -PanelKey ([string]$panel.Definition.Key) `
                -MonitorMinimumHz ([float]$after.MonitorMinimumHz) `
                -MonitorMaximumHz ([float]$after.MonitorMaximumHz) `
                -PhysicalMinimumHz $targetMinimumHz -CustomMinimumHz $experimentalMinimumHz `
                -SupportedMaximumHz $targetMaximumHz -LegacyRecoveryMaximumHz $experimentalMaximumHz
            if (-not (Test-ClawLabKnownUnmanagedFactoryProfile `
                    -PanelKey ([string]$panel.Definition.Key) -TelemetryState $afterTelemetry `
                    -ProfileId ([int]$after.ProfileId) `
                    -MinimumHz ([float]$after.ActiveMinimumHz) `
                    -MaximumHz ([float]$after.ActiveMaximumHz) `
                    -MaxIncreaseUs ([uint32]$after.ActiveMaxIncreaseUs) `
                    -MaxDecreaseUs ([uint32]$after.ActiveMaxDecreaseUs))) {
                throw 'The Intel factory profile changed while the orphaned ClawLab task was being removed.'
            }

            Write-Host 'The orphaned legacy ClawLab startup shell was removed without changing the verified Intel factory profile.' -ForegroundColor Green
            $status = Get-StatusObject -Panel $panel -Gpu $gpu -Snapshot $after `
                -OverrideState $afterOverride
            $status | Add-Member -NotePropertyName RecoveryOutcome `
                -NotePropertyValue 'ORPHANED_DEFAULT_VRR_SHELL_CLEANED_NO_DISPLAY_WRITE'
            $status | Add-Member -NotePropertyName PreviousStartupState `
                -NotePropertyValue ([string]$cleanupProof.StartupState)
            $status
        }

        'FactoryReset' {
            $recoveryOverride = Get-ClawLabRecoveryOverrideState -RegistryContext $registryContext
            if ($recoveryOverride.State -eq 'UNKNOWN_THIRD_PARTY') {
                throw 'Factory reset found an unknown EDID override block. It was not created by ClawLab and will not be removed.'
            }

            # Refuse an unknown TMA2027 CUSTOM state before changing even the
            # Windows display mode. Only the exact collected OEM signature is
            # eligible for the no-write preservation path.
            $factoryInitialDecision = Get-FactoryResetDecisionForSnapshot -Panel $panel -Snapshot $before
            if ($factoryInitialDecision -eq 'REFUSE_UNSAFE_TMA2027_CUSTOM') {
                throw "Factory reset found an unknown TMA2027 CUSTOM profile ($($before.ActiveMinimumHz)-$($before.ActiveMaximumHz) Hz, timings $($before.ActiveMaxIncreaseUs)/$($before.ActiveMaxDecreaseUs) us). No display setting, Intel profile, EDID override, managed task or managed configuration was changed."
            }

            # Resolve and validate a signed Intel startup command before making
            # any display or profile change.
            $factoryIntelStartupCommand = Get-FactoryIntelStartupCommand
            Confirm-AdministratorOrRelaunch

            $safeMode = Set-Safe120DisplayMode
            Start-Sleep -Seconds 2
            $factoryTarget = Get-TargetSnapshot -Attempts 10
            $factoryDecision = Get-FactoryResetDecisionForSnapshot -Panel $panel -Snapshot $factoryTarget
            if ($factoryDecision -ne $factoryInitialDecision) {
                throw "Factory reset stopped because the Intel profile changed during display stabilization ($factoryInitialDecision -> $factoryDecision). No EDID override, managed task or managed configuration was removed."
            }

            switch ($factoryDecision) {
                'PRESERVE_TMA2027_OEM_CUSTOM_30_120' {
                    Assert-KnownTma2027CustomBaselineEnvironment -Panel $panel `
                        -RegistryContext $registryContext -Snapshot $factoryTarget
                    $factoryProfile = $factoryTarget
                    $factoryProfileOutcome = 'TMA2027_VERIFIED_CUSTOM_30_120_PRESERVED_NO_SETTER'
                }
                'SET_INTEL_RECOMMENDED' {
                    Invoke-SetProfile -Target $factoryTarget -ProfileId $profileRecommended
                    $factoryProfile = $null
                    for ($profileAttempt = 1; $profileAttempt -le 10; $profileAttempt++) {
                        Start-Sleep -Milliseconds 500
                        $factoryProfile = Get-TargetSnapshot -Attempts 3
                        if ([int]$factoryProfile.ProfileId -eq $profileRecommended) {
                            break
                        }
                    }
                    if ($null -eq $factoryProfile -or [int]$factoryProfile.ProfileId -ne $profileRecommended) {
                        $actualProfile = if ($null -eq $factoryProfile) { 'unavailable' } else { [string]$factoryProfile.ProfileName }
                        throw "Factory reset could not verify Intel RECOMMENDED mode; current profile is $actualProfile. No EDID override, managed task or managed configuration was removed."
                    }
                    $factoryProfileOutcome = 'INTEL_RECOMMENDED_VERIFIED'
                }
                default {
                    throw "Factory reset received an unsupported profile decision: $factoryDecision. Nothing was removed."
                }
            }

            $preserveTmaFactoryBaseline = $factoryDecision -eq 'PRESERVE_TMA2027_OEM_CUSTOM_30_120'

            if ($recoveryOverride.State -eq 'CLAWLAB_RECOVERABLE') {
                if ($recoveryOverride.Block0Present) {
                    Remove-ItemProperty -LiteralPath $registryContext.OverridePath -Name '0' -ErrorAction Stop
                }
                if ($recoveryOverride.Block1Present) {
                    Remove-ItemProperty -LiteralPath $registryContext.OverridePath -Name '1' -ErrorAction Stop
                }
                $overrideState = Get-EdidOverrideState -RegistryContext $registryContext -ExperimentalEdids $experimentalEdids
                if ($overrideState.State -ne 'NONE') {
                    throw 'Factory reset could not remove the verified ClawLab EDID override completely.'
                }
            }

            Remove-StartupReapply
            Set-FactoryIntelStartupCommand -Command $factoryIntelStartupCommand
            Remove-FileIfPresent -LiteralPath $backupPath
            Remove-FileIfPresent -LiteralPath $experimentalStatePath
            Remove-FileIfPresent -LiteralPath $managedModeStatePath
            Remove-FileIfPresent -LiteralPath $intelStartupBackupPath

            Write-Host 'ClawLab VRR factory reset completed.' -ForegroundColor Green
            if ($preserveTmaFactoryBaseline) {
                Write-Host ("Windows is at {0}x{1} 120 Hz and the exact verified TMA2027 OEM CUSTOM 30-120 baseline was preserved." -f $safeMode.Width, $safeMode.Height) -ForegroundColor Green
            }
            else {
                Write-Host ("Windows is at {0}x{1} 120 Hz and Intel RECOMMENDED is selected." -f $safeMode.Width, $safeMode.Height) -ForegroundColor Green
            }
            Write-Host 'Restart the PC to unload any previously active EDID override and restore the physical 48-120 Hz panel data.' -ForegroundColor Yellow
            [pscustomobject]@{
                FixVersion = $fixVersion
                State = 'FACTORY_RESET_COMPLETE_RESTART_REQUIRED'
                WindowsDisplayMode = '{0}x{1} @ {2} Hz' -f $safeMode.Width, $safeMode.Height, $safeMode.RefreshHz
                DriverProfile = $factoryProfile.ProfileName
                DriverProfileOutcome = $factoryProfileOutcome
                EdidOverride = $overrideState.State
                StartupReapply = Get-StartupReapplyState
                IntelGraphicsStartup = Get-IntelStartupOrderState
                RestartRequired = $true
            }
        }

        { $_ -in @('Restore', 'RestoreGuardedTrial') } {
            $original = Get-OriginalProfile
            if ($null -eq $original) {
                throw 'No saved original profile is available. No display setting was changed.'
            }

            if ($overrideState.State -eq 'UNKNOWN_OVERRIDE') {
                throw 'An unknown EDID override is installed. It was not created by this package and will not be removed.'
            }
            $restoreSnapshotMatches = Test-SnapshotMatchesSavedProfile -Snapshot $before -Profile $original
            $restoreProfileDecision = Get-ClawLabSavedProfileRestoreDecision `
                -BaselinePolicy ([string]$original.BaselinePolicy) `
                -SnapshotMatches $restoreSnapshotMatches
            if ($restoreProfileDecision -eq 'REFUSE_TMA2027_DRIFT_NO_WRITE') {
                throw "The saved TMA2027 OEM CUSTOM 30-120 baseline has drifted: current $($before.ProfileName) $($before.ActiveMinimumHz)-$($before.ActiveMaximumHz) Hz, timings $($before.ActiveMaxIncreaseUs)/$($before.ActiveMaxDecreaseUs) us. ClawLab did not call an Intel profile setter and did not remove any EDID override, managed task or managed configuration. Collect diagnostics before recovery."
            }
            if ($restoreProfileDecision -eq 'REFUSE_UNKNOWN_BASELINE_POLICY') {
                throw "The saved original profile has an unsupported baseline policy: $($original.BaselinePolicy). Nothing was changed."
            }
            $knownExperimentalOverride = $overrideState.State -in (@('CLAWLAB_30_120') + @($experimentalOverclockModes.Keys))
            if (Test-Path -LiteralPath $intelStartupBackupPath -PathType Leaf) {
                $startupOrderState = Get-IntelStartupOrderState
                if ($startupOrderState -notin @(
                        'CLAWLAB_ORDERED',
                        'ORIGINAL_STILL_PRESENT',
                        'MANAGED_COMMAND_REAPPEARED',
                        'SIGNED_INTEL_ENTRY_UPDATED'
                    )) {
                    throw "Intel Graphics Software startup state is unsafe to restore: $startupOrderState. Nothing was changed."
                }
            }
            if ($knownExperimentalOverride -or
                $restoreProfileDecision -eq 'PRESERVE_TMA2027_NO_WRITE' -or
                (Test-Path -LiteralPath $intelStartupBackupPath -PathType Leaf)) {
                Confirm-AdministratorOrRelaunch
            }

            if ((Test-IsExperimentalOverclockMode -Mode ([string]$overrideState.State)) -or
                $restoreProfileDecision -eq 'PRESERVE_TMA2027_NO_WRITE') {
                # Leave the experimental fixed high-refresh timing before
                # removing its EDID blocks. The exact TMA2027 preservation path
                # also requires native 120 Hz before its direct-state proof.
                [void](Set-Safe120DisplayMode)
                Start-Sleep -Seconds 2
                $before = Get-TargetSnapshot -Attempts 10
            }

            $restoreSnapshotMatches = Test-SnapshotMatchesSavedProfile -Snapshot $before -Profile $original
            $restoreProfileDecision = Get-ClawLabSavedProfileRestoreDecision `
                -BaselinePolicy ([string]$original.BaselinePolicy) `
                -SnapshotMatches $restoreSnapshotMatches
            switch ($restoreProfileDecision) {
                'PRESERVE_TMA2027_NO_WRITE' {
                    Assert-KnownTma2027CustomBaselineEnvironment -Panel $panel `
                        -RegistryContext $registryContext -Snapshot $before
                    $restoreProfileOutcome = 'TMA2027_VERIFIED_CUSTOM_30_120_PRESERVED_NO_SETTER'
                    Write-Host 'The exact saved TMA2027 OEM CUSTOM 30-120 baseline is active and was preserved without calling an Intel profile setter.' -ForegroundColor Green
                }
                'SKIP_ALREADY_MATCHING' {
                    $restoreProfileOutcome = 'SAVED_INTEL_STANDARD_BASELINE_ALREADY_ACTIVE'
                    Write-Host 'The saved original Intel Arc Sync profile is already active; the redundant driver write was skipped.' -ForegroundColor Green
                }
                'WRITE_SAVED_STANDARD_PROFILE' {
                    Restore-SnapshotProfile -Target $before -Profile $original
                    $restoreProfileOutcome = 'SAVED_INTEL_STANDARD_BASELINE_RESTORED'
                }
                'REFUSE_TMA2027_DRIFT_NO_WRITE' {
                    throw "The TMA2027 OEM CUSTOM baseline changed during display stabilization. No Intel profile setter was called and no EDID override, managed task or managed configuration was removed."
                }
                default {
                    throw "Original-profile restore received an unsupported decision: $restoreProfileDecision. Nothing was removed."
                }
            }
            $after = Get-TargetSnapshot -Attempts 10
            if (-not (Test-SnapshotMatchesSavedProfile -Snapshot $after -Profile $original)) {
                throw "Original profile verification failed: expected $($original.ProfileName) ($($original.MinRefreshRateInHz)-$($original.MaxRefreshRateInHz) Hz), got $($after.ProfileName) ($($after.ActiveMinimumHz)-$($after.ActiveMaximumHz) Hz)."
            }

            if ($knownExperimentalOverride) {
                Remove-ItemProperty -LiteralPath $registryContext.OverridePath -Name '0' -ErrorAction Stop
                if ($null -ne $overrideState.Block1) {
                    Remove-ItemProperty -LiteralPath $registryContext.OverridePath -Name '1' -ErrorAction Stop
                }
                $overrideState = Get-EdidOverrideState -RegistryContext $registryContext -ExperimentalEdids $experimentalEdids
                if ($overrideState.State -ne 'NONE') {
                    throw 'The ClawLab custom EDID override could not be removed completely.'
                }
            }
            if ($Action -eq 'RestoreGuardedTrial') {
                # PrepareRestore already restored the original flags while
                # retaining the LFC backup. Commit only after the saved Intel
                # profile and EDID removal above have both verified. Commit is
                # an atomic backup -> tombstone rename, so a crash remains
                # recoverable. Finalize then converts that tombstone into a
                # durable provenance marker before any runtime cleanup.
                $guardedLfcToolPath = Join-Path $PSScriptRoot 'MSI-Claw-Intel-LFC-Fix.ps1'
                if (-not (Test-Path -LiteralPath $guardedLfcToolPath -PathType Leaf)) {
                    throw 'The guarded-trial LFC commit payload is missing after VRR restore verification.'
                }
                $commitResults = @(& $guardedLfcToolPath -Action CommitRestore)
                $commitResult = if ($commitResults.Count -gt 0) { $commitResults[-1] } else { $null }
                $commitProofPresent = $null -ne $commitResult -and
                    ([bool]$commitResult.RestoreTombstonePresent -or
                        [bool]$commitResult.RestoreFinalizedPresent)
                if ($null -eq $commitResult -or
                    [bool]$commitResult.LfcTransition.BackupPresent -or
                    [string]$commitResult.LfcTransition.State -notin @(
                        'ORIGINAL_LFC_RESTORE_COMMITTED_PENDING_FINALIZE',
                        'ORIGINAL_LFC_RESTORE_FINALIZED',
                        'ORIGINAL_LFC_RESTORE_ALREADY_COMMITTED'
                    ) -or -not $commitProofPresent) {
                    throw 'The guarded-trial Intel LFC restore commit did not verify after VRR restoration.'
                }
                $finalizeResults = @(& $guardedLfcToolPath -Action FinalizeRestore)
                $finalizeResult = if ($finalizeResults.Count -gt 0) { $finalizeResults[-1] } else { $null }
                if ($null -eq $finalizeResult -or
                    [bool]$finalizeResult.LfcTransition.BackupPresent -or
                    [bool]$finalizeResult.RestoreTombstonePresent -or
                    -not [bool]$finalizeResult.RestoreFinalizedPresent -or
                    [string]$finalizeResult.LfcTransition.State -notin @(
                        'ORIGINAL_LFC_RESTORE_FINALIZED',
                        'ORIGINAL_LFC_RESTORE_ALREADY_FINALIZED'
                    )) {
                    throw 'The guarded-trial Intel LFC restore finalization did not retain verified provenance.'
                }
            }
            Remove-StartupReapply
            Restore-IntelStartupOrder
            Remove-FileIfPresent -LiteralPath $backupPath
            Remove-FileIfPresent -LiteralPath $experimentalStatePath
            Remove-FileIfPresent -LiteralPath $managedModeStatePath
            if ([string]$original.BaselinePolicy -eq 'TMA2027_VERIFIED_CUSTOM_30_120') {
                Write-Host "Preserved the exact original TMA2027 OEM Intel Arc Sync profile without a setter: $($after.ProfileName)." -ForegroundColor Green
            }
            else {
                Write-Host "Restored the original Intel Arc Sync profile: $($after.ProfileName)." -ForegroundColor Green
            }
            Write-Host 'Restart the PC to make Windows reload the physical panel EDID.' -ForegroundColor Yellow
            $status = Get-StatusObject -Panel $panel -Gpu $gpu -Snapshot $after -OverrideState $overrideState
            $status.RestartRequired = $true
            $status | Add-Member -NotePropertyName RestoreProfileOutcome `
                -NotePropertyValue $restoreProfileOutcome
            $status
        }
    }
}
catch {
    $caughtError = $_
    $normalizationRecoveryFailure = $null
    if ($Action -eq 'ApplyStartup') {
        try { Write-StartupResult -Success $false -Message $caughtError.Exception.Message } catch {}
        try { Start-ManagedIntelGraphicsSoftware } catch {}
        try { Exit-StartupTransactionLocks } catch {}
    }
    else {
        if ($null -ne $script:normalizationCompensationContext -and
            (Test-Path -LiteralPath $normalizationCompensationPath -PathType Leaf)) {
            try {
                $compensationTarget = Get-TargetSnapshot -Attempts 10
                if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
                    Complete-NormalizationCompensationAfterBackup `
                        -Panel $script:normalizationCompensationContext.Panel `
                        -Gpu $script:normalizationCompensationContext.Gpu `
                        -CurrentTarget $compensationTarget
                }
                else {
                    [void](Invoke-NormalizationCompensationRestore `
                        -Panel $script:normalizationCompensationContext.Panel `
                        -Gpu $script:normalizationCompensationContext.Gpu `
                        -CurrentTarget $compensationTarget)
                }
            }
            catch {
                $normalizationRecoveryFailure = [string]$_.Exception.Message
            }
        }
        try {
            [IO.Directory]::CreateDirectory($stateRoot) | Out-Null
            $failureMessage = [string]$caughtError.Exception.Message
            if (-not [string]::IsNullOrWhiteSpace($normalizationRecoveryFailure)) {
                $failureMessage += " | Intel normalization compensation remains pending: $normalizationRecoveryFailure"
            }
            $errorRecord = @(
                "Timestamp: $((Get-Date).ToString('o'))"
                "FixVersion: $fixVersion"
                "Action: $Action"
                "Message: $failureMessage"
                "Category: $($caughtError.CategoryInfo.Category)"
                "ScriptStackTrace: $($caughtError.ScriptStackTrace)"
            )
            [IO.File]::WriteAllLines($lastErrorPath, $errorRecord, [Text.UTF8Encoding]::new($false))
        }
        catch {}
    }
    Write-Host "ERROR: $($caughtError.Exception.Message)" -ForegroundColor Red
    if (-not [string]::IsNullOrWhiteSpace($normalizationRecoveryFailure)) {
        Write-Host "ERROR: Intel normalization compensation remains pending: $normalizationRecoveryFailure" -ForegroundColor Red
    }
    # Preserve a non-zero exit for direct -File execution while still allowing
    # Health/diagnostic callers that invoke this script to catch the failure.
    if (-not [string]::IsNullOrWhiteSpace($normalizationRecoveryFailure)) {
        throw "$($caughtError.Exception.Message) Intel normalization compensation remains pending: $normalizationRecoveryFailure"
    }
    throw $caughtError
}
