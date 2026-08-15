# Changelog

## 2.0.1 — 2026-08-15

- Integrated the community-validated Intel LFC x2 correction into all four
  installers. Its directly tested combination uses the `EXCELLENT` Arc Sync
  profile, the exact 30-120 Hz EDID override, and disables both Intel low- and
  high-FPS VRR solutions; every other profile receives the same operation only
  after its own exact mode, EDID and active-range verification.
- Replaced the 30-120-specific LFC companion with one profile-aware module whose
  backup is bound to the selected managed mode.
- Made both guarded 144 Hz confirmations require the requested range and both
  shared LFC flags before the 20-second observation can begin. Automatic
  rejection restores the original LFC and VRR state together.
- Added repository and release-build checks that reject any installer missing
  the shared LFC correction.
- Direct behavior remains real-hardware validated at 30-120 Hz; both 144 Hz
  profiles retain experimental status.
- Documented that disabling Intel's low-FPS solution removes LFC below the
  selected 30 or 48 Hz floor. Frames below that floor can still tear or stutter.

## 2.0.0 — 2026-08-15

- Integrated the community-validated Intel LFC x2 correction into the guarded
  30-120 Hz installer. The tested combination uses the `EXCELLENT` Arc Sync
  profile, the exact 30-120 Hz EDID override, and disables both Intel low- and
  high-FPS VRR solutions.
- Added a direct, readable D3DKMT Intel display-driver interface. It changes a
  global display setting only and never opens, patches, injects into or monitors
  a game process.
- Added an independent backup of both original Intel VRR solution flags, exact
  readback verification, a windowless one-shot logon reapply, and coordinated
  restore/factory-reset handling.
- Restricted the LFC x2 correction to the validated 30-120 Hz mode. Official
  48-120 Hz and optional 48-144 Hz remain separate and receive no unverified
  LFC claim.
- Documented that disabling Intel's low-FPS solution removes LFC below the new
  30 Hz floor. Frames below 30 FPS can still tear or stutter.
- Documented conflicts with display-profile tools that force Intel
  `RECOMMENDED` after sign-in or when a game starts. No resource-consuming
  background watchdog is installed.
- Reorganized the public choices around four profiles: default corrected
  30-120 Hz, official Intel/MSI 48-120 Hz, guarded 48-144 Hz, and guarded
  30-144 Hz.
- Added a one-time 144 Hz confirmation failsafe. After driver verification and
  20 seconds of observation, Yes keeps the profile; No, closing the dialog, a
  30-second timeout or verification failure restores 120 Hz and restarts
  Windows. The temporary task removes itself.
- Exposed 30-144 only through that guarded flow and retained the prominent
  disclosure that it visibly flickered on the reference panel.

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
