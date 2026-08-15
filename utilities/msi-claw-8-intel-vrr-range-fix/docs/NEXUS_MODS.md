# Optional Nexus Mods publication draft

Recommended metadata:

- Title: **MSI Claw 8 AI+ / 8 EX AI+ Intel VRR Range Fix**
- Version: **1.0.3**
- Category: **Utilities** or **Bug Fixes**
- Installation: **Manual only**

## Short description

Activates the compatible Claw 8 AI+ / Claw 8 EX AI+ panel's official 48-120 Hz
Intel Arc Sync range instead of the driver's constrained 60-120 Hz recommended
profile. Includes clearly separated experimental 30-120 Hz and 48-144 Hz EDID
options, driver-update-aware sign-in reapply, exact status reporting, backup,
restore and Safe Mode recovery. Fixed 144 Hz was stable on tested panels, but
VRR at 144 Hz is not guaranteed.

## Required disclosure

Official mode uses Intel's public Control Library `EXCELLENT` profile. The
experimental mode is outside MSI's official 48-120 Hz specification and can
cause flicker or display instability. It is restricted to the exact validated
`CSW0801 / PN8007QB1-2` panel and EDID SHA-256. Model naming alone is not
sufficient: the installer refuses either Claw model if the display identity or
EDID differs. The AMD-powered Claw A8 is not compatible with this Intel package.

The 48-144 installer is an out-of-spec panel overclock. Fixed 144 Hz remained
stable on tested panels and Intel reported the declared range, but follow-up
game testing did not prove operational VRR at 144 Hz. VRR is not guaranteed.
The 30-144 combination visibly flickered and remains unavailable; its exact
historical ClawLab signature is retained only for recovery.

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

If a graphics-driver update replaces Intel Graphics Software, version 1.0.3
renews its saved hash only after a fresh Windows Authenticode check validates a
genuine Intel-signed executable at the canonical path. A hash change by itself
is never accepted.

Version 1.0.2 and later refuse every cross-profile installation. Users must run
`RESTORE_ORIGINAL_VRR.bat` successfully and restart before choosing another
mode. `FACTORY_RESET_CLAWLAB_VRR.bat` is included only for mixed or damaged
ClawLab state that normal restore cannot repair; it refuses unknown third-party
EDID overrides.

The project includes AI-assisted code and documentation. Do not enter it in an
event whose rules prohibit generative-AI-assisted submissions.

## Publishing recommendation

GitHub should remain the canonical source and checksum location. The main file
should emphasize official 48-120 and experimental 30-120 operation. If the
48-144 installer is published, label it prominently as an optional panel
overclock: fixed 144 Hz was stable on tested units, but VRR is not guaranteed.
Do not publish or reconstruct a 30-144 installer.
