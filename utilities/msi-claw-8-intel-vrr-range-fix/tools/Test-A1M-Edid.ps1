[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$physicalSha256 = '3518AB4456669D12A7B8D254F63005EAE143C784DCE02EC56C3753C41A664CA1'
$custom30Sha256 = '7B5EE7D96BC91E83EBD2419B3A4F12771035D76303F77EEB0E356C996BFA4647'
$observedZeroPaddedSha256 = 'E0CE06B0510173DDCA88CE8FEA65B3E7B29183C8E3E67425A7CA6249C6C5B224'
$normalizationModule = Join-Path $PSScriptRoot '..\Edid-Normalization.ps1'
if (-not (Test-Path -LiteralPath $normalizationModule -PathType Leaf)) {
    $normalizationModule = Join-Path $PSScriptRoot '..\scripts\Edid-Normalization.ps1'
}
. $normalizationModule
$hex = @'
00 ff ff ff ff ff ff 00 51 a1 27 20 00 00 00 00
1e 21 01 04 a5 10 08 78 07 6e a1 a4 52 4c 9a 25
0f 50 54 00 00 00 01 01 01 01 01 01 01 01 01 01
01 01 01 01 01 01 8b 6f 80 a0 70 38 40 40 30 20
62 0c 9b 57 00 00 00 18 c6 37 80 a0 70 38 40 40
30 20 62 0c 9b 57 00 00 00 1a 00 00 00 fd 00 30
78 8c 8c 1d 01 0a 20 20 20 20 20 20 00 00 00 fc
00 54 4c 30 37 30 46 56 58 53 30 32 2d 30 00 83
'@

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

function Assert-EdidChecksum {
    param([Parameter(Mandatory)][byte[]]$Bytes)

    $sum = 0
    foreach ($value in $Bytes) {
        $sum = ($sum + $value) % 256
    }
    if ($sum -ne 0) {
        throw "EDID checksum verification failed: $sum"
    }
}

$tokens = @($hex -split '\s+' | Where-Object { $_ })
$physical = [byte[]]@($tokens | ForEach-Object { [Convert]::ToByte($_, 16) })
if ($physical.Length -ne 128) {
    throw "The pinned A1M EDID has an unexpected length: $($physical.Length)"
}
Assert-EdidChecksum -Bytes $physical
if ((Get-ByteArraySha256 -Bytes $physical) -ne $physicalSha256) {
    throw 'The pinned A1M physical EDID hash does not match its catalog identity.'
}

$zeroPadded = [byte[]]::new(256)
[Array]::Copy($physical, 0, $zeroPadded, 0, 128)
if ((Get-ByteArraySha256 -Bytes $zeroPadded) -ne $observedZeroPaddedSha256) {
    throw 'The reconstructed Windows zero-padded A1M buffer no longer matches both collected units.'
}
$normalized = Get-ClawLabCanonicalEdid -Bytes $zeroPadded -ExpectedLength 128
if ($normalized.State -ne 'ZERO_PADDED_128_NORMALIZED' -or
    $normalized.SourceLength -ne 256 -or
    (Get-ByteArraySha256 -Bytes ([byte[]]$normalized.Bytes)) -ne $physicalSha256) {
    throw 'The observed A1M 128-byte EDID plus 128-byte zero padding was not normalized safely.'
}
$invalidPadding = [byte[]]$zeroPadded.Clone()
$invalidPadding[200] = 1
$invalidPaddingRejected = $false
try { Get-ClawLabCanonicalEdid -Bytes $invalidPadding -ExpectedLength 128 | Out-Null }
catch { $invalidPaddingRejected = $true }
if (-not $invalidPaddingRejected) {
    throw 'A non-zero fake EDID extension was incorrectly accepted as padding.'
}
if ($physical[95] -ne 48 -or $physical[96] -ne 120 -or $physical[126] -ne 0) {
    throw 'The pinned A1M EDID no longer describes one 48-120 Hz base block.'
}

$custom = [byte[]]$physical.Clone()
$custom[95] = 30
$custom[127] = 0
$sum = 0
for ($index = 0; $index -lt 127; $index++) {
    $sum += $custom[$index]
}
$custom[127] = [byte]((256 - ($sum % 256)) % 256)
Assert-EdidChecksum -Bytes $custom
if ($custom[127] -ne 0x95) {
    throw ('The expected A1M custom checksum is 0x95, got 0x{0:X2}.' -f $custom[127])
}
if ((Get-ByteArraySha256 -Bytes $custom) -ne $custom30Sha256) {
    throw 'The generated A1M 30-120 Hz EDID hash does not match the catalog identity.'
}

[pscustomobject]@{
    Result = 'PASS'
    PanelId = 'TMA2027'
    PanelName = 'TL070FVXS02-0'
    PhysicalSha256 = $physicalSha256
    Custom30Sha256 = $custom30Sha256
    CustomChecksumByte = '0x95'
    ObservedWindowsPadding = '256_BYTES_WITH_ZERO_PADDED_TAIL_ACCEPTED'
    ObservedWindowsBufferSha256 = $observedZeroPaddedSha256
    NonZeroExtensionRejection = 'PASS'
}
