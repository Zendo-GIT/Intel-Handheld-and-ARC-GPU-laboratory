# MSI Claw Intel VRR Range Fix 2.3.0

Version 2.3.0 is the first public release of the new transactional ClawLab
runtime. It keeps the community-validated 30–120 Hz and official Intel/MSI
48–120 Hz profiles, the Intel LFC correction and the optional desktop helper,
while rebuilding installation, startup, experimental confirmation and recovery
around durable, fail-closed state transitions.

## Highlights

- One localized public coordinator now owns every install, restore, emergency
  and guarded-trial operation across a single verified UAC boundary. If the
  launcher is already administrator-elevated, its token is inherited by the
  bound child instead of generating a redundant second UAC request. A failed
  elevation launch now exposes its actual technical error.
- Automatic interface localization covers 34 languages, with invariant English
  state identifiers and JSON keys for support reports. `SELECT_LANGUAGE.bat`
  provides an optional manual override. Yes/No confirmations accept the
  localized one-letter shortcut immediately, without requiring Enter. Runtime
  PowerShell remains code-page-independent 7-bit ASCII and loads the external
  catalog explicitly as UTF-8, including on Korean Windows PowerShell 5.1.
  Korean text remains localized while its confirmation shortcuts use the
  community-requested conventional `Y/N` keys.
- Stable same-profile repair preserves the existing exact VRR/LFC backups.
  After a driver update, the same 30–120 or 48–120 installer can also repair a
  narrowly recognized Intel `RECOMMENDED`/`EXCELLENT` reset or rebuild missing
  managed tasks/payloads. Panel, EDID, mode and both backups must remain one
  identity; failure preserves those backups. Unknown `CUSTOM`, wrong-panel,
  wrong-EDID and unknown-range drift remain refused.
- First-install Intel profile normalization now uses a durable compensation
  journal written before any `CUSTOM` to `RECOMMENDED`/`EXCELLENT` mutation.
  A failure or power loss restores and verifies the exact captured profile; an
  unresolved journal blocks every new install until Recovery resumes it.
- Intel LFC 2.0.7 stores exact low/high-FPS flags and uses durable restore and
  factory-default transactions. Normal restore follows
  `PrepareRestore -> VRR restore -> CommitRestore -> joint proof -> FinalizeRestore`
  and retains verified terminal provenance. Factory Defaults is an emergency
  action, is resumable after interruption, and leaves separate verified terminal
  provenance that a later install can safely convert into a normal backup.
- Startup reapplication is one coordinated
  `VRR apply/readback -> LFC apply/readback -> helper/persistence verification`
  pass under shared global locks. It prevents VRR and LFC tasks from racing at
  sign-in. A separate limited-user task starts the native Win32/D3D11/DXGI
  flip-model Cursor Refresh Engine directly at logon with no delay and explicit
  `AboveNormal` priority. Its alternating near-black backbuffer prevents DWM
  from coalescing unchanged frames. After final Intel/display
  verification the process receives a named resynchronization event and
  recreates its swap chain in place, then returns to kernel-event deep idle.
  WPF is an automatic helper-only fallback. None of this satisfies, bypasses or
  rewrites the terminal VRR/LFC transaction.
- Interactive logon tasks are registered through the Windows account name
  resolved from the bound caller SID, then read back and owned exclusively by
  that SID. This avoids the Task Scheduler `(32,8):UserId` invalid-parameter
  failure observed on an affected Claw 8 EX account while retaining limited
  `InteractiveToken` execution and exact ownership checks.
- Recovery understands a legacy installation whose Intel Graphics Software Run
  entry was rewritten by a later Intel update. The new entry is preserved only
  if its executable remains under the canonical Intel directory and passes a
  fresh Intel Authenticode and stable file-identity check. An unknown or unsigned
  replacement is still refused without modification.

## Stable profiles

- `INSTALL_30_120_VRR.bat`: community-validated ClawLab 30–120 Hz profile.
- `INSTALL_48_120_VRR.bat`: official Intel/MSI 48–120 Hz range.

Both profiles include the same Intel LFC correction and one-shot startup
reapplication. No process injection, game hook, executable patch or continuous
VRR/LFC polling service is installed.

## Guarded display-overclock profiles

The `EXPERIMENTAL` folder contains 48–144/165/180/192 Hz and
30–144/165/180/192 Hz profiles. Every maximum above 120 Hz is outside MSI
specifications and depends on the individual panel silicon lottery.

The initial installer presents the range, risks and recovery behavior during a
visible ten-second countdown, then requests the exact typed risk phrase once.
At the next sign-in **no overclock is applied until the user explicitly starts
the test**. The exact final Windows maximum and Intel `EXCELLENT` range then run
inside a dedicated animated 30-second observation window and are verified again
at its end. **No VRR, LFC or Cursor Helper persistence is installed during that
observation window.** The trial attempts and verifies a return to safe 120 Hz
before confirmation. Persistence for the confirmed VRR range, Intel LFC
correction and Cursor Refresh Helper is created only after explicit confirmation
and a bound UAC approval, in the same verified terminal order used by the two
stable profiles. Once those components are independently verified, the
transaction durably records `PERSISTENCE_APPLIED`, accepts only the exact
guarded `EXPERIMENTAL_TRIAL_PENDING` pre-commit state, then commits and consumes
the one-time task. This avoids rejecting a successful trial merely because its
safety task correctly remained present until commit.

