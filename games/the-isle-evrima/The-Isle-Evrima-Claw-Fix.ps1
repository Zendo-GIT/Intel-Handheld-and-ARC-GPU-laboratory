[CmdletBinding()]
param(
    [ValidateSet('Status', 'Install', 'Uninstall')]
    [string]$Action = 'Status',

    [string]$ConfigDirectory,

    [string]$StateDirectory,

    [string]$BuildIdOverride
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$FixVersion = '1.0.0'
$SteamAppId = '376210'
$ValidatedBuildId = '24664737'
$ValidatedGameVersion = '0.21.784'
$utf8NoBom = [Text.UTF8Encoding]::new($false)

$defaultConfigDirectory = Join-Path $env:LOCALAPPDATA 'TheIsle\Saved\Config\WindowsClient'
$defaultStateDirectory = Join-Path $env:LOCALAPPDATA 'ClawLab\The-Isle-Evrima-Claw-Fix'
if ([string]::IsNullOrWhiteSpace($ConfigDirectory)) {
    $ConfigDirectory = $defaultConfigDirectory
}
if ([string]::IsNullOrWhiteSpace($StateDirectory)) {
    $StateDirectory = $defaultStateDirectory
}

$ConfigDirectory = [IO.Path]::GetFullPath($ConfigDirectory)
$StateDirectory = [IO.Path]::GetFullPath($StateDirectory)
$defaultConfigDirectory = [IO.Path]::GetFullPath($defaultConfigDirectory)
$isLiveConfig = $ConfigDirectory.Equals($defaultConfigDirectory, [StringComparison]::OrdinalIgnoreCase)
if ($isLiveConfig -and -not [string]::IsNullOrWhiteSpace($BuildIdOverride)) {
    throw 'BuildIdOverride is restricted to an isolated test configuration directory.'
}

$enginePath = Join-Path $ConfigDirectory 'Engine.ini'
$gameUserSettingsPath = Join-Path $ConfigDirectory 'GameUserSettings.ini'
$statePath = Join-Path $StateDirectory 'install-state.json'
$engineBackupPath = Join-Path $StateDirectory 'original-Engine.ini'
$gameUserSettingsBackupPath = Join-Path $StateDirectory 'original-GameUserSettings.ini'

$engineValues = [ordered]@{
    '/Script/Engine.UserInterfaceSettings' = [ordered]@{
        'bAllowHighDPIInGameMode' = 'True'
        'ApplicationScale' = '0.900000'
    }
    'SystemSettings' = [ordered]@{
        'r.ShaderPipelineCache.Enabled' = '1'
        'r.ShaderPipelineCache.StartupMode' = '3'
        'r.PSOPrecaching' = '1'
        'r.PSOPrecache.Components' = '1'
        'r.PSOPrecache.GlobalShaders' = '1'
        'r.PSOPrecache.ProxyCreationWhenPSOReady' = '1'
        'r.PSOPrecache.ProxyCreationDelayStrategy' = '0'
        'D3D12.PSOPrecache.KeepLowLevel' = '1'
        'D3D12.PSO.KeepUsedPSOsInLowLevelCache' = '1'
        'r.ShaderCodeLibrary.PreloadShaderMaps' = '1'
        'r.ShaderCodeLibrary.ShaderMapResourceRef' = '1'
        'r.PreloadShaderPriority' = '4'
        'r.TSR.History.ScreenPercentage' = '100'
        'r.TSR.History.R11G11B10' = '1'
        'r.TSR.Velocity.WeightClampingSampleCount' = '2'
        'r.VRS.Enable' = '1'
        'r.VRS.ContrastAdaptiveShading' = '1'
        'r.Streaming.PoolSize' = '6144'
        'r.Streaming.AmortizeCPUToGPUCopy' = '1'
        'r.Streaming.MaxNumTexturesToStreamPerFrame' = '4'
        'r.Streaming.FramesForFullUpdate' = '10'
        'r.Streaming.UseBackgroundThreadPool' = '1'
    }
}

$gameUserSettingsValues = [ordered]@{
    '/Script/Engine.GameUserSettings' = [ordered]@{
        'LumenEnabled' = 'False'
        'AMDFSR' = '0'
        'ShadowSmoothing' = '0'
        'PhysicsFoliage' = 'False'
        'PhysicsFoliageAllPlayers' = 'False'
        'PhysicsGrass' = 'False'
        'bUseVSync' = 'True'
        'bUseDynamicResolution' = 'False'
        'ResolutionSizeX' = '1920'
        'ResolutionSizeY' = '1200'
        'LastUserConfirmedResolutionSizeX' = '1920'
        'LastUserConfirmedResolutionSizeY' = '1200'
        'FullscreenMode' = '1'
        'LastConfirmedFullscreenMode' = '1'
        'PreferredFullscreenMode' = '1'
        'DesiredScreenWidth' = '1920'
        'bUseDesiredScreenHeight' = 'False'
        'DesiredScreenHeight' = '1200'
        'LastUserConfirmedDesiredScreenWidth' = '1920'
        'LastUserConfirmedDesiredScreenHeight' = '1200'
        'bUseHDRDisplayOutput' = 'False'
        'ScreenPercentage' = '40'
    }
    'ScalabilityGroups' = [ordered]@{
        'sg.ViewDistanceQuality' = '1'
        'sg.AntiAliasingQuality' = '0'
        'sg.ShadowQuality' = '0'
        'sg.GlobalIlluminationQuality' = '0'
        'sg.ReflectionQuality' = '0'
        'sg.PostProcessQuality' = '0'
        'sg.TextureQuality' = '0'
        'sg.EffectsQuality' = '0'
        'sg.FoliageQuality' = '0'
        'sg.ShadingQuality' = '0'
        'sg.ResolutionQuality' = '100'
        'sg.LandscapeQuality' = '0'
    }
    '/Script/Engine.RendererSettings' = [ordered]@{
        'MotionBlurQuality' = '0'
    }
}

function Add-UniquePath {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [Collections.Generic.List[string]]$List,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }
    try {
        $fullPath = [IO.Path]::GetFullPath($Path)
    }
    catch {
        return
    }
    if ($List -notcontains $fullPath) {
        [void]$List.Add($fullPath)
    }
}

