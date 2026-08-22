# Offline, dependency-free localization validation for Windows PowerShell 5.1+
# and PowerShell 7+. This test does not modify the system.

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Parent $PSScriptRoot
$runtimeRoot = if (Test-Path -LiteralPath (Join-Path $moduleRoot 'scripts\ClawLab-Localization.ps1') -PathType Leaf) {
    Join-Path $moduleRoot 'scripts'
}
else { $moduleRoot }
$localizationScript = Join-Path $runtimeRoot 'ClawLab-Localization.ps1'
$catalogPath = Join-Path $runtimeRoot 'locales\messages.json'
$selectorScript = if ($runtimeRoot -eq $moduleRoot) {
    Join-Path $moduleRoot 'tools\Select-ClawLab-Language.ps1'
}
else { Join-Path $runtimeRoot 'Select-ClawLab-Language.ps1' }

function Assert-ClawLabTest {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

# Windows PowerShell 5.1 treats a UTF-8 script without a BOM as the current
# ANSI code page. Runtime source must therefore remain 7-bit ASCII so parsing
# is identical on Korean, Japanese, Chinese and every Western Windows locale.
$localizationBytes = [IO.File]::ReadAllBytes($localizationScript)
$nonAsciiLocalizationBytes = @($localizationBytes | Where-Object { $_ -gt 0x7F })
Assert-ClawLabTest -Condition ($nonAsciiLocalizationBytes.Count -eq 0) `
    -Message 'ClawLab-Localization.ps1 is not code-page-independent ASCII.'

$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $localizationScript,
    [ref]$tokens,
    [ref]$parseErrors
)
Assert-ClawLabTest -Condition ($parseErrors.Count -eq 0) -Message 'ClawLab-Localization.ps1 has parser errors.'

$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $selectorScript,
    [ref]$tokens,
    [ref]$parseErrors
)
Assert-ClawLabTest -Condition ($parseErrors.Count -eq 0) -Message 'Select-ClawLab-Language.ps1 has parser errors.'

. $localizationScript

$validation = Test-ClawLabLocalizationCatalog -CatalogPath $catalogPath -ThrowOnError
Assert-ClawLabTest -Condition $validation.IsComplete -Message 'The localization catalog is incomplete.'
Assert-ClawLabTest -Condition ($validation.LanguageCount -eq 34) -Message 'The catalog must contain exactly 34 languages.'
Assert-ClawLabTest -Condition ($validation.MessageCount -gt 0) -Message 'The catalog contains no messages.'

$expectedLanguages = @(
    'ar', 'bn', 'zh', 'cs', 'da', 'nl', 'en', 'fil', 'fi', 'fr', 'de', 'el',
    'hi', 'hu', 'id', 'it', 'ja', 'ko', 'mr', 'fa', 'pl', 'pt', 'pa', 'ro',
    'ru', 'es', 'sw', 'sv', 'ta', 'th', 'tr', 'uk', 'ur', 'vi'
)
$actualLanguages = @(Get-ClawLabSupportedLanguages)
Assert-ClawLabTest -Condition (($actualLanguages -join ',') -eq ($expectedLanguages -join ',')) -Message 'Supported languages are not in the required Clawptimize order.'

# Reject accidental cross-script contamination such as Arabic or Hangul words
# leaking into a Tamil/Punjabi translation. Latin technical names are allowed.
$catalog = Import-ClawLabLocalizationCatalog -CatalogPath $catalogPath
$scriptBlocks = @(
    [pscustomobject]@{ Name = 'Arabic'; Start = 0x0600; End = 0x06ff },
    [pscustomobject]@{ Name = 'Bengali'; Start = 0x0980; End = 0x09ff },
    [pscustomobject]@{ Name = 'CJK'; Start = 0x3040; End = 0x9fff },
    [pscustomobject]@{ Name = 'Greek'; Start = 0x0370; End = 0x03ff },
    [pscustomobject]@{ Name = 'Devanagari'; Start = 0x0900; End = 0x097f },
    [pscustomobject]@{ Name = 'Hangul'; Start = 0xac00; End = 0xd7af },
    [pscustomobject]@{ Name = 'Gurmukhi'; Start = 0x0a00; End = 0x0a7f },
    [pscustomobject]@{ Name = 'Cyrillic'; Start = 0x0400; End = 0x04ff },
    [pscustomobject]@{ Name = 'Tamil'; Start = 0x0b80; End = 0x0bff },
    [pscustomobject]@{ Name = 'Thai'; Start = 0x0e00; End = 0x0e7f }
)
$allowedScripts = @{
    ar = @('Arabic'); fa = @('Arabic'); ur = @('Arabic')
    bn = @('Bengali', 'Devanagari'); zh = @('CJK'); el = @('Greek')
    hi = @('Devanagari'); mr = @('Devanagari'); ja = @('CJK')
    ko = @('Hangul', 'CJK'); pa = @('Gurmukhi', 'Devanagari')
    ru = @('Cyrillic'); uk = @('Cyrillic'); ta = @('Tamil'); th = @('Thai')
}
foreach ($language in $allowedScripts.Keys) {
    $locale = $catalog.locales.PSObject.Properties[$language].Value
    foreach ($message in $locale.PSObject.Properties) {
        foreach ($character in ([string]$message.Value).ToCharArray()) {
            $codePoint = [int]$character
            if ($codePoint -eq 0x0964 -or $codePoint -eq 0x0965) {
                continue
            }
            foreach ($block in $scriptBlocks) {
                if ($codePoint -ge $block.Start -and
                    $codePoint -le $block.End -and
                    -not ($allowedScripts[$language] -contains $block.Name)) {
                    throw "Unexpected $($block.Name) character in locale '$language', key '$($message.Name)'."
                }
            }
        }
    }
}

Assert-ClawLabTest -Condition ((Resolve-ClawLabLanguage -Language 'tl-PH') -eq 'fil') -Message 'tl-PH must map to fil.'
Assert-ClawLabTest -Condition ((Resolve-ClawLabLanguage -Language 'fr-FR') -eq 'fr') -Message 'fr-FR must map to fr.'
Assert-ClawLabTest -Condition ((Resolve-ClawLabLanguage -Language 'PT_BR') -eq 'pt') -Message 'PT_BR must map to pt.'
Assert-ClawLabTest -Condition ((Resolve-ClawLabLanguage -Language 'zh-Hant-TW') -eq 'zh') -Message 'zh-Hant-TW must map to zh.'
Assert-ClawLabTest -Condition ((Resolve-ClawLabLanguage -Language 'xx-YY') -eq 'en') -Message 'Unknown languages must fall back to en.'

$formatted = Get-ClawLabString -Key 'install_success' -Arguments @('30-120 Hz') -Language 'en-US'
Assert-ClawLabTest -Condition ($formatted -eq 'Profile 30-120 Hz was installed successfully.') -Message 'Message formatting failed.'

$experimentalTrialKeys = @(
    'experimental_trial_confirmation',
    'experimental_trial_title',
    'experimental_keep_success',
    'experimental_declined',
    'experimental_recovery_success',
    'experimental_recovery_reported',
    'experimental_schedule_details'
)
foreach ($language in $expectedLanguages) {
    $yesKey = Get-ClawLabString -Key 'common_yes_key' -Language $language
    $noKey = Get-ClawLabString -Key 'common_no_key' -Language $language
    Assert-ClawLabTest -Condition (
        [Globalization.StringInfo]::ParseCombiningCharacters($yesKey).Count -eq 1
    ) -Message "Yes shortcut is not one localized text element for '$language'."
    Assert-ClawLabTest -Condition (
        [Globalization.StringInfo]::ParseCombiningCharacters($noKey).Count -eq 1
    ) -Message "No shortcut is not one localized text element for '$language'."
    Assert-ClawLabTest -Condition (
        -not $yesKey.Equals($noKey, [StringComparison]::CurrentCultureIgnoreCase)
    ) -Message "Yes and No shortcuts collide for '$language'."

    foreach ($key in $experimentalTrialKeys) {
        $message = Get-ClawLabString -Key $key -Language $language
        Assert-ClawLabTest -Condition ($message -ne "[$key]") -Message "Missing trial key '$key' for '$language'."
    }

    $confirmation = Get-ClawLabString -Key 'experimental_trial_confirmation' -Arguments @('144') -Language $language
    Assert-ClawLabTest -Condition ($confirmation.Contains('144')) -Message "Trial target frequency was lost for '$language'."

    $keptRange = Get-ClawLabString -Key 'experimental_keep_success' -Arguments @('30', '144') -Language $language
    Assert-ClawLabTest -Condition ($keptRange.Contains('30') -and $keptRange.Contains('144')) -Message "Kept trial range was lost for '$language'."

    $schedule = Get-ClawLabString -Key 'experimental_schedule_details' -Arguments @('48', '165') -Language $language
    Assert-ClawLabTest -Condition ($schedule.Contains('48') -and $schedule.Contains('165')) -Message "Scheduled trial range was lost for '$language'."

    $recovery = Get-ClawLabString -Key 'experimental_recovery_reported' -Arguments @('DETAIL_SENTINEL') -Language $language
    Assert-ClawLabTest -Condition ($recovery.Contains('DETAIL_SENTINEL')) -Message "Recovery detail was lost for '$language'."
}

Assert-ClawLabTest -Condition (
    (Get-ClawLabString -Key 'common_yes_key' -Language 'en') -eq 'Y' -and
    (Get-ClawLabString -Key 'common_no_key' -Language 'en') -eq 'N'
) -Message 'English Yes/No shortcuts must be Y/N.'
Assert-ClawLabTest -Condition (
    (Get-ClawLabString -Key 'common_yes_key' -Language 'fr') -eq 'O' -and
    (Get-ClawLabString -Key 'common_no_key' -Language 'fr') -eq 'N'
) -Message 'French Yes/No shortcuts must be O/N.'
Assert-ClawLabTest -Condition (
    (Get-ClawLabString -Key 'common_yes_key' -Language 'ko') -eq 'Y' -and
    (Get-ClawLabString -Key 'common_no_key' -Language 'ko') -eq 'N' -and
    (Get-ClawLabString -Key 'prompt_yes_no' -Language 'ko').Contains('Y') -and
    (Get-ClawLabString -Key 'prompt_yes_no' -Language 'ko').Contains('N')
) -Message 'Korean confirmations must use the community-requested Y/N shortcuts.'
Assert-ClawLabTest -Condition (
    (Get-ClawLabString -Key 'common_yes_key' -Language 'th') -eq ([string][char]0x0E0A) -and
    (Get-ClawLabString -Key 'common_no_key' -Language 'th') -eq ([string][char]0x0E21)
) -Message 'Thai Yes/No shortcuts must remain distinct localized consonants.'

$previousEnvironmentOverride = $env:CLAWLAB_LANGUAGE
$thread = [System.Threading.Thread]::CurrentThread
$previousUiCulture = $thread.CurrentUICulture
try {
    $env:CLAWLAB_LANGUAGE = $null
    Set-ClawLabLanguage -Language $null | Out-Null

    $thread.CurrentUICulture = [System.Globalization.CultureInfo]::GetCultureInfo('ja-JP')
    $savedUserLanguage = [System.Environment]::GetEnvironmentVariable(
        'CLAWLAB_LANGUAGE',
        [System.EnvironmentVariableTarget]::User
    )
    if ([string]::IsNullOrWhiteSpace($savedUserLanguage)) {
        Assert-ClawLabTest -Condition ((Resolve-ClawLabLanguage) -eq 'ja') -Message 'CurrentUICulture detection failed.'
    }
    else {
        Assert-ClawLabTest -Condition (
            (Resolve-ClawLabLanguage) -eq (Resolve-ClawLabLanguage -Language $savedUserLanguage)
        ) -Message 'Saved user-language preference was not honored.'
    }

    $env:CLAWLAB_LANGUAGE = 'es-MX'
    Assert-ClawLabTest -Condition ((Resolve-ClawLabLanguage) -eq 'es') -Message 'Environment language override failed.'

    Set-ClawLabLanguage -Language 'de-DE' | Out-Null
    Assert-ClawLabTest -Condition ((Resolve-ClawLabLanguage) -eq 'de') -Message 'Manual language override failed.'
    Assert-ClawLabTest -Condition ((Resolve-ClawLabLanguage -Language 'fr-CA') -eq 'fr') -Message 'Explicit language must take priority over the manual override.'

    Initialize-ClawLabLocalization -Language 'pt-BR' -CatalogPath $catalogPath | Out-Null
    Assert-ClawLabTest -Condition ((Resolve-ClawLabLanguage) -eq 'pt') -Message 'Initialization language override failed.'

    foreach ($language in $expectedLanguages) {
        $status = Get-ClawLabString -Key 'status_title' -Language $language
        Assert-ClawLabTest -Condition (-not [string]::IsNullOrWhiteSpace($status)) -Message "Empty lookup result for '$language'."
        Assert-ClawLabTest -Condition ($status -ne '[status_title]') -Message "Missing status_title for '$language'."

        $localizedFormat = Get-ClawLabString -Key 'diagnostics_saved' -Arguments @('C:\ClawLab\report.json') -Language $language
        Assert-ClawLabTest -Condition ($localizedFormat.Contains('C:\ClawLab\report.json')) -Message "Formatted value was lost for '$language'."
    }
}
finally {
    $thread.CurrentUICulture = $previousUiCulture
    $env:CLAWLAB_LANGUAGE = $previousEnvironmentOverride
    Set-ClawLabLanguage -Language $null | Out-Null
}

Write-Host "PASS: ClawLab localization catalog ($($validation.LanguageCount) languages, $($validation.MessageCount) messages)."
