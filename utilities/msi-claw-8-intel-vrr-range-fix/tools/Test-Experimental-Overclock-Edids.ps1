[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Convert-HexEdid {
    param([Parameter(Mandatory)][string]$Hex)
    return [byte[]]@($Hex -split '\s+' | Where-Object { $_ } | ForEach-Object { [Convert]::ToByte($_, 16) })
}

function Get-Sha256 {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '') }
    finally { $sha.Dispose() }
}

function Set-Checksum {
    param([Parameter(Mandatory)][byte[]]$Bytes, [Parameter(Mandatory)][int]$Start)
    $sum = 0
    for ($index = $Start; $index -lt ($Start + 127); $index++) { $sum += $Bytes[$index] }
    $Bytes[$Start + 127] = [byte]((256 - ($sum % 256)) % 256)
}

function Assert-Hash {
    param([Parameter(Mandatory)][byte[]]$Bytes, [Parameter(Mandatory)][string]$Expected, [Parameter(Mandatory)][string]$Label)
    $actual = Get-Sha256 -Bytes $Bytes
    if ($actual -ne $Expected) { throw "$Label hash mismatch. Expected $Expected, got $actual." }
}

[byte[]]$csw = Convert-HexEdid @'
00 ff ff ff ff ff ff 00 0e 77 01 08 00 00 00 00
00 22 01 04 a5 11 0b 78 03 b2 41 a5 54 4c 9e 24
0d 4e 53 00 00 00 01 01 01 01 01 01 01 01 01 01
01 01 01 01 01 01 3e 7b 80 a0 70 b0 40 40 30 20
66 0c ac 6b 00 00 00 18 9f 3d 80 a0 70 b0 40 40
30 20 66 0c ac 6b 00 00 00 18 00 00 00 fd 00 1e
78 98 98 20 01 0a 20 20 20 20 20 20 00 00 00 fc
00 50 4e 38 30 30 37 51 42 31 2d 32 0a 20 01 01
70 20 79 02 00 81 00 14 74 1a 00 00 03 01 1e 78
00 00 00 00 00 00 78 00 00 00 00 80 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 9e a2
'@
$csw[95] = 48
$csw[142] = 48
Set-Checksum -Bytes $csw -Start 0
Set-Checksum -Bytes $csw -Start 128
Assert-Hash -Bytes $csw -Expected 'E49BC570225510B7C889ED292570F1345CAA07F5840DB57EA6998A403DB5CEF0' -Label 'CSW physical EDID'

[byte[]]$tma = Convert-HexEdid @'
00 ff ff ff ff ff ff 00 51 a1 27 20 00 00 00 00
1e 21 01 04 a5 10 08 78 07 6e a1 a4 52 4c 9a 25
0f 50 54 00 00 00 01 01 01 01 01 01 01 01 01 01
01 01 01 01 01 01 8b 6f 80 a0 70 38 40 40 30 20
62 0c 9b 57 00 00 00 18 c6 37 80 a0 70 38 40 40
30 20 62 0c 9b 57 00 00 00 1a 00 00 00 fd 00 30
78 8c 8c 1d 01 0a 20 20 20 20 20 20 00 00 00 fc
00 54 4c 30 37 30 46 56 58 53 30 32 2d 30 00 83
'@
Assert-Hash -Bytes $tma -Expected '3518AB4456669D12A7B8D254F63005EAE143C784DCE02EC56C3753C41A664CA1' -Label 'TMA physical EDID'

$expected = @{
    'CSW_48_144' = '4CFB165CE96119BA37A07176F9D346691D447E0A40E8697777E499E1556A744E'
    'CSW_48_165' = 'FBB2CEFA8A0CC36CD5231D1070D4271165CAB9EA43A22271E3B2FD49D6914677'
    'CSW_48_180' = '279EA02FF5AEB3FA474235ECFCD3119AE7845A969C2F6BB7A63866CC3151EF62'
    'CSW_48_192' = 'DC60F9E3CC7B33C4F094181C57E4AF271C1BFB4449AFDE2614B4EAC27C032752'
    'CSW_30_144' = '0B8E8A25325B4D9CAC2B6A03CF9B574688B1A6D2DEDF10401605C4898E0CAC05'
    'CSW_30_165' = '8EDC82A04D9E1FAD037CA4D794D53BD0D374C9554059B137E75C40D9F9C416A7'
    'CSW_30_180' = '0D1969CF0C7CFBA3CF9F077667C1427E202DB895DFA0A750FAF1323F57A88E4B'
    'CSW_30_192' = '949A7143DB4549FC7D0D36F9F2521A528C1C796DE8F3F1FA948E4B3DBF5ECED6'
    'TMA_48_144' = 'AF1F6DEB144767F089522C37B89C1171DE59D06107B5F5073877A5693EBC9ADB'
    'TMA_48_165' = '89B0BDD6ACEB5A2320F235864314CC33CD67E4F3E4107E21573D506594E902D2'
    'TMA_48_180' = '0AA3BFD4DA2D6EB8D36BBA9F87CD476D453AD86651348CC3D17E8314BD3C898D'
    'TMA_48_192' = '4FA15135645E89BF10DA6B007921BA6702E03951C8FB9D2E2576F2837AD02BDE'
    'TMA_30_144' = 'DFD9CBDDB7C0B8A711F026C43E3EB73165958F2E129857B97EB7EB008CB71B5E'
    'TMA_30_165' = 'C0147C505E16907C62E66B56A3436870B591E1CB7B2FBA6CA410EEE3BEBDDC51'
    'TMA_30_180' = 'CE853C0CB689CC6247E72E59C7965FEDCAE49479BCFD04EE7959FA3113A9D679'
    'TMA_30_192' = '6553A5DA6651D29D447F0E0D14EC80CA631B1178544DA60E1CC2D54C4FAFB4C9'
}