function Get-SteamLibraryRoots {
    $steamRoots = [Collections.Generic.List[string]]::new()
    $registryValues = @(
        @('HKCU:\Software\Valve\Steam', 'SteamPath'),
        @('HKCU:\Software\Valve\Steam', 'InstallPath'),
        @('HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'InstallPath'),
        @('HKLM:\SOFTWARE\Valve\Steam', 'InstallPath')
    )

    foreach ($entry in $registryValues) {
        try {
            Add-UniquePath -List $steamRoots -Path (
                Get-ItemPropertyValue -LiteralPath $entry[0] -Name $entry[1]
            )
        }
        catch {
            # Optional registry location.
        }
    }
    if ($null -ne ${env:ProgramFiles(x86)}) {
        Add-UniquePath -List $steamRoots -Path (Join-Path ${env:ProgramFiles(x86)} 'Steam')
    }
    if ($null -ne $env:ProgramFiles) {
        Add-UniquePath -List $steamRoots -Path (Join-Path $env:ProgramFiles 'Steam')
    }

    $libraryRoots = [Collections.Generic.List[string]]::new()
    foreach ($steamRoot in @($steamRoots)) {
        Add-UniquePath -List $libraryRoots -Path $steamRoot
        $libraryFile = Join-Path $steamRoot 'steamapps\libraryfolders.vdf'
        if (-not (Test-Path -LiteralPath $libraryFile -PathType Leaf)) {
            continue
        }
        foreach ($line in [IO.File]::ReadLines($libraryFile)) {
            $candidate = $null
            if ($line -match '^\s*"path"\s+"([^"]+)"') {
                $candidate = $Matches[1]
            }
            elseif ($line -match '^\s*"\d+"\s+"([^"]+)"') {
                $candidate = $Matches[1]
            }
            if ($null -ne $candidate) {
                Add-UniquePath -List $libraryRoots -Path ($candidate -replace '\\\\', '\')
            }
        }
    }
    return $libraryRoots
}

function Get-InstalledBuild {
    if (-not [string]::IsNullOrWhiteSpace($BuildIdOverride)) {
        return [pscustomobject]@{
            BuildId = $BuildIdOverride
            Manifest = 'OVERRIDE_FOR_TESTING'
        }
    }

    foreach ($libraryRoot in Get-SteamLibraryRoots) {
        $manifest = Join-Path $libraryRoot "steamapps\appmanifest_$SteamAppId.acf"
        if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
            continue
        }
        $text = Get-Content -LiteralPath $manifest -Raw
        $buildId = if ($text -match '"buildid"\s+"(\d+)"') { $Matches[1] } else { 'UNKNOWN' }
        return [pscustomobject]@{
            BuildId = $buildId
            Manifest = $manifest
        }
    }

    return [pscustomobject]@{
        BuildId = 'NOT_FOUND'
        Manifest = $null
    }
}

function Assert-GameStopped {
    if (-not $isLiveConfig) {
        return
    }
    if ($null -ne (Get-Process -Name 'TheIsle' -ErrorAction SilentlyContinue)) {
        throw 'The Isle is running. Close the game completely before installing or uninstalling.'
    }
}

function Assert-SupportedDisplayProfile {
    if (-not (Test-Path -LiteralPath $gameUserSettingsPath -PathType Leaf)) {
        throw 'GameUserSettings.ini is missing. Launch the game once, select 1920x1200, close it, then retry.'
    }
    $settingsText = Get-Content -LiteralPath $gameUserSettingsPath -Raw
    $resolutionX = Get-IniValue -Text $settingsText -Section '/Script/Engine.GameUserSettings' `
        -Key 'ResolutionSizeX'
    $resolutionY = Get-IniValue -Text $settingsText -Section '/Script/Engine.GameUserSettings' `
        -Key 'ResolutionSizeY'
    if ($resolutionX -cne '1920' -or $resolutionY -cne '1200') {
        throw "Unsupported display configuration '${resolutionX}x${resolutionY}'. Select 1920x1200 in the game, close it, then retry. Nothing was changed."
    }
}

function Find-IniSection {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()]
        [Collections.Generic.List[string]]$Lines,
        [Parameter(Mandatory)][string]$Section
    )

    $start = -1
    $end = $Lines.Count
    for ($index = 0; $index -lt $Lines.Count; $index++) {
        if ($Lines[$index] -match '^\s*\[([^\]]+)\]\s*$') {
            if ($start -ge 0) {
                $end = $index
                break
            }
            if ($Matches[1].Equals($Section, [StringComparison]::OrdinalIgnoreCase)) {
                $start = $index
            }
        }
    }
    return [pscustomobject]@{ Start = $start; End = $end }
}

