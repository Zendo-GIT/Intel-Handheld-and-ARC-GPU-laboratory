# MSI Claw Intel VRR Range Fix 2.2.0

Version 2.2.0 is the largest VRR release so far. It adds exact A1M/Claw 7 AI+
Intel telemetry handling, restores optional high-refresh experimentation behind
a fail-safe transaction, applies the Intel LFC patch to every profile, and
strengthens conflict and profile-switch protection.

## Supported devices

- MSI Claw A1M;
- MSI Claw 7 AI+;
- MSI Claw 8 AI+;
- MSI Claw 8 EX AI+.

Support remains restricted to exact `TMA2027 / TL070FVXS02-0` or
`CSW0801 / PN8007QB1-2` identities and pinned physical EDIDs.

## Stable profiles

- ClawLab default 30–120 Hz;
- official Intel/MSI 48–120 Hz.

Both include Intel LFC component 2.0.5 and the event-driven desktop cursor
helper.

## Guarded experimental profiles

- **Stable Experimental:** 48–144 Hz, tested on one MSI Claw 8 AI+ Polar
  Tempest Edition.
- **Unstable Experimental:** 48–165, 48–180, 30–144, 30–165 and 30–180 Hz.

All values above 120 Hz are display overclocks outside MSI specifications.
Results depend on panel silicon lottery. The unstable profiles are not presented
as tested.

Every overclock now requires a non-skippable 10-second warning, exact typed
acceptance and a post-restart trial. The requested maximum is active for no
more than 15 seconds before Windows automatically returns to 120 Hz. The user
is asked to keep the mode only after safe restoration. No, no answer within 30
seconds, a missing mode, timeout or failed readback restores the original
VRR/LFC state and restarts Windows.

The one-time trial task runs with normal-user rights from a protected
`%ProgramData%` runtime. Its directory rejects reparse points, grants standard
users read/execute access only, and binds every payload file to a SHA-256
manifest verified before execution. It is registered inside the initial
elevated EDID transaction, which rolls the pending profile back if scheduling
fails. The final confirmed persistent change may request another normal Windows
UAC approval and re-verifies the same protected runtime first.

## A1M and Claw 7 AI+ fix

Collected A1M Core Ultra 5/7 diagnostics and a Claw 7 AI+ report showed Intel
Control Library exposing `24–120 Hz` monitor telemetry while the physical EDID
remains 48–120 and the selected active profile is independently 30–120 or
48–120. Version 2.2.0 handles this only for the exact pinned TMA2027 EDID and
validates the active profile separately. No 24 Hz profile exists or can be
installed.

## Stronger profile ownership

- A managed installation from 2.1.2 or any older release is reported as
  `OLDER_VERSION_RESTORE_REQUIRED` and cannot be overwritten. Restore it with
  its original package, restart Windows, then install 2.2.0. Factory Reset is
  not part of a normal upgrade.
- Every change to a different stable or experimental profile is refused until
  `RESTORE_ORIGINAL_VRR.bat` succeeds and Windows restarts.
- Same-profile repair remains idempotent within version 2.2.0.
- The offline transition test exercises every profile pair for both panel
  families.
- Every installer asks users to confirm CRU cleanup and that conflicting
  VRR/EDID tools are disabled before any profile action.
- A first installation now refuses an unmanaged Intel `CUSTOM` profile rather
  than recording an unknown or previously modified state as the original.
  Start from Intel `RECOMMENDED` or `EXCELLENT` and restart before retrying.
- A collected A1M recovery case showed an already-active saved CUSTOM 30–120
  profile receiving Intel KMD error `0x40000017` when redundantly rewritten.
  Restore now skips that write only after exact ID/range/timing comparison,
  performs fresh readback, and then completes cleanup.
- Transient Intel KMD/device failures are retried in fresh ControlLib sessions;
  ClawLab target-selection failures now have distinct diagnostic messages.
- `CHECK_STATUS` now reports a completely restored machine as
  `CLEAN_NOT_INSTALLED` instead of incorrectly requesting another Restore. If
  that clean state still uses unmanaged Intel CUSTOM, it gives the required
  RECOMMENDED/EXCELLENT baseline instruction.
- Experimental installers then require a separate timed overclock warning and
  typed risk acceptance.

The only supported coexistence exception is
[ClawTweaks 3.0 or later](https://github.com/enterTheVoidCode/ClawTweaks), which
contains the compatibility patch. ClawTweaks remains optional and is not
required for the standalone fix.

## Validation and recovery

- 12 generated overclock EDIDs are reproduced offline and checked against
  pinned full SHA-256 values.
- Intel LFC 2.0.5 recognizes all stable and experimental managed modes.
- A missing LFC backup with either Intel solution flag already disabled is
  refused before a new backup, task or flag change can be made.
- Experimental success explicitly selects the chosen Windows maximum refresh.
- Rollback selects safe 120 Hz before removing an overclock EDID.
- If CRU was ever used, `reset-all.exe` plus restart remains mandatory. A
  machine on which CRU was never used needs no CRU reset.
- Guarded refresh-rate changes require the validated internal panel to be the
  only active display; disconnect every external display before the trial.
- Concurrent VRR/LFC sign-in requests are serialized to prevent duplicate
  profile or Cursor Refresh Helper startup work.
- The windowless sign-in launcher now starts the Cursor Refresh Helper before
  PowerShell/WMI/Intel initialization. The fully verified startup path still
  performs an idempotent fallback check, avoiding the observed tens-of-seconds
  desktop-helper delay without weakening profile verification.
- Unknown third-party EDID data remains untouched.

## Safety boundary

The utility changes global Windows/Intel display configuration only. It does
not patch, inject into, hook, open or monitor a game process and does not bundle
CRU, Intel drivers or proprietary firmware.
