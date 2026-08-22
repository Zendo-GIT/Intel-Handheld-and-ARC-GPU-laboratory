[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Parent $PSScriptRoot
$localizationScript = Join-Path $PSScriptRoot 'ClawLab-Localization.ps1'
if (-not [System.IO.File]::Exists($localizationScript)) {
    $localizationScript = Join-Path $moduleRoot 'ClawLab-Localization.ps1'
}
if (-not [System.IO.File]::Exists($localizationScript)) {
    throw "ClawLab localization component not found: $localizationScript"
}

. $localizationScript
[void](Initialize-ClawLabLocalization)

function Get-ClawLabNativeLanguageName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Language
    )

    $cultureNames = @{
        ar = 'ar-SA'; bn = 'bn-BD'; zh = 'zh-CN'; cs = 'cs-CZ'; da = 'da-DK';
        nl = 'nl-NL'; en = 'en-US'; fil = 'fil-PH'; fi = 'fi-FI'; fr = 'fr-FR';
        de = 'de-DE'; el = 'el-GR'; hi = 'hi-IN'; hu = 'hu-HU'; id = 'id-ID';
        it = 'it-IT'; ja = 'ja-JP'; ko = 'ko-KR'; mr = 'mr-IN'; fa = 'fa-IR';
        pl = 'pl-PL'; pt = 'pt-PT'; pa = 'pa-IN'; ro = 'ro-RO'; ru = 'ru-RU';
        es = 'es-ES'; sw = 'sw-KE'; sv = 'sv-SE'; ta = 'ta-IN'; th = 'th-TH';
        tr = 'tr-TR'; uk = 'uk-UA'; ur = 'ur-PK'; vi = 'vi-VN'
    }

    try {
        $culture = [System.Globalization.CultureInfo]::GetCultureInfo($cultureNames[$Language])
        return $culture.NativeName
    }
    catch {
        return $Language
    }
}

function Publish-ClawLabEnvironmentChange {
    [CmdletBinding()]
    param()

    try {
        if ($null -eq ('ClawLabEnvironmentBroadcast' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class ClawLabEnvironmentBroadcast
{
    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd,
        uint message,
        UIntPtr wParam,
        string lParam,
        uint flags,
        uint timeout,
        out UIntPtr result);
}
'@
        }

        $broadcast = [IntPtr]0xffff
        $settingChange = [uint32]0x001A
        $abortIfHung = [uint32]0x0002
        $result = [UIntPtr]::Zero
        [void][ClawLabEnvironmentBroadcast]::SendMessageTimeout(
            $broadcast,
            $settingChange,
            [UIntPtr]::Zero,
            'Environment',
            $abortIfHung,
            2000,
            [ref]$result
        )
    }
    catch {
        # The user-scoped preference is already saved. Broadcasting is only a
        # convenience for newly launched processes in the current session.
    }
}

function Save-ClawLabLanguagePreference {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Language
    )

    if ([string]::IsNullOrWhiteSpace($Language)) {
        [System.Environment]::SetEnvironmentVariable(
            'CLAWLAB_LANGUAGE',
            $null,
            [System.EnvironmentVariableTarget]::User
        )
        $env:CLAWLAB_LANGUAGE = $null
        [void](Set-ClawLabLanguage -Language $null)
    }
    else {
        $resolved = Resolve-ClawLabLanguage -Language $Language
        [System.Environment]::SetEnvironmentVariable(
            'CLAWLAB_LANGUAGE',
            $resolved,
            [System.EnvironmentVariableTarget]::User
        )
        $env:CLAWLAB_LANGUAGE = $resolved
        [void](Set-ClawLabLanguage -Language $resolved)
    }

    Publish-ClawLabEnvironmentChange
}

$languages = @(Get-ClawLabSupportedLanguages)
$currentLanguage = Resolve-ClawLabLanguage

Write-Host ''
Write-Host ('=== ' + (Get-ClawLabString -Key 'language_selector_title') + ' ===') -ForegroundColor Cyan
Write-Host (Get-ClawLabString -Key 'language_selector_current' -Arguments @(
    "$currentLanguage - $(Get-ClawLabNativeLanguageName -Language $currentLanguage)"
))
Write-Host ''
Write-Host (Get-ClawLabString -Key 'language_selector_auto_option')

for ($index = 0; $index -lt $languages.Count; $index++) {
    $language = $languages[$index]
    $nativeName = Get-ClawLabNativeLanguageName -Language $language
    Write-Host ('{0,2} - {1,-3} - {2}' -f ($index + 1), $language, $nativeName)
}

Write-Host ''
$selection = (Read-Host (Get-ClawLabString -Key 'language_selector_prompt')).Trim()
if ([string]::IsNullOrWhiteSpace($selection) -or $selection -match '^(?i:a|auto|automatic)$') {
    Save-ClawLabLanguagePreference -Language $null
    $detected = Resolve-ClawLabLanguage
    Write-Host ''
    Write-Host (Get-ClawLabString -Key 'language_selector_automatic' -Arguments @(
        "$detected - $(Get-ClawLabNativeLanguageName -Language $detected)"
    )) -ForegroundColor Green
}
else {
    $selectedLanguage = $null
    $numericSelection = 0
    if ([int]::TryParse($selection, [ref]$numericSelection) -and
        $numericSelection -ge 1 -and
        $numericSelection -le $languages.Count) {
        $selectedLanguage = $languages[$numericSelection - 1]
    }
    else {
        $normalizedSelection = $selection.Trim().Replace('_', '-').ToLowerInvariant()
        $primarySelection = ($normalizedSelection -split '-', 2)[0]
        if ($primarySelection -eq 'tl') {
            $primarySelection = 'fil'
        }
        if ($languages -contains $primarySelection) {
            $selectedLanguage = $primarySelection
        }
    }

    if ([string]::IsNullOrWhiteSpace($selectedLanguage)) {
        Write-Host ''
        Write-Host (Get-ClawLabString -Key 'language_selector_invalid' -Arguments @($selection)) -ForegroundColor Red
        exit 2
    }

    Save-ClawLabLanguagePreference -Language $selectedLanguage
    Write-Host ''
    Write-Host (Get-ClawLabString -Key 'language_selector_saved' -Arguments @(
        "$selectedLanguage - $(Get-ClawLabNativeLanguageName -Language $selectedLanguage)"
    ) -Language $selectedLanguage) -ForegroundColor Green
}

Write-Host (Get-ClawLabString -Key 'language_selector_restart_note')
Write-Host ''
[void](Read-Host (Get-ClawLabString -Key 'press_enter'))