function Set-IniSectionValues {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()]
        [Collections.Generic.List[string]]$Lines,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][Collections.IDictionary]$Values
    )

    $bounds = Find-IniSection -Lines $Lines -Section $Section
    if ($bounds.Start -lt 0) {
        if ($Lines.Count -gt 0 -and $Lines[$Lines.Count - 1] -ne '') {
            [void]$Lines.Add('')
        }
        [void]$Lines.Add("[$Section]")
    }

    foreach ($key in $Values.Keys) {
        $bounds = Find-IniSection -Lines $Lines -Section $Section
        $matches = [Collections.Generic.List[int]]::new()
        for ($index = $bounds.Start + 1; $index -lt $bounds.End; $index++) {
            $separator = $Lines[$index].IndexOf('=')
            if ($separator -lt 0) {
                continue
            }
            $candidateKey = $Lines[$index].Substring(0, $separator).Trim()
            if ($candidateKey.Equals([string]$key, [StringComparison]::OrdinalIgnoreCase)) {
                [void]$matches.Add($index)
            }
        }

        $replacement = "$key=$($Values[$key])"
        if ($matches.Count -eq 0) {
            $Lines.Insert($bounds.End, $replacement)
        }
        else {
            $Lines[$matches[0]] = $replacement
            for ($matchIndex = $matches.Count - 1; $matchIndex -ge 1; $matchIndex--) {
                $Lines.RemoveAt($matches[$matchIndex])
            }
        }
    }
}

function Set-IniProfile {
    param(
        [AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][Collections.IDictionary]$Profile
    )

    $lines = [Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrEmpty($Text)) {
        foreach ($line in [regex]::Split($Text, '\r\n|\n|\r')) {
            [void]$lines.Add($line)
        }
        while ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') {
            $lines.RemoveAt($lines.Count - 1)
        }
    }
    foreach ($section in $Profile.Keys) {
        Set-IniSectionValues -Lines $lines -Section ([string]$section) -Values $Profile[$section]
    }
    return (($lines -join "`r`n") + "`r`n")
}

