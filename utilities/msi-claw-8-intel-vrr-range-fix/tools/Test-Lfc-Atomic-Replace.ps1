[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testRoot = [IO.Path]::GetFullPath((Join-Path $temporaryRoot ('ClawLab-Lfc-Atomic-Test-{0}' -f [Guid]::NewGuid().ToString('N'))))
if (-not $testRoot.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe atomic test path: $testRoot"
}

try {
    [IO.Directory]::CreateDirectory($testRoot) | Out-Null
    $destinationPath = Join-Path $testRoot 'original-intel-vrr-solutions.json'
    $temporaryPath = Join-Path $testRoot '.lfc-backup.tmp'
    $replacementBackupPath = Join-Path $testRoot '.lfc-previous.bak'

    [IO.File]::WriteAllText($destinationPath, '{"SchemaVersion":3}', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($temporaryPath, '{"SchemaVersion":4}', [Text.UTF8Encoding]::new($false))
    [IO.File]::Replace($temporaryPath, $destinationPath, $replacementBackupPath)

    $current = [IO.File]::ReadAllText($destinationPath, [Text.Encoding]::UTF8)
    $previous = [IO.File]::ReadAllText($replacementBackupPath, [Text.Encoding]::UTF8)
    if ($current -ne '{"SchemaVersion":4}' -or $previous -ne '{"SchemaVersion":3}') {
        throw 'Atomic replacement did not preserve both the new and previous data correctly.'
    }

    [pscustomobject]@{
        Result = 'PASS'
        Runtime = [Environment]::Version.ToString()
        Replacement = 'REAL_SAME_DIRECTORY_BACKUP_PATH'
        PreviousDataPreserved = $true
    }
}
finally {
    if (Test-Path -LiteralPath $testRoot -PathType Container) {
        [IO.Directory]::Delete($testRoot, $true)
    }
}
