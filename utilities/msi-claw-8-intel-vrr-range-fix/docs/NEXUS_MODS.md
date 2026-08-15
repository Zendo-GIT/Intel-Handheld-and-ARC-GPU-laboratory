# Optional Nexus Mods publication draft

Recommended metadata:

- Title: **MSI Claw 8 AI+ / 8 EX AI+ Intel VRR Range Fix**
- Version: **2.0.1**
- Category: **Utilities** or **Bug Fixes**
- Installation: **Manual only**

## Short description

Default 30-120 Hz MSI Claw Intel VRR profile, plus the official Intel/MSI
48-120 Hz profile. All four profiles include the shared Intel LFC x2 correction.
Includes
guarded 48-144 and 30-144 trials, 20-second confirmation with automatic
rollback, driver-update-aware sign-in reapply, exact status, backup, restore and
Safe Mode recovery.

## Required disclosure

Official 48-120 mode uses Intel's public Control Library `EXCELLENT` profile.
The default 30-120 mode is outside MSI's official 48-120 Hz specification and can
cause flicker or display instability. It is restricted to the exact validated
`CSW0801 / PN8007QB1-2` panel and EDID SHA-256. Model naming alone is not
sufficient: the installer refuses either Claw model if the display identity or
EDID differs. The AMD-powered Claw A8 is not compatible with this Intel package.

Both 144 Hz installers are out-of-spec panel-overclock trials. Fixed 144 Hz
remained stable on tested panels and Intel reported the declared ranges, but
follow-up game testing did not prove operational VRR at 144 Hz. VRR is not
guaranteed. The 30-144 combination visibly flickered on the reference panel.
After restart, each 144 profile is verified and observed for 20 seconds, then a
Yes/No dialog requires confirmation. No, closing the prompt, or a 30-second
timeout restores 120 Hz and restarts Windows.

The shared LFC x2 correction uses a readable Windows D3DKMT request to Intel's
driver-private VRR interface. Every profile saves and disables both Intel
low/high-FPS solutions as one combination, only after verifying its exact
managed mode, EDID and active range. This is not a public Intel API. It performs
no game-process operation and installs no continuous watcher. The observed x2
removal is validated on real hardware at 30-120 Hz; the identical guarded
mechanism is integrated into 48-120, 48-144 and 30-144 without claiming that
those three paths have already received separate real-hardware LFC validation.
Intel refresh multiplication below the selected 30 or 48 Hz floor is unavailable
while the correction is active.

The archive contains no driver, Intel DLL, CRU executable, prepackaged EDID
dump, compiled binary, game file, injector or anti-cheat component. It modifies no monitor
firmware. Custom ranges use Windows' reversible EDID override mechanism.
Official installation creates one documented current-user scheduled task
because Intel restores its constrained profile during a full Windows restart.
Installation backs up and removes only Intel Graphics Software's exact signed
automatic-startup entry. The windowless task starts Intel Graphics Software
with its original command, allows initialization to settle, then applies and
verifies the profile. Normal restore
removes the task and scripts and restores the exact Intel startup entry.

If a graphics-driver update replaces Intel Graphics Software, version 2.0.1
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
should emphasize the default validated 30-120 combination, retain 48-120 as the
official Intel/MSI profile, and state that the shared LFC correction is installed
with all four profiles. Label both 144 installers prominently as guarded
panel-overclock trials. State that 30-144 visibly flickered on the reference
panel and that VRR at 144 Hz is not guaranteed.