function Get-IniValue {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string]$Key
    )

    $lines = [Collections.Generic.List[string]]::new()
    foreach ($line in [regex]::Split($Text, '\r\n|\n|\r')) {
        [void]$lines.Add($line)
    }
    $bounds = Find-IniSection -Lines $lines -Section $Section
    if ($bounds.Start -lt 0) {
        return $null
    }
    for ($index = $bounds.Start + 1; $index -lt $bounds.End; $index++) {
        $separator = $lines[$index].IndexOf('=')
        if ($separator -lt 0) {
            continue
        }
        $candidateKey = $lines[$index].Substring(0, $separator).Trim()
        if ($candidateKey.Equals($Key, [StringComparison]::OrdinalIgnoreCase)) {
            return $lines[$index].Substring($separator + 1).Trim()
        }
    }
    return $null
}

function Test-IniProfile {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][Collections.IDictionary]$Profile
    )

    $mismatches = [Collections.Generic.List[string]]::new()
    foreach ($section in $Profile.Keys) {
        foreach ($key in $Profile[$section].Keys) {
            $actual = Get-IniValue -Text $Text -Section ([string]$section) -Key ([string]$key)
            $expected = [string]$Profile[$section][$key]
            if ($null -eq $actual -or $actual -cne $expected) {
                [void]$mismatches.Add("[$section] $key expected '$expected', found '$actual'")
            }
        }
    }
    return $mismatches
}

function Set-ReadOnly {
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)][bool]$Enabled
    )

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        return
    }
    $item = Get-Item -LiteralPath $LiteralPath -Force
    $item.IsReadOnly = $Enabled
}

function Write-TextAtomic {
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)][string]$Text
    )

    $directory = [IO.Path]::GetDirectoryName($LiteralPath)
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $temporaryPath = Join-Path $directory ('.clawlab-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($temporaryPath, $Text, $utf8NoBom)
        Move-Item -LiteralPath $temporaryPath -Destination $LiteralPath -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
}

function Get-InstallState {
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        return $null
    }
    return (Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json)
}

function Assert-BackupIntegrity {
    param([Parameter(Mandatory)]$State)

    if ([bool]$State.EngineExisted -and -not (Test-Path -LiteralPath $engineBackupPath -PathType Leaf)) {
        throw "Original Engine.ini backup is missing: $engineBackupPath"
    }
    if ([bool]$State.GameUserSettingsExisted -and
        -not (Test-Path -LiteralPath $gameUserSettingsBackupPath -PathType Leaf)) {
        throw "Original GameUserSettings.ini backup is missing: $gameUserSettingsBackupPath"
    }
}

function New-OriginalBackup {
    param([Parameter(Mandatory)]$Build)

    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        $existingState = Get-InstallState
        Assert-BackupIntegrity -State $existingState
        return $existingState
    }

    [IO.Directory]::CreateDirectory($StateDirectory) | Out-Null
    $engineExisted = Test-Path -LiteralPath $enginePath -PathType Leaf
    $settingsExisted = Test-Path -LiteralPath $gameUserSettingsPath -PathType Leaf
    if (-not $engineExisted -or -not $settingsExisted) {
        throw 'The Isle configuration is incomplete. Launch the game once, close it, then run the installer again.'
    }

    foreach ($orphanedBackup in @($engineBackupPath, $gameUserSettingsBackupPath)) {
        if (Test-Path -LiteralPath $orphanedBackup -PathType Leaf) {
            throw "An incomplete earlier backup exists without install-state.json: $orphanedBackup. Preserve it and restore or move the incomplete state before retrying."
        }
    }

    $engineItem = Get-Item -LiteralPath $enginePath -Force
    $settingsItem = Get-Item -LiteralPath $gameUserSettingsPath -Force
    try {
        Copy-Item -LiteralPath $enginePath -Destination $engineBackupPath
        Copy-Item -LiteralPath $gameUserSettingsPath -Destination $gameUserSettingsBackupPath

        $state = [ordered]@{
            SchemaVersion = 1
            FixVersion = $FixVersion
            CreatedAtUtc = [DateTime]::UtcNow.ToString('o')
            SteamBuildId = [string]$Build.BuildId
            SteamManifest = [string]$Build.Manifest
            EngineExisted = $true
            EngineAttributes = [int]$engineItem.Attributes
            GameUserSettingsExisted = $true
            GameUserSettingsAttributes = [int]$settingsItem.Attributes
        }
        Write-TextAtomic -LiteralPath $statePath -Text ($state | ConvertTo-Json -Depth 4)
    }
    catch {
        foreach ($incompleteFile in @($statePath, $engineBackupPath, $gameUserSettingsBackupPath)) {
            if (Test-Path -LiteralPath $incompleteFile -PathType Leaf) {
                Remove-Item -LiteralPath $incompleteFile -Force
            }
        }
        if ((Test-Path -LiteralPath $StateDirectory -PathType Container) -and
            @(Get-ChildItem -LiteralPath $StateDirectory -Force).Count -eq 0) {
            Remove-Item -LiteralPath $StateDirectory -Force
        }
        throw
    }
    return (Get-InstallState)
}

