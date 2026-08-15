MSI CLAW 8 AI+ / 8 EX AI+ INTEL VRR RANGE FIX 1.0.2
====================================================

SUPPORTED PANEL
---------------
CSW0801 / PN8007QB1-2, physical EDID SHA-256:
E49BC570225510B7C889ED292570F1345CAA07F5840DB57EA6998A403DB5CEF0

The utility targets Claw 8 AI+ and Claw 8 EX AI+ configurations only when this
exact internal panel and physical EDID are detected. Model names alone are not
used as a safety check. The Claw A1M has a different 7-inch 1920x1080 panel and
is not yet supported. The AMD-powered Claw A8 is not compatible with this Intel
Control Library package.

OFFICIAL MODE - RECOMMENDED
---------------------------
Run INSTALL_48_120_VRR.bat.

This selects Intel's official EXCELLENT Arc Sync profile and verifies the
driver's active range as 48-120 Hz. Because Intel can restore 60-120 Hz after a
Windows restart, it also installs a current-user task. Installation backs up
and replaces only Intel Graphics Software's automatic startup order. At sign-in,
a readable Windows Script Host launcher starts the verified Intel application,
allows display initialization to settle, then applies and verifies 48-120 Hz
through a fully hidden PowerShell process.

EXPERIMENTAL MODE - OPTIONAL
----------------------------
Run INSTALL_EXPERIMENTAL_30_120_VRR.bat and accept the administrator prompt.

This installs a Windows EDID override that advertises 30-120 Hz, comparable in
purpose to a CRU configuration. It is outside MSI's official 48-120 Hz
specification and can cause flicker or display instability. The physical panel
firmware is not modified.

EXPERIMENTAL 144 HZ MODE - OPTIONAL PANEL OVERCLOCK
----------------------------------------------------
Run INSTALL_EXPERIMENTAL_48_144_VRR.bat and accept the administrator prompt.

This preserves the 48 Hz minimum and adds a 1920x1200 144 Hz DisplayID timing.
The reference panel was stable after transient stutter and line artifacts while
the Intel display device reloaded, and the driver verified EXCELLENT / 48-144
Hz. Persistent flicker, lines or blanking means restore immediately.

Windows can fall back to the fixed 120 Hz mode after a restart. The hidden
sign-in task now selects 1920x1200 at 144 Hz for this profile, waits for the
display transition, and verifies EXCELLENT / 48-144 Hz. No manual Windows
Display Settings step is required.

The combined 30-144 Hz profile is not distributed because real-hardware testing
produced visible flicker even though the Intel API accepted the range.

UNSUPPORTED CLAW / A1M DIAGNOSTICS
----------------------------------
COLLECT_UNSUPPORTED_CLAW_DISPLAY.bat only reads system, GPU, monitor, mode and
EDID information. It creates a local diagnostics folder under Documents and
changes no display setting. This collector prepares future A1M research; it is
not an A1M fix.

RESTART
-------
Each installer asks whether to restart the PC. Experimental EDID changes require
a restart. After signing in, wait for Intel Graphics Software to start, then run
CHECK_STATUS.bat.

Intel Graphics Software can keep showing a stale 60-120 Hz value. CHECK_STATUS
reads the active profile directly from Intel Control Library and also verifies
the EDID override.

Fully exit and restart the Intel Graphics Software tray process to refresh its
displayed current range. Restarting the UI does not control the driver profile.

MANDATORY PROFILE SWITCH RULE
-----------------------------
Run RESTORE_ORIGINAL_VRR.bat successfully and restart before installing a
different mode. Version 1.0.2 records the installed mode and refuses every
cross-profile installation. Reinstalling the same mode is allowed.

RESTORE
-------
Run RESTORE_ORIGINAL_VRR.bat, then restart when prompted. Restore removes the
scheduled task and installed scripts, then restores Intel's original signed
startup entry.

If experimental mode causes a blank or unstable display, boot Safe Mode and run
EMERGENCY_REMOVE_EXPERIMENTAL_EDID.bat. After normal Windows returns, run the
regular restore script to restore the original Intel profile.

If the saved state has already been mixed or damaged and normal restore cannot
complete, run FACTORY_RESET_CLAWLAB_VRR.bat. It restores 1920x1200 at 120 Hz,
Intel RECOMMENDED, the verified Intel startup entry, and removes only exact
ClawLab EDID overrides plus ClawLab tasks/state. It refuses unknown third-party
overrides and requires a restart.

SAFETY
------
- Refuses every panel and physical EDID not explicitly validated.
- Refuses unknown existing EDID overrides.
- Saves the first original Intel profile and never silently overwrites it.
- Verifies every Intel profile change and every registry override block.
- Modifies no game, driver file, monitor firmware or game process.
- Includes no Intel DLL, CRU executable, driver, EDID dump or compiled binary.
