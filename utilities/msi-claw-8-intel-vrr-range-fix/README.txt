MSI CLAW 8 AI+ / 8 EX AI+ INTEL VRR RANGE FIX 1.0.1
====================================================

SUPPORTED PANEL
---------------
CSW0801 / PN8007QB1-2, physical EDID SHA-256:
E49BC570225510B7C889ED292570F1345CAA07F5840DB57EA6998A403DB5CEF0

The utility targets Claw 8 AI+ and Claw 8 EX AI+ configurations only when this
exact internal panel and physical EDID are detected. Model names alone are not
used as a safety check. The AMD-powered Claw A8 is not compatible with this
Intel Control Library package.

OFFICIAL MODE - RECOMMENDED
---------------------------
Run INSTALL_48_120_VRR.bat.

This selects Intel's official EXCELLENT Arc Sync profile and verifies the
driver's active range as 48-120 Hz. Because Intel can restore 60-120 Hz after a
Windows restart, it also installs a current-user task. The task waits for the
automatically started Intel Graphics Software process, then applies 48-120 Hz
after Intel has finished initializing.

EXPERIMENTAL MODE - OPTIONAL
----------------------------
Run INSTALL_EXPERIMENTAL_30_120_VRR.bat and accept the administrator prompt.

This installs a Windows EDID override that advertises 30-120 Hz, comparable in
purpose to a CRU configuration. It is outside MSI's official 48-120 Hz
specification and can cause flicker or display instability. The physical panel
firmware is not modified.

RESTART
-------
Each installer asks whether to restart the PC. Experimental EDID changes require
a restart. Wait about two minutes after signing in, then run CHECK_STATUS.bat.

Intel Graphics Software can keep showing a stale 60-120 Hz value. CHECK_STATUS
reads the active profile directly from Intel Control Library and also verifies
the EDID override.

RESTORE
-------
Run RESTORE_ORIGINAL_VRR.bat, then restart when prompted. Restore also removes
the scheduled task and the installed startup copy of the script.

If experimental mode causes a blank or unstable display, boot Safe Mode and run
EMERGENCY_REMOVE_EXPERIMENTAL_EDID.bat. After normal Windows returns, run the
regular restore script to restore the original Intel profile.

SAFETY
------
- Refuses every panel and physical EDID not explicitly validated.
- Refuses unknown existing EDID overrides.
- Saves the first original Intel profile and never silently overwrites it.
- Verifies every Intel profile change and every registry override block.
- Modifies no game, driver file, monitor firmware or game process.
- Includes no Intel DLL, CRU executable, driver, EDID dump or compiled binary.