function Restore-OperationSnapshot {
    param(
        [Parameter(Mandatory)][string]$EngineText,
        [Parameter(Mandatory)][string]$SettingsText,
        [Parameter(Mandatory)][int]$EngineAttributes,
        [Parameter(Mandatory)][int]$SettingsAttributes
    )

    Set-ReadOnly -LiteralPath $enginePath -Enabled $false
    Set-ReadOnly -LiteralPath $gameUserSettingsPath -Enabled $false
    Write-TextAtomic -LiteralPath $enginePath -Text $EngineText
    Write-TextAtomic -LiteralPath $gameUserSettingsPath -Text $SettingsText
    (Get-Item -LiteralPath $enginePath -Force).Attributes = [IO.FileAttributes]$EngineAttributes
    (Get-Item -LiteralPath $gameUserSettingsPath -Force).Attributes = [IO.FileAttributes]$SettingsAttributes
}

function Get-Status {
    $build = Get-InstalledBuild
    $state = Get-InstallState
    $engineExists = Test-Path -LiteralPath $enginePath -PathType Leaf
    $settingsExist = Test-Path -LiteralPath $gameUserSettingsPath -PathType Leaf
    $engineMismatch = @('FILE_MISSING')
    $settingsMismatch = @('FILE_MISSING')
    if ($engineExists) {
        $engineMismatch = @(Test-IniProfile -Text (Get-Content -LiteralPath $enginePath -Raw) -Profile $engineValues)
    }
    if ($settingsExist) {
        $settingsMismatch = @(
            Test-IniProfile -Text (Get-Content -LiteralPath $gameUserSettingsPath -Raw) -Profile $gameUserSettingsValues
        )
    }
    $engineReadOnly = $engineExists -and (Get-Item -LiteralPath $enginePath -Force).IsReadOnly
    $settingsReadOnly = $settingsExist -and (Get-Item -LiteralPath $gameUserSettingsPath -Force).IsReadOnly

    $profileState = if ($null -eq $state) {
        'NOT_INSTALLED'
    }
    elseif ($engineMismatch.Count -eq 0 -and $settingsMismatch.Count -eq 0 -and
        $engineReadOnly -and $settingsReadOnly) {
        'FIX_INSTALLED'
    }
    else {
        'FIX_DRIFTED_OR_INCOMPLETE'
    }

    [pscustomobject]@{
        FixVersion = $FixVersion
        State = $profileState
        ValidatedGameVersion = $ValidatedGameVersion
        ValidatedSteamBuild = $ValidatedBuildId
        InstalledSteamBuild = [string]$build.BuildId
        ValidatedBuildActive = ([string]$build.BuildId -ceq $ValidatedBuildId)
        ConfigDirectory = $ConfigDirectory
        OriginalBackupSaved = ($null -ne $state)
        EngineProfileHealthy = ($engineMismatch.Count -eq 0)
        GameSettingsProfileHealthy = ($settingsMismatch.Count -eq 0)
        EngineReadOnly = $engineReadOnly
        GameSettingsReadOnly = $settingsReadOnly
        EngineMismatches = @($engineMismatch)
        GameSettingsMismatches = @($settingsMismatch)
        OutputResolution = '1920x1200'
        InternalRenderScale = '40 percent (approximately 768x480)'
        AntiCheatMethod = 'CONFIGURATION_ONLY_NO_INJECTION'
    }
}

