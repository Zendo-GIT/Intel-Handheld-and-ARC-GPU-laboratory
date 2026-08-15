MSI CLAW INTEL VRR RANGE FIX 2.1.1
==================================

EXACT PANEL CATALOG

- Claw 8 AI+ / 8 EX AI+: CSW0801 / PN8007QB1-2, 1920x1200.
- Claw A1M: TMA2027 / TL070FVXS02-0, 1920x1080.

PUBLIC PROFILES

- INSTALL_30_120_VRR.bat: default corrected ClawLab profile.
- INSTALL_48_120_VRR.bat: official Intel/MSI profile.

Both profiles include the shared Intel LFC x2 correction, exact range/EDID
verification, original flag backup and windowless one-shot sign-in reapply.

Both profiles also install the event-driven Cursor Refresh Helper. While the
mouse moves on the Windows desktop, it animates a nearly transparent 2x2 DWM
surface in the extreme lower-right corner so the panel rises from its idle
floor to 120 Hz. It stays active for 1.5 seconds after input. At idle it stops
the animation, releases its 1 ms timer-resolution request, trims its own working
set and waits for the next visible raw-mouse event.

This tool-independent idle state also covers controller/game profiles selected
through ClawTweaks, MSI Center M or any other utility. No profile-manager or
game process is monitored. Hidden cursors suppress animation; Xbox Full Screen
Experience remains supported.

The 48-144 and 30-144 profiles have been removed. Version 2.1.1 cannot install
or persist them. Their exact signatures remain only so older installations can
be detected and restored safely to 120 Hz.

INSTALL

1. Extract the ZIP completely.
2. If CRU was ever used on this Windows installation, regardless of when or
   whether it now appears inactive, download the current official CRU release,
   run the included reset-all.exe, and restart Windows before continuing:
   https://www.monitortests.com/forum/Thread-Custom-Resolution-Utility-CRU
3. Remove other third-party EDID overrides with their original tool and restart.
4. Restore any different ClawLab profile before switching.
5. Run exactly one of the two supported installers.
6. Restart and run CHECK_STATUS.bat. HEALTHY is the final expected state.

CHECK_STATUS can temporarily report INITIALIZING while the sign-in tasks are
still running. Wait up to two minutes and check again before repairing anything.
It also identifies Intel driver changes and verifies whether the fix survived.

ClawTweaks is optional. If it is not installed, the one-shot startup skips its
coordination check and the complete fix remains available.

RESTORE

Run RECOVERY\RESTORE_ORIGINAL_VRR.bat and restart. This restores the original Intel
solution flags, Arc Sync profile, EDID, tasks and startup state.

If a retired 144 Hz profile is present, run restore immediately. Factory and
Safe Mode recovery retain exact legacy cleanup support.

ZIP LAYOUT

- Root: two installers, CHECK_STATUS, README, changelog and license.
- RECOVERY: normal restore operations.
- EMERGENCY: factory reset and exact ClawLab EDID emergency removal.
- DIAGNOSTICS: display data collection.
- scripts: internal runtime components.
- SOURCE: rebuildable helper source and integrity test.

SAFETY

- Exact validated panel/EDID checks are mandatory.
- Unknown CRU or third-party overrides are refused.
- No game process, game file, anti-cheat, driver or panel firmware is modified.
- No continuous polling loop or game-process monitor is installed.
