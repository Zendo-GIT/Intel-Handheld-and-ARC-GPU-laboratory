# ClawLab offline localization foundation.
# Compatible with Windows PowerShell 5.1 and PowerShell 7+.

Set-StrictMode -Version 2.0

$script:ClawLabLocalizationDefaultCatalogPath = Join-Path $PSScriptRoot 'locales\messages.json'
$script:ClawLabLocalizationCatalog = $null
$script:ClawLabLocalizationCatalogPath = $null
$script:ClawLabLocalizationLanguageOverride = $null
$script:ClawLabLocalizationSupportedLanguages = @(
    'ar', 'bn', 'zh', 'cs', 'da', 'nl', 'en', 'fil', 'fi', 'fr', 'de', 'el',
    'hi', 'hu', 'id', 'it', 'ja', 'ko', 'mr', 'fa', 'pl', 'pt', 'pa', 'ro',
    'ru', 'es', 'sw', 'sv', 'ta', 'th', 'tr', 'uk', 'ur', 'vi'
)

function Get-ClawLabSupportedLanguages {
    [CmdletBinding()]
    param()

    return @($script:ClawLabLocalizationSupportedLanguages)
}

function Resolve-ClawLabLanguage {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Language
    )

    $candidate = $Language
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $candidate = $script:ClawLabLocalizationLanguageOverride
    }
    if ([string]::IsNullOrWhiteSpace($candidate) -and
        -not [string]::IsNullOrWhiteSpace($env:CLAWLAB_LANGUAGE)) {
        $candidate = $env:CLAWLAB_LANGUAGE
    }
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        try {
            $savedUserLanguage = [System.Environment]::GetEnvironmentVariable(
                'CLAWLAB_LANGUAGE',
                [System.EnvironmentVariableTarget]::User
            )
            if (-not [string]::IsNullOrWhiteSpace($savedUserLanguage)) {
                $candidate = $savedUserLanguage
            }
        }
        catch {
            # A locked-down user environment must not prevent automatic
            # CurrentUICulture detection or the English fallback.
        }
    }
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        try {
            $candidate = [System.Globalization.CultureInfo]::CurrentUICulture.Name
        }
        catch {
            $candidate = 'en'
        }
    }

    $normalized = ([string]$candidate).Trim().Replace('_', '-').ToLowerInvariant()
    $primary = ($normalized -split '-', 2)[0]
    if ($primary -eq 'tl') {
        $primary = 'fil'
    }

    if ($script:ClawLabLocalizationSupportedLanguages -contains $primary) {
        return $primary
    }

    return 'en'
}

function Import-ClawLabLocalizationCatalog {
    [CmdletBinding()]
    param(
        [string]$CatalogPath = $script:ClawLabLocalizationDefaultCatalogPath,
        [switch]$Force
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($CatalogPath)
    if (-not $Force -and
        $null -ne $script:ClawLabLocalizationCatalog -and
        $script:ClawLabLocalizationCatalogPath -eq $resolvedPath) {
        return $script:ClawLabLocalizationCatalog
    }

    if (-not [System.IO.File]::Exists($resolvedPath)) {
        throw "ClawLab localization catalog not found: $resolvedPath"
    }

    try {
        $raw = [System.IO.File]::ReadAllText($resolvedPath, [System.Text.Encoding]::UTF8)
        $catalog = $raw | ConvertFrom-Json
    }
    catch {
        throw "ClawLab localization catalog could not be loaded: $($_.Exception.Message)"
    }

    if ($null -eq $catalog -or
        $null -eq $catalog.PSObject.Properties['schemaVersion'] -or
        [int]$catalog.schemaVersion -ne 1 -or
        $null -eq $catalog.PSObject.Properties['locales']) {
        throw 'ClawLab localization catalog schema is invalid.'
    }

    $script:ClawLabLocalizationCatalog = $catalog
    $script:ClawLabLocalizationCatalogPath = $resolvedPath
    return $catalog
}

function Initialize-ClawLabLocalization {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Language,
        [string]$CatalogPath = $script:ClawLabLocalizationDefaultCatalogPath
    )

    [void](Import-ClawLabLocalizationCatalog -CatalogPath $CatalogPath)
    if ($PSBoundParameters.ContainsKey('Language')) {
        $script:ClawLabLocalizationLanguageOverride = Resolve-ClawLabLanguage -Language $Language
    }

    return Resolve-ClawLabLanguage
}