48–144, 48–165 and 48–180 Hz have now reached successful tests on Claw 8 AI+
hardware, including 48–180 Hz on one Polar Tempest Edition. Only 48–144 keeps
the **Stable Experimental** classification; 165/180 remain explicitly unstable
and every above-120 result remains individual panel silicon lottery.

No, timeout, UAC cancellation, failed verification, crash or power loss enters
the same fail-closed recovery state machine. Exact original VRR/LFC proof is
required before the trial runtime or durable recovery records can be removed and
before Windows may restart automatically. If terminal proof fails, ClawLab does
not restart automatically; it neutralizes the one-time task when safe and keeps
the evidence for Diagnostics and Recovery. If the screen is black or unstable
during the test, wait while automatic recovery is attempted and do not power the
device off.

A completed normal Restore leaves exact durable LFC provenance so original Intel
flag values are never guessed. Guarded installers accept that verified terminal
state as a clean baseline. If an earlier 2.3.0 guarded-scheduling attempt left a
false `RECOVERY_REQUIRED` journal while every VRR/LFC, task, EDID and protected
runtime check is independently clean, rerunning the desired installer safely
reconciles that journal. Any mismatch remains fail-closed and requires Recovery.
`CHECK_STATUS.bat` exposes the journal action and phase instead of reporting a
misleading clean state.

A collected local-account/modified-Windows case also exposed an older ClawLab
startup task remaining after the Intel VRR and LFC state had already returned
exactly to factory defaults and no original backup remained. Normal 2.3.0
Recovery now detects that exact orphaned shell and removes only the provably
owned task and payloads. The path requires the pinned factory profile, range,
timings, native 120 Hz mode, factory LFC flags, no EDID or other recovery state,
and no other ClawLab task. It performs no display-profile, mode or EDID write;
all ambiguous variants remain fail-closed. `CHECK_STATUS.bat` reports
`ORPHANED_DEFAULT_VRR_SHELL_RECOVERABLE` with the precise Recovery instruction.

Protected-runtime verification explicitly loads both Windows ACL access rules
and owner metadata before checking the administrator owner. This applies to all
eight guarded profiles and prevents a null owner from surfacing as the
misleading PowerShell `Value property was not found` scheduling error.

## A1M and Claw 7 AI+

The exact `TMA2027 / TL070FVXS02-0` panel may expose Intel's half-physical-floor
`24–120` monitor telemetry while the physical EDID remains 48–120 Hz. No 24 Hz
profile exists. Version 2.3.0 keeps the anomaly separated from the selected
driver range and accepts it only for the pinned panel/EDID identity.

A field-tested 30–120 installation also exposed a `15–120` monitor-capability
value after the real 30 Hz profile loaded. Version 2.3.0 recognizes this second
halved-floor signature only for an existing, exact ClawLab 30 Hz managed record
whose independently queried Intel active profile still matches the requested
range. It is rejected on clean/unmanaged systems and all 48 Hz profiles. No
15 Hz profile exists.

Some collected drivers also expose an immutable OEM `CUSTOM 30–120` baseline
and reject both standard setters. A narrow, no-setter path preserves that exact
baseline for `INSTALL_30_120_VRR.bat` only, from 1920×1080 at 120 Hz and after
all panel, timing, display-count, telemetry and direct-driver checks pass.

## Upgrade from 2.2.1 or older

To upgrade from any older managed release:

1. Run `RECOVERY\RESTORE_ORIGINAL_VRR.bat`. The matching older package remains
   preferred when available. If its ZIP was deleted, the current 2.3.0 Recovery
   can consume the retained legacy backup and safely preserve a newer verified
   Intel Graphics Software startup entry.
2. Complete the required Windows restart.
3. Extract 2.3.0 into a new folder.
4. Install one desired profile.
5. Restart Windows and run `CHECK_STATUS.bat`.

Do not use Factory Reset for a normal update and never manually delete
`%LOCALAPPDATA%\ClawLab`.

Do not loosen the system PowerShell execution policy as a workaround. Public
launchers use their own bounded `ExecutionPolicy Bypass`; `RemoteSigned` was not
the cause of the collected Task Scheduler `UserId` registration failure.

For an already verified **2.3.0** profile, a Cursor Refresh Engine update does
not require those profile-upgrade steps. Run
`UPDATE_CURSOR_REFRESH_ENGINE.bat`; it validates the current managed range and
updates only the helper executable and its direct logon task. It does not write
EDID, Intel Arc Sync or LFC, and it does not require a restart.

Before the final requested restart, `*_PENDING_RESTART`,
`READY_AT_NEXT_SIGN_IN` and `LfcFixActive: False` can be normal transitional
values. Complete the restart before judging final health; afterwards the exact
managed profile and LFC correction must read back active and `LfcFixActive` must
be `True`.

If CRU has ever been used on this Windows installation, run `reset-all.exe`
from the current official CRU release and restart first. If CRU has never been
used, no reset is needed. Disable every other VRR/EDID writer. ClawTweaks 3.0+
is the only supported coexistence exception and remains optional.

## Versions

- Package and coordinator: 2.3.0
- Cursor Refresh Helper: 2.3.0
- Intel LFC component: 2.0.7
