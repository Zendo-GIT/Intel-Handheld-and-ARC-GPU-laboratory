# Optional Nexus Mods publication draft

Recommended metadata:

- Title: **MSI Claw 8 AI+ Intel Arc Sync VRR Range Fix**
- Version: **1.0.0**
- Category: **Utilities** or **Bug Fixes**
- Installation: **Manual only**

## Short description

Activates the Claw 8 AI+ panel's official 48-120 Hz Intel Arc Sync range instead
of the driver's constrained 60-120 Hz recommended profile. Includes an optional,
clearly separated experimental 30-120 Hz EDID override, exact status reporting,
backup, restore and Safe Mode recovery.

## Required disclosure

Official mode uses Intel's public Control Library `EXCELLENT` profile. The
experimental mode is outside MSI's official 48-120 Hz specification and can
cause flicker or display instability. It is restricted to the exact validated
`CSW0801 / PN8007QB1-2` panel and EDID SHA-256.

The archive contains no driver, Intel DLL, CRU executable, EDID dump, compiled
binary, game file, injector or anti-cheat component. It modifies no monitor
firmware. Experimental mode uses Windows' reversible EDID override mechanism.

The project includes AI-assisted code and documentation. Do not enter it in an
event whose rules prohibit generative-AI-assisted submissions.

## Publishing recommendation

GitHub should remain the canonical source and checksum location. Consider
publishing the Nexus page only after experimental 30-120 mode has completed a
post-restart visual and driver-readback validation on the reference Claw.
