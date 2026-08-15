MSI CLAW 8 AI+ / 8 EX AI+ INTEL VRR RANGE FIX 2.0.2
====================================================

PUBLIC PROFILES

- INSTALL_30_120_VRR.bat: default corrected ClawLab profile.
- INSTALL_48_120_VRR.bat: official Intel/MSI profile.

Both profiles include the shared Intel LFC x2 correction, exact range/EDID
verification, original flag backup and windowless one-shot sign-in reapply.

The 48-144 and 30-144 profiles have been removed. Version 2.0.2 cannot install
or persist them. Their exact signatures remain only so older installations can
be detected and restored safely to 120 Hz.

INSTALL

1. Extract the ZIP completely.
2. Remove third-party CRU overrides with their original tool and restart.
3. Restore any different ClawLab profile before switching.
4. Run exactly one of the two supported installers.
5. Restart and run CHECK_STATUS.bat.

RESTORE

Run RESTORE_ORIGINAL_VRR.bat and restart. This restores the original Intel
solution flags, Arc Sync profile, EDID, tasks and startup state.

If a retired 144 Hz profile is present, run restore immediately. Factory and
Safe Mode recovery retain exact legacy cleanup support.

SAFETY

- Exact validated panel/EDID checks are mandatory.
- Unknown CRU or third-party overrides are refused.
- No game process, game file, anti-cheat, driver or panel firmware is modified.
- No continuous watcher is installed.
