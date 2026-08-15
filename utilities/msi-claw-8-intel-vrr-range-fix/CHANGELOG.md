# Changelog

## 1.0.3 — 2026-08-15

- Added safe Intel Graphics Software update detection: a replaced executable is
  trusted only after fresh Authenticode validation confirms Intel Corporation,
  the canonical path and original `-s` command, followed by stable SHA-256
  verification and an atomic identity-record update.
- Added automatic schema-2 migration for identities saved by earlier releases,
  including signer thumbprint, file version and SHA-256.
- Retained the 48-144 Hz installer as a clearly disclosed experimental panel
  overclock: fixed 144 Hz was stable on tested hardware, but VRR at 144 Hz or
  throughout the advertised range is not guaranteed.
- Kept the visibly flickering 30-144 profile unavailable and recovery-only,
  with an explicit rejected-profile status directing affected historical users
  to `RESTORE_ORIGINAL_VRR.bat`.

## 1.0.2 — 2026-08-15

- Added an optional 48-144 Hz DisplayID profile after guarded hardware testing
  confirmed 1920x1200 at 144 Hz and Intel `EXCELLENT / 48-144 Hz` readback.
- Recorded and withheld 30-144 Hz after visible flicker on the reference panel.
- Added a read-only display/EDID collector for unsupported Claw models such as
  the A1M; this is diagnostics only, not an A1M compatibility claim.
- Added verified fixed-refresh persistence for the 48-144 profile after
  community testing found Windows returning to 120 Hz after restart.
- Added startup-safe SHA-256 verification of the previously Authenticode-
  validated Intel Graphics Software executable.
- Added a mandatory managed-mode interlock that refuses every profile change
  until `RESTORE_ORIGINAL_VRR.bat` completes; same-mode repair remains allowed.
- Added `FACTORY_RESET_CLAWLAB_VRR.bat` to recover mixed or damaged ClawLab VRR
  state without requiring the saved original Arc Sync profile.

## 1.0.1 — 2026-08-15

- Added persistent `EXCELLENT / 48-120 Hz` reapply after restart validation
  showed Intel restoring `RECOMMENDED / 60-120 Hz` during driver startup.
- Added a windowless current-user task that retries until the Intel display API
  is ready, applies and verifies the profile, then starts Intel Graphics
  Software.
- Added exact backup and restoration of Intel Graphics Software's verified,
  Intel-signed machine-wide startup entry to guarantee launch order.
- Added task, startup-order and last-run status reporting.

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