function Set-ClawLabLanguage {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Language
    )

    if ([string]::IsNullOrWhiteSpace($Language)) {
        $script:ClawLabLocalizationLanguageOverride = $null
    }
    else {
        $script:ClawLabLocalizationLanguageOverride = Resolve-ClawLabLanguage -Language $Language
    }

    return Resolve-ClawLabLanguage
}

function Get-ClawLabLocaleObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Language
    )

    if ($null -eq $script:ClawLabLocalizationCatalog) {
        [void](Import-ClawLabLocalizationCatalog)
    }

    $localeProperty = $script:ClawLabLocalizationCatalog.locales.PSObject.Properties[$Language]
    if ($null -eq $localeProperty) {
        $localeProperty = $script:ClawLabLocalizationCatalog.locales.PSObject.Properties['en']
    }
    if ($null -eq $localeProperty) {
        throw 'ClawLab localization catalog has no English fallback locale.'
    }

    return $localeProperty.Value
}

function Get-ClawLabString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Key,

        [Parameter(Position = 1)]
        [AllowNull()]
        [object[]]$Arguments,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Language
    )

    $resolvedLanguage = Resolve-ClawLabLanguage -Language $Language
    $locale = Get-ClawLabLocaleObject -Language $resolvedLanguage
    $messageProperty = $locale.PSObject.Properties[$Key]

    if ($null -eq $messageProperty -and $resolvedLanguage -ne 'en') {
        $fallback = Get-ClawLabLocaleObject -Language 'en'
        $messageProperty = $fallback.PSObject.Properties[$Key]
    }
    if ($null -eq $messageProperty) {
        return "[$Key]"
    }

    $template = [string]$messageProperty.Value
    if ($null -eq $Arguments -or $Arguments.Count -eq 0) {
        return $template
    }

    $formatCulture = [System.Globalization.CultureInfo]::InvariantCulture
    try {
        $formatCulture = [System.Globalization.CultureInfo]::GetCultureInfo($resolvedLanguage)
    }
    catch {
        # Some older Windows installations do not expose every neutral culture.
    }

    try {
        return [string]::Format($formatCulture, $template, [object[]]$Arguments)
    }
    catch {
        throw "ClawLab localization format error for key '$Key': $($_.Exception.Message)"
    }
}

function Format-ClawLabString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Key,

        [Parameter(Position = 1)]
        [AllowNull()]
        [object[]]$Arguments,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Language
    )

    return Get-ClawLabString -Key $Key -Arguments $Arguments -Language $Language
}

function Get-ClawLabFormatTokens {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Value
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return @()
    }

    $tokens = @(
        [regex]::Matches($Value, '(?<!\{)\{[0-9]+(?:,[^}:]+)?(?::[^}]+)?\}(?!\})') |
            ForEach-Object { $_.Value } |
            Sort-Object -Unique
    )
    return $tokens
}

