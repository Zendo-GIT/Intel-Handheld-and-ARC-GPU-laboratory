# MSI Claw Intel VRR Range Fix

![Version](https://img.shields.io/badge/release-2.3.0-blue)
![Stable profiles](https://img.shields.io/badge/stable-30--120_%2F_48--120_Hz-green)
![Experimental maximum](https://img.shields.io/badge/experimental-up_to_192_Hz-orange)

ClawLab 2.3.0 corrects Intel Arc VRR/LFC behavior on exact, pinned internal
panels used by these handhelds:

- MSI Claw A1M;
- MSI Claw 7 AI+;
- MSI Claw 8 AI+;
- MSI Claw 8 EX AI+.

The utility changes global Windows/Intel display state only. It never injects
into, patches, hooks, opens or monitors a game process.

See the [2.3.0 release notes](docs/RELEASE_NOTES_2.3.0.md),
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

On the exact A1M / Claw 7 AI+ driver state that exposes an immutable OEM
`CUSTOM 30–120` baseline, 2.3.0 can safely install only the 30–120 profile.
The 48–120 and overclock installers remain refused on that path because the
driver will not establish the standard baseline required for their verified
restoration.

## Experimental display-overclock profiles

The `EXPERIMENTAL` folder contains:

| Profile | Classification | Validation |
|---|---|---|
| 48–144 Hz | **Stable Experimental** | Tested on one MSI Claw 8 AI+ Polar Tempest Edition |
| 48–165 Hz | **Unstable Experimental** | Successfully tested on Claw 8 AI+ hardware; panel silicon lottery still applies |
| 48–180 Hz | **Unstable Experimental** | Tested on one MSI Claw 8 AI+ Polar Tempest Edition; panel silicon lottery still applies |
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

1. It shows the target range, overclock risks and automatic-recovery behavior
   throughout a visible 10-second reading countdown.
2. The user must type `I ACCEPT THE OVERCLOCK RISK` exactly once.
3. The initial elevated installation transaction stages the exact-hash EDID and
   registers a one-time normal-user trial for the next sign-in. A scheduling
   failure rolls the pending EDID and partial trial artifacts back together;
   the limited task runs only from a SHA-256-manifested `%ProgramData%` runtime
   that standard users cannot modify.
4. After restart, no overclock is applied until the user explicitly starts the
   trial from a visible ready dialog. The trial then selects the exact Windows
   maximum and Intel `EXCELLENT` range used by final persistence and displays a
   dedicated animated 30-second observation window. It creates **no VRR, LFC
   or Cursor Helper persistence** during this observation window.
5. It verifies the exact refresh and Intel range again at the end, then attempts
   and verifies a return to the safe 120 Hz mode before asking whether the
   profile should be kept.
6. The stable profile is committed only after the user confirms that the target
   refresh was reached and remained stable, then accepts the visible UAC prompt.
   The protected runtime applies and verifies VRR first, applies and verifies
   the Intel LFC correction second, and only then accepts the Cursor Refresh
   Helper and normal one-shot persistence as verified terminal state.
7. **No, no answer within 30 seconds, any error, or failed verification enters
   exact saved-state recovery. Windows restarts only after VRR and LFC restore
   proof succeeds. If proof fails, ClawLab does not restart automatically; it
   neutralizes the one-time task when safe, retains the transaction evidence and
   directs the user to Diagnostics and Recovery.**

The screen may flicker, show artifacts or go black during those 30 seconds. If
that happens, wait patiently while the automatic 120 Hz recovery is attempted
and verified. **Do not
power off or reboot during the trial.**

After a successful confirmation, Windows is explicitly set to the chosen
maximum refresh, Intel `EXCELLENT` is verified at the requested range, the same
LFC patch is applied, and normal one-shot sign-in persistence is installed.

## Mandatory pre-install conditions

1. Extract the complete ZIP to a normal folder.
2. **Upgrade from 2.2.1 or any older ClawLab VRR release:** run
   `RECOVERY\RESTORE_ORIGINAL_VRR.bat`, complete the Windows restart, then use
   the newly extracted 2.3.0 package. Use the matching older Recovery when its
   ZIP is still available. If it was deleted, current 2.3.0 Recovery can consume
   the retained legacy backup; a startup entry rewritten by an Intel update is
   preserved only after fresh canonical-path and Intel-signature verification.
   Version 2.3.0 refuses to install over an unrestored older managed state. Do
   not use Factory Reset for a normal upgrade and do not delete the ClawLab
   state directory manually.
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
   baseline. Before the first setter, ClawLab atomically journals the exact
   profile and its panel, GPU, driver and target identity. A failed or
   interrupted normalization restores and verifies that snapshot; an unresolved
   journal blocks installation until Recovery resumes it. The only exception is
   the exact pinned TMA2027 OEM `CUSTOM 30–120` state. It is
   accepted only for `INSTALL_30_120_VRR.bat`, from native 1920×1080 at 120 Hz,
   after exact panel, timing, telemetry and direct Intel-state verification.
   No other custom profile is adopted.

Every installer asks for CRU-cleanup and exclusive VRR-ownership confirmation
before doing anything. Experimental installers then add the separate mandatory
10-second overclock warning and typed risk acknowledgement.

## Strict restore-before-switch interlock

The switch guard applies identically to every supported model and every stable
or experimental profile:

- clean state → any one profile is allowed;
- exact same fully installed **stable 2.3.0** profile → guarded repair/reinstall
  is allowed only when the panel, physical EDID, managed mode and both original
  backups still form one exact identity. Missing managed tasks or payloads may
  be rebuilt without consuming those backups;
- the same stable profile after a narrowly recognized Intel driver reset to
  `RECOMMENDED`/`EXCELLENT` and an allowlisted 30/48/60–120 readback → guarded
  repair is allowed; unknown `CUSTOM`, wrong EDID and unknown ranges are not.
  Any failed repair preserves the original backups and directs the user to
  Recovery;
- any already-confirmed experimental profile → restore and restart before
  starting another guarded overclock trial, even at the same range;
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

The exact `TMA2027 / TL070FVXS02-0` panel can expose halved floor values through
one Intel Control Library monitor-capability query. The physical 48 Hz floor
may appear as `24–120 Hz`; after a managed 30 Hz profile has loaded, its floor
may appear as `15–120 Hz`. The physical EDID and independently queried active
profile remain 48–120 and 30–120 respectively. Version 2.3.0 recognizes these
values only as telemetry anomalies on the exact pinned Tianma EDID. The 15 Hz
case additionally requires an existing, exact ClawLab 30 Hz managed record and
matching active Intel profile. It never creates, offers or installs a 15 or
24 Hz profile.

Collected A1M drivers can also report an exact OEM `CUSTOM 30–120` profile and
reject both `RECOMMENDED` and `EXCELLENT` setter requests. Version 2.3.0
preserves that state as the original baseline without rewriting it only when
all pinned TMA2027 checks pass. Select **1920×1080 at 120 Hz** in Windows before
running the 30–120 installer; 1080p at 60 Hz remains refused.

## Localized interface

Public launchers automatically use the Windows display language for the same
34 languages supported by Clawptimize: Arabic, Bengali, Chinese, Czech,
Danish, Dutch, English, Filipino, Finnish, French, German, Greek, Hindi,
Hungarian, Indonesian, Italian, Japanese, Korean, Marathi, Persian, Polish,
Portuguese, Punjabi, Romanian, Russian, Spanish, Swahili, Swedish, Tamil,
Thai, Turkish, Ukrainian, Urdu and Vietnamese.

English is the fail-safe fallback. `SELECT_LANGUAGE.bat` can save a manual
choice or return to automatic detection. Technical state identifiers and JSON
diagnostic property names remain English so reports stay comparable worldwide.
The runtime PowerShell code is code-page-independent ASCII and reads the
translation catalog explicitly as UTF-8, so non-Western Windows PowerShell 5.1
code pages do not alter script parsing.
Yes/No confirmations display the local one-letter shortcuts, such as `[Y/N]`
in English and `[O/N]` in French. Press the chosen letter once: **Enter is not
required**. Hosts without direct console-key support retain a text fallback.

Normal double-click launch requests one Windows UAC approval. If a launcher is
already running as administrator, 2.3.0 reuses that verified token and does not
request a redundant second elevation.

ClawLab registers limited interactive tasks through the Windows account name
resolved from that same caller SID, then verifies ownership by SID on readback.
This supports Windows accounts that reject a raw SID in Task Scheduler's XML
`UserId` field. The public launchers already use a bounded execution-policy
bypass; changing a system `RemoteSigned` policy to `Unrestricted` is neither
required nor a fix for task-registration errors.

`CHECK_STATUS.bat` reports physical panel range, Intel monitor telemetry and
the independently selected driver-active range separately. The active profile
must still read back exactly as the requested profile.

## Cursor Refresh Helper

Windows may leave the complete desktop at the VRR floor while only the hardware
cursor moves. Version 2.3.0 uses a native Win32 window and a D3D11/DXGI flip-
model swap chain in the extreme lower-right corner. Every submitted frame
alternates the opaque 2×2 backbuffer between black and a nearly indistinguishable
near-black value, preventing DWM from discarding it as unchanged content.
Background Raw Input wakes the surface for visible mouse movement; 1.5 seconds
after the last packet the engine stops presenting and blocks on kernel events
with no polling loop and no high-resolution timer request. Controller use
naturally leaves it in this deep-idle state.

A dedicated limited-user task launches the native executable directly at
interactive logon, independently of the slower PowerShell, WMI and Intel path.
It has no trigger delay and explicitly uses Task Scheduler priority 2
(`AboveNormal`) instead of the background-task default 7 (`BelowNormal`). The
process also verifies its own `AboveNormal` class without requesting elevation.
No secondary launcher races the dedicated task.
After the shell and DWM appear, a bounded 30-second warm-up covers Steam and
desktop startup. The coordinated pass then verifies VRR and LFC and signals the
existing process to recreate its DXGI swap chain in place. There is no process
gap and no additional VRR/LFC write. If native DXGI initialization fails, only
the desktop helper falls back to the former WPF engine; the managed display
profile is never restored or changed by that fallback.

It does not inject into games, inspect launchers, or alter VRR/LFC settings.
Elevated always-on-top windows can cover its non-elevated surface; this does not
affect game VRR or the Intel LFC correction.

`UPDATE_CURSOR_REFRESH_ENGINE.bat` upgrades or repairs only this desktop engine
and its direct logon task. It first proves that the existing 2.3.0 managed
profile is consistent and that the active Intel range matches it. It then
reports `ProfileChanged: False`, `LfcChanged: False` and `EdidChanged: False`.
The current 30–120, 48–120 or confirmed experimental profile does **not** need
to be restored, reinstalled or retested for a cursor-engine-only update.

## Status and driver updates

After every installation and Intel graphics-driver update, run
`CHECK_STATUS.bat`. Intel Graphics Software may cache old text; the ClawLab
report queries both Intel interfaces directly and separates capability
telemetry from the selected profile.

Before the final requested restart, a new installation can legitimately report
`*_PENDING_RESTART`, `READY_AT_NEXT_SIGN_IN` and `LfcFixActive: False`. These are
transitional values, not proof of failure. Complete the restart before judging
the final state; afterwards the managed profile and LFC correction must verify
as active and `LfcFixActive` must be `True`.

After a complete restoration, `OverallHealth: CLEAN_NOT_INSTALLED`,
`ManagedMode: NONE` and `ProfileSwitchGuard: CLEAN` are expected. Do not run
Restore again in that state.

`TransactionJournalPresent: True` takes precedence over those individual clean
fields: the overall result is `ATTENTION_REQUIRED` and the transaction action and
phase are displayed. Version 2.3.0 can automatically remove a false journal left
by an experimental scheduling failure only after it independently proves the
complete original VRR/LFC state, absence of trial tasks/runtime and exact
verified terminal LFC provenance. It never adopts a partially restored state.

Recovery also recognizes one narrowly defined legacy-shell case: fresh driver
readback already proves the exact unmanaged Intel factory VRR/LFC state, no
original backup or EDID override exists, and the only remaining managed object
is one provably owned but invalid ClawLab startup task. In that exact state,
`CHECK_STATUS.bat` reports `ORPHANED_DEFAULT_VRR_SHELL_RECOVERABLE` and the
normal 2.3.0 Restore removes only the stale task and its payloads. It does not
write an Intel profile, Windows display mode or EDID. Any mismatch remains
blocked and requires a diagnostic report.

Do not repair while status is `INITIALIZING`; wait up to two minutes and check
again. If the driver update reset the profile, reinstall the **same** profile.
Switching profiles still requires a verified restore and restart.

If only `CursorRefreshHelper` or `DesktopHelperHealth` needs attention while
`CoreVrrAndLfcHealth` is healthy, run `UPDATE_CURSOR_REFRESH_ENGINE.bat` instead
of reinstalling the profile.

Startup profile work is serialized under shared global locks. ClawLab verifies
and reapplies VRR first, then applies and verifies the Intel LFC correction;
the two startup paths cannot race at sign-in.

## Restore and emergency recovery

- `RECOVERY\RESTORE_ORIGINAL_VRR.bat` restores the exact saved Intel VRR/LFC
  state, removes the known ClawLab EDID and tasks, and requires a restart. If
  the saved profile is already active, the redundant Intel driver write is
  skipped and exact readback is still required before cleanup. If a legacy
  package lost its backup but is already at the exact independently verified
  Intel factory state, the same action may remove only its provably owned stale
  startup shell through the bounded no-display-write path described above.
- `RECOVERY\RESTORE_INTEL_LFC_DEFAULTS.bat` restores only the saved Intel
  low/high-FPS flags.
- `EMERGENCY` is reserved for the explicitly named recovery failures.
  `SET_INTEL_LFC_FACTORY_DEFAULTS.bat` uses a resumable intent/finalization
  journal and is only for cases where the exact original LFC backup is truly
  unavailable. Its verified terminal provenance is retained for a future
  clean install.
- `DIAGNOSTICS\EXPORT_STATUS_REPORT.bat` creates the support JSON to share.

Never delete `%LOCALAPPDATA%\ClawLab` manually. It contains the original values
needed for verified restoration. Unknown CRU or third-party EDID data is never
removed by ClawLab.

Normal restoration is a durable write-ahead transaction: LFC restoration is
prepared while its backup remains recoverable, VRR is restored, the LFC backup
is committed only after exact readback, and terminal provenance is finalized
only after an independent joint proof. Interrupted work is resumable. If the
terminal proof fails, ClawLab keeps the recovery records and does not request an
automatic restart.

## Build

```powershell
.\tools\Build-Release.ps1 -Version 2.3.0
```

The builder parses every PowerShell file, regenerates the helper, verifies all
16 overclock EDID hashes, checks the A1M/Claw 7 telemetry policy, exercises the
complete profile-transition matrix, validates warning/timeout/rollback markers,
and writes a SHA-256 manifest.

## ZIP layout

- Root: stable installers, language selector, status, README, changelog and
  license.
- `EXPERIMENTAL`: guarded display-overclock installers.
- `RECOVERY`: normal exact-state restoration.
- `EMERGENCY`: explicitly labelled last-resort actions.
- `DIAGNOSTICS`: support data collection.
- `scripts`: internal runtime components and the validated offline interface
  catalog for 34 languages.
- `SOURCE`: reproducible source and offline safety tests.
