# MSI Claw Intel VRR Range Fix 2.2.1

Version 2.2.1 is a corrective release built on the proven 2.2.0 profile,
recovery and guarded-trial paths.

## What changed

- Preserves the validated 30–120 Hz ClawLab profile and official Intel/MSI
  48–120 Hz profile without trying to hide normal Windows refresh choices.
- Removes the unsafe requirement that Windows expose exactly one selectable
  refresh rate. Intel and Windows may enumerate several valid fixed modes
  inside the panel capability; that enumeration is not an installation-health
  criterion.
- Keeps exact Intel profile, active range, EDID, LFC flags, startup persistence
  and profile-switch state as the authoritative verification points.
- Keeps the existing guarded overclock flow: safe 120 Hz rollback, explicit
  confirmation, exact readback and automatic restoration on failure.
- Keeps original-profile restoration on the known-good 2.2.0 path. Restore
  returns the saved Intel/LFC state and removes only ClawLab-owned EDID and task
  data.
- Adds guarded, untested `48–192` and `30–192` extreme-overclock profiles for
  both pinned panel families. They use the same 10-second warning, 15-second
  trial, safe 120 Hz return and fail-closed rollback as every other overclock.
- Extends the Intel LFC correction, transition matrix, exact EDID hashes and
  recovery allowlist to both 192 Hz profiles.

## Supported profiles

- Stable: 30–120 Hz and official 48–120 Hz.
- Experimental overclock: 48–144, 48–165, 48–180, 48–192, 30–144, 30–165,
  30–180 and 30–192 Hz, with the same warnings and automatic rollback as 2.2.0.

The 192 Hz profiles can align the display maximum with a 48 FPS ×4
frame-generation target. They do not install or guarantee XeSS/XeFG and are
classified **Unstable Experimental**.

No 24 Hz profile exists. The A1M/Claw 7 AI+ Intel 24–120 telemetry anomaly is
reported separately from the selected 30–120 or 48–120 driver profile.

## Upgrade from 2.2.0 or older

1. Use `RECOVERY\RESTORE_ORIGINAL_VRR.bat` from the currently installed
   package.
2. Complete the Windows restart.
3. Extract 2.2.1 to a new folder.
4. Install the desired profile and restart again.
5. Run `CHECK_STATUS.bat`.

Do not use Factory Reset for a normal upgrade.

If a pre-release 2.2.1 attempt already rolled itself back and status shows
`ManagedMode: NONE`, `ProfileSwitchGuard: CLEAN`, `EdidOverride: NONE`, no
ClawLab startup task and no saved original profile, simply restart Windows and
use this corrected package. Repeated Restore or Factory Reset is unnecessary.

## Windows refresh choices

Seeing 48, 60, 75, 100 and 120 Hz on a native 120 Hz panel can be normal. The
utility does not claim to remove those fixed-mode choices. The installed VRR
profile is verified through Intel driver readback and the exact active range,
not by counting entries in Windows Settings.
