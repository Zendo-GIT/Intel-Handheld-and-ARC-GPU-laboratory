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
driver state, installation records Intel Graphics Software's machine-wide Run
state. If the exact signed entry exists, it is backed up and removed. If both
the entry and Intel Graphics Software are absent, schema 4 records that absence
without inventing a registry value or command. The windowless task launches the
verified Intel-signed command with `-s` only when that application originally
existed, then applies and verifies the profile. Normal restore recreates the
original entry only when it existed. A new external entry appearing later is
preserved rather than deleted.

## Event-driven desktop cursor refresh

With the validated 30-120 configuration active, Windows can leave the entire
desktop at 30 Hz when only the hardware cursor changes. A scroll or other true
window animation immediately raises the panel to 120 Hz. Tests with
`DCompositionBoostCompositorClock` and Windows pointer trails did not change
this behavior. A genuine changing WPF/DWM surface did.

Version 2.1.0 therefore installs `ClawLab-Cursor-Refresh-Helper.exe`. The helper
registers a standard Raw Input mouse sink and changes a nearly transparent 2x2
WPF surface at the extreme lower-right coordinates:

```text
X = PrimaryScreenWidth  - 2
Y = PrimaryScreenHeight - 2
```

The render timer runs at an 8 ms request interval only while Raw Input arrives
and stops 500 ms after the last event. At idle, the timer is stopped and the
process waits in the Windows message loop. Real-hardware tests confirmed the
panel rises to 120 Hz during mouse activity, falls back to 30 Hz after activity,
and repeats that transition without a visible square at 1 percent opacity.

Before starting animation, the helper verifies that the system cursor is
visible. It deliberately does not reject full-monitor windows because Windows
Xbox Full Screen Experience is itself a full-monitor shell. It uses no DLL
injection, process handle, global code hook, game-file access,
network access, driver request or LFC operation.

The existing limited current-user sign-in task launches the helper only after
the managed Arc Sync profile has been reapplied and verified. Installation
copies the exact packaged binary, records its SHA-256, and startup refuses a
hash mismatch. Restore stops only the process whose executable path equals the
installed ClawLab path, then removes the binary and state record.

The LFC task starts the VRR reapply as a direct child and calls `WaitForExit()`
on that process object. `Start-Process -Wait` is deliberately not used here:
Windows PowerShell can wait for the complete descendant tree, which now
includes the intentionally resident Cursor Refresh Helper.

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

The 2.0.3 LFC correction remains unchanged in release 2.1.0 and is integrated
into both supported installers. Before
changing either flag, the shared script requires the exact managed-mode record,
the exact physical or pinned custom EDID expected for that mode, and the exact
active Intel range shown below:

| Managed mode | Required Intel range | Release role |
|---|---:|---|
| `CLAWLAB_30_120` | 30-120 Hz | Default corrected profile |
| `OFFICIAL_48_120` | 48-120 Hz | Official Intel/MSI range |

The observed removal of LFC x2 has been validated on real hardware at 30-120
Hz. The 48-120 path uses the identical guarded flag operation and per-range
readback, but this does not turn it into a separate claimed real-hardware LFC
validation.

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

### Claw A1M 30-120 transformation

The A1M Tianma EDID contains one 128-byte base block and no extension:

```text
Panel:   TMA2027 / TL070FVXS02-0
Bytes:   128
SHA-256: 3518AB4456669D12A7B8D254F63005EAE143C784DCE02EC56C3753C41A664CA1
```

Only two byte positions differ in the generated A1M override:

| Absolute offset | Meaning | Physical | ClawLab 30-120 |
|---:|---|---:|---:|
| `0x5F` | Base EDID range-descriptor minimum | `0x30` (48) | `0x1E` (30) |
| `0x7F` | Base-block checksum | `0x83` | `0x95` |

Generated A1M 30-120 SHA-256:

```text
7B5EE7D96BC91E83EBD2419B3A4F12771035D76303F77EEB0E356C996BFA4647
```

The catalog test reconstructs this block from pinned source bytes and verifies
its checksum and both hashes during release validation. The A1M path writes no
extension block. This validates the transformation, not untested physical-panel
behavior; the runtime installer additionally requires Intel Arc Sync and exact
range readback on the target device.

## Retired 144 Hz recovery identifiers

Version 2.1.0 contains no 144 Hz installer, installation action, fixed-refresh
selector or confirmation task. Exact complete and per-block hashes from older
ClawLab 48-144 and 30-144 releases remain pinned only to identify a known legacy
override. Normal restore first selects the detected panel's native resolution
at 120 Hz; normal,
factory and emergency recovery can then remove only those exact known blocks.
Unknown third-party data is still never removed. Startup and LFC reapply refuse
a retired 144 Hz managed record and direct the user to recovery.

## Signed Intel Graphics Software update detection

The ordered startup path pins the exact Intel Graphics Software identity after
validating its canonical path, `-s` argument and Windows Authenticode signature.
Graphics-driver updates can legitimately replace that executable. Version
2.1.0 compares the current SHA-256 and saved schema at every managed startup.

When they differ, the task performs a fresh Authenticode validation, requires a
valid signer whose certificate subject identifies Intel Corporation, recomputes
the file hash to detect a concurrent replacement, and atomically stores schema
4 identity metadata containing the original entry-presence flag, signer
thumbprint, file version and SHA-256.
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
