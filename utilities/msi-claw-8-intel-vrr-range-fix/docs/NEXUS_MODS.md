# Optional Nexus Mods publication draft

Recommended metadata:

- Title: **MSI Claw 8 AI+ / 8 EX AI+ Intel VRR Range Fix**
- Version: **1.0.2**
- Category: **Utilities** or **Bug Fixes**
- Installation: **Manual only**

## Short description

Activates the compatible Claw 8 AI+ / Claw 8 EX AI+ panel's official 48-120 Hz
Intel Arc Sync range instead of the driver's constrained 60-120 Hz recommended
profile. Includes clearly separated experimental 30-120 Hz and 48-144 Hz EDID
options, delayed sign-in reapply, exact status reporting, backup, restore and
Safe Mode recovery. The 144 Hz option is an unsupported panel overclock.

## Required disclosure

Official mode uses Intel's public Control Library `EXCELLENT` profile. The
experimental mode is outside MSI's official 48-120 Hz specification and can
cause flicker or display instability. It is restricted to the exact validated
`CSW0801 / PN8007QB1-2` panel and EDID SHA-256. Model naming alone is not
sufficient: the installer refuses either Claw model if the display identity or
EDID differs. The AMD-powered Claw A8 is not compatible with this Intel package.

The combined 30-144 range is not included because it visibly flickered during
reference-hardware validation, despite being accepted by the Intel driver.

The archive contains no driver, Intel DLL, CRU executable, prepackaged EDID
dump, compiled binary, game file, injector or anti-cheat component. It modifies no monitor
firmware. Experimental mode uses Windows' reversible EDID override mechanism.
Official installation creates one documented current-user scheduled task
because Intel restores its constrained profile during a full Windows restart.
Installation backs up and removes only Intel Graphics Software's exact signed
automatic-startup entry. The windowless task starts Intel Graphics Software
with its original command, allows initialization to settle, then applies and
verifies the profile. Normal restore
removes the task and scripts and restores the exact Intel startup entry.

Version 1.0.2 refuses every cross-profile installation. Users must run
`RESTORE_ORIGINAL_VRR.bat` successfully and restart before choosing another
mode. `FACTORY_RESET_CLAWLAB_VRR.bat` is included only for mixed or damaged
ClawLab state that normal restore cannot repair; it refuses unknown third-party
EDID overrides.

The project includes AI-assisted code and documentation. Do not enter it in an
event whose rules prohibit generative-AI-assisted submissions.

## Publishing recommendation

GitHub should remain the canonical source and checksum location. Publish the
48-144 profile only as an optional experimental file with an explicit panel
overclock warning and immediate restore instructions. Version 1.0.2 also
reselects 1920x1200 at 144 Hz at sign-in, because Windows can otherwise return
to the fixed 120 Hz mode after a restart.
