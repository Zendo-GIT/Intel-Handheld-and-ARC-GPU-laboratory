# MSI Claw A1M EDID reference

Release 2.1.0 includes a strict definition for the Intel-powered MSI Claw A1M
internal display. This document records the immutable inputs used by the
installer; it is not an instruction to flash panel firmware.

## Identity

| Field | Value |
|---|---|
| Panel manufacturer | Tianma Micro-Electronics |
| Module | `TL070FVXS02-00` |
| EDID product name | `TL070FVXS02-0` |
| PnP identity | `TMA2027` / `MONITOR\TMA2027` |
| Native resolution | 1920x1080 |
| Preferred refresh | 120 Hz |
| Native VRR descriptor | 48-120 Hz |
| EDID length | 128 bytes, no extension |
| Physical SHA-256 | `3518AB4456669D12A7B8D254F63005EAE143C784DCE02EC56C3753C41A664CA1` |

## Pinned physical EDID

```text
00 ff ff ff ff ff ff 00 51 a1 27 20 00 00 00 00
1e 21 01 04 a5 10 08 78 07 6e a1 a4 52 4c 9a 25
0f 50 54 00 00 00 01 01 01 01 01 01 01 01 01 01
01 01 01 01 01 01 8b 6f 80 a0 70 38 40 40 30 20
62 0c 9b 57 00 00 00 18 c6 37 80 a0 70 38 40 40
30 20 62 0c 9b 57 00 00 00 1a 00 00 00 fd 00 30
78 8c 8c 1d 01 0a 20 20 20 20 20 20 00 00 00 fc
00 54 4c 30 37 30 46 56 58 53 30 32 2d 30 00 83
```

The extension-count byte is `0x00` and the checksum byte is `0x83`. The sum of
all 128 bytes is zero modulo 256.

## ClawLab 30-120 derivation

The generator changes the range-descriptor minimum at `0x5F` from `0x30`
(48) to `0x1E` (30), then recomputes the base-block checksum from `0x83` to
`0x95`. It writes this single block as Windows `EDID_OVERRIDE\0`; no block 1 is
created.

Generated SHA-256:
`7B5EE7D96BC91E83EBD2419B3A4F12771035D76303F77EEB0E356C996BFA4647`.

Run `tools\Test-A1M-Edid.ps1` to rebuild and verify the custom identity without
accessing a display device.

## Validation boundary

The physical bytes, checksum, identity and deterministic 30-120 transformation
are verified. Installation additionally fails closed unless the target A1M
returns the exact identity, EDID and Intel Arc Sync range. Real A1M panel/LFC
behavior was not available for development validation and remains explicitly
community-validation pending.
