# Changelog

## 1.0.1 — 2026-08-15

- Added a delayed current-user sign-in task after restart validation showed
  that Intel restores `RECOMMENDED / 60-120 Hz` during startup initialization.
- The task waits for Intel Graphics Software, applies `EXCELLENT / 48-120 Hz`
  last, verifies the driver readback and exits.
- Added task status reporting, a last-run result and complete removal through
  the normal restore action.

## 1.0.0 — 2026-08-14

- Targeted compatible MSI Claw 8 AI+ and Claw 8 EX AI+ configurations through
  exact panel and EDID validation rather than model-name assumptions.
- Added direct Intel Arc Sync monitor and profile diagnostics through the
  official Intel Control Library.
- Added verified official `EXCELLENT / 48-120 Hz` installation.
- Added a separately marked experimental `30-120 Hz` Windows EDID override for
  the exact validated Claw panel and EDID only.
- Added original-profile backup, exact override verification, normal restore and
  API-independent emergency EDID removal.
- Added an explicit restart choice after installation and restoration.
- Added reproducible GitHub/Nexus packaging with no bundled executable or
  third-party binary.
