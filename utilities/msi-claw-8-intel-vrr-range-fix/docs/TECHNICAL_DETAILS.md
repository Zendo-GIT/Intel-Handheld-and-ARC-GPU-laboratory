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

## Shared Intel LFC x2 correction

On driver 32.0.101.8974, game telemetry showed Intel's Adaptive Sync Plus/LFC
path multiplying refresh inside the desired range (`60 FPS -> 120 Hz` and
`68 FPS -> 136 Hz` were observed). Installing only the 30-120 EDID was not
sufficient. The validated result required all of the following at the same time:

```text
Managed mode:                 CLAWLAB_30_120
Arc Sync profile:             EXCELLENT
Monitor/driver range:         30-120 Hz
LowFpsSolutionEnabled:        false
HighFpsSolutionEnabled:       false
Third-party profile overwrite: none
```

`MSI-Claw-Intel-LFC-Fix.ps1` uses `D3DKMTEscape` with Intel's driver-private
VRR display payload. Read operation 0 returns the current range and solution
flags; operations 4 and 6 disable the low- and high-FPS solutions. The script
backs up both original values before using them and operations 3 and 5 restore
them. Every change is read back, and a range change or failed flag verification
causes rollback.

Release 2.0.1 integrates this same correction into all four installers. Before
changing either flag, the shared script requires the exact managed-mode record,
the exact physical or pinned custom EDID expected for that mode, and the exact
active Intel range shown below:

| Managed mode | Required Intel range | Release role |
|---|---:|---|
| `CLAWLAB_30_120` | 30-120 Hz | Default corrected profile |
| `OFFICIAL_48_120` | 48-120 Hz | Official Intel/MSI range |
| `CLAWLAB_48_144` | 48-144 Hz | Experimental overclock |
| `CLAWLAB_30_144` | 30-144 Hz | Experimental overclock |

The observed removal of LFC x2 has been validated on real hardware at 30-120
Hz. The 48-120 and 144 Hz paths use the identical guarded flag operation and
per-range readback, but this does not turn those configurations into claimed
real-hardware LFC validation. Both 144 Hz profiles remain experimental.

This driver-private path is independent of both Intel Graphics Software and the
legacy Intel Graphics Command Center application assemblies. It is transparent
source code, but it is not a documented public Intel API. The two flags remain
a single empirically validated combination; the project does not infer which
one alone causes the x2 behavior.

The consequence is intentional: Intel's refresh-multiplication solution below
the selected floor is disabled. Frames below 30 FPS in a 30 Hz profile, or
below 48 FPS in a 48 Hz profile, remain outside the corrected direct-VRR range.

## Validated 30-120 EDID transformation

Validated physical EDID:

```text
Bytes:   256
SHA-256: E49BC570225510B7C889ED292570F1345CAA07F5840DB57EA6998A403DB5CEF0
```

Only four byte positions differ in the generated override:

| Absolute offset | Meaning | Physical | ClawLab 30-120 |
|---:|---|---:|---:|
| `0x5F` | Base EDID range-descriptor minimum | `0x30` (48) | `0x1E` (30) |
| `0x7F` | Base-block checksum | `0xEF` | `0x01` |
| `0x8E` | DisplayID Adaptive-Sync minimum | `0x30` (48) | `0x1E` (30) |
| `0xFF` | Extension-block checksum | `0x90` | `0xA2` |

Generated 30-120 EDID SHA-256:

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
`EXCELLENT / 30-144 Hz`, but the panel visibly flickered while active. Release
2.0.1 therefore exposes it only as a prominently warned, self-rolling trial.

Follow-up game testing did not reliably validate functioning VRR behavior at
144 Hz. A stable fixed overclock and an API range readback do not prove that
variable refresh is operating. Version 2.0.1 therefore keeps 48-144 only as an
explicit experimental panel-refresh overclock: fixed 144 Hz was stable on
tested panels, but VRR at 144 Hz or throughout the advertised range is not
guaranteed.

Both 144 Hz installers write the pinned override, install the shared LFC x2
correction and register a temporary current-user confirmation task. At the next
sign-in, the normal startup task selects 1920x1200 at 144 Hz and verifies Intel
`EXCELLENT` at the requested range. The trial task also requires both Intel
low/high-FPS solution flags to remain disabled, then observes that complete
state for 20 seconds and asks the user whether to keep it. A No answer, closed
dialog, 30-second timeout or verification failure restores the original LFC
flags, selects 120 Hz, runs the normal restore path and restarts Windows. A Yes
answer keeps the profile and removes only the temporary task.

For the exact managed 48-144 state, startup first selects the enumerated
1920x1200 at 144 Hz Windows mode, waits for the display path to settle, launches
the verified Intel Graphics Software command, then applies and verifies Intel
`EXCELLENT / 48-144 Hz`. The status result confirms the declared EDID, fixed
mode and API range only; it deliberately makes no claim about per-game VRR.

The 30-144 complete and per-block hashes are pinned for installation,
verification, normal restore, emergency recovery and factory recovery. Unknown
third-party data is still never removed.

## Signed Intel Graphics Software update detection

The ordered startup path pins the exact Intel Graphics Software identity after
validating its canonical path, `-s` argument and Windows Authenticode signature.
Graphics-driver updates can legitimately replace that executable. Version
2.0.1 compares the current SHA-256 and saved schema at every managed startup.

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
EDID override must match the recorded custom mode, while official mode
requires no EDID override. `ApplyStartup` also requires this invariant before it
can touch the fixed refresh or Arc Sync profile.

Factory recovery deliberately restores Intel profile ID 1 (`RECOMMENDED`), not
`EXCELLENT`, because its objective is the vendor-default software state. Once
the physical EDID reloads after restart, the expected default active range is
the driver-selected subset of the native 48-120 Hz panel capability.

Recovery classification is block-based rather than requiring a valid complete
custom pair. This permits repair after an interrupted or cross-profile
write left block 0 and block 1 from different ClawLab variants. Each present
block must still match one of the pinned ClawLab hashes; an unknown block is
never removed.

## Restart model

Windows reads monitor EDID override blocks while initializing the monitor
device. Custom-range installation and removal therefore require a restart.
Every mutating batch file presents an explicit `Y/N` restart choice. No restart
occurs without the user selecting `Y`.

Official profile changes are live, but the driver does not persist them reliably
through a full restart. The sign-in task reapplies the profile only after Intel
startup initialization. The same restart choice is presented to validate that
complete ordered-startup path. Stale text from a pre-installation session can be
refreshed by fully exiting and restarting the tray process.
