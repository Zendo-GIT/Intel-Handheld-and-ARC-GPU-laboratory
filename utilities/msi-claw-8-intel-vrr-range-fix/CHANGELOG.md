# Changelog

## 2.1.2 — 2026-08-16

- Accepts the real A1M/Claw 7 AI+ Windows representation consisting of the
  exact pinned 128-byte EDID followed by 128 zero bytes; any non-zero tail or
  unknown canonical hash is still rejected.
- Records the same zero-padded representation on independently collected Core
  Ultra 5 and Core Ultra 7 Claw A1M diagnostics.
- Updates the Intel LFC component to 2.0.4 with atomic schema-4 stable panel
  identity, allowing a verified Windows monitor-instance rename after an Intel
  driver update without a restore/reinstall loop.
- Keeps unverifiable schema-1/2 backups fail-closed and rejects every physical
  panel or EDID mismatch.
- Separates game-facing VRR/LFC health from optional desktop-helper health.
- Adds one-click read-only JSON status export under `DIAGNOSTICS`.
- Warns users never to delete `%LOCALAPPDATA%\ClawLab`, which contains the
  original state required for safe restoration.
- Detects a missing original backup with disabled Intel flags instead of
  claiming they are already restored, and adds a separate fail-closed emergency
  factory-default action that refuses to overwrite an existing backup.

## 2.1.1 — 2026-08-16

- Starts the Cursor Refresh Helper near the beginning of sign-in reapply instead
  of after the slower Intel driver stabilization path.
- Extends the cursor activity tail from 500 ms to 1.5 seconds to reduce rapid
  floor/ceiling transitions during short pauses.
- Adds source-agnostic controller/game deep idle: no usable visible-mouse input
  stops animation, releases the 1 ms timer-resolution request and trims the
  helper's own working set. The first visible raw-mouse packet resumes it.
- Keeps controller detection independent of ClawTweaks, MSI Center M or any
  other profile manager and adds no polling loop or game-process inspection.
- Adds an overall health report with explicit `HEALTHY`, `INITIALIZING` and
  `ATTENTION_REQUIRED` states plus Intel driver-change verification.
- Treats an installed helper from an older package as `VERSION_MISMATCH` rather
  than accepting its internally consistent old hash as current.
- Adds an interactive CRU preflight to both installers.
- Reorganizes the public ZIP: installers and status at root, normal restore in
  `RECOVERY`, destructive fallbacks in `EMERGENCY`, diagnostics in
  `DIAGNOSTICS`, and internal runtime components in `scripts`.
- Retains the unchanged 2.0.3 Intel LFC driver correction and both supported
  30-120 and official 48-120 profiles.

## 2.1.0 — 2026-08-16

- Added the real-hardware-validated Cursor Refresh Helper for the Windows
  desktop. Raw mouse activity animates a nearly transparent 2x2 WPF/DWM surface
  at the extreme lower-right corner so the panel rises from its idle VRR floor
  to 120 Hz.
- Stops the animation 500 milliseconds after mouse input; the high-frequency
  timer is not running at idle.
- Suppresses animation when the system cursor is hidden while remaining active
  in Windows Xbox Full Screen Experience.
- Uses standard Raw Input and desktop composition only, with no game injection,
  process hook, game-file access or modification of the existing LFC fix.
- Added helper binary integrity state, automatic sign-in launch, status,
  complete restore cleanup and publicly rebuildable C# source.
- Removed per-Raw-Input native allocations and extended the activity tail to
  500 ms, eliminating the cursor micro-stutter reproduced on the reference Claw.
- Added strict Claw A1M `TMA2027 / TL070FVXS02-0` support with its exact
  128-byte physical EDID and deterministic one-block 30-120 transformation.
- Generalized install, restore, factory and emergency recovery for one- or
  two-block catalogued panels without weakening unknown-override refusal.
- Added an offline A1M EDID generator/integrity test. A1M real-hardware
  driver/LFC and panel behavior remains community-validation pending.
- Fixed 2.1.0 sign-in orchestration so the LFC parent waits only for the direct
  VRR child, not for the resident Cursor Refresh Helper descendant. This keeps
  the one-shot task from reaching its four-minute execution limit.
- Made historical CRU cleanup explicit and mandatory: run `reset-all.exe` from
  the current official CRU release and restart before ClawLab installation,
  regardless of when CRU was used or whether it now appears inactive.

## 2.0.3 — 2026-08-15

- Fixed first installation when Intel Graphics Software and its machine Run
  entry are both absent, as confirmed by a Claw 8 AI+ / driver 8974 diagnostic.
- Added schema-4 startup state that preserves true application absence without
  constructing, validating or launching a nonexistent executable.
- Leaves a newly installed third-party Intel startup entry untouched during
  restore instead of deleting an external change.
- Persists elevated failure details in `last-error.txt` and echoes them back to
  the original console after a failed UAC child process.

## 2.0.2 — 2026-08-15

- Removed the 48-144 and 30-144 installers, confirmation task and every public
  144 Hz installation action.
- Retained exact legacy 144 Hz hashes only for status, normal restore, factory
  reset and Safe Mode recovery.
- Refuses startup or LFC persistence for a retired 144 Hz managed profile and
  directs the user to `RESTORE_ORIGINAL_VRR.bat`.
- Reduced the supported public choices to corrected 30-120 and official
  Intel/MSI 48-120.
- Made LFC and startup-file cleanup idempotent when a previous installation
  never created its local state directory.
- Added an explicit schema-3 startup backup for systems where Intel Graphics
  Software has no machine Run entry; normal restore now preserves that entry
  as absent instead of blocking first installation.

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
