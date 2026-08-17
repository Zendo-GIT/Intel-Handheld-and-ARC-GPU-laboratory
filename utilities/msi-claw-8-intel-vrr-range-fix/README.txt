MSI CLAW INTEL VRR RANGE FIX 2.2.0
=================================

SUPPORTED EXACT PANELS
----------------------
- MSI Claw A1M / Claw 7 AI+: TMA2027 / TL070FVXS02-0, 1920x1080.
- MSI Claw 8 AI+ / Claw 8 EX AI+: CSW0801 / PN8007QB1-2, 1920x1200.

STABLE INSTALLERS
-----------------
- INSTALL_30_120_VRR.bat: ClawLab default 30-120 Hz profile.
- INSTALL_48_120_VRR.bat: official Intel/MSI 48-120 Hz profile.

Both include the Intel LFC x2 correction and event-driven desktop cursor helper.

EXPERIMENTAL FOLDER
-------------------
- 48-144 Hz: Stable Experimental. Tested on one MSI Claw 8 AI+ Polar Tempest.
- 48-165, 48-180, 30-144, 30-165 and 30-180 Hz: Unstable Experimental and untested.

Every value above 120 Hz is a display overclock outside MSI specifications.
Results depend on each panel's silicon lottery. The experimental installers
force a 10-second warning, typed risk acceptance, and a one-time guarded test.
After restart the selected maximum is tested for no more than 15 seconds, then
Windows automatically returns to safe 120 Hz before asking for confirmation.
The one-time test runs with normal-user rights. The initial installer UAC also
registers that limited task as one transaction; scheduling failure rolls back
the pending profile. Its scripts are copied to a SHA-256-verified, administrator-
protected ProgramData directory. The final persistent change can show another
normal UAC prompt after Yes. Accept it only when you started this process.
If the screen flickers, shows artifacts or goes black, WAIT PATIENTLY. DO NOT
POWER OFF OR REBOOT. No, no response within 30 seconds, any error, or failed
verification restores the original VRR/LFC state and restarts Windows.

MANDATORY BEFORE INSTALLATION
-----------------------------
1. Extract the complete ZIP.
2. If version 2.1.2 or any older ClawLab VRR release is installed, run its
   RECOVERY\RESTORE_ORIGINAL_VRR.bat and complete the restart first. Version
   2.2.0 refuses to overwrite an older managed installation. Do not use Factory
   Reset for a normal upgrade.
3. If CRU was ever used, run reset-all.exe from the current official CRU
   release and restart Windows.
   If CRU was NEVER used on this Windows installation, no CRU reset is needed.
   ClawLab checks the real EDID_OVERRIDE registry values too. Any remaining
   CRU_* or other third-party metadata stops installation before a profile or
   EDID change is made.
4. Disable or remove every other tool that changes or reapplies VRR/EDID.
5. The only supported exception is ClawTweaks 3.0 or later:
   https://github.com/enterTheVoidCode/ClawTweaks
   ClawTweaks is OPTIONAL and is NOT required for ClawLab VRR to work.
6. Earlier ClawTweaks versions and all other VRR-writing tools must be disabled.
7. Disconnect every external display during installation and guarded trials.
   Only the validated internal panel may be active while refresh rate changes.
8. A clean first installation accepts Intel Arc Sync RECOMMENDED or EXCELLENT.
   If it finds an unmanaged CUSTOM profile, ClawLab does not save those unknown
   values. Intel Graphics Software cannot select the internal standard profiles
   manually. The installer tries RECOMMENDED, verifies fresh readback, and falls
   back to EXCELLENT if the driver silently retains CUSTOM. It saves only the
   first standard profile actually confirmed by the driver.

PROFILE SWITCHING
-----------------
Before applying any different stable or experimental profile, successfully run
RECOVERY\RESTORE_ORIGINAL_VRR.bat and complete the restart. The installer
refuses every cross-profile change. Only an exact same-profile repair is
idempotent within version 2.2.0. Any managed 2.1.2-or-older state requires the
upgrade restoration described above.

A1M / CLAW 7 AI+ NOTE
---------------------
Intel Control Library can expose a 24-120 monitor-capability value on the exact
TMA2027 panel. ClawLab treats this only as known telemetry and validates the
selected active profile separately. It never creates or installs a 24 Hz mode.

STATUS
------
After installation and after every Intel driver update, run CHECK_STATUS.bat.
Expected core results include ProfileSwitchGuard CONSISTENT,
CLAWLAB_LFC_FIX_ACTIVE, both Intel solution flags False and LfcFixActive True.
After complete removal, CLEAN_NOT_INSTALLED, ManagedMode NONE and
ProfileSwitchGuard CLEAN are expected. Do not run Restore again in that state.
The cursor helper starts before slow PowerShell/WMI initialization, waits for
the interactive shell and DWM, then recreates its surface once after Intel
startup so it is both prompt and effective.

RECOVERY
--------
- RECOVERY\RESTORE_ORIGINAL_VRR.bat: complete verified original-state restore.
  If that exact saved profile is already active, its redundant Intel driver
  write is skipped and cleanup completes only after exact readback.
- RECOVERY\RESTORE_INTEL_LFC_DEFAULTS.bat: Intel LFC flags only.
- DIAGNOSTICS\EXPORT_STATUS_REPORT.bat: support report.
- EMERGENCY: use only for the explicitly named failure case.

Never delete %%LOCALAPPDATA%%\ClawLab manually. Unknown third-party EDID data is
refused and never removed by ClawLab.

SAFETY
------
This utility changes global Windows/Intel display state only. It does not patch,
inject into, hook, open or monitor a game process. It bundles no Intel driver,
CRU binary or proprietary EDID dump.
