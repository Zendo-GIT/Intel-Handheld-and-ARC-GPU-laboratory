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

A later full Windows restart did revert the direct driver state to
`RECOMMENDED / 60-120 Hz`. Release installation therefore creates a
current-user sign-in task that waits for the display API and applies
`EXCELLENT` as soon as the driver becomes available.

The task originally waited for Intel Graphics Software, but further testing
showed that dependency was unnecessary. After task reapply, the direct driver
state was already `48-120 Hz`; completely exiting and restarting the Intel
Graphics Software tray process merely refreshed its cached current-range text
from 60-120 to 48-120 Hz.

To guarantee correct text on the application's first launch as well as correct
driver state, installation backs up and removes Intel Graphics Software's exact
machine-wide Run value. The windowless task launches the previously verified
Intel-signed command with its original `-s` argument, allows initialization to
settle, then applies and verifies the profile. Normal restore writes the exact
original Run value back.

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

## Experimental 48-144 Hz overclock

The 48-144 override leaves the 48 Hz floor unchanged, raises both
pinned range maxima to 144, and inserted one DisplayID 2.0 Type VII timing:

```text
Active:       1920x1200
Refresh:      144 Hz
Totals:       2080x1264
Pixel clock:  378.593 MHz
EDID SHA-256: 4CFB165CE96119BA37A07176F9D346691D447E0A40E8697777E499E1556A744E
```

The native 60 and 120 Hz detailed timings remained present. During guarded
real-hardware testing, applying the mode caused transient stutter and line
artifacts while the Intel device reloaded. Once active, the fixed 144 Hz image
remained stable, Windows exposed 1920x1200 at 144 Hz, and the Intel API read
back `EXCELLENT / 48-144 Hz`.

A separate guarded 30-144 test was also accepted by the Intel API as
`EXCELLENT / 30-144 Hz`, but the panel visibly flickered while active. That
combination failed visual validation and has no public installer.

Follow-up game testing did not reliably validate functioning VRR behavior at
144 Hz. A stable fixed overclock and an API range readback do not prove that
variable refresh is operating. Version 1.0.3 therefore keeps 48-144 only as an
explicit experimental panel-refresh overclock: fixed 144 Hz was stable on
tested panels, but VRR at 144 Hz or throughout the advertised range is not
guaranteed.

For the exact managed 48-144 state, startup first selects the enumerated
1920x1200 at 144 Hz Windows mode, waits for the display path to settle, launches
the verified Intel Graphics Software command, then applies and verifies Intel
`EXCELLENT / 48-144 Hz`. The status result confirms the declared EDID, fixed
mode and API range only; it deliberately makes no claim about per-game VRR.

The 30-144 complete and per-block hashes remain in the source only so normal,
emergency and factory recovery can identify and remove an existing ClawLab
override without touching unknown third-party data.

## Signed Intel Graphics Software update detection

The ordered startup path pins the exact Intel Graphics Software identity after
validating its canonical path, `-s` argument and Windows Authenticode signature.
Graphics-driver updates can legitimately replace that executable. Version
1.0.3 compares the current SHA-256 and saved schema at every managed startup.

When they differ, the task performs a fresh Authenticode validation, requires a
valid signer whose certificate subject identifies Intel Corporation, recomputes
the file hash to detect a concurrent replacement, and atomically stores schema
2 identity metadata containing the signer thumbprint, file version and SHA-256.
The identity is checked again before launch. Failure at any stage prevents the
application launch and VRR reapply rather than trusting a hash change alone.

## Managed-mode transition model

The utility treats mode selection as an explicit state transition:

```text
CLEAN -> one installer -> MANAGED MODE
MANAGED MODE -> same installer -> MANAGED MODE
MANAGED MODE -> different installer -> REFUSED
MANAGED MODE -> RESTORE_ORIGINAL_VRR -> CLEAN
BROKEN/UNKNOWN -> FACTORY_RESET_CLAWLAB_VRR -> CLEAN after restart
```

The managed record is written only after installation verification. The current
EDID override must match the recorded experimental mode, while official mode
requires no EDID override. `ApplyStartup` also requires this invariant before it
can touch the fixed refresh or Arc Sync profile.

Factory recovery deliberately restores Intel profile ID 1 (`RECOMMENDED`), not
`EXCELLENT`, because its objective is the vendor-default software state. Once
the physical EDID reloads after restart, the expected default active range is
the driver-selected subset of the native 48-120 Hz panel capability.

Recovery classification is block-based rather than requiring a valid complete
experimental pair. This permits repair after an interrupted or cross-profile
write left block 0 and block 1 from different ClawLab variants. Each present
block must still match one of the pinned ClawLab hashes; an unknown block is
never removed.

## Restart model

Windows reads monitor EDID override blocks while initializing the monitor
device. Experimental installation and removal therefore require a restart.
Every mutating batch file presents an explicit `Y/N` restart choice. No restart
occurs without the user selecting `Y`.

Official profile changes are live, but the driver does not persist them reliably
through a full restart. The sign-in task reapplies the profile only after Intel
startup initialization. The same restart choice is presented to validate that
complete ordered-startup path. Stale text from a pre-installation session can be
refreshed by fully exiting and restarting the tray process.
