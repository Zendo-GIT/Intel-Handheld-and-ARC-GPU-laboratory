# MSI Claw Intel VRR Range Fix

![Version](https://img.shields.io/badge/release-2.2.1-blue)
![Stable profiles](https://img.shields.io/badge/stable-30--120_%2F_48--120_Hz-green)
![Experimental maximum](https://img.shields.io/badge/experimental-up_to_192_Hz-orange)

ClawLab 2.2.1 corrects Intel Arc VRR/LFC behavior on exact, pinned internal
panels used by these handhelds:

- MSI Claw A1M;
- MSI Claw 7 AI+;
- MSI Claw 8 AI+;
- MSI Claw 8 EX AI+.

The utility changes global Windows/Intel display state only. It never injects
into, patches, hooks, opens or monitors a game process.

See the [2.2.1 release notes](docs/RELEASE_NOTES_2.2.1.md),
[compatibility](docs/COMPATIBILITY.md), [safety](docs/SAFETY.md), and
[technical details](docs/TECHNICAL_DETAILS.md).

## Stable public profiles

- `INSTALL_30_120_VRR.bat` — ClawLab default 30–120 Hz profile. The 30 Hz
  floor is outside MSI's official 48 Hz minimum but is the primary validated
  ClawLab profile.
- `INSTALL_48_120_VRR.bat` — official Intel/MSI 48–120 Hz panel range.

Both profiles include the Intel LFC x2 correction. It saves the original Intel
low/high-FPS solution flags, disables both as one verified combination, reads
the final state back from the driver, and reapplies it once at sign-in. It does
not install a continuous LFC watcher.

## Experimental display-overclock profiles

The `EXPERIMENTAL` folder contains:

| Profile | Classification | Validation |
|---|---|---|
| 48–144 Hz | **Stable Experimental** | Tested on one MSI Claw 8 AI+ Polar Tempest Edition |
| 48–165 Hz | **Unstable Experimental** | Untested; panel silicon lottery |
| 48–180 Hz | **Unstable Experimental** | Untested; panel silicon lottery |
| 48–192 Hz | **Unstable Experimental** | Untested; extreme overclock and panel silicon lottery |
| 30–144 Hz | **Unstable Experimental** | Untested; unofficial 30 Hz floor plus overclock |
| 30–165 Hz | **Unstable Experimental** | Untested; unofficial 30 Hz floor plus overclock |
| 30–180 Hz | **Unstable Experimental** | Untested; unofficial 30 Hz floor plus overclock |
| 30–192 Hz | **Unstable Experimental** | Untested; unofficial 30 Hz floor plus extreme overclock |

“Stable Experimental” is a ClawLab classification, not an MSI specification or
a guarantee for another unit. Every refresh rate above 120 Hz is a display
overclock. Success depends on the individual panel silicon lottery, even when
the model and EDID are identical.

The 192 Hz profiles provide an optional display target that can align with a
48 FPS ×4 frame-generation output. They do not install, enable or guarantee
XeSS/XeFG and remain untested extreme panel overclocks.

### Mandatory guarded overclock test

Every experimental installer enforces the complete safety sequence:

1. It shows a prominent overclock warning and cannot continue for 10 seconds.
2. The user must type `I ACCEPT THE OVERCLOCK RISK` exactly.
3. The initial elevated installation transaction stages the exact-hash EDID and
   registers a one-time normal-user trial for the next sign-in. A scheduling
   failure rolls the pending EDID and partial trial artifacts back together;
   the limited task runs only from a SHA-256-manifested `%ProgramData%` runtime
   that standard users cannot modify.
4. The trial explicitly selects the requested Windows refresh rate for no more
   than 15 seconds.
5. It automatically returns Windows to the safe 120 Hz mode before asking any
   question.
6. The requested profile is persisted only after the user confirms that the
   target refresh was reached and remained stable, then accepts the visible UAC
   prompt for the persistent machine-level change. That elevation also executes
   only the protected, re-verified runtime.
7. **No, no answer within 30 seconds, any error, or failed verification restores
   the saved original VRR/LFC state and restarts Windows.**

The screen may flicker, show artifacts or go black during those 15 seconds. If
that happens, wait patiently for the automatic 120 Hz restoration. **Do not
power off or reboot during the trial.**

After a successful confirmation, Windows is explicitly set to the chosen
maximum refresh, Intel `EXCELLENT` is verified at the requested range, the same
LFC patch is applied, and normal one-shot sign-in persistence is installed.

## Mandatory pre-install conditions

1. Extract the complete ZIP to a normal folder.
2. **Upgrade from 2.2.0 or any older ClawLab VRR release:** use that release's
   `RECOVERY\RESTORE_ORIGINAL_VRR.bat`, complete the Windows restart, then use
   the newly extracted 2.2.1 package. Version 2.2.1 detects and refuses to
   overwrite an older managed installation. Do not use Factory Reset for a
   normal upgrade.
3. Close games and display-control applications.
4. If Custom Resolution Utility (CRU) has ever been used on this Windows
   installation, download the current official
   [CRU release](https://www.monitortests.com/forum/Thread-Custom-Resolution-Utility-CRU),
   run `reset-all.exe`, and restart Windows before using ClawLab.
   **If CRU has never been used on this Windows installation, no CRU reset is
   needed.**
   ClawLab also inspects the active `EDID_OVERRIDE` registry values. Remaining
   `CRU_*` or other third-party metadata stops installation before ClawLab
   changes the Intel profile or EDID. Do not answer the preflight with `Y`
   until `reset-all.exe` and the required Windows restart are complete.
5. Disable or uninstall every other application that writes, restores,
   synchronizes or reapplies VRR/EDID settings.
6. The only supported coexistence exception is
   [ClawTweaks 3.0 or later](https://github.com/enterTheVoidCode/ClawTweaks),
   which includes the ClawLab VRR compatibility patch. **ClawTweaks is optional
   and is not required for this VRR fix to work.** Earlier ClawTweaks versions
   and every other VRR-writing tool must be disabled.
7. Disconnect every external display during installation and any guarded
   overclock trial. Only the validated internal panel may be active while
   Windows refresh rate is changed.
8. If any different ClawLab profile is installed, successfully run
   `RECOVERY\RESTORE_ORIGINAL_VRR.bat` and complete the restart first.
9. A clean first installation normally starts from Intel Arc Sync `RECOMMENDED`
   or `EXCELLENT`. If the driver instead exposes an unmanaged `CUSTOM` profile,
   ClawLab does not adopt its unknown values. Because current Intel Graphics
   Software builds cannot select these internal profiles manually, the installer
   tries Intel `RECOMMENDED`, verifies fresh readback, and falls back to
   `EXCELLENT` if that driver silently retains `CUSTOM`. Only the first standard
   profile actually confirmed by the driver is saved as the restoration
   baseline. A failed normalization stops before any backup is created.

Every installer asks for CRU-cleanup and exclusive VRR-ownership confirmation
before doing anything. Experimental installers then add the separate mandatory
10-second overclock warning and typed risk acknowledgement.

## Strict restore-before-switch interlock

The switch guard applies identically to every supported model and every stable
or experimental profile:

- clean state → any one profile is allowed;
- exact same fully installed **2.2.1** profile → idempotent repair/reinstall is
  allowed;
- an older ClawLab release → refused until its original profile is restored and
  Windows is restarted;
- any profile → any different profile → refused until
  `RECOVERY\RESTORE_ORIGINAL_VRR.bat` succeeds and Windows restarts;
- mixed, legacy, pending or inconsistent state → fail closed and request
  recovery.

This prevents ranges, EDID hashes, LFC backups and startup tasks from different
profiles being combined.

## Intel LFC correction

Affected Intel configurations can multiply refresh inside the requested direct
VRR range, for example `60 FPS → 120 Hz` or `68 FPS → 136 Hz`. ClawLab disables
Intel's low- and high-FPS “solutions” only after the managed profile, exact EDID
and range identity verify. Expected status:

```text
CLAWLAB_LFC_FIX_ACTIVE
LowFpsSolutionEnabled  = False
HighFpsSolutionEnabled = False
StartupPersistence     = INSTALLED_ONE_SHOT_AT_LOGON
LfcFixActive            = True
```

This removes Intel refresh multiplication below the selected floor. Traditional
LFC below 30 FPS in a 30 Hz profile, or below 48 FPS in a 48 Hz profile, is
therefore unavailable.

## A1M and Claw 7 AI+ telemetry handling

The exact `TMA2027 / TL070FVXS02-0` panel can expose `24–120 Hz` through one
Intel Control Library monitor-capability query even though its physical EDID is
48–120 Hz and the selected active profile is independently 30–120 or 48–120 Hz.
Version 2.2.1 recognizes that value only as a telemetry anomaly on the exact
pinned Tianma EDID. It never creates, offers or installs a 24 Hz profile.

`CHECK_STATUS.bat` reports physical panel range, Intel monitor telemetry and
the independently selected driver-active range separately. The active profile
must still read back exactly as the requested profile.

## Cursor Refresh Helper

Windows may leave the complete desktop at the VRR floor while only the hardware
cursor moves. The event-driven helper animates a nearly transparent 2×2 DWM
surface in the extreme lower-right corner while a visible mouse moves. It stops
1.5 seconds after input, releases its timer-resolution request, trims only its
own working set and enters deep idle. Controller use naturally leaves it idle.

At sign-in, the windowless launcher starts this helper immediately before the
slower PowerShell, WMI and Intel profile-verification path. The later verified
startup pass recreates its DWM surface once after Intel/display initialization
has settled. Internally, the early process waits for the interactive shell and
DWM composition before creating that surface. This keeps desktop cursor refresh
from waiting on Intel driver startup without racing the Windows desktop.

It does not inject into games, inspect launchers, or alter VRR/LFC settings.
Elevated always-on-top windows can cover its non-elevated surface; this does not
affect game VRR or the Intel LFC correction.

## Status and driver updates

After every installation and Intel graphics-driver update, run
`CHECK_STATUS.bat`. Intel Graphics Software may cache old text; the ClawLab
report queries both Intel interfaces directly and separates capability
telemetry from the selected profile.

After a complete restoration, `OverallHealth: CLEAN_NOT_INSTALLED`,
`ManagedMode: NONE` and `ProfileSwitchGuard: CLEAN` are expected. Do not run
Restore again in that state.

Do not repair while status is `INITIALIZING`; wait up to two minutes and check
again. If the driver update reset the profile, reinstall the **same** profile.
Switching profiles still requires a verified restore and restart.

## Restore and emergency recovery

- `RECOVERY\RESTORE_ORIGINAL_VRR.bat` restores the exact saved Intel VRR/LFC
  state, removes the known ClawLab EDID and tasks, and requires a restart. If
  the saved profile is already active, the redundant Intel driver write is
  skipped and exact readback is still required before cleanup.
- `RECOVERY\RESTORE_INTEL_LFC_DEFAULTS.bat` restores only the saved Intel
  low/high-FPS flags.
- `EMERGENCY` is reserved for the explicitly named recovery failures.
- `DIAGNOSTICS\EXPORT_STATUS_REPORT.bat` creates the support JSON to share.

Never delete `%LOCALAPPDATA%\ClawLab` manually. It contains the original values
needed for verified restoration. Unknown CRU or third-party EDID data is never
removed by ClawLab.

## Build

```powershell
.\tools\Build-Release.ps1 -Version 2.2.1
```

The builder parses every PowerShell file, regenerates the helper, verifies all
16 overclock EDID hashes, checks the A1M/Claw 7 telemetry policy, exercises the
complete profile-transition matrix, validates warning/timeout/rollback markers,
and writes a SHA-256 manifest.

## ZIP layout

- Root: stable installers, status, README, changelog and license.
- `EXPERIMENTAL`: guarded display-overclock installers.
- `RECOVERY`: normal exact-state restoration.
- `EMERGENCY`: explicitly labelled last-resort actions.
- `DIAGNOSTICS`: support data collection.
- `scripts`: internal runtime components.
- `SOURCE`: reproducible source and offline safety tests.