function Test-ClawLabLocalizationCatalog {
    [CmdletBinding()]
    param(
        [string]$CatalogPath = $script:ClawLabLocalizationDefaultCatalogPath,
        [switch]$ThrowOnError
    )

    $errors = New-Object 'System.Collections.Generic.List[string]'
    try {
        $catalog = Import-ClawLabLocalizationCatalog -CatalogPath $CatalogPath -Force
    }
    catch {
        $errors.Add($_.Exception.Message)
        $catalog = $null
    }

    if ($null -ne $catalog) {
        $actualLanguages = @($catalog.locales.PSObject.Properties.Name | Sort-Object)
        $expectedLanguages = @($script:ClawLabLocalizationSupportedLanguages | Sort-Object)
        if (($actualLanguages -join ',') -ne ($expectedLanguages -join ',')) {
            $errors.Add("Language set mismatch. Expected: $($expectedLanguages -join ', '). Actual: $($actualLanguages -join ', ').")
        }
        if ($null -eq $catalog.PSObject.Properties['sourceLanguage'] -or
            [string]$catalog.sourceLanguage -ne 'en') {
            $errors.Add('The catalog sourceLanguage must be en.')
        }
        if ($null -eq $catalog.PSObject.Properties['languageCount'] -or
            [int]$catalog.languageCount -ne $actualLanguages.Count) {
            $errors.Add('The catalog languageCount metadata is incorrect.')
        }

        $englishProperty = $catalog.locales.PSObject.Properties['en']
        if ($null -eq $englishProperty) {
            $errors.Add('English fallback locale is missing.')
        }
        else {
            $englishMessages = $englishProperty.Value
            $expectedKeys = @($englishMessages.PSObject.Properties.Name | Sort-Object)
            $technicalTerms = @(
                'ClawLab', 'ClawTweaks', 'MSI Claw', 'Windows', 'Intel',
                'VRR', 'LFC', 'EDID', 'CRU', 'UAC', 'reset-all.exe'
            )
            if ($null -eq $catalog.PSObject.Properties['messageCount'] -or
                [int]$catalog.messageCount -ne $expectedKeys.Count) {
                $errors.Add('The catalog messageCount metadata is incorrect.')
            }
            foreach ($language in $script:ClawLabLocalizationSupportedLanguages) {
                $localeProperty = $catalog.locales.PSObject.Properties[$language]
                if ($null -eq $localeProperty) {
                    continue
                }

                $messages = $localeProperty.Value
                $actualKeys = @($messages.PSObject.Properties.Name | Sort-Object)
                if (($actualKeys -join ',') -ne ($expectedKeys -join ',')) {
                    $errors.Add("Message-key mismatch for locale '$language'.")
                    continue
                }

                foreach ($key in $expectedKeys) {
                    $translated = [string]$messages.PSObject.Properties[$key].Value
                    if ([string]::IsNullOrWhiteSpace($translated)) {
                        $errors.Add("Empty translation for locale '$language', key '$key'.")
                        continue
                    }
                    # Keep this PowerShell source strictly 7-bit ASCII. Windows
                    # PowerShell 5.1 decodes a UTF-8 file without a BOM through
                    # the active ANSI code page. Literal Unicode sentinels made
                    # this line syntactically invalid on Korean Windows. Regex
                    # Unicode escapes preserve the exact validation without
                    # making script parsing depend on the system language.
                    if ($translated -match 'ZXQ|QXZ|\u241F|\u241E|\uFFFD') {
                        $errors.Add("Internal translation marker found for locale '$language', key '$key'.")
                    }

                    $source = [string]$englishMessages.PSObject.Properties[$key].Value
                    $sourceTokens = @(Get-ClawLabFormatTokens -Value $source)
                    $translatedTokens = @(Get-ClawLabFormatTokens -Value $translated)
                    if (($sourceTokens -join ',') -ne ($translatedTokens -join ',')) {
                        $errors.Add("Format-token mismatch for locale '$language', key '$key'.")
                    }

                    foreach ($technicalTerm in $technicalTerms) {
                        if ($source.Contains($technicalTerm) -and
                            -not $translated.Contains($technicalTerm)) {
                            $errors.Add("Technical term '$technicalTerm' was not preserved for locale '$language', key '$key'.")
                        }
                    }

                    $sameAsEnglishAllowed = (
                        $key -in @('common_yes_key', 'common_no_key') -or
                        ($key -eq 'common_no' -and
                            @('es', 'it') -contains $language)
                    )
                    if ($language -ne 'en' -and
                        -not $sameAsEnglishAllowed -and
                        $translated -ceq $source) {
                        $errors.Add("Untranslated English message for locale '$language', key '$key'.")
                    }
                }

                $yesKey = ([string]$messages.common_yes_key).Trim()
                $noKey = ([string]$messages.common_no_key).Trim()
                if ([Globalization.StringInfo]::ParseCombiningCharacters($yesKey).Count -ne 1) {
                    $errors.Add("The localized Yes shortcut for '$language' must contain exactly one text element.")
                }
                if ([Globalization.StringInfo]::ParseCombiningCharacters($noKey).Count -ne 1) {
                    $errors.Add("The localized No shortcut for '$language' must contain exactly one text element.")
                }
                if ($yesKey.Equals($noKey, [StringComparison]::CurrentCultureIgnoreCase)) {
                    $errors.Add("The localized Yes and No shortcuts for '$language' must be distinct.")
                }
            }
        }
    }

    $result = [pscustomobject]@{
        IsComplete = ($errors.Count -eq 0)
        LanguageCount = if ($null -ne $catalog) { @($catalog.locales.PSObject.Properties).Count } else { 0 }
        MessageCount = if ($null -ne $catalog -and $null -ne $catalog.locales.PSObject.Properties['en']) {
            @($catalog.locales.PSObject.Properties['en'].Value.PSObject.Properties).Count
        }
        else {
            0
        }
        Errors = @($errors)
    }

    if ($ThrowOnError -and -not $result.IsComplete) {
        throw "ClawLab localization catalog validation failed:`r`n - $($result.Errors -join "`r`n - ")"
    }

    return $result
}