$expected192Blocks = @{
    'CSW_48_192_0' = '1BFACB4E04EA4311DB37602B37993084B92224409D74F1E02B72FB60960780DA'
    'CSW_48_192_1' = 'D64A5FBADB951D28D0B48D798E90844192D91974F60331E95FBF7AEB8A90E93E'
    'CSW_30_192_0' = 'F2C2663185750971DDCB28E8398F4F39E42E97864F0D738069003C5A26F98B42'
    'CSW_30_192_1' = '10768276A262262FC0C99256AE0E2AFD23CFE6C2061A4FC90918AB758CA3FEFE'
    'TMA_48_192_0' = '4FA15135645E89BF10DA6B007921BA6702E03951C8FB9D2E2576F2837AD02BDE'
    'TMA_30_192_0' = '6553A5DA6651D29D447F0E0D14EC80CA631B1178544DA60E1CC2D54C4FAFB4C9'
}

foreach ($minimum in @(48, 30)) {
    foreach ($maximum in @(144, 165, 180, 192)) {
        $variant = [byte[]]$csw.Clone()
        $variant[95] = [byte]$minimum
        $variant[96] = [byte]$maximum
        $variant[142] = [byte]$minimum
        $variant[143] = [byte]$maximum
        $pixelClockKHz = [uint32]([Math]::Floor((2080.0 * 1264.0 * $maximum) / 1000.0) - 1)
        $timing = [byte[]]@(
            0x22, 0x00, 0x14,
            [byte]($pixelClockKHz -band 0xFF), [byte](($pixelClockKHz -shr 8) -band 0xFF),
            [byte](($pixelClockKHz -shr 16) -band 0xFF), [byte](($pixelClockKHz -shr 24) -band 0xFF),
            0x7F, 0x07, 0x9F, 0x00, 0x2F, 0x00, 0x1F, 0x00,
            0xAF, 0x04, 0x3F, 0x00, 0x35, 0x00, 0x05, 0x00
        )
        [Array]::Copy($timing, 0, $variant, 156, $timing.Length)
        Set-Checksum -Bytes $variant -Start 0
        Set-Checksum -Bytes $variant -Start 128
        Assert-Hash -Bytes $variant -Expected $expected["CSW_${minimum}_${maximum}"] -Label "CSW $minimum-$maximum"
        if ($maximum -eq 192) {
            Assert-Hash -Bytes ([byte[]]$variant[0..127]) -Expected $expected192Blocks["CSW_${minimum}_192_0"] -Label "CSW $minimum-192 block 0"
            Assert-Hash -Bytes ([byte[]]$variant[128..255]) -Expected $expected192Blocks["CSW_${minimum}_192_1"] -Label "CSW $minimum-192 block 1"
        }

        $variant = [byte[]]$tma.Clone()
        $variant[95] = [byte]$minimum
        $variant[96] = [byte]$maximum
        [Array]::Copy($tma, 54, $variant, 72, 18)
        $pixelClock10KHz = [uint16][Math]::Round((2080.0 * 1144.0 * $maximum) / 10000.0)
        $variant[72] = [byte]($pixelClock10KHz -band 0xFF)
        $variant[73] = [byte](($pixelClock10KHz -shr 8) -band 0xFF)
        $variant[98] = [byte][Math]::Ceiling((1144.0 * $maximum) / 1000.0)
        $variant[99] = [byte][Math]::Ceiling((2080.0 * 1144.0 * $maximum) / 10000000.0)
        Set-Checksum -Bytes $variant -Start 0
        Assert-Hash -Bytes $variant -Expected $expected["TMA_${minimum}_${maximum}"] -Label "TMA $minimum-$maximum"
        if ($maximum -eq 192) {
            Assert-Hash -Bytes $variant -Expected $expected192Blocks["TMA_${minimum}_192_0"] -Label "TMA $minimum-192 block 0"
        }
    }
}

[pscustomobject]@{
    Result = 'PASS'
    ProfilesVerified = 16
    PanelsVerified = 'CSW0801, TMA2027'
    Unsupported24HzProfiles = 0
}
