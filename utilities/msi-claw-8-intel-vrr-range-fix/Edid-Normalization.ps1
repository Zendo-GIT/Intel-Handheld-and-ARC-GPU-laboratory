Set-StrictMode -Version Latest

function Get-ClawLabCanonicalEdid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][byte[]]$Bytes,
        [Parameter(Mandatory)][ValidateSet(128, 256)][int]$ExpectedLength
    )

    if ($Bytes.Length -eq $ExpectedLength) {
        return [pscustomobject]@{
            Bytes = [byte[]]$Bytes.Clone()
            SourceLength = $Bytes.Length
            State = 'EXACT_LENGTH'
        }
    }

    # Some Claw A1M / Claw 7 AI+ Intel configurations expose the physical
    # 128-byte EDID followed by one entirely zero-filled 128-byte buffer. The
    # base block itself declares zero extensions. Accept only that exact,
    # non-semantic padding shape; every other length/content combination stays
    # rejected and the canonical 128-byte block is still checked by SHA-256.
    if ($ExpectedLength -eq 128 -and $Bytes.Length -eq 256) {
        $baseBlock = [byte[]]$Bytes[0..127]
        $paddingIsZero = $true
        for ($index = 128; $index -lt 256; $index++) {
            if ($Bytes[$index] -ne 0) {
                $paddingIsZero = $false
                break
            }
        }
        if ($baseBlock[126] -eq 0 -and $paddingIsZero) {
            return [pscustomobject]@{
                Bytes = $baseBlock
                SourceLength = $Bytes.Length
                State = 'ZERO_PADDED_128_NORMALIZED'
            }
        }
    }

    throw "Unexpected panel EDID length/content: $($Bytes.Length) bytes."
}