switch ($Action) {
    'Status' {
        Get-Status
    }

    'Install' {
        Assert-GameStopped
        $build = Get-InstalledBuild
        if ([string]$build.BuildId -cne $ValidatedBuildId) {
            throw "Unsupported or unverified Steam build '$($build.BuildId)'. This release supports build $ValidatedBuildId only. Nothing was changed."
        }
        Assert-SupportedDisplayProfile

        $state = New-OriginalBackup -Build $build
        Assert-BackupIntegrity -State $state

        $engineText = Get-Content -LiteralPath $enginePath -Raw
        $settingsText = Get-Content -LiteralPath $gameUserSettingsPath -Raw
        $engineAttributes = [int](Get-Item -LiteralPath $enginePath -Force).Attributes
        $settingsAttributes = [int](Get-Item -LiteralPath $gameUserSettingsPath -Force).Attributes

        try {
            $newEngineText = Set-IniProfile -Text $engineText -Profile $engineValues
            $newSettingsText = Set-IniProfile -Text $settingsText -Profile $gameUserSettingsValues
            Set-ReadOnly -LiteralPath $enginePath -Enabled $false
            Set-ReadOnly -LiteralPath $gameUserSettingsPath -Enabled $false
            Write-TextAtomic -LiteralPath $enginePath -Text $newEngineText
            Write-TextAtomic -LiteralPath $gameUserSettingsPath -Text $newSettingsText
            Set-ReadOnly -LiteralPath $enginePath -Enabled $true
            Set-ReadOnly -LiteralPath $gameUserSettingsPath -Enabled $true

            $status = Get-Status
            if ($status.State -cne 'FIX_INSTALLED') {
                throw "Post-install verification failed: $($status.State)"
            }
        }
        catch {
            Restore-OperationSnapshot -EngineText $engineText -SettingsText $settingsText `
                -EngineAttributes $engineAttributes -SettingsAttributes $settingsAttributes
            throw
        }

        Write-Host 'The Isle Evrima MSI Claw profile installed and verified.' -ForegroundColor Green
        Write-Host 'Both configuration files are locked read-only so the game cannot overwrite hidden values.'
        Write-Host 'Uninstall the profile before changing graphics or input settings.' -ForegroundColor Yellow
        Get-Status
    }

    'Uninstall' {
        Assert-GameStopped
        $state = Get-InstallState
        if ($null -eq $state) {
            Write-Host 'No ClawLab installation state was found. Nothing was changed.' -ForegroundColor Yellow
            Get-Status
            break
        }
        Assert-BackupIntegrity -State $state

        Set-ReadOnly -LiteralPath $enginePath -Enabled $false
        Set-ReadOnly -LiteralPath $gameUserSettingsPath -Enabled $false

        if ([bool]$state.EngineExisted) {
            Copy-Item -LiteralPath $engineBackupPath -Destination $enginePath -Force
            (Get-Item -LiteralPath $enginePath -Force).Attributes = [IO.FileAttributes][int]$state.EngineAttributes
        }
        elseif (Test-Path -LiteralPath $enginePath -PathType Leaf) {
            Remove-Item -LiteralPath $enginePath -Force
        }

        if ([bool]$state.GameUserSettingsExisted) {
            Copy-Item -LiteralPath $gameUserSettingsBackupPath -Destination $gameUserSettingsPath -Force
            (Get-Item -LiteralPath $gameUserSettingsPath -Force).Attributes = (
                [IO.FileAttributes][int]$state.GameUserSettingsAttributes
            )
        }
        elseif (Test-Path -LiteralPath $gameUserSettingsPath -PathType Leaf) {
            Remove-Item -LiteralPath $gameUserSettingsPath -Force
        }

        foreach ($managedFile in @($statePath, $engineBackupPath, $gameUserSettingsBackupPath)) {
            if (Test-Path -LiteralPath $managedFile -PathType Leaf) {
                Remove-Item -LiteralPath $managedFile -Force
            }
        }
        if ((Test-Path -LiteralPath $StateDirectory -PathType Container) -and
            @(Get-ChildItem -LiteralPath $StateDirectory -Force).Count -eq 0) {
            Remove-Item -LiteralPath $StateDirectory -Force
        }

        Write-Host 'The original The Isle configuration was restored exactly.' -ForegroundColor Green
        Get-Status
    }
}
