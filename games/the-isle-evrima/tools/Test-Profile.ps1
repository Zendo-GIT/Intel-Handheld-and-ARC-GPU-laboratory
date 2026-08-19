[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$toolPath = Join-Path $projectRoot 'The-Isle-Evrima-Claw-Fix.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('ClawLab-TheIsle-' + [Guid]::NewGuid().ToString('N'))
$configDirectory = Join-Path $testRoot 'TheIsle\Saved\Config\WindowsClient'
$stateDirectory = Join-Path $testRoot 'ClawLab\The-Isle-Evrima-Claw-Fix'
$enginePath = Join-Path $configDirectory 'Engine.ini'
$settingsPath = Join-Path $configDirectory 'GameUserSettings.ini'
$validatedBuild = '24664737'
$utf8NoBom = [Text.UTF8Encoding]::new($false)

$originalEngine = @'
; existing user comment
[GameNetDriver StatelessConnectHandlerComponent]
CachedClientID=42

[/Script/Engine.UserInterfaceSettings]
ApplicationScale=1.000000
'@ -replace "`n", "`r`n"

$originalSettings = @'
[/Script/Engine.GameUserSettings]
ResolutionSizeX=1920
ResolutionSizeY=1200
ScreenPercentage=88
MasterAudioVolume=0.75

[ScalabilityGroups]
sg.ViewDistanceQuality=3
sg.FoliageQuality=3

[SavedInput]
ActionMappings=(ActionName="Use",Key=Gamepad_FaceButton_Left)
'@ -replace "`n", "`r`n"

try {
    [IO.Directory]::CreateDirectory($configDirectory) | Out-Null
    [IO.File]::WriteAllText($enginePath, $originalEngine, $utf8NoBom)
    $unsupportedSettings = $originalSettings -replace 'ResolutionSizeY=1200', 'ResolutionSizeY=1080'
    [IO.File]::WriteAllText($settingsPath, $unsupportedSettings, $utf8NoBom)
    $displayRejected = $false
    try {
        & $toolPath -Action Install -ConfigDirectory $configDirectory `
            -StateDirectory $stateDirectory -BuildIdOverride $validatedBuild | Out-Null
    }
    catch {
        $displayRejected = $_.Exception.Message -like "Unsupported display configuration*"
    }
    if (-not $displayRejected -or (Test-Path -LiteralPath $stateDirectory)) {
        throw 'The unsupported-display fail-closed test failed.'
    }

    [IO.File]::WriteAllText($settingsPath, $originalSettings, $utf8NoBom)
    $buildRejected = $false
    try {
        & $toolPath -Action Install -ConfigDirectory $configDirectory `
            -StateDirectory $stateDirectory -BuildIdOverride 'UNVERIFIED_TEST_BUILD' | Out-Null
    }
    catch {
        $buildRejected = $_.Exception.Message -like "Unsupported or unverified Steam build*"
    }
    if (-not $buildRejected -or (Test-Path -LiteralPath $stateDirectory)) {
        throw 'The unsupported-build fail-closed test failed.'
    }

    $originalEngineHash = (Get-FileHash -LiteralPath $enginePath -Algorithm SHA256).Hash
    $originalSettingsHash = (Get-FileHash -LiteralPath $settingsPath -Algorithm SHA256).Hash

    $install = & $toolPath -Action Install -ConfigDirectory $configDirectory `
        -StateDirectory $stateDirectory -BuildIdOverride $validatedBuild
    if ($install.State -cne 'FIX_INSTALLED') {
        throw "Install test failed: $($install.State)"
    }
    if (-not (Get-Item -LiteralPath $enginePath -Force).IsReadOnly -or
        -not (Get-Item -LiteralPath $settingsPath -Force).IsReadOnly) {
        throw 'The installed profile did not lock both configuration files.'
    }

    $engineText = Get-Content -LiteralPath $enginePath -Raw
    $settingsText = Get-Content -LiteralPath $settingsPath -Raw
    foreach ($marker in @(
            'CachedClientID=42',
            'bAllowHighDPIInGameMode=True',
            'ApplicationScale=0.900000',
            'r.ShaderPipelineCache.StartupMode=3'
        )) {
        if ($engineText -notmatch [regex]::Escape($marker)) {
            throw "Engine.ini merge test is missing: $marker"
        }
    }
    foreach ($marker in @(
            'MasterAudioVolume=0.75',
            'ScreenPercentage=40',
            'sg.ViewDistanceQuality=1',
            'sg.FoliageQuality=0',
            'ActionMappings=(ActionName="Use",Key=Gamepad_FaceButton_Left)'
        )) {
        if ($settingsText -notmatch [regex]::Escape($marker)) {
            throw "GameUserSettings.ini merge test is missing: $marker"
        }
    }

    $reinstall = & $toolPath -Action Install -ConfigDirectory $configDirectory `
        -StateDirectory $stateDirectory -BuildIdOverride $validatedBuild
    if ($reinstall.State -cne 'FIX_INSTALLED') {
        throw "Idempotent reinstall test failed: $($reinstall.State)"
    }
    foreach ($marker in @('ApplicationScale=', 'sg.FoliageQuality=')) {
        $targetText = if ($marker -like 'sg.*') {
            Get-Content -LiteralPath $settingsPath -Raw
        }
        else {
            Get-Content -LiteralPath $enginePath -Raw
        }
        if (([regex]::Matches($targetText, "(?im)^$([regex]::Escape($marker))")).Count -ne 1) {
            throw "Idempotent merge created a duplicate key: $marker"
        }
    }

    $uninstall = & $toolPath -Action Uninstall -ConfigDirectory $configDirectory `
        -StateDirectory $stateDirectory -BuildIdOverride $validatedBuild
    if ($uninstall.State -cne 'NOT_INSTALLED') {
        throw "Uninstall test failed: $($uninstall.State)"
    }
    if ((Get-FileHash -LiteralPath $enginePath -Algorithm SHA256).Hash -cne $originalEngineHash) {
        throw 'Engine.ini was not restored byte-for-byte.'
    }
    if ((Get-FileHash -LiteralPath $settingsPath -Algorithm SHA256).Hash -cne $originalSettingsHash) {
        throw 'GameUserSettings.ini was not restored byte-for-byte.'
    }
    if (Test-Path -LiteralPath $stateDirectory) {
        throw 'The empty test state directory was not removed.'
    }

    [pscustomobject]@{
        Result = 'PASS'
        InstallState = $install.State
        ReinstallState = $reinstall.State
        UninstallState = $uninstall.State
        UnsupportedDisplayRejected = $displayRejected
        UnsupportedBuildRejected = $buildRejected
        ExactRestore = $true
    }
}
finally {
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    if (-not $resolvedTestRoot.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($resolvedTestRoot) -notlike 'ClawLab-TheIsle-*') {
        throw "Unsafe test cleanup path: $resolvedTestRoot"
    }
    if (Test-Path -LiteralPath $resolvedTestRoot) {
        [IO.Directory]::Delete($resolvedTestRoot, $true)
    }
}
