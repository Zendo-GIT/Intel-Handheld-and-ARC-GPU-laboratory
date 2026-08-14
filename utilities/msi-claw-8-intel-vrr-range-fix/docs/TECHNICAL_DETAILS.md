# Technical details

## Confirmed driver behavior

Direct Intel Control Library queries on the reference panel returned:

```text
ctlGetIntelArcSyncInfoForMonitor:
  supported = true
  minimum = 48 Hz
  maximum = 120 Hz

ctlGetIntelArcSyncProfile before:
  profile = RECOMMENDED
  active minimum = 60 Hz
  active maximum = 120 Hz

ctlGetIntelArcSyncProfile after EXCELLENT:
  profile = EXCELLENT
  active minimum = 48 Hz
  active maximum = 120 Hz
```

Reopening Intel Graphics Software did not revert the profile. A new direct query
still returned `EXCELLENT / 48-120 Hz`, even though the application UI could
continue showing `60-120 Hz`.

## Why custom 30 Hz is not the official path

A direct call requesting `CUSTOM / 30-120 Hz` against the physical `48-120 Hz`
monitor capability returned:

```text
0x4000000B = CTL_RESULT_ERROR_INVALID_ARGUMENT
```

Intel's sample documents that custom minimum and maximum values must remain
inside the panel-supported range. The release therefore never claims that a
custom profile alone can unlock 30 Hz.

## Experimental EDID transformation

Validated physical EDID:

```text
Bytes:   256
SHA-256: E49BC570225510B7C889ED292570F1345CAA07F5840DB57EA6998A403DB5CEF0
```

Only four byte positions differ in the generated override:

| Absolute offset | Meaning | Physical | Experimental |
|---:|---|---:|---:|
| `0x5F` | Base EDID range-descriptor minimum | `0x30` (48) | `0x1E` (30) |
| `0x7F` | Base-block checksum | `0xEF` | `0x01` |
| `0x8E` | DisplayID Adaptive-Sync minimum | `0x30` (48) | `0x1E` (30) |
| `0xFF` | Extension-block checksum | `0x90` | `0xA2` |

Generated experimental EDID SHA-256:

```text
14CDDC390CF69367C4B6821A46728518200446A33F708A1A87CA673B68B66918
```

Both 128-byte blocks retain a checksum sum of zero modulo 256. The script writes
them as separate Windows EDID override blocks, matching Microsoft's documented
monitor-driver mechanism. The physical EEPROM remains unchanged.

## Restart model

Windows reads monitor EDID override blocks while initializing the monitor
device. Experimental installation and removal therefore require a restart.
Every mutating batch file presents an explicit `Y/N` restart choice. No restart
occurs without the user selecting `Y`.

Official profile changes are live, but the same restart choice is presented for
a consistent installation flow and to clear stale display-control UI state.
